// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFConsumerBaseV2Upgradeable} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Upgradeable.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {Table} from "./Table.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Pit is Initializable, UUPSUpgradeable, OwnableUpgradeable, VRFConsumerBaseV2Upgradeable {
    error Pit__InsufficientBalance();
    error Pit__NotApprovedToken();
    error Pit__NotManager();
    error Pit__NotTable();
    error Pit__VrfRequestNotFound();
    error Pit__InsufficientManagerBalance();
    error Pit__InvalidMaxPlayers();
    error Pit__InvalidManagerBalance();

    uint256 public constant LIQUIDATION_FEE_PRECISION = 10000;

    // Config
    address[] private s_approvedTokens;
    uint256 public s_liquidationGracePeriod;
    uint256 public s_liquidationFee;

    // Chainlink VRF
    address private s_vrfCoordinator;
    bytes32 private s_vrfKeyHash;
    uint256 private s_vrfSubscriptionId;
    uint32 private s_vrfCallbackGasLimit;
    mapping(uint256 _requestId => Table) public s_vrfRequests;

    // Managers
    mapping(address => address[]) public s_managerToTables;
    mapping(address => mapping(address => uint256)) public s_managerToTokenToBalance;

    // Tables
    address s_tableImplementation;
    mapping(address => address) public s_tableToManager;

    event TableCreated(address indexed tableAddress, address indexed managerAddress, Table.BetRange betRange);
    event Received(address indexed sender, uint256 indexed value);

    modifier onlyTable {
        if (s_tableToManager[msg.sender] != address(0)) {
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

    modifier approveToken(address _token) {
        bool approved = false;
        
        for (uint8 i = 0; i < s_approvedTokens.length; i++) {
            if (s_approvedTokens[i] == _token) {
                approved = true;
                break;
            }
        }

        if (!approved) {
            revert Pit__NotApprovedToken();
        }
        _;
    }

    function initialize(
        address[] memory _approvedTokens,
        uint256 _liquidationGracePeriod,
        uint256 _liquidationFee,
        address _vrfCoordinator,
        bytes32 _vrfKeyHash, 
        uint256 _vrfSubscriptionId, 
        uint32 _vrfCallbackGasLimit
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __VRFConsumerBaseV2_init(_vrfCoordinator);
        
        s_approvedTokens = _approvedTokens;
        s_liquidationGracePeriod = _liquidationGracePeriod;
        s_liquidationFee = _liquidationFee;
        s_vrfCoordinator = _vrfCoordinator;
        s_vrfKeyHash =  _vrfKeyHash;
        s_vrfSubscriptionId = _vrfSubscriptionId;
        s_vrfCallbackGasLimit = _vrfCallbackGasLimit;
        
        s_tableImplementation = address(new Table());
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setApprovedTokens(address[] memory _tokens) external onlyOwner {
        s_approvedTokens = _tokens;
    }

    function setLiquidationGracePeriod(uint256 _seconds) external onlyOwner {
        s_liquidationGracePeriod = _seconds;
    }

    function setLiquidationFee(uint256 _percentage) external onlyOwner {
        s_liquidationFee = _percentage;
    }

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

    function getAvailableBalance(address _manager, address _token) private view returns(uint256) {
        uint256 balance = s_managerToTokenToBalance[_manager][_token];
        uint256 unavailableBalance = getUnavailableBalance(_manager, _token);

        if (unavailableBalance > balance) {
            revert Pit__InvalidManagerBalance();
        }
 
        return balance - unavailableBalance;
    }

    function getUnavailableBalance(address _manager, address _token) private view returns(uint256) {
        uint256 balance = 0;
        address[] memory tables = s_managerToTables[_manager];

        for (uint8 i = 0; i < tables.length; i++) {
            Table table = Table(tables[i]);

            if (table.s_token() == _token) {
                balance += table.s_managerBalance();
            }
        }

        return balance;
    }

    function deposit(address _token, uint256 _amount) {

    }

    function createTable(
        uint8 _maxPlayers,
        Table.BetRange memory _betRange,
        Table.Rules memory _rules,
        address _token,
        uint256 _startingBalance
    ) external approveToken(_token) {
        if (_maxPlayers < 1 || _maxPlayers > 7) {
            revert Pit__InvalidMaxPlayers();
        }
        
        address table = Clones.clone(s_tableImplementation);
        Table(table).initialize(
            msg.sender, 
            _maxPlayers,
            _betRange,
            _rules,
            _token
        );

        if (_startingBalance > 0) {
            fundTable(table, _startingBalance);
        }

        s_tableToManager[table] = msg.sender;
        s_managerToTables[msg.sender].push(table);

        emit TableCreated(table, msg.sender, _betRange);
    }

    function fundTable(address _table, uint256 _amount) public onlyManager(_table) {        
        address token = Table(_table).s_token();
        uint256 availableBalance = getAvailableBalance(msg.sender, token);

        if (_amount > availableBalance) {
            revert Pit__InsufficientBalance();
        }

        Table(_table).fund(_amount);
    }
    
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function chargeFee() external {
        address manager = s_tableToManager[msg.sender];

        if (manager == address(0)) {
            revert Pit__NotTable();
        }

        Table table = Table(msg.sender);
        uint256 feePercentage = s_liquidationFee / LIQUIDATION_FEE_PRECISION;
        uint256 feeAmount = table.s_managerBalance() * feePercentage;

        if (s_managerToTokenToBalance[manager][table.s_token()] < feeAmount) {
            revert Pit__InsufficientManagerBalance();
        }

        s_managerToTokenToBalance[manager][table.s_token()] -= feeAmount;
    }

    // mapping (address _dealer => mapping (uint _role => Game _game)) public currentGames

    // function depositStaked() external

    /// @param max bet
    /// @param number of players
    /// @param timeout
    // function createGame() external
}
