// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Pit } from "./Pit.sol";
import { Game } from "./Game.sol";

contract Table is OwnableUpgradeable {
    error Table__NotGame();
    error Table__InvalidSeatNumber();
    error Table__SeatOccupied();
    error Table__NoCards();

    mapping(address => uint8) public s_playerToSeatNumber;
    mapping(uint8 => address) public s_seatNumberToPlayer;
    uint256[] internal s_randomWords;
    Game s_currentGame;
    uint256 internal s_minBet;
    uint256 internal s_maxBet;

    modifier onlyGame {
        if (msg.sender == address(s_currentGame)) {
            revert Table__NotGame();
        }
        _;
    }

    function initialize(uint256 _minBet, uint256 _maxBet) public initializer {
        __Ownable_init(msg.sender);

        s_minBet = _minBet;
        s_maxBet = _maxBet;

        refreshRandomWords();
    }

    function sit(uint8 _seatNumber) external {
        if (_seatNumber > 7 || _seatNumber < 1) {
            revert Table__InvalidSeatNumber();
        }

        address occupant = s_seatNumberToPlayer[_seatNumber];
        
        if (occupant != msg.sender && occupant != address(0)) {
            revert Table__SeatOccupied();
        }

        s_playerToSeatNumber[msg.sender] = _seatNumber;
        s_seatNumberToPlayer[_seatNumber] = msg.sender;
    }

    function newGame() internal {
        address[] memory playerAddresses;
        
        for(uint8 i = 1; i < 8; i++) {
            if (s_seatNumberToPlayer[i] != address(0)) {
                playerAddresses[playerAddresses.length] = s_seatNumberToPlayer[i];
            }
        }

        s_currentGame = new Game(playerAddresses, s_minBet, s_maxBet);
    }

    function setMinBet(uint256 _amount) external onlyOwner {
        s_minBet = _amount;
    }

    function setMaxBet(uint256 _amount) external onlyOwner {
        s_maxBet = _amount;
    }

    function setRandomWords(uint256[] calldata _randomWords) external onlyOwner {
        s_randomWords = _randomWords;
    }

    function refreshRandomWords() internal {
        Pit(owner()).requestRandomWords();
    }
    function drawCard() onlyGame external returns (uint8) {
        if (s_randomWords.length == 0) {
            revert Table__NoCards();
        }

        uint8 card = uint8(s_randomWords[s_randomWords.length - 1] % 52);

        s_randomWords.pop();

        if (s_randomWords.length < 50) {
            refreshRandomWords();
        }

        return card;
    }

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
