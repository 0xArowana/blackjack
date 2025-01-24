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
    error Table__InvalidBetAmount();
    error Table__InvalidDebtClearanceAmount();
    error Table__InvalidDeckCount();
    error Table__InvalidMaxResplitHands();
    error Table__InvalidSeat();
    error Table__InvalidSeatCount();
    error Table__InvalidPlayer();
    error Table__Locked();
    error Table__NoCards();
    error Table__NotEmpty();
    error Table__PlayerAlreadySeated();
    error Table__PlayerNotFound();
    error Table__SeatOccupied();
    error Table__BetAlreadyPlaced();
    error Table__BetLessThanMin();
    error Table__BettingInProgress();
    error Table__GameInProgress();
    error Table__MaxResplitHandsReached();
    error Table__NoActiveHand();
    error Table__NoBalanceAvailable();
    error Table__NotBetStatus();
    error Table__NotCurrentSeat();
    error Table__NotInactiveStatus();
    error Table__NotManager();
    error Table__NotPlayerTurnStatus();
    error Table__CashOutTransferFailed();
    error Table__TokenTransferFailed();

    /// @notice The player, bet, hands, and balance of a seat
    struct Seat {
        address player;
        uint256 bet;
        Hand[] hands;
        bool waiting;
    }

    struct TableInfo {
        address id;
        address manager;
        address token;
        GameStatus gameStatus;
        SeatInfo[] seats;
        uint8 seatCount;
        Rules rules;
    }

    struct SeatInfo {
        address player;
        uint256 bet;
        bool waiting;
    }

    /// @notice Determines the hand value forward which the bet can be doubled
    enum DoubleRule {
        Any,
        NineToEleven,
        TenToEleven
    }

    /// @notice Standard blackjack parameters by which the game logic operates
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

    // @notice The range in which bets may be placed
    struct BetRange {
        uint256 min;
        uint256 max;
    }

    // @notice A list of cards and other details for a hand
    struct Hand {
        uint8[] cards;
        uint8 minValue;
        uint8 aceCount;
        HandStatus status;
        bool doubled;
    }

    // @notice The status of a hand
    enum HandStatus {
        Active,
        Stand,
        Bust
    }

    // @notice The status of the current game
    enum GameStatus {
        Inactive,
        Bet,
        Pending,
        Insurance,
        PlayerTurn,
        DealerTurn
    }

    address public s_token;
    address public s_manager;
    mapping (uint8 => Seat) internal s_seats;
    mapping(address => uint256) internal s_playerToBalance;
    uint256 public s_lockTimestamp;
    GameStatus public s_gameStatus;
    Hand internal s_dealerHand;
    uint8 internal s_currentSeatIndex;
    Rules internal s_rules;
    BetRange internal s_betRange;
    uint8 internal s_seatCount;
    uint256 internal s_debt;
    uint256 internal s_betTotal;
    uint256 internal s_gameMaxPayout;
    uint256[] internal s_randomWords;
    uint8[] internal s_drawableCards;
    mapping(uint8 => uint8) internal s_cardToDrawCount;
    bool internal s_continuousPlay;

    event BetsStarted();
    event GameStarted();
    event Hit(uint8 indexed card);
    event PlayerSeated(address indexed player, uint8 indexed seat);
    event TableLocked();

    modifier onlyManager {
        if (msg.sender != address(s_manager)) {
            revert Table__NotManager();
        }
        _;
    }

    modifier onlyCurrentSeat {
        if (s_gameStatus != GameStatus.PlayerTurn) {
            revert Table__NotPlayerTurnStatus();
        }
        if (msg.sender != s_seats[s_currentSeatIndex].player) {
            revert Table__NotCurrentSeat();
        }
        _;
    }

    modifier whenEmpty {
        for (uint8 i = 0; i < 7; i++) {
            if (s_seats[i].player != address(0)) {
                revert Table__NotEmpty();
            }
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
        if (s_lockTimestamp != 0) {
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

    // constructor() {
    //     _disableInitializers();
    // }

    function initialize(
        address _manager,  
        uint8 _seatCount,
        BetRange memory _betRange,
        Rules memory _rules,
        address _token
    ) public initializer {
        if (_seatCount < 1 || _seatCount > 7) {
            revert Table__InvalidSeatCount();
        }

        if (_rules.maxResplitHands < 2 || _rules.maxResplitHands > 4) {
            revert Table__InvalidMaxResplitHands();
        }

        if (_rules.deckCount > 8 || _rules.deckCount == 3 || _rules.deckCount == 7) {
            revert Table__InvalidDeckCount();
        }

        __Ownable_init(msg.sender);

        s_manager = _manager;
        s_seatCount = _seatCount;
        s_betRange = _betRange;
        s_rules = _rules; // TODO: validate rules
        s_token = _token;

        resetDrawableCards();
        refreshRandomWords();
    }

    function getTableInfo() external view returns(TableInfo memory) {
        SeatInfo[] memory seatInfo;

        for (uint8 i = 0; i < s_seatCount; i++) {
            Seat storage seat = s_seats[i];

            if (seat.player != address(0)) {
                seatInfo[i] = SeatInfo(seat.player, seat.bet, seat.waiting);
            }
        }

        TableInfo memory tableInfo = TableInfo(
            address(this),
            s_manager,
            s_token,
            s_gameStatus,
            seatInfo,
            s_seatCount,
            s_rules
        );

        return tableInfo;
    }

    function setSeatCount(uint8 _seatCount) external onlyManager whenInactive whenEmpty whenUnlocked {
        if (_seatCount < 1 || _seatCount > 7) {
            revert Table__InvalidSeatCount();
        }
        
        s_seatCount = _seatCount;
    }
    
    function setBetRange(BetRange memory _betRange) external onlyManager whenInactive whenUnlocked {
        s_betRange = _betRange;
    }

    function setToken(address _token) external onlyManager whenInactive whenUnlocked whenEmpty {
        s_token = _token;
    }

    function setRandomWords(uint256[] calldata _randomWords) external onlyOwner {
        s_randomWords = _randomWords;
    }

    function startBets() external onlyManager whenInactive whenUnlocked {
        s_gameStatus = GameStatus.Bet;
        emit BetsStarted();
    }

    function sit(uint8 _index) external whenUnlocked {
        if (msg.sender == s_manager) {
            revert Table__InvalidPlayer();
        }
        if (_index >= s_seatCount || _index < 0) {
            revert Table__InvalidSeat();
        }
        if (s_seats[_index].player != address(0)) {
            revert Table__SeatOccupied();
        }

        Pit pit = Pit(payable(owner()));
        address table = pit.s_playerToTable(msg.sender);

        if (table != address(0) && table != address(this)) {
            revert Table__PlayerAlreadySeated();
        }

        Seat storage seat = s_seats[_index];
        seat.waiting = s_gameStatus != GameStatus.Inactive && s_gameStatus != GameStatus.Bet;
        seat.player = msg.sender;

        pit.playerSeated(msg.sender);
        emit PlayerSeated(msg.sender, _index);
    }

    function leave(uint8 _seatIndex) external whenInactiveOrBet whenUnlocked {
        Seat storage seat = s_seats[_seatIndex];

        if (seat.player != msg.sender) {
            revert Table__InvalidSeat();
        }

        if (seat.bet > 0) {
            s_playerToBalance[msg.sender] += seat.bet;
            s_betTotal -= seat.bet;
        }

        seat.player = address(0);
        seat.bet = 0;
        delete seat.hands;
        seat.waiting = false;

        bool playerAtTable = false;
        bool missingBet = false;

        for (uint8 i = 0; i < s_seatCount; i++) {
            Seat storage s = s_seats[i];
            
            if (s.player == msg.sender) {
                playerAtTable = true;
            }

            if (s.bet == 0) {
                missingBet = true;
            }
        }

        if (!playerAtTable) {
            // TODO: Should remaining balance value be stored on pit to notify user?
            Pit(payable(owner())).playerLeft(msg.sender);
        }

        // Start game if all remaining players placed bets
        if (s_gameStatus == GameStatus.Bet && !missingBet) {
            finalizeBets();
        }
    }

    function placeBet(uint256 _amount, uint8 _seatIndex) external payable whenBet whenUnlocked checkCurrency nonReentrant {
        Seat storage seat = s_seats[_seatIndex];

        if (seat.player != msg.sender) {
            revert Table__InvalidSeat();
        }
        if (seat.bet > 0) {
            revert Table__BetAlreadyPlaced();
        }

        uint256 amount = s_token != address(0) ? _amount : msg.value;

        if (amount < s_betRange.min || amount > s_betRange.max) {
            revert Table__InvalidBetAmount();
        }

        // All bets from the same player must be the same amount
        for (uint8 i = 0; i < s_seatCount; i++) {
            if (i == _seatIndex) continue;

            Seat storage s = s_seats[i];
            
            if (s.player == msg.sender && s.bet > 0 && s.bet != amount) {
                revert Table__InvalidBetAmount();
            }
        }

        seat.bet = amount;
        s_betTotal += amount;

        if (s_token != address(0)) {
            bool success = IERC20(s_token).transferFrom(msg.sender, address(this), _amount);

            if (!success) {
                revert Table__TokenTransferFailed();
            }
        }

        for (uint8 i = 0; i < s_seatCount; i++) {
            Seat storage s = s_seats[i];
            if (s.player != address(0) && s.bet == 0) return;
        }

        finalizeBets();
    }

    function double() payable external onlyCurrentSeat whenUnlocked checkCurrency nonReentrant {
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

    function hit() external onlyCurrentSeat whenUnlocked {
        (Hand storage hand, uint256 index) = getActiveHand();
        drawCard(hand);

        if (hand.minValue > 21) {
            finishHand(index, HandStatus.Bust);
        } else if (hand.doubled) {
            finishHand(index, HandStatus.Stand);
        }
    }

    function stand() external onlyCurrentSeat whenUnlocked {
        (, uint256 index) = getActiveHand();
        finishHand(index, HandStatus.Stand);
    }

    function split() payable external onlyCurrentSeat whenUnlocked checkCurrency nonReentrant {
        Seat storage seat = s_seats[s_currentSeatIndex];

        if (seat.hands.length == s_rules.maxResplitHands) {
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
        Hand[] storage hands = seat.hands;
        hands.push(newHand);
        hands[hands.length - 1].cards.push(card2);
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
        s_lockTimestamp = 0;
    }

    function cashOut() external whenUnlocked nonReentrant {
        uint256 amount = s_playerToBalance[msg.sender];

        if (amount == 0) {
            revert Table__NoBalanceAvailable();
        }

        // CEI: Zero out balance before external calls
        s_playerToBalance[msg.sender] = 0;

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

    function startGame() internal {
        for (uint8 i = 0; i < s_seatCount; i++) {
            Seat storage seat = s_seats[i];
            if (seat.player == address(0)) continue;

            Hand storage hand = seat.hands[0];
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

    function resetDrawableCards() internal {
        delete s_drawableCards;

        for (uint8 i = 1; i < 53; i++) {
            s_cardToDrawCount[i] = 0;
            s_drawableCards.push(i);
        }
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

    function refreshRandomWords() internal {
        Pit(payable(owner())).requestRandomWords();
    }

    function increaseBet() internal {
        uint256 amount = s_seats[s_currentSeatIndex].bet;

        // CEI: Update bet total before external calls
        s_betTotal += amount;

        if (s_token == address(0)) {
            if (msg.value < amount || msg.value > amount) {
                revert Table__InvalidBetAmount();
            }
        } else {
            bool success = IERC20(s_token).transferFrom(msg.sender, address(this), amount);

            if (!success) {
                revert Table__TokenTransferFailed();
            }
        }
    }

    function finishHand(uint256 _index, HandStatus _status) internal {
        Hand[] storage hands = s_seats[s_currentSeatIndex].hands;
        hands[_index].status = _status;

        if (_index == hands.length - 1) {
            nextTurn();
        } else {
            Hand storage nextHand = hands[_index + 1];
            drawCard(nextHand);
        }
    }

    function nextTurn() internal {
        uint8 nextSeatIndex;

        for (uint8 i = s_currentSeatIndex + 1; i < s_seatCount; i++) {
            if (isSeatActive(s_seats[i])) {
                nextSeatIndex = i;
                break;
            } 
        }

        s_currentSeatIndex = nextSeatIndex;

        if (nextSeatIndex == 0) {
            s_gameStatus = GameStatus.DealerTurn;
            dealerPlay();
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

        for (uint8 i = 0; i < s_seatCount; i++) {
            Seat storage seat = s_seats[i];
            if (!isSeatActive(seat)) continue;

            for (uint j = 0; j < seat.hands.length; j++) {
                Hand memory hand = seat.hands[j];
                uint256 bet = hand.doubled ? seat.bet * 2 : seat.bet;

                // If hand already busted
                if (hand.status == HandStatus.Bust) {
                    earnings += int256(bet);
                    continue;
                }

                uint256 handValue = getHandValue(hand);

                // If player wins
                if (handValue > dealerHandValue || s_dealerHand.status == HandStatus.Bust) {
                    bool isBlackjack = handValue == 21 && hand.cards.length == 2;
                    uint256 payout = isBlackjack ? getBlackJackPayout(bet) : bet;
                    s_playerToBalance[seat.player] += payout;
                    earnings -= int256(payout);
                    continue;
                }

                // If push/tie
                if (handValue == dealerHandValue) {
                    s_playerToBalance[seat.player] += bet;
                }
            }
        }

        uint256 ethEarnings;

        if (earnings < 0) {
            s_debt = uint256(-earnings);
            s_lockTimestamp = block.timestamp; // Lock will be removed when Pit calls clearDebt
        } else if (earnings > 0) {
            if (s_token == address(0)) {
                ethEarnings = uint256(earnings);
            } else {
                IERC20(s_token).approve(owner(), uint256(earnings));
            }
        } 
        
        Pit(payable(owner())).gameEnded{value: ethEarnings}(s_token, earnings, s_gameMaxPayout);
        s_gameMaxPayout = 0;

        // Reset bets and hands, and seat waiting players
        for (uint8 i = 1; i <= s_seatCount; i++) {
            Seat storage seat = s_seats[i];
            if (seat.player == address(0)) continue;

            seat.bet = 0;
            delete seat.hands;
            seat.waiting = false;
        }

        bool skipInactive = s_continuousPlay && s_lockTimestamp == 0;
        s_gameStatus = skipInactive ? GameStatus.Bet : GameStatus.Inactive;
    }

    function isSeatActive(Seat storage _seat) internal view returns (bool) {
        return _seat.player != address(0) && !_seat.waiting;
    }

    function getBlackJackPayout(uint256 _bet) internal view returns (uint256) {
        uint256 factor = s_rules.sixToFive ? 5 : 4;
        return _bet * 6 / factor;
    }

    function getActiveHand() internal view returns (Hand storage hand, uint256 index) {
        Hand[] storage hands = s_seats[s_currentSeatIndex].hands;

        for (uint256 i = 0; i < hands.length; i++) {
            if (hands[i].status == HandStatus.Active) {
                return (hands[i], i);
            }
        }

        revert Table__NoActiveHand();
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
}
