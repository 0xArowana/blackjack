// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Table} from "../../src/Table.sol";

contract TableHarness is Table {
    function getMaxPlayers() external view returns (uint8) {
        return s_maxPlayers;
    }

    function getBetRange() external view returns (BetRange memory) {
        return s_betRange;
    }

    function getGameStatus() external view returns (GameStatus) {
        return s_gameStatus;
    }

    function getRules() external view returns (Rules memory) {
        return s_rules;
    }

    function getDrawableCards() external view returns (uint8[] memory) {
        return s_drawableCards;
    }

    function setManager(address _manager) external {
        s_manager = _manager;
    }

    function setBalance(address _player, uint256 _amount) external {
        s_playerToState[_player].balance = _amount;
    }

    function setTestToken(address _token) external {
        s_token = _token;
    }

    function setGameStatus(GameStatus _status) external {
        s_gameStatus = _status;
    }

    function setRules(Rules memory _rules) external {
        s_rules = _rules;
    }

    function setBetTotal(uint256 _betTotal) external {
        s_betTotal = _betTotal;
    }

    function setCurrentPlayer(address _player) external {
        s_currentPlayer = _player;
    }

    function callFinalizeBets() external {
        finalizeBets();
    }
}
