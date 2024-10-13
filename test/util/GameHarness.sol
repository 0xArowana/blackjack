// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Game} from "../../src/Game.sol";

contract GameHarness is Game {
    constructor(uint8[] memory _players) Game(_players) {}
    
    function getPlayerState(uint8 _spot) external view returns (Game.PlayerState memory) {
        return s_players[_spot];
    } 

    function getPlayersDrawingCards() external view returns (uint8[] memory) {
        return s_playersDrawingCards;
    }

    function getCardsPerPlayerToDraw() external view returns (uint8) {
        return s_cardsPerPlayerToDraw;
    }

    function callDrawCards(uint8[] memory _players, uint8 _cardsPerPlayer) external {
        drawCards(_players, _cardsPerPlayer);
    }
}
