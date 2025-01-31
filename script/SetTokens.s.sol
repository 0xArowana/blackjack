// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MintTokens is Script {
    function run() external {
        vm.startBroadcast();
        ERC20 token = ERC20(0xeC12Ffe943b53DF4884A55b14168553d43eA28c7);
        token._mint(0x29490c0Acca3301912d71e9adE566138fE30ce91, 100e18);
        vm.stopBroadcast();
    }
}