// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Pit} from "../../src/Pit.sol";

contract PitHarness is Pit {
    function setTableToManager(address _table, address _manager) external {
        s_tableToManager[_table] = _manager;
    }

    function setManagerToTokenToState(address _manager, address _token, TokenState memory _state) external {
        s_managerToTokenToState[_manager][_token] = _state;
    }

    function setVrfRequest(uint256 _requestId, address _table) external {
        s_vrfRequests[_requestId] = _table;
    }

    function callFulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) external {
        fulfillRandomWords(_requestId, _randomWords);
    }
}