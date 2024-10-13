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

        uint8[] memory spots = new uint8[](4);
        spots[0] = 0;
        spots[1] = 1;
        spots[2] = 4;
        spots[3] = 6;

        vm.prank(address(table));
        game = new GameHarness(spots);
    }

    function test_drawCards() public {
        uint8[] memory playersArg = new uint8[](2);
        playersArg[0] = 0;
        playersArg[1] = 4;

        game.callDrawCards(playersArg, 3);

        uint8[] memory playersStored = game.getPlayersDrawingCards();
        assertEq(playersStored.length, 2);
        assertEq(playersStored[0], 0);
        assertEq(playersStored[1], 4);

        assertEq(table.drawCardsCallCount(), 1);

        uint8[50] memory cards;

        for (uint256 i; i < 50; i++) {
            cards[i] = uint8(int8(vm.randomInt())) % 50;
        }

        vm.prank(address(table));
        game.cardsDrawn(cards);

        uint8[] memory hand1 = game.getPlayerState(0).hand;
        assertEq(hand1.length, 3);
        assertEq(hand1[0], cards[0]);
        assertEq(hand1[1], cards[1]);
        assertEq(hand1[2], cards[2]);

        uint8[] memory hand2 = game.getPlayerState(1).hand;
        assertEq(hand2.length, 0);

        uint8[] memory hand3 = game.getPlayerState(4).hand;
        assertEq(hand3.length, 3);
        assertEq(hand3[0], cards[3]);
        assertEq(hand3[1], cards[4]);
        assertEq(hand3[2], cards[5]);

        uint8[] memory hand4 = game.getPlayerState(6).hand;
        assertEq(hand4.length, 0);
    }
}
