// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

contract TableMock {
    uint256 public drawCardsCallCount;

    function drawCards() external {
        drawCardsCallCount++;
    }
}
