// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IPit {
  struct TokenInfo {
    address id;
    string symbol;
    string name;
    uint8 decimals;
  }

  struct TokenState {
    uint256 balance;
    uint256 allocatedTotal;
  }

  function getTimeout() external view returns (uint256);

  function getPlayerTable(address _player) external view returns (address);

  function allocate(int256 _amount, address _token) external;

  function playerSeated(address _player) external;

  function playerLeft(address _player) external;

  function gameEnded(address _token, int256 _earnings) external payable;

  function requestRandomWords(uint32 _numWords) external;
}