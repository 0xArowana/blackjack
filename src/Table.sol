// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Pit} from "./Pit.sol";
import {Game} from "./Game.sol";

contract Table is Initializable, OwnableUpgradeable {
    error Table__NotGame();
    error Table__InvalidSeatNumber();
    error Table__InvalidPlayer();
    error Table__NoCards();
    error Table__PlayerNotFound();
    error Table__SeatOccupied();
    error Table__BetAlreadyPlaced();
    error Table__BetGreaterThanMax();
    error Table__BetLessThanMin();
    error Table__BettingInProgress();
    error Table__GameInProgress();
    error Table__NotBetStatus();
    error Table__NotCurrentPlayer();
    error Table__NotInactiveStatus();
    error Table__NotPlayerTurnStatus();
    error Table__WithdrawExceedsBalance();

    mapping(address => uint8) public s_playerToSeatNumber;
    mapping(uint8 => address) public s_seatNumberToPlayer;
    address[] s_players;
    uint256 internal s_minBet;
    uint256 internal s_maxBet;
    uint8 internal s_maxPlayers;
    address public s_manager;
    uint256 public s_managerBalance;
    Pit.Currency public s_currency;
    uint256[] internal s_randomWords;
    bool s_continuousPlay;

    // Game
    mapping(address => PlayerState) internal s_playerStates;
    
    GameStatus internal s_gameStatus;
    uint8[] internal s_dealerHand;
    address internal s_currentPlayerAddress;

    enum GameStatus {
        Inactive,
        Bet,
        PlayerTurn,
        DealerTurn
    }

    struct PlayerState {
        uint8[] hand;
        uint256 bet;
    }

    event GameStarted();

    modifier onlyCurrentPlayer {
        if (s_gameStatus != GameStatus.PlayerTurn) {
            revert Table__NotPlayerTurnStatus();
        }
        if (msg.sender == address(s_currentPlayerAddress)) {
            revert Table__NotCurrentPlayer();
        }
        _;
    }

    modifier onlyInactive{
        if (s_gameStatus != GameStatus.Inactive) {
            revert Table__NotInactiveStatus();
        }
        _;
    }

    modifier notDuringGame {
        if (s_gameStatus != GameStatus.Bet && s_gameStatus != GameStatus.Inactive) {
            revert Table__GameInProgress();
        }
        _;
    }

    function initialize(address _manager, uint256 _minBet, uint256 _maxBet, uint8 _maxPlayers, Pit.Currency _currency) public initializer {
        __Ownable_init(msg.sender);

        s_manager = _manager;
        s_minBet = _minBet;
        s_maxBet = _maxBet;
        s_maxPlayers = _maxPlayers;
        s_currency = _currency;

        refreshRandomWords();
    }

    function fund(uint256 _amount) external onlyOwner {
        s_managerBalance += _amount;
    }

    function withdraw(uint256 _amount) external onlyOwner {
        if (_amount > s_managerBalance) {
            revert Table__WithdrawExceedsBalance();
        }

        s_managerBalance -= _amount;
    }

    function startGame() external onlyOwner onlyInactive {
        s_gameStatus = GameStatus.Bet;

        emit GameStarted();
    }

    function sit(uint8 _seatNumber) external {
        if (msg.sender == owner()) {
            revert Table__InvalidPlayer();
        }

        if (_seatNumber > s_maxPlayers || _seatNumber < 1) {
            revert Table__InvalidSeatNumber();
        }

        address occupant = s_seatNumberToPlayer[_seatNumber];
        
        if (occupant != msg.sender && occupant != address(0)) {
            revert Table__SeatOccupied();
        }

        s_playerToSeatNumber[msg.sender] = _seatNumber;
        s_seatNumberToPlayer[_seatNumber] = msg.sender;
        s_players.push(msg.sender);
    }

    function leave() external notDuringGame {
        uint8 seatNumber = s_playerToSeatNumber[msg.sender];

        if (seatNumber == 0) {
            revert Table__PlayerNotFound();
        }

        s_playerToSeatNumber[msg.sender] = 0;
        s_seatNumberToPlayer[seatNumber] = address(0);
        removePlayer(msg.sender);

        // Start game if all remaining players placed bets
        if (s_gameStatus == GameStatus.Bet) {
            for (uint8 i = 0; i < s_players.length; i++) {
                address player = s_players[i];
                uint256 bet = s_playerStates[player].bet;
                if (bet == 0) return;
            }

            initialDeal();
            s_gameStatus = GameStatus.PlayerTurn;
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

    function setMinBet(uint256 _amount) external onlyOwner onlyInactive {
        s_minBet = _amount;
    }

    function setMaxBet(uint256 _amount) external onlyOwner onlyInactive {
        s_maxBet = _amount;
    }

    function setMaxPlayers(uint8 _maxPlayers) external onlyOwner onlyInactive {
        s_maxPlayers = _maxPlayers;
    }

    function setCurrency(Pit.Currency _currency) external onlyOwner onlyInactive {
        s_currency = _currency;
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
                s_playerStates[playerAddress].hand.push(card);
            }
        }

        s_dealerHand.push(drawCard());
    }

    function placeBet(uint256 _amount) external payable {
        if (s_gameStatus != GameStatus.Bet) {
            revert Table__NotBetStatus();
        }

        if (_amount > s_maxBet) {
            revert Table__BetGreaterThanMax();
        }

        if (_amount < s_minBet) {
            revert Table__BetGreaterThanMax();
        }

        if (s_playerStates[msg.sender].bet > 0) {
            revert Table__BetAlreadyPlaced();
        }

        s_playerStates[msg.sender].bet = _amount;

        for (uint8 i = 0; i < s_players.length; i++) {
            address playerAddress = s_players[i];
            if (s_playerStates[playerAddress].bet == 0) return;
        }

        initialDeal();
        s_gameStatus = GameStatus.PlayerTurn;
    }

    function hit() onlyCurrentPlayer external {
        uint8 card = drawCard();

        // If card drawn is ace...
        if (card < 4) {

        } 
    }

    // TODO: Prohibit more than 6 of same card drawn per game?


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
