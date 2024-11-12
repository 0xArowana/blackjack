// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pit} from "./Pit.sol";

contract Table is Initializable, OwnableUpgradeable, ReentrancyGuard {
    error Table__BetTransferFailed();
    error Table__InvalidBet();
    error Table__InvalidSeat();
    error Table__InvalidMaxPlayers();
    error Table__InvalidPlayer();
    error Table__NoCards();
    error Table__NotEmpty();
    error Table__PlayerNotFound();
    error Table__SeatOccupied();
    error Table__BetAlreadyPlaced();
    error Table__BetGreaterThanMax();
    error Table__BetLessThanMin();
    error Table__BettingInProgress();
    error Table__GameInProgress();
    error Table__LiquidationGracePeriod();
    error Table__NoRefundAvailable();
    error Table__NotBetStatus();
    error Table__NotCurrentPlayer();
    error Table__NotInactiveStatus();
    error Table__NotPlayerTurnStatus();
    error Table__RefundTransferFailed();
    error Table__UsesEth();
    error Table__UsesToken();

    address[] s_players;
    mapping(address => PlayerState) public s_playerToState;
    mapping(uint8 => address) public s_seatToPlayer;
    BetRange s_betRange;
    Rules s_rules;
    uint8 internal s_maxPlayers;
    address public s_token;
    address public s_manager;
    uint256[] internal s_randomWords;
    uint256 internal s_betTotal;
    bool s_continuousPlay;    
    
    GameStatus internal s_gameStatus;
    uint8[] internal s_dealerHand;
    address internal s_currentPlayer;

    struct Rules {
        uint8 deckCount;
        bool sixToFive;
        bool dealerHitOnSoft17;
        bool allowDoubleAfterSplit;
        uint8 maxResplitHands;
        bool allowResplitAces;
        bool allowHitSplitAces;
        bool allowLateSurrender;
    }

    struct BetRange {
        uint256 min;
        uint256 max;
    }

    struct PlayerState {
        uint8 seat;
        uint256 bet;
        uint8[] hand;
        uint256 refund;
    }

    enum GameStatus {
        Inactive,
        Bet,
        PlayerTurn,
        DealerTurn
    }

    event BetsStarted();
    event GameStarted();

    modifier onlyCurrentPlayer {
        if (s_gameStatus != GameStatus.PlayerTurn) {
            revert Table__NotPlayerTurnStatus();
        }
        if (msg.sender == address(s_currentPlayer)) {
            revert Table__NotCurrentPlayer();
        }
        _;
    }

    modifier onlyEth {
        if (s_token != address(0)) {
            revert Table__UsesEth();
        }
        _;
    }

    modifier onlyToken {
        if (s_token == address(0)) {
            revert Table__UsesToken();
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

    modifier handleBet(uint256 _amount) {
        if (s_gameStatus != GameStatus.Bet) {
            revert Table__NotBetStatus();
        }
        if (_amount == 0) {
            revert Table__InvalidBet();
        }
        if (s_betRange.max != 0 && _amount > s_betRange.max) {
            revert Table__BetGreaterThanMax();
        }
        if (_amount < s_betRange.min) {
            revert Table__BetGreaterThanMax();
        }
        if (s_playerToState[msg.sender].bet > 0) {
            revert Table__BetAlreadyPlaced();
        }

        s_playerToState[msg.sender].bet = _amount;
        s_betTotal += _amount;
    
        _;

        for (uint8 i = 0; i < s_players.length; i++) {
            address playerAddress = s_players[i];
            if (s_playerToState[playerAddress].bet == 0) return;
        }

        startGame();
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
        s_rules = _rules;
        s_token = _token;

        refreshRandomWords();
    }

    function getMinManagerBalance() internal view returns (uint256) {
        uint256 minBalance = 0;

        for (uint8 i = 0; i < s_players.length; i++) {
            address player = s_players[i];
            minBalance += s_playerToState[player].bet;
        }

        return minBalance;
    }

    function claimRefund() external {
        uint256 amount = s_playerToState[msg.sender].refund;

        if (amount == 0) {
            revert Table__NoRefundAvailable();
        }

        bool success = IERC20(s_token).transfer(msg.sender, amount);

        if (!success) {
            revert Table__RefundTransferFailed();
        }

        s_playerToState[msg.sender].refund = 0;
    }

    function startBets() external onlyOwner whenInactive {
        s_gameStatus = GameStatus.Bet;
        emit BetsStarted();
    }

    function startGame() internal {
        Pit pit = Pit(payable(owner()));
        (
            uint256 balance, 
            uint256 maxPayout
        ) = pit.s_managerToTokenToState(s_manager, s_token);
        uint256 bjPayoutFactor = s_rules.sixToFive ? 5 : 4;

        uint256 newMaxPayout = maxPayout;

        if (s_rules.allowDoubleAfterSplit) {
            newMaxPayout += s_betTotal * 2 * s_rules.maxResplitHands * 6 / bjPayoutFactor;
        } else {
            newMaxPayout += s_betTotal * (s_rules.maxResplitHands + 1) * 6 / bjPayoutFactor;
        }

        if (newMaxPayout < balance) {
            // TODO: restore lock logic
            return;
        }

        initialDeal();
        s_gameStatus = GameStatus.PlayerTurn;
        emit GameStarted();
    }

    function resetGame() external onlyOwner {
        uint256 betsToRemove = 0;

        for (uint8 i = 0; i < s_players.length; i++) {
            address player = s_players[i];
            uint256 bet = s_playerToState[player].bet;
            betsToRemove += bet;
            s_playerToState[player].refund = bet;
            s_playerToState[player].bet = 0;
            delete s_playerToState[player].hand;
        }

        s_gameStatus = GameStatus.Inactive;
    }

    function sit(uint8 _seat) external {
        if (msg.sender == owner()) {
            revert Table__InvalidPlayer();
        }

        if (_seat > s_maxPlayers || _seat < 1) {
            revert Table__InvalidSeat();
        }

        address occupant = s_seatToPlayer[_seat];
        
        if (occupant != msg.sender && occupant != address(0)) {
            revert Table__SeatOccupied();
        }

        s_playerToState[msg.sender].seat = _seat;
        s_seatToPlayer[_seat] = msg.sender;
        s_players.push(msg.sender);
    }

    function leave() external whenInactiveOrBet {
        uint8 seat = s_playerToState[msg.sender].seat;

        if (seat == 0) {
            revert Table__PlayerNotFound();
        }

        s_playerToState[msg.sender].seat = 0;
        s_seatToPlayer[seat] = address(0);
        removePlayer(msg.sender);

        // Start game if all remaining players placed bets
        if (s_gameStatus == GameStatus.Bet) {
            for (uint8 i = 0; i < s_players.length; i++) {
                address player = s_players[i];
                if (s_playerToState[player].bet == 0) return;
            }

            startGame();
        }
    }

    function removePlayer(address _player) internal {
        bool found = false;

        for (uint8 i = 0; i < s_players.length; i++) {
            if (found) {
                s_players[i] = s_players[i + 1];
            } else if (_player == s_players[i]) {
                found = true;
            }
        }

        s_players.pop();
    }

    function setBetRange(BetRange memory _betRange) external onlyOwner whenInactive {
        s_betRange = _betRange;
    }

    function setMaxPlayers(uint8 _maxPlayers) external onlyOwner whenInactive {
        if (_maxPlayers < (s_players.length + 1) || _maxPlayers > 7) {
            revert Table__InvalidMaxPlayers();
        }
        
        s_maxPlayers = _maxPlayers;
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

    function drawCard() internal returns (uint8) {
        if (s_randomWords.length == 0) {
            revert Table__NoCards();
        }

        uint8 card = uint8(s_randomWords[s_randomWords.length - 1] % 52);

        s_randomWords.pop();

        if (s_randomWords.length < 50) {
            refreshRandomWords();
        }

        // if (s_cardsDrawn[card] >= 5) {
        //     return drawCard();
        // }

        // s_cardsDrawn[card]++;

        return card;
    }

    function initialDeal() internal {
        for (uint8 i = 0; i < s_players.length; i++) {
            address playerAddress = s_players[i];

            for (uint256 j = 0; j < 2; j++) {
                uint8 card = drawCard();
                s_playerToState[playerAddress].hand.push(card);
            }
        }

        s_dealerHand.push(drawCard());
    }

    function placeBet(uint256 _amount) external onlyToken nonReentrant handleBet(_amount) {
        bool success = IERC20(s_token).transferFrom(msg.sender, address(this), _amount);

        if (!success) {
            revert Table__BetTransferFailed();
        }
    }

    function hit() external onlyCurrentPlayer {
        uint8 card = drawCard();

        // If card drawn is ace...
        if (card < 4) {

        } 
    }

    receive() external payable onlyEth handleBet(msg.value) {}

    // mapping (address => uint256) public bets
    
    // uint[] deck immutable;
        // Obfuscate deck data
        // Created and shuffled in constructor (Chainlink not needed?)

    // mapping (address => uint256) public hands 
        // Need to obfuscate hand data?
        // Store hand totals to save gas?

    // address currentTurn
        // dealer address is "this"

    // uint status

    // function placeBet external payable
        // TODO: Should payable function actually be on Pit, where earnings/deposits are held? (save gas without transfer between contracts)
        // TODO: How should game create/start flow go and which contract owns it?

        // check status of game - revert if not in "START"
        // check role of msg.sender - if dealer, revert
        // check max and min bets - revert if outside bounds
        // check if bet has already been placed - revert if so

        // set bet amount for player in bets mapping
        // start game if last player

    // function dealCard(address) private
        // check status of game? (revert if not in "ACTIVE")
        
        // call chainlink VRF, (check if already got card/number 6 times?)
        // evaluate game status

    // function evaluateStatus internal
        // if currentTerm == "this" (i.e. dealer)
            // dealerPlay
        // else

    // function dealerPlay internal
        // dealerTotal = sum of values of hands[this] (or store hand totals)

        // if dealerTotal < 17
            // dealCard(this)
        // else if dealerTotal >= 21
            // 

}
