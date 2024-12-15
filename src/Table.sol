// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Pit} from "./Pit.sol";

contract Table is Initializable, OwnableUpgradeable, ReentrancyGuard {
    error Table__CannotDoubleAfterHit();
    error Table__CannotSplitAfterHit();
    error Table__CannotSplitOnDifferentCards();
    error Table__CurrencyNotEth();
    error Table__HandNotNineToEleven();
    error Table__HandNotTenToEleven();
    error Table__InsufficientBet();
    error Table__InvalidDebtClearanceAmount();
    error Table__InvalidSeat();
    error Table__InvalidMaxPlayers();
    error Table__InvalidPlayer();
    error Table__Locked();
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
    error Table__TokenTransferFailed();

    address[] s_players;
    mapping(address => PlayerState) public s_playerToState;
    mapping(uint8 => address) public s_seatToPlayer;
    mapping(uint8 => address) public s_seatToWaitingPlayer;
    BetRange s_betRange;
    Rules s_rules;
    uint8 s_maxPlayers;
    address public s_token;
    address public s_manager;
    uint256 internal s_debt;
    uint256[] internal s_randomWords;
    uint256 internal s_betTotal;
    uint256 internal s_gameMaxPayout;
    uint8[] internal s_drawableCards;
    mapping(uint8 => uint8) internal s_cardToDrawCount;
    uint256 public s_lockTimestamp;
    bool s_continuousPlay;    
    
    GameStatus internal s_gameStatus;
    Hand internal s_dealerHand;
    address internal s_currentPlayer;

    enum DoubleRule {
        Any,
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
        Hand[] hands;
        uint256 balance;
    }

    struct Hand {
        uint8[] cards;
        uint8 minValue;
        uint8 aceCount;
        HandStatus status;
        bool doubled;
    }

    enum HandStatus {
        Active,
        Stand,
        Bust
    }

    enum GameStatus {
        Inactive,
        Bet,
        Pending,
        Insurance,
        PlayerTurn,
        DealerTurn
    }

    event BetsStarted();
    event GameStarted();
    event Hit(uint8 indexed card);
    event TableLocked();

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

    modifier whenBet {
        if (s_gameStatus != GameStatus.Bet) {
            revert Table__NotBetStatus();
        }
        _;
    }

    modifier whenInactiveOrBet {
        if (s_gameStatus != GameStatus.Bet && s_gameStatus != GameStatus.Inactive) {
            revert Table__GameInProgress();
        }
        _;
    }

    modifier whenUnlocked {
        if (s_lockTimestamp == 0) {
           revert Table__Locked();
        }
        _;
    }

    modifier checkCurrency {
        if (s_token != address(0) && msg.value > 0) {
            revert Table__CurrencyNotEth();
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
            address player = s_players[i];
            Hand storage hand = s_playerToState[player].hands[0];
            drawCard(hand);
            drawCard(hand);
        }

        drawCard(s_dealerHand);
        uint256 value = s_dealerHand.minValue;

        if (s_rules.allowInsurance && (value == 10 || value == 1)) {
            s_gameStatus = GameStatus.Insurance;
        } else {
            s_gameStatus = GameStatus.PlayerTurn;
            emit GameStarted();
        }
    }

    function lock() external onlyOwner {
        s_lockTimestamp = block.timestamp;
        emit TableLocked();
    }

    function unlock() public onlyOwner {
        s_lockTimestamp = 0;

        if (s_gameStatus == GameStatus.Pending) {
            startGame();
        }
    }

    function resetDrawableCards() internal {
        delete s_drawableCards;

        for (uint8 i = 1; i < 53; i++) {
            s_cardToDrawCount[i] = 0;
            s_drawableCards.push(i);
        }
    }

    function sit(uint8 _seat) external whenUnlocked {
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

        if (!isGameStarted) {
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

    function placeBet(uint256 _amount) external payable whenBet checkCurrency nonReentrant {
        if (s_playerToState[msg.sender].bet > 0) {
            revert Table__BetAlreadyPlaced();
        }

        uint256 amount = s_token != address(0) ? _amount : msg.value;

        if (amount == 0 || amount < s_betRange.min) {
            revert Table__InsufficientBet();
        }
        if (amount > s_betRange.max) {
            revert Table__BetExceedsMax();
        }

        PlayerState storage state = s_playerToState[msg.sender];
        state.bet = amount;

        s_betTotal += amount;

        if (s_token != address(0)) {
            bool success = IERC20(s_token).transferFrom(msg.sender, address(this), _amount);

            if (!success) {
                revert Table__TokenTransferFailed();
            }
        }

        for (uint8 i = 0; i < s_players.length; i++) {
            address playerAddress = s_players[i];
            if (s_playerToState[playerAddress].bet == 0) return;
        }

        finalizeBets();
    }

    function clearDebt() external payable onlyOwner checkCurrency {
        if (s_token != address(0)) {
            bool success = IERC20(s_token).transferFrom(msg.sender, address(this), s_debt);

            if (!success) {
                revert Table__TokenTransferFailed();
            }
        } else if (msg.value != s_debt) {
            revert Table__InvalidDebtClearanceAmount();
        }

        s_debt = 0;
    }

    function finalizeBets() internal {
        Pit pit = Pit(payable(owner()));
        (uint256 balance, uint256 maxPayout) = pit.s_managerToTokenToState(s_manager, s_token);

        uint256 gameMaxPayout = getBlackJackPayout(s_betTotal);

        if (s_rules.allowDoubleAfterSplit) {
            gameMaxPayout *= 2 * s_rules.maxResplitHands;
        } else {
            gameMaxPayout *= (s_rules.maxResplitHands + 1);
        }

        s_gameMaxPayout = gameMaxPayout;
        pit.increaseMaxPayout(gameMaxPayout, s_token);

        if (maxPayout + gameMaxPayout > balance) {
            s_lockTimestamp = block.timestamp;
            s_gameStatus = GameStatus.Pending;
            emit TableLocked();
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
    
    function drawCard(Hand storage _hand) internal {
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

        _hand.cards.push(card);
        _hand.minValue += getCardMinValue(card);

        if (card < 5) {
            _hand.aceCount++;
        }
    }

    function getCardMinValue(uint8 _card) internal pure returns (uint8) {
        return uint8(Math.min(Math.ceilDiv(_card, 4), 10));
    }

    function getHandValue(Hand memory _hand) internal pure returns (uint8) {
        uint8 value = _hand.minValue;

        for (uint8 i = 0; i < _hand.aceCount; i++) {
            if (value + 10 < 21) {
                value += 10;
            } else {
                break;
            }
        }

        return value;
    }

    function getBlackJackPayout(uint256 _bet) internal view returns (uint256) {
        uint256 factor = s_rules.sixToFive ? 5 : 4;
        return _bet * 6 / factor;
    }

    function getActiveHand() internal view returns (Hand storage, uint256) {
        Hand[] storage hands = s_playerToState[msg.sender].hands;

        for (uint256 i = 0; i < hands.length; i++) {
            if (hands[i].status == HandStatus.Active) {
                return (hands[i], i);
            }
        }

        revert Table__NoActiveHand();
    }

    function split() payable external onlyCurrentPlayer checkCurrency nonReentrant {
        if (s_playerToState[msg.sender].hands.length == s_rules.maxResplitHands) {
            revert Table__MaxResplitHandsReached();
        }
        
        (Hand storage hand,) = getActiveHand();

        if (hand.cards.length > 2) {
            revert Table__CannotSplitAfterHit();
        }

        uint8 card1 = hand.cards[0];
        uint8 card2 = hand.cards[1];
        uint8 cardMinValue = getCardMinValue(card1);

        if (cardMinValue != getCardMinValue(card2)) {
            revert Table__CannotSplitOnDifferentCards();
        }

        increaseBet();

        drawCard(hand);
        hand.minValue -= cardMinValue;

        Hand memory newHand;
        newHand.minValue = cardMinValue;
        Hand[] storage hands = s_playerToState[msg.sender].hands;
        hands.push(newHand);
        hands[hands.length - 1].cards.push(card2);
    }

    function double() payable external onlyCurrentPlayer checkCurrency nonReentrant {
        (Hand storage hand,) = getActiveHand();

        if (hand.cards.length > 2) {
            revert Table__CannotDoubleAfterHit();
        }

        if (s_rules.doubleRule == DoubleRule.NineToEleven && (hand.minValue > 11 || hand.minValue < 9)) {
            revert Table__HandNotNineToEleven();
        }

        if (s_rules.doubleRule == DoubleRule.TenToEleven && (hand.minValue > 11 || hand.minValue < 10)) {
            revert Table__HandNotTenToEleven();
        }

        hand.doubled = true;
        increaseBet();
    }

    function increaseBet() internal {
        PlayerState storage state = s_playerToState[msg.sender];
        uint256 amount = state.bet;

        s_betTotal += amount;

        if (s_token == address(0)) {
            if (msg.value < amount) {
                revert Table__InsufficientBet();
            }
            if (msg.value > amount) {
                revert Table__BetExceedsMax();
            }
        } else {
            bool success = IERC20(s_token).transferFrom(msg.sender, address(this), amount);

            if (!success) {
                revert Table__TokenTransferFailed();
            }
        }
    }

    function hit() external onlyCurrentPlayer {
        (Hand storage hand, uint256 index) = getActiveHand();
        drawCard(hand);

        if (hand.minValue > 21) {
            finishHand(index, HandStatus.Bust);
        } else if (hand.doubled) {
            finishHand(index, HandStatus.Stand);
        }
    }

    function stand() external onlyCurrentPlayer {
        (, uint256 index) = getActiveHand();
        finishHand(index, HandStatus.Stand);
    }

    function finishHand(uint256 _index, HandStatus _status) internal {
        Hand[] storage hands = s_playerToState[msg.sender].hands;
        hands[_index].status = _status;

        if (_index == hands.length - 1) {
            nextTurn();
        } else {
            Hand storage nextHand = hands[_index + 1];
            drawCard(nextHand);
        }
    }

    function nextTurn() internal {
        uint256 playerIndex;

        for (uint256 i = 0; i < s_players.length; i++) {
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
        drawCard(s_dealerHand);
        uint256 dealerHandValue = getHandValue(s_dealerHand);

        if (dealerHandValue < 17 || (dealerHandValue == 17 && s_dealerHand.aceCount > 0 && s_rules.dealerHitOnSoft17)) {
            dealerPlay();
            return;
        }

        if (dealerHandValue > 21) {
            s_dealerHand.status = HandStatus.Bust;
        }

        int256 earnings;

        for (uint8 i = 0; i < s_players.length; i++) {
            PlayerState storage playerState = s_playerToState[s_players[i]];

            for (uint j = 0; j < playerState.hands.length; j++) {
                Hand memory hand = playerState.hands[j];
                uint256 bet = hand.doubled ? playerState.bet * 2 : playerState.bet;

                // If hand already busted
                if (hand.status == HandStatus.Bust) {
                    earnings += int256(bet);
                    continue;
                }

                uint256 handValue = getHandValue(hand);

                // If player wins
                if (handValue > dealerHandValue || s_dealerHand.status == HandStatus.Bust) {
                    uint256 payout = handValue == 21 ? getBlackJackPayout(bet) : bet;
                    playerState.balance += payout;
                    earnings -= int256(payout);
                    continue;
                }

                // If push/tie
                if (handValue == dealerHandValue) {
                    playerState.balance += bet;
                }
            }
        }

        uint256 ethEarnings;

        if (earnings < 0) {
            s_debt = uint256(-earnings); 
        } else if (earnings > 0) {
            if (s_token == address(0)) {
                ethEarnings = uint256(earnings);
            } else {
                IERC20(s_token).approve(owner(), uint256(earnings));
            }
        } 
        
        Pit(payable(owner())).gameEnded{value: ethEarnings}(s_token, earnings, s_gameMaxPayout);
        s_gameMaxPayout = 0;

        // Reset player bet and hands
        for (uint8 i = 0; i < s_players.length; i++) {
            address player = s_players[i];
            PlayerState storage playerState = s_playerToState[player];
            delete playerState.hands;
            playerState.bet = 0;
        }

        // NOTE: Should not happen after clearDebt call from Pit - test invariant
        if (s_debt > 0) {
            s_lockTimestamp = block.timestamp;
            s_gameStatus = GameStatus.Inactive;
            return;
        }

        s_gameStatus = s_continuousPlay ? GameStatus.Bet : GameStatus.Inactive;
    }
}
