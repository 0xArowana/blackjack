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
    uint256 allocated;
  }

  function getPlayerTable(address _player) external view returns (address);

  function getManagerTokenState(address _manager, address _token) external view returns (TokenState memory);

  function allocate(uint256 _amount, address _token) external;

  function playerSeated(address _player) external;

  function playerLeft(address _player) external;

  function gameEnded(address _token, int256 _earnings, uint256 _gameAllocation) external payable;

  function requestRandomWords(uint32 _numWords) external;
}