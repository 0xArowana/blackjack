// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Game} from "../../src/Game.sol";

contract GameHarness is Game {
    constructor(address[] memory _playerAddresses, uint256 _minBet, uint256 _maxBet) Game(_playerAddresses, _minBet, _maxBet) {}
    
    function getPlayerState(address _playerAddress) external view returns (Game.PlayerState memory) {
        return s_playerStates[_playerAddress];
    } 

    function getPlayersDrawingCards() external view returns (address[] memory) {
        return s_playersDrawingCards;
    }

    function getCardsPerPlayerToDraw() external view returns (uint8) {
        return s_cardsPerPlayerToDraw;
    }

    function callDrawCards(address[] memory _playerAddresses, uint8 _cardsPerPlayer) external {
        drawCards(_playerAddresses, _cardsPerPlayer);
    }
}
