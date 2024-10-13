// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Table } from "./Table.sol";

contract Game is Ownable {
    mapping (uint8 => PlayerState) internal s_players;
    GameStatus internal s_status;
    uint8 internal s_currentPlayerTurn;
    uint8[] internal s_playersDrawingCards;
    uint8 internal s_cardsPerPlayerToDraw;
    
    enum GameStatus {
        Bet,
        PlayerTurn,
        DealerTurn,
        Complete
    }

    struct PlayerState {
        uint8[] hand;
        uint256 bet;
    }

    constructor(uint8[] memory _players) Ownable(msg.sender) {
        for(uint256 i = 0; i < _players.length; i++) {
            uint8 playerIndex = _players[i];

            s_players[playerIndex] = PlayerState(new uint8[](0), 0);
        }

        s_status = GameStatus.Bet;
    }

    function drawCards(uint8[] memory _players, uint8 _cardsPerPlayer) internal {
        s_playersDrawingCards = _players;
        s_cardsPerPlayerToDraw = _cardsPerPlayer;

        Table(owner()).drawCards();
    }

    function cardsDrawn(uint8[50] memory _cards) external onlyOwner {
        uint256 cardsPerPlayer = uint256(uint8(s_cardsPerPlayerToDraw));

        for (uint256 i = 0; i < s_playersDrawingCards.length; i++) {
            uint8 playerSpot = s_playersDrawingCards[i];

            for (uint256 j = 0; j < cardsPerPlayer; j++) {
                uint256 cardIndex = (i * cardsPerPlayer) + j;
                uint8 card = _cards[cardIndex];
                s_players[playerSpot].hand.push(card);
            }
        }
    }

    function updateBet(uint8 _player, uint256 _amount) external onlyOwner {
        
    }

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
