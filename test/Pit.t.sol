// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TableHarness} from "./util/TableHarness.sol";
import {PitHarness} from "./util/PitHarness.sol";
import {ERC20Mock} from "./util/ERC20Mock.sol";
import {Table} from "../src/Table.sol";
import {Pit} from "../src/Pit.sol";

contract PitTest is Test {
    PitHarness pit;
    address token = address(new ERC20Mock());

    function setUp() public {
        address pitImpl = address(new PitHarness());
        pit = PitHarness(payable(address(new ERC1967Proxy(pitImpl, ""))));
        address[] memory tokens = new address[](1);
        tokens[0] = token;

        pit.initialize(
            tokens,
            address(0), 
            100, 
            Pit.VrfConfig(
                vm.randomAddress(),
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

    function test_getManagerTokenInfo() public {
        address manager = vm.randomAddress();
        vm.startPrank(manager);

        Pit.TokenInfo[] memory tokens = pit.getManagerTokenInfo(manager);
    }

    function test_deposit() public {
        address manager = vm.randomAddress();
        vm.startPrank(manager);

        pit.deposit(token, 123);
    }
}