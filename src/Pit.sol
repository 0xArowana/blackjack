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
    error Pit__InsufficientBalance();
    error Pit__NotManager();
    error Pit__NotTable();
    error Pit__VrfRequestNotFound();
    error Pit__InvalidMaxBet();
    error Pit__InvalidMaxPlayers();
    error Pit__InvalidStartingBalance();

    // Managers
    mapping(address => uint256) public s_managerToEthBalance;

    address private s_usdc;
    uint256 private s_minTableReservesEth;
    uint256 private s_minTableReservesUsdc;

    // Chainlink VRF
    address private s_vrfCoordinator;
    bytes32 private s_vrfKeyHash;
    uint256 private s_vrfSubscriptionId;
    uint32 private s_vrfCallbackGasLimit;
    mapping(uint256 _requestId => Table) public s_vrfRequests;
    
    // Tables
    address s_tableImplementation;
    mapping(address => TableState) public s_tableToState;
    mapping(address => Table[]) public s_managerToTables;

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

    modifier onlyManager(address _table) {
        if (Table(_table).s_manager() != msg.sender) {
            revert Pit__NotManager();
        }
        _;
    }

    function initialize(
        address _usdc,
        uint256 _minTableReservesEth,
        uint256 _minTableReservesUsdc,
        address _vrfCoordinator,
        bytes32 _vrfKeyHash, 
        uint256 _vrfSubscriptionId, 
        uint32 _vrfCallbackGasLimit
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __VRFConsumerBaseV2_init(_vrfCoordinator);
        
        s_usdc = _usdc;
        s_minTableReservesEth = _minTableReservesEth;
        s_minTableReservesUsdc = _minTableReservesUsdc;
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

    function getBalance(address _manager, Currency _currency) private view returns(uint256) {
        if (_currency == Currency.USDC) {
            return 0;
        }

        return s_managerToEthBalance[_manager];
    }

    function getAvailableBalance(address _manager, Currency _currency) private view returns(uint256) {
        uint256 balance = getBalance(_manager, _currency);
        uint256 unavailableBalance = getUnavailableBalance(_manager, _currency);
        return balance - unavailableBalance;
    }

    function getUnavailableBalance(address _manager, Currency _currency) private view returns(uint256) {
        uint256 balance = 0;
        Table[] memory tables = s_managerToTables[_manager];

        for (uint8 i = 0; i < tables.length; i++) {
            Table table = tables[i];

            if (table.s_currency() == _currency) {
                balance += table.s_managerBalance();
            }
        }

        return balance;
    }

    function getMinTableReserves(Currency _currency) private view returns(uint256) {
        if (_currency == Currency.USDC) {
            return s_minTableReservesUsdc;
        }

        return s_minTableReservesEth;
    }

    function createTable(uint256 _minBet, uint256 _maxBet, uint8 _maxPlayers, Currency _currency, uint256 _startingBalance) external {
        if (_maxBet == 0) {
            revert Pit__InvalidMaxBet();
        }

        if (_maxPlayers < 1 || _maxPlayers > 7) {
            revert Pit__InvalidMaxPlayers();
        }

        uint256 maxPayout = _maxBet * _maxPlayers;
        uint256 minBalance = maxPayout + getMinTableReserves(_currency);
        
        if (_startingBalance > 0 && _startingBalance < minBalance) {
            revert Pit__InvalidStartingBalance();
        }

        uint256 availableBalance = getAvailableBalance(msg.sender, _currency);
        uint256 amountToFund = max(minBalance, _startingBalance);

        if (availableBalance < amountToFund) {
            revert Pit__InsufficientBalance();
        }
        
        address table = Clones.clone(s_tableImplementation);
        Table(table).initialize(msg.sender, _minBet, _maxBet, _maxPlayers, _currency);

        fundTable(table, amountToFund);

        s_tableToState[table] = TableState(false, 0);
        s_managerToTables[msg.sender].push(Table(table));

        emit TableCreated(table, msg.sender, _minBet, _maxBet);
    }

    function fundTable(address _table, uint256 _amount) public payable onlyManager(_table) {
        if (msg.value > 0) {
            s_managerToEthBalance[msg.sender] += msg.value;
            emit Received(msg.sender, msg.value);
        }
        
        Currency currency = Table(_table).s_currency();
        uint256 availableBalance = getAvailableBalance(msg.sender, currency);

        if (_amount < availableBalance) {
            revert Pit__InsufficientBalance();
        }

        Table(_table).fund(_amount);
    }
    
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    receive() external payable {
        s_managerToEthBalance[msg.sender] += msg.value;

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
