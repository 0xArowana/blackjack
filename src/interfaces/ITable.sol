// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IPit} from "./IPit.sol";

interface ITable {
    // @notice The range in which bets may be placed
    struct BetRange {
      uint256 min;
      uint256 max;
    }

    // @notice Standard blackjack parameters by which the game logic operates
    struct Rules {
      uint8 deckCount;
      DeckReset deckReset;
      bool dealerHitOnSoft17;
      bool allowDoubleAfterSplit;
      DoubleRule doubleRule;
      uint8 maxResplitHands;
      bool allowResplitAces;
      bool allowHitSplitAces;
      bool allowLateSurrender;
      bool allowInsurance;
      bool sixToFive;
    }

    struct SeatInfo {
      address player;
      uint256 bet;
    }

    // @notice Determines the hand values for which the bet can be doubled
    enum DoubleRule {
      Any,
      NineToEleven,
      TenToEleven
    }

    // @notice Determines the hand value forward which the bet can be doubled
    enum DeckReset {
      EveryHand,
      FourDecksLeft,
      TwoDecksLeft
    }

    // @notice The status of the current game
    enum GameStatus {
        Bet,
        Pending,
        Insurance,
        PlayerTurn,
        DealerTurn
    }

    struct TableInfo {
      address id;
      address manager;
      IPit.TokenInfo tokenInfo;
      GameStatus gameStatus;
      SeatInfo[] seats;
      uint8 seatCount;
      BetRange betRange;
      Rules rules;
      uint256 lockTimestamp;
    }

    function initialize(address _manager, uint8 _seatCount, BetRange memory _betRange, Rules memory _rules, address _token) external;

    function getToken() external view returns (address);

    function getManager() external view returns (address);

    function getTableInfo() external view returns(TableInfo memory);

    function lock() external;

    function unlock() external;

    function clearDebt() external payable;

    function fulfillRandomWords(uint256[] calldata _randomWords) external;

}