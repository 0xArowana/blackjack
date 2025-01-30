// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DeployTestERC20 is Script {
    uint256 public constant INITIAL_SUPPLY = 1000000;
    function run() external returns (address) {
        vm.startBroadcast();
        TestERC20 token = new TestERC20(INITIAL_SUPPLY);
        vm.stopBroadcast();
        return address(token);
    }
}

contract TestERC20 is ERC20 {
    constructor(uint256 _initialSupply) ERC20("Test ERC20", "TST") {
        _mint(msg.sender, _initialSupply);
    }
}