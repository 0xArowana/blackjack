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

    function getRules() external view returns (Rules memory) {
        return s_rules;
    }

    function getDrawableCards() external view returns (uint8[] memory) {
        return s_drawableCards;
    }
}
