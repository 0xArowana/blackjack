// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Table} from "./Table.sol";

contract Game is Initializable, OwnableUpgradeable {


    // address currentTurn
        // dealer address is "this"

    // function placeBet external payable
        // TODO: Should payable function actually be on Pit, where earnings/deposits are held? (save gas without transfer between contracts)
        // TODO: How should game create/start flow go and which contract owns it?

        // check status of game - revert if not in "START"
        // check role of msg.sender - if dealer, revert
        // check max and min bets - revert if outside bounds
        // check if bet has already been placed - revert if so

        // set bet amount for player in bets mapping
        // start game if last player

    // function dealCard(address) private
        // check status of game? (revert if not in "ACTIVE")
        
        // call chainlink VRF, (check if already got card/number 6 times?)
        // evaluate game status

    // function evaluateStatus internal
        // if currentTerm == "this" (i.e. dealer)
            // dealerPlay
        // else

    // function dealerPlay internal
        // dealerTotal = sum of values of hands[this] (or store hand totals)

        // if dealerTotal < 17
            // dealCard(this)
        // else if dealerTotal >= 21
            // 

}
