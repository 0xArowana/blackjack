// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {TableHarness} from "./util/TableHarness.sol";
import {PitHarness} from "./util/PitHarness.sol";
import {ERC20Mock} from "./util/ERC20Mock.sol";
import {ITable} from "../src/interfaces/ITable.sol";
import {Table} from "../src/Table.sol";
import {IPit} from "../src/interfaces/IPit.sol";
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

        address tableImpl = address(new TableHarness());
        table = TableHarness(Clones.clone(tableImpl));
    }

    function fullSetup() internal returns (Table.Rules memory, address, address) {
        address manager = vm.randomAddress();
        pit.setTableToManager(address(table), manager);
        address token = address(new ERC20Mock());
        pit.setManagerToTokenToState(manager, token, IPit.TokenState(100e18, 0));

        ITable.Rules memory rules = ITable.Rules(
            8, // deckCount
            ITable.DeckReset.FourDecksLeft, // deckReset
            false, // dealerHitOnSoft17
            false, // allowDoubleAfterSplit
            ITable.DoubleRule.Any, // doubleRule
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
            ITable.BetRange(1, 100), 
            rules, 
            token
        );

        table.callResetDecks();

        uint256[] memory words = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            words[i] = vm.randomUint();
        }
        table.setRandomWords(words);

        return (rules, token, manager);
    }

    // initialize
    function test_initialize_SetsStateVariables() public {
        address manager = vm.randomAddress();
        uint8 maxPlayers = uint8(vm.randomUint());
        ITable.BetRange memory betRange = ITable.BetRange(vm.randomUint(), vm.randomUint());
        ITable.Rules memory rules = ITable.Rules(
            uint8(vm.randomUint()),
            ITable.DeckReset(vm.randomUint() % 3),
            vm.randomBool(),
            vm.randomBool(),
            ITable.DoubleRule(vm.randomUint() % 3),
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
        assertEq(table.getManager(), manager);
        assertEq(table.getSeatCount(), maxPlayers);
        assertEq(keccak256(abi.encode(table.getBetRange())), keccak256(abi.encode(betRange)));
        assertEq(keccak256(abi.encode(table.getRules())), keccak256(abi.encode(rules)));
        assertEq(table.getToken(), token);
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

        assertEq(uint(table.getGameStatus()), uint(ITable.GameStatus.Bet));
    }

    function test_startBets_RevertsIfNotInactive() public {
        table.setGameStatus(ITable.GameStatus.DealerTurn);

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
    function test_finalizeBets_AllocatesFunds() public {
        (ITable.Rules memory rules, address token,) = fullSetup();

        table.setBetTotal(789);
        
        rules.maxResplitHands = 3;
        table.setRules(rules);

        vm.expectCall(address(pit), abi.encodeCall(pit.allocate, (4734, token)));
        table.callFinalizeBets();

        rules.sixToFive = true;
        table.setRules(rules);

        vm.expectCall(address(pit), abi.encodeCall(pit.allocate, (8522, token)));
        table.callFinalizeBets();

        rules.allowDoubleAfterSplit = true;
        table.setRules(rules);

        vm.expectCall(address(pit), abi.encodeCall(pit.allocate, (14203, token)));
        table.callFinalizeBets();

        rules.maxResplitHands = 4;
        rules.sixToFive = false;
        table.setRules(rules);

        vm.expectCall(address(pit), abi.encodeCall(pit.allocate, (23671, token)));
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
        assertEq(uint(table.getGameStatus()), uint(ITable.GameStatus.PlayerTurn));
    }

    function test_sit() public {
        fullSetup();

        table.sit(1);
    }

    function test_getTableInfo() public {
        fullSetup();
        vm.prank(vm.randomAddress());
        table.sit(3);
        Table.SeatInfo[] memory seats = table.getTableInfo().seats;
        console.log("TABLE INFO... %d %s", seats.length, seats[3].player);
    }

    function test_placeBet() public {
        fullSetup();

        table.setGameStatus(ITable.GameStatus.Bet);

        vm.startPrank(vm.randomAddress());
        table.sit(2);
        table.sit(3);
        table.placeBet(90);
    }

    function test_tableFulfillRandomWords() public {
        fullSetup();
        table.setDrawRequest(Table.DrawRequest.Start);

        uint256[] memory words = new uint256[](15);
        for (uint256 i = 0; i < 15; i++) {
            words[i] = vm.randomUint();
        }
        vm.prank(address(pit));
        table.fulfillRandomWords(words);
    }

    function test_tableInitialDeal() public {
        fullSetup();

        table.callInitialDeal();
    }

    function test_tableAddCardToHand() public {
        uint256 randomWord1 = vm.randomUint();
        uint256 randomWord2 = vm.randomUint();
        uint256 randomWord3 = vm.randomUint();

        uint256[] memory randomWords = new uint256[](3);
        randomWords[0] = randomWord1;
        randomWords[1] = randomWord2;
        randomWords[2] = randomWord3;
        table.setRandomWords(randomWords);

        table.callAddCardToHand();
        table.callAddCardToHand();
        table.callAddCardToHand();

        uint256 totalCards = table.getDrawableCards().length;
        console.logUint(totalCards);

        console.logUint(table.getCard(0));
        console.logUint(table.getCard(1));
        console.logUint(table.getCard(2));

        console.logUint(uint8(randomWord1 % totalCards));
        console.logUint(uint8(randomWord2 % totalCards));
        console.logUint(uint8(randomWord3 % totalCards));
    }

    function test_tableNextTurn() public {
        fullSetup();
        table.sit(3);
        table.sit(5);
        table.setCurrentSeatNumber(6);

        table.callNextTurn();

        console.logString("CURRENT SEAT AFTER");
        console.logUint(table.getCurrentSeatNumber());
    }

    function test_tableHit() public {
        fullSetup();
        table.sit(2);
        table.sit(3);

        uint256[] memory randomWords = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            randomWords[i] = 30;
        }
        table.setRandomWords(randomWords);
        table.callInitialDeal();

        console.logString("RANDOM WORDS LENGTH...");
        console.logUint(table.getRandomWords().length);

        console.logString("Seat Index Before hit");
        console.logUint(table.getCurrentSeatNumber());
        console.logString("Hand status Before hit");
        Table.Hand memory handBefore = table.getSeats()[1].hands[0];
        console.log("Hand status before: %i", uint256(handBefore.status));

        table.callHit();

        Table.Hand memory handAfter = table.getSeats()[1].hands[0];
        console.logString("Min value after");
        console.logUint(handAfter.minValue);
        console.logString("Seat Index after hit");
        console.logUint(table.getCurrentSeatNumber()); 
        console.log("Hand status after: %i", uint256(handAfter.status));    
    }

    function test_tableDealerPlay() public {
        fullSetup();
        table.sit(2);
        table.sit(3);
        uint256[] memory randomWords = new uint256[](9);
        randomWords[0] = 34;
        randomWords[1] = 34;
        randomWords[2] = 34;
        randomWords[3] = 34;
        randomWords[4] = 34;
        randomWords[5] = 38;
        randomWords[6] = 38;
        randomWords[7] = 30;
        randomWords[8] = 30;
        table.setRandomWords(randomWords);
        table.callInitialDeal();

        table.callDealerPlay();
        table.getSeats();
        table.getDealerHand();
    }

    function test_tableLeave() public {
        fullSetup();
        table.sit(1);
        table.sit(2);
        table.sit(3);
        table.sit(4);
        table.sit(5);
        table.sit(6);
        table.sit(7);

        table.leave(7);
    }
}