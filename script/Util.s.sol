// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Pit} from "../src/Pit.sol";
import {ITable} from "../src/interfaces/ITable.sol";
import {Table} from "../src/Table.sol";
import {console} from "forge-std/console.sol";

contract SetTokens is Script {
    function run() external {
        vm.startBroadcast();
        Pit pit = Pit(payable(0x990aD8A81553735fCc80d4eCB00f4C2c54fb7dD3));
        address[] memory tokens = new address[](1);
        tokens[0] = 0xeC12Ffe943b53DF4884A55b14168553d43eA28c7;
        pit.setTokens(tokens);
        vm.stopBroadcast();
    }
}

contract GetLock is Script {
    function run() external returns(ITable.Lock memory) {
        vm.startBroadcast();
        Table table = Table(0x974D22e8363325e1d20F92c3F2B723B440248582);
        ITable.TableInfo memory info = table.getTableInfo();
        vm.stopBroadcast();
        return info.lock;
    }
}

contract CreateTable is Script {
    function run() external {
        vm.startBroadcast();
        Pit pit = Pit(payable(0x12B17178B7B12b2e188bAA6A1543e1DDdCcA8560));
        pit.createTable(
            4, 
            ITable.BetRange(1,100), 
            ITable.Rules(
                2, // deckCount
                ITable.DeckReset.EveryHand,
                false, // dealerHitOnSoft17
                false, // allowDoubleAfterSplit
                ITable.DoubleRule.Any, // doubleRule
                3, // maxResplitHands
                true, // allowResplitAces
                true, // allowHitSplitAces
                true, // allowLateSurrender
                true, // allowInsurance
                false // sixToFive
            ),
            0xeC12Ffe943b53DF4884A55b14168553d43eA28c7
        );
        vm.stopBroadcast();
    }
}

contract PlaceBet is Script {
    function run() external {
        vm.startBroadcast();
        // Pit pit = Pit(payable(0x1816fBdAb809D6B67Ce7CF75586E51A4795d5534));
        Table table = Table(0x142Cbe6a66aED310db9D0560c7d0268e4Ec9d9bb);
        table.placeBet(0.55 * 10 ** 18);
        vm.stopBroadcast();
    }
}

contract Hit is Script {
    function run() external {
        vm.startBroadcast();
        Table table = Table(0xED8e6fA487cCbb02182E573dBf7CC9EED3f1729B);
        table.requestHit();
        vm.stopBroadcast();
    }
}

contract Stand is Script {
    function run() external {
        vm.startBroadcast();
        Table table = Table(0xED8e6fA487cCbb02182E573dBf7CC9EED3f1729B);
        table.stand();
        vm.stopBroadcast();
    }
}

contract DealerPlay is Script {
    function run() external {
        vm.startBroadcast();
        Table table = Table(0xf69524c3f0a5234bD78c3cC3e75724eaA1D8e87E);
        // table.dealerPlay();
        vm.stopBroadcast();
    }
}

contract FulfillRandomWords is Script {
    function run() external {
        vm.startBroadcast();
        Table table = Table(0xbf135B5D18A5cb014fbd28109C48C4a265668578);
        uint256[] memory words = new uint256[](15);
        for (uint256 i = 1; i < 13; i++) {
            words[i] = i;
        }
        table.fulfillRandomWords(words);
        vm.stopBroadcast();
    }
}