// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {VRFConsumerBaseV2Upgradeable} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Upgradeable.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Table} from "./Table.sol";

contract Pit is Initializable, UUPSUpgradeable, OwnableUpgradeable, VRFConsumerBaseV2Upgradeable, ReentrancyGuard {
    error Pit__CurrencyNotEth();
    error Pit__InsufficientBalance();
    error Pit__InsufficientManagerBalance();
    error Pit__InvalidEarningsAmountSent();
    error Pit__NotApprovedToken();
    error Pit__NotManager();
    error Pit__NotTable();
    error Pit__TokenTransferFailed();
    error Pit__VrfRequestNotFound();

    // Config
    address[] private s_tokens;
    address s_pool;
    uint256 public s_playerTimeout;

    // Chainlink VRF
    VrfConfig internal s_vrfConfig;
    mapping(uint256 _requestId => address) public s_vrfRequests;

    // Managers
    mapping(address => address[]) public s_managerToTables;
    mapping(address => mapping(address => TokenState)) public s_managerToTokenToState;

    // Players
    mapping(address => address) public s_playerToTable;

    // Tables
    address s_tableImplementation;
    mapping(address => address) public s_tableToManager;

    struct VrfConfig {
        address coordinator;
        bytes32 keyHash;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
    }

    struct TokenState {
        uint256 balance;
        uint256 maxPayout;
    }

    event TableCreated(address indexed tableAddress, address indexed managerAddress, Table.BetRange betRange);
    event Received(address indexed sender, uint256 indexed value);

    modifier onlyTable {
        if (s_tableToManager[msg.sender] == address(0)) {
            revert Pit__NotTable();
        }
        _;
    }

    modifier onlyManager(address _table) {
        if (Table(payable(_table)).s_manager() != msg.sender) {
            revert Pit__NotManager();
        }
        _;
    }

    modifier approveToken(address _token, bool _allowEth) {
        bool approved = false;
        
        if (_allowEth && _token == address(0)) {
            approved = true;
        } else {
            for (uint8 i = 0; i < s_tokens.length; i++) {
                if (s_tokens[i] == _token) {
                    approved = true;
                    break;
                }
            }
        }

        if (!approved) {
            revert Pit__NotApprovedToken();
        }

        _;
    }

    modifier handleDeposit(address _token, uint256 _amount) {
        _;

        TokenState memory state = s_managerToTokenToState[msg.sender][_token];
        uint256 newBalance = state.balance + _amount;

        // Unlock locked tables if sufficient balance
        if (state.balance < state.maxPayout && newBalance >= state.maxPayout) {
            address[] memory tables = s_managerToTables[msg.sender];

            for (uint256 i = 0; i < tables.length; i++) {
                Table(payable(tables[i])).unlock();
            }
        }

        s_managerToTokenToState[msg.sender][_token].balance = newBalance;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address[] memory _tokens,
        address _pool,
        uint256 _playerTimeout,
        VrfConfig memory _vrfConfig,
        address _tableImplementation
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __VRFConsumerBaseV2_init(_vrfConfig.coordinator);
        
        s_tokens = _tokens;
        s_pool = _pool;
        s_playerTimeout = _playerTimeout;
        s_vrfConfig = _vrfConfig;
        s_tableImplementation = _tableImplementation;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setTokens(address[] memory _tokens) external onlyOwner {
        s_tokens = _tokens;
    }

    function setPlayerTimeout(uint256 _seconds) external onlyOwner {
        s_playerTimeout = _seconds;
    }

    function increaseMaxPayout(uint256 _amount, address _token) external onlyTable {
        address manager = s_tableToManager[msg.sender];
        s_managerToTokenToState[manager][_token].maxPayout += _amount;
    }

    function decreaseMaxPayout(uint256 _amount, address _token) external onlyTable {
        address manager = s_tableToManager[msg.sender];        
        s_managerToTokenToState[manager][_token].maxPayout -= _amount;
    }

    function gameEnded(address _token, int256 _earnings, uint256 _gameMaxPayout) external payable onlyTable nonReentrant {
        if (_token != address(0) && msg.value > 0) {
            revert Pit__CurrencyNotEth();
        }

        address manager = s_tableToManager[msg.sender];
        TokenState storage tokenState = s_managerToTokenToState[manager][_token];
        tokenState.maxPayout -= _gameMaxPayout;

        if (_earnings < 0) {
            uint256 absValue = uint256(-_earnings);
            tokenState.balance -= absValue;
            uint256 ethAmount;

            if (_token == address(0)) {
                ethAmount = absValue;
            } else {
                IERC20(_token).approve(msg.sender, absValue);
            }

            Table(msg.sender).clearDebt{value: ethAmount}();

            // Lock tables if token balance less than maxPayout
            // NOTE: This should never happen - test this invariant
            if (tokenState.balance < tokenState.maxPayout) {
                address[] memory tables = s_managerToTables[msg.sender];

                for (uint256 i = 0; i < tables.length; i++) {
                    Table table = Table(tables[i]);
                    
                    if (table.s_token() == _token) {
                        table.lock();
                    }
                }
            }
        } else if (_earnings > 0) {
            uint256 earnings = uint256(_earnings);

            if (_token == address(0)) {
                if (msg.value != earnings) {
                    revert Pit__InvalidEarningsAmountSent();
                }
            } else {
                bool success = IERC20(_token).transferFrom(msg.sender, address(this), earnings);

                if (!success) {
                    revert Pit__TokenTransferFailed();
                }
            }

            s_managerToTokenToState[manager][_token].balance += earnings;
        }
    }

    function requestRandomWords() external onlyTable {
        IVRFCoordinatorV2Plus coordinator = IVRFCoordinatorV2Plus(s_vrfConfig.coordinator);

        uint256 requestId = coordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_vrfConfig.keyHash, 
                subId: s_vrfConfig.subscriptionId, 
                requestConfirmations: 3, 
                callbackGasLimit: s_vrfConfig.callbackGasLimit, 
                numWords: 500,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({ nativePayment: false }))
            })
        );

        s_vrfRequests[requestId] = msg.sender;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        address table = s_vrfRequests[_requestId];

        if (address(table) == address(0)) {
            revert Pit__VrfRequestNotFound();
        }

        Table(payable(table)).setRandomWords(_randomWords);
    }

    function deposit(address _token, uint256 _amount) external approveToken(_token, false) handleDeposit(_token, _amount) {
        bool success = IERC20(_token).transferFrom(msg.sender, address(this), _amount);

        if (!success) {
            revert Pit__TokenTransferFailed();
        }

        // TODO: Sort out Aave accounting
        IPool(s_pool).supply(_token, _amount, address(this), 0);
    }

    function createTable(
        uint8 _seatCount,
        Table.BetRange memory _betRange,
        Table.Rules memory _rules,
        address _token
    ) external approveToken(_token, true) {        
        address table = Clones.clone(s_tableImplementation);
        s_tableToManager[table] = msg.sender;
        s_managerToTables[msg.sender].push(table);

        Table(payable(table)).initialize(
            msg.sender, 
            _seatCount,
            _betRange,
            _rules,
            _token
        );

        emit TableCreated(table, msg.sender, _betRange);
    }

    function playerSeated(address _player) external onlyTable {
        s_playerToTable[_player] = msg.sender;
    }

    function playerLeft(address _player) external onlyTable {
        s_playerToTable[_player] = address(0);
    }

    function getManagerTableInfo(address _manager) external view returns (Table.TableInfo[] memory) {
        address[] storage tables = s_managerToTables[_manager];
        Table.TableInfo[] memory tableInfo = new Table.TableInfo[](tables.length);

        for (uint8 i = 0; i < tables.length; i++) {
            tableInfo[i] = Table(tables[i]).getTableInfo();
        }

        return tableInfo;
    }

    function getPlayerTableInfo(address _player) external view returns (Table.TableInfo memory) {
        address table = s_playerToTable[_player];
        return Table(table).getTableInfo();
    }
    
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }
}
