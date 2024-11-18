// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {TableHarness} from "./util/TableHarness.sol";
import {ERC20Mock} from "./util/ERC20Mock.sol";
import {Table} from "../src/Table.sol";
import {Pit} from "../src/Pit.sol";

contract TableTest is Test {
    Pit pit;
    TableHarness table;

    function setUp() public {
        pit = new Pit();

        vm.mockCall(
            address(pit),
            abi.encodeWithSelector(pit.requestRandomWords.selector),
            ""
        );

        vm.prank(address(pit));
        table = new TableHarness();
    }

    function test_initialize_SetsStateVariables() public {
        address manager = vm.randomAddress();
        uint8 maxPlayers = uint8(vm.randomUint());
        Table.BetRange memory betRange = Table.BetRange(vm.randomUint(), vm.randomUint());
        Table.Rules memory rules = Table.Rules(
            uint8(vm.randomUint()),
            vm.randomBool(),
            vm.randomBool(),
            Table.DoubleRule(vm.randomUint() % 3),
            uint8(vm.randomUint()),
            vm.randomBool(),
            vm.randomBool(),
            vm.randomBool(),
            vm.randomBool()
        );
        address token = vm.randomAddress();

        vm.expectCall(address(pit), abi.encodeWithSelector(pit.requestRandomWords.selector));

        vm.prank(address(pit));
        table.initialize(manager, maxPlayers, betRange, rules, token);

        assertEq(table.owner(), address(pit));
        assertEq(table.s_manager(), manager);
        assertEq(table.getMaxPlayers(), maxPlayers);
        assertEq(keccak256(abi.encode(table.getBetRange())), keccak256(abi.encode(betRange)));
        assertEq(keccak256(abi.encode(table.getRules())), keccak256(abi.encode(rules)));
        assertEq(table.s_token(), token);
        assertEq(table.getDrawableCards().length, 52);   
    }

    function test_initialize_RevertsOnMultipleCalls() public {
        Table.BetRange memory betRange;
        Table.Rules memory rules;
        
        vm.startPrank(address(pit));
        table.initialize(address(0), 0, betRange, rules, address(0));

        bytes4 selector = bytes4(keccak256("InvalidInitialization()"));
        vm.expectRevert(abi.encodeWithSelector(selector));
        table.initialize(address(0), 0, betRange, rules, address(0));
    }

    function test_cashOut_RevertsIfNoBalance() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("Table__NoBalanceAvailable()"))));
        table.cashOut();
    }

    function test_cashOut_TransfersTokensIfERC20() public {
        address player = vm.randomAddress();
        uint256 amount = vm.randomUint();
        table.setBalance(player, amount);

        ERC20Mock token = new ERC20Mock();
        table.setTestToken(address(token));

        vm.expectCall(address(token), abi.encodeCall(ERC20Mock(token).transfer, (player, amount)));

        vm.prank(player);
        table.cashOut();
    }

    function test_cashOut_RevertsOnERC20TransferFailure() public {
        address player = vm.randomAddress();
        uint256 amount = vm.randomUint();
        table.setBalance(player, amount);

        ERC20Mock token = new ERC20Mock();
        table.setTestToken(address(token));

        vm.mockCall(
            address(token),
            abi.encodeWithSelector(token.transfer.selector),
            abi.encode(false)
        );

        vm.prank(player);
        vm.expectRevert(bytes4(keccak256("Table__CashOutTransferFailed()")));
        table.cashOut();
    }

    function test_cashOut_TransfersETHIfNotERC20() public {
        address player = vm.randomAddress();
        uint256 amount = vm.randomUint();
        table.setBalance(player, amount);

        vm.deal(address(table), amount);
        vm.prank(player);
        table.cashOut();

        assertEq(player.balance, amount);
    }

    function test_cashOut_RevertsOnETHTransferFailure() public {
        address player = vm.randomAddress();
        uint256 amount = vm.randomUint();
        table.setBalance(player, amount);

        vm.prank(player);
        vm.expectRevert(bytes4(keccak256("Table__CashOutTransferFailed()")));
        table.cashOut();
    }

    function test_cashOut_RevertsOnReentrancy() public {
        address player = vm.randomAddress();
        uint256 amount = vm.randomUint();
        table.setBalance(player, amount);

        ERC20Mock token = new ERC20Mock();
        table.setTestToken(address(token));

        token.setReenterCashOut(true);

        vm.prank(player);
        vm.expectRevert(bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        table.cashOut();
    }

    function test_startBets_UpdatesGameStatus() public {
        address manager = vm.randomAddress();
        table.setManager(manager);

        vm.prank(manager);
        table.startBets();

        assertEq(uint(table.getGameStatus()), uint(Table.GameStatus.Bet));
    }

    function test_startBets_RevertsIfNotInactive() public {
        table.setGameStatus(Table.GameStatus.DealerTurn);

        address manager = vm.randomAddress();
        table.setManager(manager);

        vm.prank(manager);
        vm.expectRevert(bytes4(keccak256("Table__NotInactiveStatus()")));
        table.startBets();
    }

    function test_startBets_RevertsIfNotManager() public {
        address manager = vm.randomAddress();
        table.setManager(manager);

        vm.prank(vm.randomAddress());
        vm.expectRevert(bytes4(keccak256("Table__NotManager()")));
        table.startBets();
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