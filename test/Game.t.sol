// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {GameHarness} from "./util/GameHarness.sol";
import {TableMock} from "./util/TableMock.sol";

contract GameTest is Test {
    GameHarness game;
    TableMock table;

    address player1 = makeAddr("player1");
    address player2 = makeAddr("player2");
    address player3 = makeAddr("player3");
    address player4 = makeAddr("player4");

    function setUp() public {
        table = new TableMock();

        address[] memory playerAddresses = new address[](4);
        playerAddresses[0] = player1;
        playerAddresses[1] = player2;
        playerAddresses[2] = player3;
        playerAddresses[3] = player4;

        vm.prank(address(table));
        game = new GameHarness(playerAddresses, 5, 100);
    }

    function test_drawCards() public {
        address[] memory playerAddresses = new address[](2);
        playerAddresses[0] = player1;
        playerAddresses[1] = player3;

        game.callFetchCards(playerAddresses, 3);

        address[] memory playersStored = game.getPlayersDrawingCards();
        assertEq(playersStored.length, 2);
        assertEq(playersStored[0], player1);
        assertEq(playersStored[1], player3);

        assertEq(table.drawCardsCallCount(), 1);

        uint8[50] memory cards;

        for (uint256 i = 0; i < 50; i++) {
            cards[i] = uint8(int8(vm.randomInt())) % 50;
        }

        vm.prank(address(table));
        game.cardsDrawn(cards);

        uint8[] memory hand1 = game.getPlayerState(player1).hand;
        assertEq(hand1.length, 3);
        assertEq(hand1[0], cards[0]);
        assertEq(hand1[1], cards[1]);
        assertEq(hand1[2], cards[2]);

        uint8[] memory hand2 = game.getPlayerState(player2).hand;
        assertEq(hand2.length, 0);

        uint8[] memory hand3 = game.getPlayerState(player3).hand;
        assertEq(hand3.length, 3);
        assertEq(hand3[0], cards[3]);
        assertEq(hand3[1], cards[4]);
        assertEq(hand3[2], cards[5]);

        uint8[] memory hand4 = game.getPlayerState(player4).hand;
        assertEq(hand4.length, 0);
    }

    function test_placeBet() public {
        game.placeBet(90);
    }
}
