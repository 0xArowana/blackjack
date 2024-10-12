// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Table } from "./Table.sol";

contract Game is OwnableUpgradeable {
    mapping (int8 => PlayerState) internal s_players;
    int8[] internal s_playersDrawingCards;
    int8 internal s_cardsPerPlayerToDraw;

    struct PlayerState {
        int8[] hand;
    }

    constructor(int8[] memory _players) {
        for(uint256 i = 0; i < _players.length; i++) {
            int8 playerIndex = _players[i];

            // TODO: calculate gas costs for various initial array sizes
            s_players[playerIndex] = PlayerState(new int8[](10));
        }
    }

    function drawCards(int8[] memory _players, int8 _cardsPerPlayer) internal {
        s_playersDrawingCards = _players;
        s_cardsPerPlayerToDraw = _cardsPerPlayer;

        // Table(owner()).drawCards();
    }

    function cardsDrawn(int8[10] memory _cards) external onlyOwner {
        uint256 cardsPerPlayer = uint256(uint8(s_cardsPerPlayerToDraw));

        for (uint256 i = 0; i < s_playersDrawingCards.length; i++) {
            int8 playerSpot = s_playersDrawingCards[i];

            for (uint256 j = 0; j < cardsPerPlayer; j++) {
                uint256 cardIndex = (i * cardsPerPlayer) + j;
                int8 card = _cards[cardIndex];
                s_players[playerSpot].hand.push(card);
            }
        }
    }


    // mapping (address => uint256 _status) public players
        // status 

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
