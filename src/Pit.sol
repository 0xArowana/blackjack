// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {VRFConsumerBaseV2Upgradeable} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Upgradeable.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {Table} from "./Table.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Pit is UUPSUpgradeable, OwnableUpgradeable, VRFConsumerBaseV2Upgradeable {
    error Pit__NotTable();
    error Pit__VrfRequestNotFound();

    // Chainlink VRF
    address private s_vrfCoordinator;
    bytes32 private s_vrfKeyHash;
    uint64 private s_vrfSubscriptionId;
    uint32 private s_vrfCallbackGasLimit;
    mapping(uint256 _requestId => Table) public s_vrfRequests;
    
    // Tables
    address s_tableImplementation;
    mapping(address => TableState) public s_tables;

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

    function initialize(
        address _vrfCoordinator,
        bytes32 _vrfKeyHash, 
        uint64 _vrfSubscriptionId, 
        uint32 _vrfCallbackGasLimit
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __VRFConsumerBaseV2_init(_vrfCoordinator);
        
        s_vrfCoordinator = _vrfCoordinator;
        s_vrfKeyHash =  _vrfKeyHash;
        s_vrfSubscriptionId = _vrfSubscriptionId;
        s_vrfCallbackGasLimit = _vrfCallbackGasLimit;
        
        s_tableImplementation = address(new Table());
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function requestRandomWords() external onlyTable {
        VRFCoordinatorV2Interface coordinator = VRFCoordinatorV2Interface(s_vrfCoordinator);

        uint256 requestId = coordinator.requestRandomWords(
            s_vrfKeyHash, 
            s_vrfSubscriptionId, 
            3, 
            s_vrfCallbackGasLimit, 
            500
        );

        s_vrfRequests[requestId] = Table(msg.sender);
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        Table table = s_vrfRequests[_requestId];

        if (address(table) == address(0)) {
            revert Pit__VrfRequestNotFound();
        }

        table.setRandomWords(_randomWords);
    }

    function createTable(uint256 _minBet, uint256 _maxBet) external {
        address table = Clones.clone(s_tableImplementation);
        Table(table).initialize(_minBet, _maxBet);

        s_tables[table] = TableState(false, 0);
    }

    // mapping (address _dealer => mapping (uint _role => Game _game)) public currentGames

    // function deposit() external

    // function depositStaked() external

    /// @param max bet
    /// @param number of players
    /// @param timeout
    // function createGame() external
}
