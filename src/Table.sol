// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ITable} from "./interfaces/ITable.sol";
import {IPit} from "./interfaces/IPit.sol";

contract Table is ITable, Initializable, OwnableUpgradeable, ReentrancyGuard {
    error Table__CannotDoubleAfterHit();
    error Table__CannotSplitAfterHit();
    error Table__CannotSplitOnDifferentCards();
    error Table__CurrencyNotEth();
    error Table__HandNotNineToEleven();
    error Table__HandNotTenToEleven();
    error Table__InsufficientManagerBalance();
    error Table__InvalidBetAmount();
    error Table__InvalidDebtClearanceAmount();
    error Table__InvalidDeckCount();
    error Table__InvalidDeckReset();
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

    /// @notice The info and hands of a seat
    struct Seat {
        SeatInfo info;
        Hand[] hands;
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

    enum DrawRequest {
        None,
        Start,
        Split,
        Hit,
        Dealer
    }

    address internal s_token;
    address internal s_manager;
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
    uint8[] internal s_drawableCards;
    DrawRequest internal s_drawRequest;
    mapping(uint8 => uint8) internal s_cardToDrawCount;
    uint16 internal s_totalCardsDrawn;
    bool internal s_continuousPlay;

    event BetPlaced(address indexed player, uint256 indexed amount);
    event BetsStarted();
    event CardDrawn(uint8 indexed card);
    event RandomWordsFulfilled(DrawRequest indexed drawRequest);
    event GameStarted();
    event Hit(uint8 indexed card);
    event PlayerSeated(address indexed player, uint8 indexed seat);
    event PlayerLeft(address indexed player, uint8 indexed seat);
    event TableLocked();

    event WillCreateHand();
    event HandSet();

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
        if (msg.sender != s_seats[s_currentSeatIndex].info.player) {
            revert Table__NotCurrentSeat();
        }
        _;
    }

    modifier whenEmpty {
        for (uint8 i = 0; i < 7; i++) {
            if (s_seats[i].info.player != address(0)) {
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

    constructor() {
        _disableInitializers();
    }

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

        if (_rules.deckCount < 6 && _rules.deckReset != DeckReset.EveryHand) {
            revert Table__InvalidDeckReset();
        }

        IPit pit = IPit(msg.sender);
        IPit.TokenState memory tokenState = pit.getManagerTokenState(_manager, _token);
        uint256 availableBalance = tokenState.balance - tokenState.allocated;
        uint256 maxBetTotal = _betRange.max * _seatCount;
        uint256 newAllocation = getMaxPayout(maxBetTotal);

        if (availableBalance < newAllocation) {
            revert Table__InsufficientManagerBalance();
        }

        __Ownable_init(msg.sender);

        s_manager = _manager;
        s_seatCount = _seatCount;
        s_betRange = _betRange;
        s_rules = _rules; // TODO: validate rules
        s_token = _token;

        pit.allocate(newAllocation, _token);
    }

    function token() external view returns (address) {
        return s_token;
    }

    function manager() external view returns (address) {
        return s_manager;
    }

    function getTableInfo() external view returns(TableInfo memory) {
        SeatInfo[] memory seats = new SeatInfo[](s_seatCount);

        for (uint8 i = 0; i < s_seatCount; i++) {
            seats[i] = s_seats[i].info;
        }

        IPit.TokenInfo memory tokenInfo = IPit.TokenInfo(
            s_token,
            ERC20(s_token).symbol(), 
            ERC20(s_token).name(),
            ERC20(s_token).decimals()
        );

        TableInfo memory tableInfo = TableInfo(
            address(this),
            s_manager,
            tokenInfo,
            s_gameStatus,
            seats,
            s_seatCount,
            s_betRange,
            s_rules,
            s_lockTimestamp
        );

        return tableInfo;
    }

    function getSeats() external view returns(Seat[] memory) {
        Seat[] memory seats = new Seat[](s_seatCount);

        for (uint8 i = 0; i < s_seatCount; i++) {
            seats[i] = s_seats[i];
        }

        return seats;
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
        if (s_seats[_index].info.player != address(0)) {
            revert Table__SeatOccupied();
        }

        IPit pit = IPit(owner());
        address table = pit.getPlayerTable(msg.sender);

        if (table != address(0) && table != address(this)) {
            revert Table__PlayerAlreadySeated();
        }

        SeatInfo storage seatInfo = s_seats[_index].info;
        seatInfo.waiting = s_gameStatus != GameStatus.Inactive && s_gameStatus != GameStatus.Bet;
        seatInfo.player = msg.sender;

        pit.playerSeated(msg.sender);
        emit PlayerSeated(msg.sender, _index);
    }

    // TODO: Accept multiple indices (allows leaving table entirely in one transaction)
    function leave(uint8 _index) external whenInactiveOrBet whenUnlocked {
        SeatInfo storage seatInfo = s_seats[_index].info;

        if (seatInfo.player != msg.sender) {
            revert Table__InvalidSeat();
        }

        if (seatInfo.bet > 0) {
            s_playerToBalance[msg.sender] += seatInfo.bet;
            s_betTotal -= seatInfo.bet;
        }

        seatInfo.player = address(0);
        seatInfo.bet = 0;
        seatInfo.waiting = false;
        delete s_seats[_index].hands;
        
        bool playerAtTable = false;
        bool missingBet = false;

        for (uint8 i = 0; i < s_seatCount; i++) {
            SeatInfo storage info = s_seats[i].info;
            
            if (info.player == msg.sender) {
                playerAtTable = true;
            }

            if (info.bet == 0) {
                missingBet = true;
            }
        }

        if (!playerAtTable) {
            // TODO: Should remaining balance value be stored on pit to notify user?
            IPit(owner()).playerLeft(msg.sender);
        }

        emit PlayerLeft(msg.sender, _index);

        // Start game if all remaining players placed bets
        if (s_gameStatus == GameStatus.Bet && !missingBet) {
            finalizeBets();
        }
    }

    function placeBet(uint256 _amount) external payable whenBet whenUnlocked checkCurrency nonReentrant {
        uint256 amount = s_token != address(0) ? _amount : msg.value;

        if (amount < s_betRange.min || amount > s_betRange.max) {
            revert Table__InvalidBetAmount();
        }

        uint256 totalAmount = 0;
        bool missingBet = false;
        bool playerFound = false;

        for (uint8 i = 0; i < s_seatCount; i++) {
            SeatInfo storage seatInfo = s_seats[i].info;

            if (seatInfo.player == address(0)) {
                continue;
            }

            if (seatInfo.player == msg.sender) {
                if  (seatInfo.bet > 0) {
                    revert Table__BetAlreadyPlaced();
                }

                seatInfo.bet = amount;
                totalAmount += amount;
                playerFound = true;
            } else if (seatInfo.bet == 0) {
                missingBet = true;
            }
        }

        if (!playerFound) {
            revert Table__PlayerNotFound();
        }

        s_betTotal += totalAmount;

        if (s_token == address(0)) {
            if (msg.value != totalAmount) {
                revert Table__InvalidBetAmount();
            }
        } else {
            bool success = ERC20(s_token).transferFrom(msg.sender, address(this), totalAmount);

            if (!success) {
                revert Table__TokenTransferFailed();
            }
        }

        emit BetPlaced(msg.sender, _amount);

        if (!missingBet) {
            finalizeBets();
        }
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

    function requestSplit() payable external onlyCurrentSeat whenUnlocked checkCurrency nonReentrant {
        Seat storage seat = s_seats[s_currentSeatIndex];

        if (seat.hands.length == s_rules.maxResplitHands) {
            revert Table__MaxResplitHandsReached();
        }

        (Hand storage hand,) = getActiveHand();

        if (hand.cards.length > 2) {
            revert Table__CannotSplitAfterHit();
        }

        if (getCardMinValue(hand.cards[0]) != getCardMinValue(hand.cards[1])) {
            revert Table__CannotSplitOnDifferentCards();
        }

        increaseBet();

        draw(DrawRequest.Split, 2);
    }

    function requestHit() external onlyCurrentSeat whenUnlocked {
        draw(DrawRequest.Hit, 1);
    }

    function stand() external onlyCurrentSeat whenUnlocked {
        (, uint256 index) = getActiveHand();
        finishHand(index, HandStatus.Stand);
    }

    function clearDebt() external payable onlyOwner checkCurrency {
        if (s_token != address(0)) {
            bool success = ERC20(s_token).transferFrom(msg.sender, address(this), s_debt);

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
            success = ERC20(s_token).transfer(msg.sender, amount);
        }

        if (!success) {
            revert Table__CashOutTransferFailed();
        }
    }

    function fulfillRandomWords(uint256[] calldata _randomWords) external onlyOwner {
        emit RandomWordsFulfilled(s_drawRequest);
        s_lockTimestamp = 0;

        if (s_drawRequest == DrawRequest.Start) {
            initialDeal(_randomWords);
        } else if (s_drawRequest == DrawRequest.Split) {  
            split(_randomWords);
        } else if (s_drawRequest == DrawRequest.Hit) {  
            hit(_randomWords);
        } else if (s_drawRequest == DrawRequest.Dealer) {
            dealerPlay(_randomWords);
        }

        s_drawRequest = DrawRequest.None;
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
        if (shouldResetDecks()) {
            resetDecks();
        }
        
        uint32 numWords = 1;

        for (uint8 i = 0; i < s_seatCount; i++) {
            if (s_seats[i].info.player != address(0)) {
                numWords += 2;
            }
        }

        draw(DrawRequest.Start, numWords);
    }

    function shouldResetDecks() internal view returns(bool) {
        if (s_rules.deckReset == DeckReset.EveryHand) {
            return true;
        }

        uint16 totalCards = uint16(s_rules.deckCount) * 52;
        uint16 cardsLeft = s_rules.deckReset == DeckReset.TwoDecksLeft ? 104 : 208;
        uint16 maxDrawCount = totalCards - cardsLeft;
        return s_totalCardsDrawn >= maxDrawCount;
    }

    function resetDecks() internal {
        s_totalCardsDrawn = 0;
        delete s_drawableCards;

        for (uint8 i = 1; i < 53; i++) {
            s_cardToDrawCount[i] = 0;
            s_drawableCards.push(i);
        }
    }

    function finalizeBets() internal {
        IPit pit = IPit(owner());
        IPit.TokenState memory tokenState = pit.getManagerTokenState(s_manager, s_token);

        uint256 gameMaxPayout = getMaxPayout(s_betTotal);
        s_gameMaxPayout = gameMaxPayout;
        pit.allocate(gameMaxPayout, s_token);

        if (tokenState.allocated + gameMaxPayout > tokenState.balance) {
            s_lockTimestamp = block.timestamp;
            s_gameStatus = GameStatus.Pending;
            emit TableLocked();
        } else {
            startGame();
        }
    }
    
    function draw(DrawRequest _drawRequest, uint32 _numWords) internal {
        s_drawRequest = _drawRequest;
        s_lockTimestamp = block.timestamp;
        IPit(owner()).requestRandomWords(_numWords);
    }

    function addCardToHand(Hand storage _hand, uint256[] calldata _randomWords) internal {
        uint256 randomWord = _randomWords[_randomWords.length - 1];
        uint8 cardIndex = uint8(randomWord % s_drawableCards.length);
        uint8 card = s_drawableCards[cardIndex];

        s_cardToDrawCount[card]++;
        s_totalCardsDrawn++;

        // Remove card from drawable cards if drawn max number of times
        // Reset drawable cards if all drawn
        if (s_cardToDrawCount[card] == s_rules.deckCount) {
            for (uint8 i = cardIndex; i < s_drawableCards.length; i++) {
                s_drawableCards[i] = s_drawableCards[i + 1];
            }

            s_drawableCards.pop();
        }

        _hand.cards.push(card);
        _hand.minValue += getCardMinValue(card);

        if (card < 5) {
            _hand.aceCount++;
        }
    }

    function initialDeal(uint256[] calldata _randomWords) internal {
        for (uint8 i = 0; i < s_seatCount; i++) {
            Seat storage seat = s_seats[i];
            if (seat.info.player == address(0)) continue;

            Hand memory newHand;
            seat.hands.push(newHand);
    
            Hand storage hand = seat.hands[0];
            addCardToHand(hand, _randomWords);
            addCardToHand(hand, _randomWords);
        }

        addCardToHand(s_dealerHand, _randomWords);
        uint256 value = s_dealerHand.minValue;

        if (s_rules.allowInsurance && (value == 10 || value == 1)) {
            s_gameStatus = GameStatus.Insurance;
        } else {
            s_gameStatus = GameStatus.PlayerTurn;
        }

        emit GameStarted();
    }

    function split(uint256[] calldata _randomWords) internal {
        (Hand storage hand1,) = getActiveHand();
        uint8 splitCard = hand1.cards[1];
        uint8 cardValue = getCardMinValue(splitCard);

        addCardToHand(hand1, _randomWords);
        hand1.minValue -= cardValue;

        Hand memory newHand;
        Hand[] storage hands = s_seats[s_currentSeatIndex].hands;
        hands.push(newHand);

        Hand storage hand2 = hands[hands.length - 1];
        hand2.cards.push(splitCard);
        hand2.minValue = cardValue;
        hand2.aceCount = cardValue == 1 ? 1 : 0;
        addCardToHand(hand2, _randomWords);
    }

    function hit(uint256[] calldata _randomWords) internal {
        (Hand storage hand, uint256 index) = getActiveHand();
        addCardToHand(hand, _randomWords);

        if (hand.minValue > 21) {
            finishHand(index, HandStatus.Bust);
        } else if (hand.minValue == 21 || hand.doubled) {
            finishHand(index, HandStatus.Stand);
        }
    }

    function increaseBet() internal {
        uint256 amount = s_seats[s_currentSeatIndex].info.bet;

        // CEI: Update bet total before external calls
        s_betTotal += amount;

        if (s_token == address(0)) {
            if (msg.value < amount || msg.value > amount) {
                revert Table__InvalidBetAmount();
            }
        } else {
            bool success = ERC20(s_token).transferFrom(msg.sender, address(this), amount);

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
        }
    }

    function nextTurn() internal {
        uint8 nextSeatIndex;

        for (uint8 i = s_currentSeatIndex + 1; i < s_seatCount; i++) {
            if (isSeatActive(s_seats[i].info)) {
                nextSeatIndex = i;
                break;
            } 
        }

        s_currentSeatIndex = nextSeatIndex;

        if (nextSeatIndex == 0) {
            s_gameStatus = GameStatus.DealerTurn;
            draw(DrawRequest.Dealer, 12);
        }
    }

    function dealerPlay(uint256[] calldata _randomWords) internal {
        addCardToHand(s_dealerHand, _randomWords);
        uint256 dealerHandValue = getHandValue(s_dealerHand);

        if (dealerHandValue < 17 || (dealerHandValue == 17 && s_dealerHand.aceCount > 0 && s_rules.dealerHitOnSoft17)) {
            dealerPlay(_randomWords);
            return;
        }

        if (dealerHandValue > 21) {
            s_dealerHand.status = HandStatus.Bust;
        }

        int256 earnings;

        for (uint8 i = 0; i < s_seatCount; i++) {
            Seat storage seat = s_seats[i];
            if (!isSeatActive(seat.info)) continue;

            for (uint j = 0; j < seat.hands.length; j++) {
                Hand memory hand = seat.hands[j];
                uint256 bet = hand.doubled ? seat.info.bet * 2 : seat.info.bet;

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
                    s_playerToBalance[seat.info.player] += payout;
                    earnings -= int256(payout);
                    continue;
                }

                // If push/tie
                if (handValue == dealerHandValue) {
                    s_playerToBalance[seat.info.player] += bet;
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
                ERC20(s_token).approve(owner(), uint256(earnings));
            }
        } 
        
        IPit(owner()).gameEnded{value: ethEarnings}(s_token, earnings, s_gameMaxPayout);
        s_gameMaxPayout = 0;

        // Reset bets and hands, and seat waiting players
        for (uint8 i = 1; i <= s_seatCount; i++) {
            SeatInfo storage seatInfo = s_seats[i].info;
            if (seatInfo.player == address(0)) continue;

            seatInfo.bet = 0;
            seatInfo.waiting = false;
            delete s_seats[i].hands;
        }

        bool skipInactive = s_continuousPlay && s_lockTimestamp == 0;
        s_gameStatus = skipInactive ? GameStatus.Bet : GameStatus.Inactive;
    }

    function getMaxPayout(uint256 _bet) internal view returns (uint256) {
        uint256 maxPayout = getBlackJackPayout(_bet);

        if (s_rules.allowDoubleAfterSplit) {
            maxPayout *= 2 * s_rules.maxResplitHands;
        } else {
            maxPayout *= (s_rules.maxResplitHands + 1);
        }

        return maxPayout;
    }

    function isSeatActive(SeatInfo storage _seatInfo) internal view returns (bool) {
        return _seatInfo.player != address(0) && !_seatInfo.waiting;
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
