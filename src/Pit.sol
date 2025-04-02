// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {VRFConsumerBaseV2PlusUpgradeable} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2PlusUpgradeable.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPit} from "./interfaces/IPit.sol";
import {ITable} from "./interfaces/ITable.sol";

contract Pit is IPit, Initializable, UUPSUpgradeable, VRFConsumerBaseV2PlusUpgradeable, ReentrancyGuard {
    error Pit__CurrencyNotEth();
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
    uint256 public s_timeout;

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

    struct ManagerToken {
        TokenInfo info;
        TokenState state;
    }

    event TableCreated(address indexed tableAddress, address indexed managerAddress, ITable.BetRange betRange);
    event Received(address indexed sender, uint256 indexed value);

    modifier onlyTable {
        if (s_tableToManager[msg.sender] == address(0)) {
            revert Pit__NotTable();
        }
        _;
    }

    modifier onlyManager(address _table) {
        if (ITable(_table).getManager() != msg.sender) {
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

        TokenState storage tokenState = s_managerToTokenToState[msg.sender][_token];
        tokenState.balance += _amount;

        if (tokenState.balance >= tokenState.allocatedTotal) {
            address[] memory tables = s_managerToTables[msg.sender];

            for (uint256 i = 0; i < tables.length; i++) {
                ITable(tables[i]).allocationCovered();
            }
        }
    }

    constructor() {
        _disableInitializers();
    }

    receive() external payable handleDeposit(address(0), msg.value) {}

    function initialize(
        address[] memory _tokens,
        address _pool,
        uint256 _timeout,
        VrfConfig memory _vrfConfig,
        address _tableImplementation
    ) public initializer {
        __UUPSUpgradeable_init();
        __VRFConsumerBaseV2Plus_init(_vrfConfig.coordinator);
        
        s_tokens = _tokens;
        s_pool = _pool;
        s_timeout = _timeout;
        s_vrfConfig = _vrfConfig;
        s_tableImplementation = _tableImplementation;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setTokens(address[] memory _tokens) external onlyOwner {
        s_tokens = _tokens;
    }

    function setTimeout(uint256 _seconds) external onlyOwner {
        s_timeout = _seconds;
    }

    function allocate(int256 _amount, address _token) external onlyTable {
        address manager = s_tableToManager[msg.sender];
        TokenState storage tokenState = s_managerToTokenToState[manager][_token];

        if (_amount < 0) {
            uint256 absValue = uint256(-_amount);

            if (absValue > tokenState.allocatedTotal) {
                tokenState.allocatedTotal = 0;
            } else {
                tokenState.allocatedTotal -= absValue;
            }
        } else {
            uint256 availableBalance = tokenState.balance - tokenState.allocatedTotal;
            uint256 amount = uint256(_amount);

            if (amount > availableBalance) {
                revert Pit__InsufficientManagerBalance();
            }

            tokenState.allocatedTotal += amount;
        }
    }

    function gameEnded(address _token, int256 _earnings) external payable onlyTable nonReentrant {
        if (_token != address(0) && msg.value > 0) {
            revert Pit__CurrencyNotEth();
        }

        address manager = s_tableToManager[msg.sender];
        TokenState storage tokenState = s_managerToTokenToState[manager][_token];

        if (_earnings < 0) {
            uint256 earningsAbs = uint256(-_earnings);
            tokenState.balance -= earningsAbs;

            uint256 ethAmount;

            if (_token == address(0)) {
                ethAmount = earningsAbs;
            } else {
                ERC20(_token).approve(msg.sender, earningsAbs);
            }

            bool needsAllocation = tokenState.balance < tokenState.allocatedTotal;
            ITable(msg.sender).clearDebt{value: ethAmount}(needsAllocation);
        } else if (_earnings > 0) {
            uint256 earnings = uint256(_earnings);

            if (_token == address(0)) {
                if (msg.value != earnings) {
                    revert Pit__InvalidEarningsAmountSent();
                }
            } else {
                bool success = ERC20(_token).transferFrom(msg.sender, address(this), earnings);

                if (!success) {
                    revert Pit__TokenTransferFailed();
                }
            }

            tokenState.balance += earnings;
        }
    }

    function requestRandomWords(uint32 _numWords) external onlyTable {
        IVRFCoordinatorV2Plus coordinator = IVRFCoordinatorV2Plus(s_vrfConfig.coordinator);

        uint256 requestId = coordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_vrfConfig.keyHash,
                subId: s_vrfConfig.subscriptionId, 
                requestConfirmations: 1, 
                callbackGasLimit: s_vrfConfig.callbackGasLimit, 
                numWords: _numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({ nativePayment: false }))
            })
        );

        s_vrfRequests[requestId] = msg.sender;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        uint256 startingGas = gasleft();
        address table = s_vrfRequests[_requestId];

        if (address(table) == address(0)) {
            revert Pit__VrfRequestNotFound();
        }

        ITable(table).fulfillRandomWords(_randomWords);
        
        uint256 gasUsed = startingGas - gasleft();
        uint256 gasCost = gasUsed * tx.gasprice;
        // TODO: Charge gas fees to table owner
    }

    function deposit(address _token, uint256 _amount) external approveToken(_token, false) handleDeposit(_token, _amount) {
        bool success = ERC20(_token).transferFrom(msg.sender, address(this), _amount);

        if (!success) {
            revert Pit__TokenTransferFailed();
        }

        // TODO: Sort out Aave accounting
        // IPool(s_pool).supply(_token, _amount, address(this), 0);
    }

    function createTable(
        uint8 _seatCount,
        ITable.BetRange memory _betRange,
        ITable.Rules memory _rules,
        address _token
    ) external approveToken(_token, true) {
        address table = Clones.clone(s_tableImplementation);
        s_tableToManager[table] = msg.sender;
        s_managerToTables[msg.sender].push(table);

        ITable(table).initialize(
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

    function getTimeout() external view returns (uint256) {
        return s_timeout;
    }

    function getPlayerTable(address _player) external view returns (address) {
        return s_playerToTable[_player];
    }

    function getManagerTokenState(address _manager, address _token) external view returns (TokenState memory) {
        return s_managerToTokenToState[_manager][_token];
    }

    function getManagerTableInfo(address _manager) external view returns (ITable.TableInfo[] memory) {
        address[] storage tables = s_managerToTables[_manager];
        ITable.TableInfo[] memory tableInfo = new ITable.TableInfo[](tables.length);

        for (uint8 i = 0; i < tables.length; i++) {
            tableInfo[i] = ITable(tables[i]).getTableInfo();
        }

        return tableInfo;
    }

    function getManagerTokens(address _manager) external view returns (ManagerToken[] memory) {
        ManagerToken[] memory tokens = new ManagerToken[](s_tokens.length + 1);

        TokenInfo memory ethInfo = TokenInfo(
            address(0), 
            "ETH", 
            "Ether",
            18
        );
        TokenState memory ethState = s_managerToTokenToState[_manager][address(0)];
        tokens[0] = ManagerToken(ethInfo, ethState);

        for (uint8 i = 0; i < s_tokens.length; i++) {
            address token = s_tokens[i];
            TokenInfo memory info = TokenInfo(
                token,
                ERC20(token).symbol(), 
                ERC20(token).name(),
                ERC20(token).decimals()
            );
            TokenState memory state = s_managerToTokenToState[_manager][token];
            tokens[i + 1] = ManagerToken(info, state);
        }

        return tokens;
    }

    function getPlayerTableInfo(address _player) external view returns (ITable.TableInfo memory) {
        address table = s_playerToTable[_player];
        return ITable(table).getTableInfo();
    }
    
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }
}
