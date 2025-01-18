// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {TableHarness} from "./util/TableHarness.sol";
import {PitHarness} from "./util/PitHarness.sol";
import {ERC20Mock} from "./util/ERC20Mock.sol";
import {Table} from "../src/Table.sol";
import {Pit} from "../src/Pit.sol";

contract PitTest is Test {
    PitHarness pit;
    address constant token = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;

    function setUp() public {
        pit = new PitHarness();
        address[] memory tokens = new address[](1);
        tokens[0] = token;

        pit.initialize(
            tokens,
            address(0), 
            100, 
            Pit.VrfConfig(
                address(0),
                0x0,
                0,
                0
            ),
            address(0)
        );
    }

    // createTable
    function test_createTable() public {
        address manager = vm.randomAddress();
        vm.startPrank(manager);

        pit.createTable(
            7, 
            Table.BetRange(0,100), 
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
            token
        );
    }
}