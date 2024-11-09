// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Pit} from "../src/Pit.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ConfigHelper} from "./ConfigHelper.s.sol";
import {Aave} from "./Interactions.s.sol";

contract DeployPit is Script {
    uint256 constant LIQUIDATION_GRACE_PERIOD = 60;
    uint256 constant LIQUIDATION_FEE = 100;

    function run() external returns (address) {
        ConfigHelper configHelper = new ConfigHelper();
        Aave aave = new Aave();

        vm.startBroadcast();

        Pit proxy = Pit(payable(deployPit()));
    
        proxy.initialize(
            configHelper.getTokens(),
            aave.getPool(configHelper.getPoolAddressesProvider()),
            LIQUIDATION_GRACE_PERIOD,
            LIQUIDATION_FEE,
            configHelper.getVrfConfig()
        );

        vm.stopBroadcast();

        return address(proxy);
    }

    function deployPit() public returns (address) {
        Pit pit = new Pit();
        ERC1967Proxy proxy = new ERC1967Proxy(address(pit), "");
        return address(proxy);
    }
}