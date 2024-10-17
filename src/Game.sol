// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Table } from "./Table.sol";
import {console} from "forge-std/console.sol";

contract Game is Ownable {
    error Game__NotBetStatus();
    error Game__BetLessThanMin();
    error Game__BetGreaterThanMax();
    error Game__BetAlreadyPlaced();

    mapping(address => PlayerState) internal s_playerStates;
    address[] s_playerAddresses;
    GameStatus internal s_status;
    uint8[] internal s_dealerHand;
    uint8 internal s_currentPlayerTurn;
    address[] internal s_playersDrawingCards;
    uint8 internal s_cardsPerPlayerToDraw;

    uint256 internal immutable i_minBet;
    uint256 internal immutable i_maxBet;

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

    constructor(address[] memory _playerAddresses, uint256 _minBet, uint256 _maxBet) Ownable(msg.sender) {
        for(uint8 i = 0; i < _playerAddresses.length; i++) {
            address playerAddress = _playerAddresses[i];
            s_playerStates[playerAddress] = PlayerState(new uint8[](0), 0);
        }

        s_playerAddresses = _playerAddresses;
        s_status = GameStatus.Bet;

        i_minBet = _minBet;
        i_maxBet = _maxBet;
    }

    function drawCards(address[] memory _playerAddresses, uint8 _cardsPerPlayer) internal {
        s_playersDrawingCards = _playerAddresses;
        s_cardsPerPlayerToDraw = _cardsPerPlayer;

        Table(owner()).drawCards();
    }

    function cardsDrawn(uint8[50] memory _cards) external onlyOwner {
        uint256 cardsPerPlayer = uint256(uint8(s_cardsPerPlayerToDraw));

        for (uint8 i = 0; i < s_playersDrawingCards.length; i++) {
            address playerAddress = s_playersDrawingCards[i];

            for (uint256 j = 0; j < cardsPerPlayer; j++) {
                uint256 cardIndex = (i * cardsPerPlayer) + j;
                uint8 card = _cards[cardIndex];
                s_playerStates[playerAddress].hand.push(card);
            }
        }
    }

    function placeBet(uint256 _amount) external payable {
        if (s_status != GameStatus.Bet) {
            revert Game__NotBetStatus();
        }

        if (_amount > i_maxBet) {
            revert Game__BetGreaterThanMax();
        }

        if (_amount < i_minBet) {
            revert Game__BetGreaterThanMax();
        }

        if (s_playerStates[msg.sender].bet > 0) {
            revert Game__BetAlreadyPlaced();
        }

        s_playerStates[msg.sender].bet = _amount;

        for (uint8 i = 0; i < s_playerAddresses.length; i++) {
            address playerAddress = s_playerAddresses[i];
            if (s_playerStates[playerAddress].bet == 0) return;
        }

        s_status = GameStatus.PlayerTurn;
        drawCards(s_playerAddresses, 2);
    }

    // address currentTurn
        // dealer address is "this"

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
