// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {GameHarness} from "./util/GameHarness.sol";
import {TableMock} from "./util/TableMock.sol";

contract GameTest is Test {
    GameHarness game;
    TableMock table;

    function setUp() public {
        table = new TableMock();

        int8[] memory spots = new int8[](4);
        spots[0] = 0;
        spots[1] = 1;
        spots[2] = 4;
        spots[3] = 6;

        vm.prank(address(table));
        game = new GameHarness(spots);
    }

    function test_drawCards() public {
        int8[] memory playersArg = new int8[](2);
        playersArg[0] = 0;
        playersArg[1] = 4;

        game.callDrawCards(playersArg, 3);

        int8[] memory playersStored = game.getPlayersDrawingCards();
        assertEq(playersStored.length, 2);
        assertEq(playersStored[0], 0);
        assertEq(playersStored[1], 4);

        assertEq(table.drawCardsCallCount(), 1);

        vm.prank(address(table));
        game.cardsDrawn([int8(8),44,21,16,36,19,24,11,15,25]);

        int8[] memory hand1 = game.getPlayerState(0).hand;
        assertEq(hand1.length, 3);
        assertEq(hand1[0], 8);
        assertEq(hand1[1], 44);
        assertEq(hand1[2], 21);

        int8[] memory hand2 = game.getPlayerState(1).hand;
        assertEq(hand2.length, 0);

        int8[] memory hand3 = game.getPlayerState(4).hand;
        assertEq(hand3.length, 3);
        assertEq(hand3[0], 16);
        assertEq(hand3[1], 36);
        assertEq(hand3[2], 19);

        int8[] memory hand4 = game.getPlayerState(6).hand;
        assertEq(hand4.length, 0);
    }
}
