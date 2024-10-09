// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {Table} from "./Table.sol";

contract Pit is VRFConsumerBaseV2Plus {
    error Pit__NotTable();
    error Pit__VrfRequestNotFound();

    bytes32 private immutable i_vrfKeyHash;
    uint256 private immutable i_vrfSubscriptionId;
    uint32 private immutable i_vrfCallbackGasLimit;

    mapping(address => TableState) public s_tables;
    mapping(uint256 _requestId => Table) public s_vrfRequests;

    struct TableState {
        bool isActive;
        uint64 spotsFilled;
    }

    modifier onlyTable {
        if (!s_tables[msg.sender].isActive) {
            revert Pit__NotTable();
        }
        _;
    }
    constructor(
        bytes32 vrfKeyHash,
        uint256 vrfSubscriptionId,
        uint32 vrfCallbackGasLimit,
        address vrfCoordinator
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_vrfKeyHash =  vrfKeyHash;
        i_vrfSubscriptionId = vrfSubscriptionId;
        i_vrfCallbackGasLimit = vrfCallbackGasLimit;
    }

    function requestRandomWords() external onlyTable {
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_vrfKeyHash,
                subId: i_vrfSubscriptionId,
                requestConfirmations: 3,
                callbackGasLimit: i_vrfCallbackGasLimit,
                numWords: 10,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: false
                    })
                )
            })
        );

        s_vrfRequests[requestId] = Table(msg.sender);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        Table table = s_vrfRequests[_requestId];

        if (address(table) == address(0)) {
            revert Pit__VrfRequestNotFound();
        }

        table.fulfillRandomWords(_randomWords);
    }

    // mapping (address _dealer => mapping (uint _role => Game _game)) public currentGames

    // function deposit() external

    // function depositStaked() external

    /// @param max bet
    /// @param number of players
    /// @param timeout
    // function createGame() external

    

}
