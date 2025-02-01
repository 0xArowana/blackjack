// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Pit} from "../src/Pit.sol";
import {Table} from "../src/Table.sol";

contract SetTokens is Script {
    function run() external {
        vm.startBroadcast();
        Pit pit = Pit(0x990aD8A81553735fCc80d4eCB00f4C2c54fb7dD3);
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