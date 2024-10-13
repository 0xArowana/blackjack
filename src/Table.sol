// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pit } from "./Pit.sol";
import { Game } from "./Game.sol";

contract Table is Ownable {
    error Table__NotGame();
    error Table__SpotOccupied();
    error Table__PlayerAlreadySitting();

    address[7] public s_players;
    Game s_currentGame;

    modifier onlyGame {
        if (msg.sender == address(s_currentGame)) {
            revert Table__NotGame();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    function sit(uint8 _spot) external {
        for(uint8 i = 0; i < 7; i++) {
            if (s_players[i] == msg.sender) {
                revert Table__PlayerAlreadySitting();
            }
        }

        if (s_players[_spot] != address(0)) {
            revert Table__SpotOccupied();
        }

        s_players[_spot] = msg.sender;
    }

    function newGame() internal {
        uint8[] memory players;
        
        for(uint8 i = 0; i < 7; i++) {
            if (s_players[uint8(i)] != address(0)) {
                players[players.length] = i;
            }
        }

        s_currentGame = new Game(players);
    }

    function fulfillRandomWords(uint256[] calldata _randomWords) external onlyOwner {
        uint8[50] memory cards;
        
        for(uint256 i = 0; i < 10; i++) {
            cards[i] = uint8(_randomWords[i] % 52) + 1;
        }

        s_currentGame.cardsDrawn(cards);
    }

    function drawCards() onlyGame external {
        Pit(owner()).requestRandomWords();
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
