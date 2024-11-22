// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Pit} from "./Pit.sol";

contract Table is Initializable, OwnableUpgradeable, ReentrancyGuard {
    error Table__BetTransferFailed();
    error Table__CannotDoubleAfterHit();
    error Table__CannotSplitAfterHit();
    error Table__CannotSplitOnDifferentCards();
    error Table__EthSentForTokenBet();
    error Table__InsufficientBet();
    error Table__InvalidSeat();
    error Table__InvalidMaxPlayers();
    error Table__InvalidPlayer();
    error Table__NoCards();
    error Table__NotEmpty();
    error Table__PlayerNotFound();
    error Table__SeatOccupied();
    error Table__BetAlreadyPlaced();
    error Table__BetExceedsMax();
    error Table__BetLessThanMin();
    error Table__BettingInProgress();
    error Table__GameInProgress();
    error Table__MaxResplitHandsReached();
    error Table__NoActiveHand();
    error Table__NoBalanceAvailable();
    error Table__NotBetStatus();
    error Table__NotCurrentPlayer();
    error Table__NotInactiveStatus();
    error Table__NotManager();
    error Table__NotPlayerTurnStatus();
    error Table__CashOutTransferFailed();

    address[] s_players;
    mapping(address => PlayerState) public s_playerToState;
    mapping(uint8 => address) public s_seatToPlayer;
    mapping(uint8 => address) public s_seatToWaitingPlayer;
    BetRange s_betRange;
    Rules s_rules;
    uint8 s_maxPlayers;
    address public s_token;
    address public s_manager;
    uint256[] internal s_randomWords;
    uint256 internal s_betTotal;
    uint8[] internal s_drawableCards;
    mapping(uint8 => uint8) internal s_cardToDrawCount;
    uint256 public s_lockTimestamp;
    bool s_continuousPlay;    
    
    GameStatus internal s_gameStatus;
    uint8[] internal s_dealerHand;
    address internal s_currentPlayer;

    enum DoubleRule {
        FirstTwoCards,
        NineToEleven,
        TenToEleven
    }

    struct Rules {
        uint8 deckCount;
        bool dealerHitOnSoft17;
        bool allowDoubleAfterSplit;
        DoubleRule doubleRule;
        uint8 maxResplitHands;
        bool allowResplitAces;
        bool allowHitSplitAces;
        bool allowLateSurrender;
        bool allowInsurance;
        bool sixToFive;
    }

    struct BetRange {
        uint256 min;
        uint256 max;
    }

    struct PlayerState {
        uint8 seat;
        uint256 bet;
        uint256 initialBet;
        Hand[] hands;
        uint256 balance;
    }

    struct Hand {
        uint8[] cards;
        uint8 value;
        HandStatus status;
    }

    enum HandStatus {
        Active,
        Stand,
        Bust
    }

    enum GameStatus {
        Inactive,
        Bet,
        Insurance,
        PlayerTurn,
        DealerTurn
    }

    event BetsStarted();
    event GameStarted();
    event Hit(uint8 indexed card);

    modifier onlyManager {
        if (msg.sender != address(s_manager)) {
            revert Table__NotManager();
        }
        _;
    }

    modifier onlyCurrentPlayer {
        if (s_gameStatus != GameStatus.PlayerTurn) {
            revert Table__NotPlayerTurnStatus();
        }
        if (msg.sender != s_currentPlayer) {
            revert Table__NotCurrentPlayer();
        }
        _;
    }

    modifier whenEmpty {
        if (s_players.length > 0) {
            revert Table__NotEmpty();
        }
        _;
    }

    modifier whenInactive {
        if (s_gameStatus != GameStatus.Inactive) {
            revert Table__NotInactiveStatus();
        }
        _;
    }

    modifier whenInactiveOrBet {
        if (s_gameStatus != GameStatus.Bet && s_gameStatus != GameStatus.Inactive) {
            revert Table__GameInProgress();
        }
        _;
    }

    function initialize(
        address _manager,  
        uint8 _maxPlayers,
        BetRange memory _betRange,
        Rules memory _rules,
        address _token
    ) public initializer {
        __Ownable_init(msg.sender);

        s_manager = _manager;
        s_maxPlayers = _maxPlayers;
        s_betRange = _betRange;
        s_rules = _rules; // TODO: validate rules
        s_token = _token;

        resetDrawableCards();
        refreshRandomWords();
    }

    function setMaxPlayers(uint8 _maxPlayers) external onlyOwner whenInactive {
        if (_maxPlayers < (s_players.length + 1) || _maxPlayers > 7) {
            revert Table__InvalidMaxPlayers();
        }
        
        s_maxPlayers = _maxPlayers;
    }
    
    function setBetRange(BetRange memory _betRange) external onlyOwner whenInactive {
        s_betRange = _betRange;
    }

    function setToken(address _token) external onlyOwner whenInactive whenEmpty {
        s_token = _token;
    }

    function setRandomWords(uint256[] calldata _randomWords) external onlyOwner {
        s_randomWords = _randomWords;
    }

    function refreshRandomWords() internal {
        Pit(payable(owner())).requestRandomWords();
    }

    function startBets() external onlyManager whenInactive {
        s_gameStatus = GameStatus.Bet;
        emit BetsStarted();
    }

    function startGame() internal {
        for (uint8 i = 0; i < s_players.length; i++) {
            Hand memory hand;
            uint8[] memory cards = new uint8[](2);

            for (uint256 j = 0; j < 2; j++) {
                uint8 card = drawCard();
                cards[j] = card;
                hand.value += getCardValue(card);
            }

            hand.cards = cards;
            s_playerToState[s_players[i]].hands = [hand];
        }

        uint8 dealerCard = drawCard();
        s_dealerHand.push(dealerCard);

        uint8 value = getCardValue(dealerCard);

        if (s_rules.allowInsurance && (value == 10 || value == 1)) {
            s_gameStatus = GameStatus.Insurance;
        } else {
            s_gameStatus = GameStatus.PlayerTurn;
            emit GameStarted();
        }
    }

    function unlock() external onlyOwner {
        if (s_lockTimestamp > 0) {
            s_lockTimestamp = 0;
            startGame();
        }
    }

    function resetGame() external onlyOwner {
        uint256 betsToRemove = 0;

        for (uint8 i = 0; i < s_players.length; i++) {
            address player = s_players[i];
            uint256 bet = s_playerToState[player].bet;
            betsToRemove += bet;
            s_playerToState[player].balance += bet;
            s_playerToState[player].bet = 0;
            delete s_playerToState[player].hands;
        }

        s_gameStatus = GameStatus.Inactive;
    }

    function resetDrawableCards() internal {
        delete s_drawableCards;

        for (uint8 i = 1; i < 53; i++) {
            s_cardToDrawCount[i] = 0;
            s_drawableCards.push(i);
        }
    }

    function sit(uint8 _seat) external {
        if (msg.sender == owner()) {
            revert Table__InvalidPlayer();
        }

        if (_seat > s_maxPlayers || _seat < 1) {
            revert Table__InvalidSeat();
        }

        if (s_seatToPlayer[_seat] != address(0) || s_seatToWaitingPlayer[_seat] != address(0)) {
            revert Table__SeatOccupied();
        }

        bool isGameStarted = s_gameStatus != GameStatus.Inactive && s_gameStatus != GameStatus.Bet;

        if (!isGameStarted && s_lockTimestamp == 0) {
            s_playerToState[msg.sender].seat = _seat;
            s_seatToPlayer[_seat] = msg.sender;
            s_players.push(msg.sender);
        } else {
            s_seatToWaitingPlayer[_seat] = msg.sender;
        }
    }

    function leave() external whenInactiveOrBet {
        uint8 seat = s_playerToState[msg.sender].seat;

        if (seat == 0) {
            revert Table__PlayerNotFound();
        }

        uint256 bet = s_playerToState[msg.sender].bet;

        if (bet > 0) {
            s_playerToState[msg.sender].balance += bet;
            s_betTotal -= bet;
        }

        s_playerToState[msg.sender].seat = 0;
        s_seatToPlayer[seat] = address(0);

        bool playerFound = false;
        bool missingBet = false;

        for (uint8 i = 0; i < s_players.length; i++) {
            address player = s_players[i];

            if (playerFound) {
                s_players[i - 1] = s_players[i];
            } else if (msg.sender == player) {
                playerFound = true;
            }

            if (s_playerToState[player].bet == 0 && player != msg.sender) {
                missingBet = true;
            }
        }

        s_players.pop();

        // Start game if all remaining players placed bets
        if (s_players.length > 0 && s_gameStatus == GameStatus.Bet && !missingBet) {
            finalizeBets();
        }
    }

    function placeBet(uint256 _amount) external payable nonReentrant {
        if (s_gameStatus != GameStatus.Bet) {
            revert Table__NotBetStatus();
        }
        if (s_playerToState[msg.sender].bet > 0) {
            revert Table__BetAlreadyPlaced();
        }
        if (s_token != address(0) && msg.value > 0) {
            revert Table__EthSentForTokenBet();
        }

        uint256 amount = s_token != address(0) ? _amount : msg.value;

        if (amount == 0 || amount < s_betRange.min) {
            revert Table__InsufficientBet();
        }
        if (amount > s_betRange.max) {
            revert Table__BetExceedsMax();
        }

        s_playerToState[msg.sender].bet = amount;
        s_playerToState[msg.sender].initialBet = amount;
        s_betTotal += amount;

        if (s_token != address(0)) {
            bool success = IERC20(s_token).transferFrom(msg.sender, address(this), _amount);

            if (!success) {
                revert Table__BetTransferFailed();
            }
        }

        for (uint8 i = 0; i < s_players.length; i++) {
            address playerAddress = s_players[i];
            if (s_playerToState[playerAddress].bet == 0) return;
        }

        finalizeBets();
    }

    function finalizeBets() internal {
        Pit pit = Pit(payable(owner()));
        (uint256 balance, uint256 maxPayout) = pit.s_managerToTokenToState(s_manager, s_token);

        uint256 bjPayoutFactor = s_rules.sixToFive ? 5 : 4;
        uint256 gameMaxPayout = 1e18 * s_betTotal * 6 / bjPayoutFactor;

        if (s_rules.allowDoubleAfterSplit) {
            gameMaxPayout *= 2 * s_rules.maxResplitHands;
        } else {
            gameMaxPayout *= (s_rules.maxResplitHands + 1);
        }

        uint256 newMaxPayout = maxPayout + Math.ceilDiv(gameMaxPayout, 1e18);
        pit.setMaxPayout(newMaxPayout, s_token);

        if (newMaxPayout > balance) {
            s_lockTimestamp = block.timestamp;
        } else {
            startGame();
        }
    }

    function cashOut() external nonReentrant {
        uint256 amount = s_playerToState[msg.sender].balance;

        if (amount == 0) {
            revert Table__NoBalanceAvailable();
        }

        s_playerToState[msg.sender].balance = 0;

        bool success;

        if (s_token == address(0)) {
            (success,) = msg.sender.call{value: amount}("");
        } else {
            success = IERC20(s_token).transfer(msg.sender, amount);
        }

        if (!success) {
            revert Table__CashOutTransferFailed();
        }
    }

    function drawCard() internal returns (uint8) {
        if (s_randomWords.length == 0) {
            revert Table__NoCards();
        }

        uint256 randomWord = s_randomWords[s_randomWords.length - 1];
        s_randomWords.pop();

        // Get new random words from VRF if running out
        if (s_randomWords.length < 50) {
            refreshRandomWords();
        }

        uint8 cardIndex = uint8(randomWord % s_drawableCards.length);
        uint8 card = s_drawableCards[cardIndex];

        s_cardToDrawCount[card]++; 

        // Remove card from drawable cards if drawn max number of times
        // Reset drawable cards if all drawn
        if (s_cardToDrawCount[card] == s_rules.deckCount) {
            if (s_drawableCards.length == 1) {
                resetDrawableCards();
            } else {
                for (uint8 i = cardIndex; i < s_drawableCards.length; i++) {
                    s_drawableCards[i] = s_drawableCards[i + 1];
                }

                s_drawableCards.pop();
            }
        }

        return card;
    }

    function getCardValue(uint8 _card) internal returns (uint8) {
        return uint8(Math.min(Math.ceilDiv(_card, 4), 10));
    }

    function getActiveHandIndex() internal returns (uint256) {
        Hand[] memory hands = s_playerToState[msg.sender].hands;

        for (uint i = 0; i < hands.length; i++) {
            if (hands[i].status == HandStatus.Active) {
                return i;
            }
        }

        revert Table__NoActiveHand();
    }

    function hit() external onlyCurrentPlayer {
        uint8 card = drawCard();
        uint256 handIndex = getActiveHandIndex();
        Hand memory hand = s_playerToState[msg.sender].hands[handIndex];
        hand.cards.push(card);
        hand.value += getCardValue(card);

        if (hand.value > 21) {
            nextTurn();
            hand.status = HandStatus.Bust;
        }

        s_playerToState[msg.sender].hands[handIndex] = hand;
    }

    function split() payable external onlyCurrentPlayer nonReentrant {
        if (s_playerToState[msg.sender].hands.length == s_rules.maxResplitHands) {
            revert Table__MaxResplitHandsReached();
        }
        
        uint256 handIndex = getActiveHandIndex();
        Hand memory hand = s_playerToState[msg.sender].hands[handIndex];

        if (hand.cards.length > 2) {
            revert Table__CannotSplitAfterHit();
        }

        uint8 card1 = hand.cards[0];
        uint8 card2 = hand.cards[1];
        uint8 cardValue = getCardValue(card1);

        if (cardValue != getCardValue(card2)) {
            revert Table__CannotSplitOnDifferentCards();
        }
        if (s_token != address(0) && msg.value > 0) {
            revert Table__EthSentForTokenBet();
        }

        uint256 betAmount = s_playerToState[msg.sender].initialBet;

        if (s_token == address(0)) {
            if (msg.value < betAmount) {
                revert Table__InsufficientBet();
            }
            if (msg.value > betAmount) {
                revert Table__BetExceedsMax();
            }
        }

        s_playerToState[msg.sender].bet += betAmount;
        s_betTotal += betAmount;

        if (s_token != address(0)) {
            bool success = IERC20(s_token).transferFrom(msg.sender, address(this), betAmount);

            if (!success) {
                revert Table__BetTransferFailed();
            }
        }

        Hand[] memory newHands = s_playerToState[msg.sender].hands;

        uint8[] memory newHandCards;
        newHandCards.push(card2);
        Hand memory newHand = Hand(newHandCards, cardValue, HandStatus.Active);
        newHands.push(newHand);

        Hand memory activeHand = newHands[handIndex];
        activeHand.cards.pop();
        activeHand.value -= cardValue;

        uint8 newCard = drawCard();
        activeHand.cards.push(newCard);
        activeHand.value += getCardValue(newCard);

        newHands[handIndex] = activeHand;
        s_playerToState[msg.sender].hands = newHands;
    }

    function double() external onlyCurrentPlayer {
        Hand memory hand = getActiveHandIndex();

        if (hand.cards > 2) {
            revert Table__CannotDoubleAfterHit();
        }
    }

    function stand() external onlyCurrentPlayer {
        // TODO: set status to stand and check if more split hands to play

        nextTurn();
    }

    function nextTurn() internal {
        uint playerIndex;

        for (uint i = 0; i < s_players.length; i++) {
            if (s_players[i] == s_currentPlayer) {
                playerIndex = i;
                break;
            } 
        }

        if (playerIndex == s_players.length) {
            s_gameStatus = GameStatus.DealerTurn;
            s_currentPlayer = address(0);
            dealerPlay();
        } else {
            s_currentPlayer = s_players[playerIndex + 1];
        }
    }

    function dealerPlay() internal {

    }
}
