// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFConsumerBaseV2Upgradeable} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Upgradeable.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {Table} from "./Table.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Pit is Initializable, UUPSUpgradeable, OwnableUpgradeable, VRFConsumerBaseV2Upgradeable {
    error Pit__NotTable();
    error Pit__VrfRequestNotFound();
    error Pit__InvalidMaxBet();
    error Pit__InvalidMaxPlayers();

    // Managers
    mapping(address => uint256) public s_managerToBalance;

    address private s_usdc;
    uint256 private s_minAvailableEth;
    uint256 private s_minAvailableUsdc;

    // Chainlink VRF
    address private s_vrfCoordinator;
    bytes32 private s_vrfKeyHash;
    uint256 private s_vrfSubscriptionId;
    uint32 private s_vrfCallbackGasLimit;
    mapping(uint256 _requestId => Table) public s_vrfRequests;
    
    // Tables
    address s_tableImplementation;
    mapping(address => TableState) public s_tableToState;
    mapping(address => address[]) public s_managerToTables;

    enum Currency {
        ETH,
        USDC
    }

    struct TableState {
        bool isActive;
        uint64 spotsFilled;
    }

    event TableCreated(address indexed tableAddress, address indexed managerAddress, uint256 minBet, uint256 maxBet);
    event Received(address indexed sender, uint256 indexed value);

    modifier onlyTable {
        if (!s_tableToState[msg.sender].isActive) {
            revert Pit__NotTable();
        }
        _;
    }

    function initialize(
        address _usdc,
        uint256 _minAvailableEth,
        uint256 _minAvailableUsdc,
        address _vrfCoordinator,
        bytes32 _vrfKeyHash, 
        uint256 _vrfSubscriptionId, 
        uint32 _vrfCallbackGasLimit
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __VRFConsumerBaseV2_init(_vrfCoordinator);
        
        s_usdc = _usdc;
        s_minAvailableEth = _minAvailableEth;
        s_minAvailableUsdc = _minAvailableUsdc;
        s_vrfCoordinator = _vrfCoordinator;
        s_vrfKeyHash =  _vrfKeyHash;
        s_vrfSubscriptionId = _vrfSubscriptionId;
        s_vrfCallbackGasLimit = _vrfCallbackGasLimit;
        
        s_tableImplementation = address(new Table());
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function requestRandomWords() external onlyTable {
        IVRFCoordinatorV2Plus coordinator = IVRFCoordinatorV2Plus(s_vrfCoordinator);

        uint256 requestId = coordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_vrfKeyHash, 
                subId: s_vrfSubscriptionId, 
                requestConfirmations: 3, 
                callbackGasLimit: s_vrfCallbackGasLimit, 
                numWords: 500,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({ nativePayment: false }))
            })
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

    function getAvailableBalance(address _manager, Currency _currency) private view returns(uint256) {
        if (_currency == Currency.USDC) {

        } else {
            
        }
    }

    function createTable(uint256 _minBet, uint256 _maxBet, uint8 _maxPlayers, Currency _currency) external {
        if (_maxBet == 0) {
            revert Pit__InvalidMaxBet();
        }

        if (_maxPlayers < 1 || _maxPlayers > 7) {
            revert Pit__InvalidMaxPlayers();
        }

        uint256 balance = s_managerToBalance[msg.sender];
        uint256 maxPayout = _maxBet * _maxPlayers;

        uint256 availableBalance = getAvailableBalance(msg.sender, _currency);
        
        address table = Clones.clone(s_tableImplementation);
        Table(table).initialize(_minBet, _maxBet, _maxPlayers, _currency);

        s_tableToState[table] = TableState(false, 0);
        s_managerToTables[msg.sender].push(table);

        emit TableCreated(table, msg.sender, _minBet, _maxBet);
    }

    receive() external payable {
        s_managerToBalance[msg.sender] += msg.value;

        emit Received(msg.sender, msg.value);
    }

    // mapping (address _dealer => mapping (uint _role => Game _game)) public currentGames

    // function deposit() external

    // function depositStaked() external

    /// @param max bet
    /// @param number of players
    /// @param timeout
    // function createGame() external
}
