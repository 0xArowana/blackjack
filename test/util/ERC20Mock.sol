// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Table} from "../../src/Table.sol";

contract ERC20Mock is IERC20 {
    function name() public view returns (string memory) {
        return "ERC20 Mock";
    }

    function symbol() public view returns (string memory) {
        return "ERC";
    }

    function decimals() public view returns (uint8) {
        return 18;
    }
    function totalSupply() public view returns (uint256) {
        return 0;
    }

    function balanceOf(address owner) public view returns (uint256) {
        return 0;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return 0;
    }

    function transfer(address to, uint256 value) public returns (bool) {
        if (s_reenterCashOut) {
            Table(payable(msg.sender)).cashOut();
            s_reenterCashOut = false;
        }
        return true;
    }

    function approve(address spender, uint256 value) public returns (bool) {
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        return true;
    }

    bool s_reenterCashOut;
    function setReenterCashOut(bool _reenter) external {
        s_reenterCashOut = _reenter;
    }
}