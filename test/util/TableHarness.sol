// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Table} from "../../src/Table.sol";

contract TableHarness is Table {
    Hand public s_hand;

    function getSeatCount() external view returns (uint8) {
        return s_seatCount;
    }

    function getBetRange() external view returns (BetRange memory) {
        return s_betRange;
    }

    function getGameStatus() external view returns (GameStatus) {
        return s_gameStatus;
    }

    function getRules() external view returns (Rules memory) {
        return s_rules;
    }

    function getDrawableCards() external view returns (uint8[] memory) {
        return s_drawableCards;
    }

    function setManager(address _manager) external {
        s_manager = _manager;
    }

    function setBalance(address _player, uint256 _amount) external {
        s_playerToBalance[_player] = _amount;
    }

    function setTestToken(address _token) external {
        s_token = _token;
    }

    function setGameStatus(GameStatus _status) external {
        s_gameStatus = _status;
    }

    function setRules(Rules memory _rules) external {
        s_rules = _rules;
    }

    function setBetTotal(uint256 _betTotal) external {
        s_betTotal = _betTotal;
    }

    function setCurrentSeatIndex(uint8 _index) external {
        s_currentSeatIndex = _index;
    }

    function setDrawRequest(DrawRequest _drawRequest) external {
        s_drawRequest = _drawRequest;
    }

    function callFinalizeBets() external {
        finalizeBets();
    }

    function getRandomWords() external view returns (uint256[] memory) {
        return s_randomWords;
    }

    function setRandomWords(uint256[] calldata _randomWords) external {
        s_randomWords = _randomWords;
    }

    function callAddCardToHand() external {
        addCardToHand(s_hand);
    }

    function getCard(uint256 _index) external view returns (uint8) {
        return s_hand.cards[_index];
    }
    
    function callResetDecks() external {
        resetDecks();
    }

    function callInitialDeal() external {
        initialDeal();
    }

    function callNextTurn() external {
        nextTurn();
    }

    function callHit() external {
        hit();
    }

    function callDealerPlay() external {
        dealerPlay();
    }
}
