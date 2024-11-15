// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {TableHarness} from "./util/TableHarness.sol";
import {Table} from "../src/Table.sol";
import {Pit} from "../src/Pit.sol";

contract TableTest is Test {
    Pit pit;
    TableHarness table;

    address player1 = makeAddr("player1");
    address player2 = makeAddr("player2");
    address player3 = makeAddr("player3");
    address player4 = makeAddr("player4");

    function setUp() public {
        pit = new Pit();

        vm.mockCall(
            address(pit),
            abi.encodeWithSelector(Pit.requestRandomWords.selector),
            ""
        );

        vm.prank(address(pit));
        table = new TableHarness();

        address[] memory playerAddresses = new address[](4);
        playerAddresses[0] = player1;
        playerAddresses[1] = player2;
        playerAddresses[2] = player3;
        playerAddresses[3] = player4;
    }

    function test_initialize() public {
        address manager = vm.randomAddress();
        uint8 maxPlayers = uint8(vm.randomUint());
        Table.BetRange memory betRange = Table.BetRange(vm.randomUint(), vm.randomUint());
        Table.Rules memory rules = Table.Rules(
            uint8(vm.randomUint()),
            vm.randomBool(),
            vm.randomBool(),
            Table.DoubleOn(vm.randomUint() % 3),
            uint8(vm.randomUint()),
            vm.randomBool(),
            vm.randomBool(),
            vm.randomBool(),
            vm.randomBool()
        );
        address token = vm.randomAddress();

        vm.prank(address(pit));
        table.initialize(manager, maxPlayers, betRange, rules, token);

        assertEq(table.owner(), address(pit));
        assertEq(table.s_manager(), manager);
        assertEq(table.getMaxPlayers(), maxPlayers);
        assertEq(keccak256(abi.encode(table.getBetRange())), keccak256(abi.encode(betRange)));
        assertEq(keccak256(abi.encode(table.getRules())), keccak256(abi.encode(rules)));
        assertEq(table.s_token(), token);
        assertEq(table.getDrawableCards().length, 52);
        vm.expectCall(address(pit), abi.encodeWithSelector(pit.requestRandomWords.selector));
    }

    // function test_drawCards() public {
    //     address[] memory playerAddresses = new address[](2);
    //     playerAddresses[0] = player1;
    //     playerAddresses[1] = player3;

    //     // game.callFetchCards(playerAddresses, 3);

    //     address[] memory playersStored; //game.getPlayersDrawingCards();
    //     assertEq(playersStored.length, 2);
    //     assertEq(playersStored[0], player1);
    //     assertEq(playersStored[1], player3);

    //     assertEq(table.drawCardsCallCount(), 1);

    //     uint8[50] memory cards;

    //     for (uint256 i = 0; i < 50; i++) {
    //         cards[i] = uint8(int8(vm.randomInt())) % 50;
    //     }

    //     vm.prank(address(table));
    //     // game.cardsDrawn(cards);

    //     uint8[] memory hand1 = game.getPlayerState(player1).hand;
    //     assertEq(hand1.length, 3);
    //     assertEq(hand1[0], cards[0]);
    //     assertEq(hand1[1], cards[1]);
    //     assertEq(hand1[2], cards[2]);

    //     uint8[] memory hand2 = game.getPlayerState(player2).hand;
    //     assertEq(hand2.length, 0);

    //     uint8[] memory hand3 = game.getPlayerState(player3).hand;
    //     assertEq(hand3.length, 3);
    //     assertEq(hand3[0], cards[3]);
    //     assertEq(hand3[1], cards[4]);
    //     assertEq(hand3[2], cards[5]);

    //     uint8[] memory hand4 = game.getPlayerState(player4).hand;
    //     assertEq(hand4.length, 0);
    // }

    // function test_placeBet() public {
    //     game.placeBet(90);
    // }
}