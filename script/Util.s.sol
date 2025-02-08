// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Pit} from "../src/Pit.sol";
import {Table} from "../src/Table.sol";

contract SetTokens is Script {
    function run() external {
        vm.startBroadcast();
        Pit pit = Pit(payable(0x990aD8A81553735fCc80d4eCB00f4C2c54fb7dD3));
        address[] memory tokens = new address[](1);
        tokens[0] = 0xeC12Ffe943b53DF4884A55b14168553d43eA28c7;
        pit.setTokens(tokens);
        vm.stopBroadcast();
    }
}

contract GetLockTimestamp is Script {
    function run() external returns(uint256) {
        vm.startBroadcast();
        Table table = Table(0x974D22e8363325e1d20F92c3F2B723B440248582);
        uint256 timestamp = table.s_lockTimestamp();
        vm.stopBroadcast();
        return timestamp;
    }
}

contract CreateTable is Script {
    function run() external {
        vm.startBroadcast();
        Pit pit = Pit(payable(0x380c1Cb55B59e86884719ee2f6bFbC15D7Ede669));
        pit.createTable(
            3, 
            Table.BetRange(1,100), 
            Table.Rules(
                2, // deckCount
                false, // dealerHitOnSoft17
                false, // allowDoubleAfterSplit
                Table.DoubleRule.Any, // doubleRule
                3, // maxResplitHands
                true, // allowResplitAces
                true, // allowHitSplitAces
                true, // allowLateSurrender
                true, // allowInsurance
                false // sixToFive
            ),
            0xeC12Ffe943b53DF4884A55b14168553d43eA28c7
        );
        vm.stopBroadcast();
    }
}