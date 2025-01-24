// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {TableHarness} from "./util/TableHarness.sol";
import {PitHarness} from "./util/PitHarness.sol";
import {ERC20Mock} from "./util/ERC20Mock.sol";
import {Table} from "../src/Table.sol";
import {Pit} from "../src/Pit.sol";

contract TableTest is Test {
    PitHarness pit;
    TableHarness table;

    function setUp() public {
        pit = new PitHarness();

        vm.mockCall(
            address(pit),
            abi.encodeWithSelector(pit.requestRandomWords.selector),
            ""
        );

        vm.prank(address(pit));
        table = new TableHarness();
    }

    function fullSetup() internal returns (Table.Rules memory, address, address) {
        address manager = vm.randomAddress();
        pit.setTableToManager(address(table), manager);

        Table.Rules memory rules = Table.Rules(
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
        );
        vm.prank(address(pit));
        table.initialize(
            manager, 
            7, 
            Table.BetRange(1, 100), 
            rules, 
            address(0)
        );
        address token = vm.randomAddress();
        table.setTestToken(token);
        
        uint256[] memory words = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            words[i] = vm.randomUint();
        }
        vm.prank(address(pit));
        table.setRandomWords(words);

        return (rules, token, manager);
    }

    // initialize
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
            vm.randomBool(),
            vm.randomBool()
        );
        address token = vm.randomAddress();

        vm.expectCall(address(pit), abi.encodeWithSelector(pit.requestRandomWords.selector));

        vm.prank(address(pit));
        table.initialize(manager, maxPlayers, betRange, rules, token);

        assertEq(table.owner(), address(pit));
        assertEq(table.s_manager(), manager);
        assertEq(table.getSeatCount(), maxPlayers);
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

    // cashOut
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

    // startBets
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

    // finalizeBets
    function test_finalizeBets_SetsMaxPayout() public {
        (Table.Rules memory rules, address token,) = fullSetup();

        table.setBetTotal(789);
        
        rules.maxResplitHands = 3;
        table.setRules(rules);

        vm.expectCall(address(pit), abi.encodeCall(pit.increaseMaxPayout, (4734, token)));
        table.callFinalizeBets();

        rules.sixToFive = true;
        table.setRules(rules);

        vm.expectCall(address(pit), abi.encodeCall(pit.increaseMaxPayout, (8522, token)));
        table.callFinalizeBets();

        rules.allowDoubleAfterSplit = true;
        table.setRules(rules);

        vm.expectCall(address(pit), abi.encodeCall(pit.increaseMaxPayout, (14203, token)));
        table.callFinalizeBets();

        rules.maxResplitHands = 4;
        rules.sixToFive = false;
        table.setRules(rules);

        vm.expectCall(address(pit), abi.encodeCall(pit.increaseMaxPayout, (23671, token)));
        table.callFinalizeBets();
    }

    function test_finalizeBets_LocksIfInsufficientBalance() public {
        fullSetup();

        table.setBetTotal(100);  

        table.callFinalizeBets();
        assertEq(table.s_lockTimestamp(), block.timestamp);
        assertEq(uint(table.getGameStatus()), 0);
    }

    function test_finalizeBets_StartsGameIfSufficientBalance() public {
        (, address token, address manager) = fullSetup();

        Pit.TokenState memory state;
        state.balance = 500;
        pit.setManagerToTokenToState(manager, token, state);   

        table.callFinalizeBets();
        assertEq(table.s_lockTimestamp(), 0);
        assertEq(uint(table.getGameStatus()), uint(Table.GameStatus.PlayerTurn));
    }

    function test_hit() public {
        fullSetup();

        table.setGameStatus(Table.GameStatus.PlayerTurn);

        table.hit();
    }

    function test_sit() public {
        fullSetup();

        table.sit(1);
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