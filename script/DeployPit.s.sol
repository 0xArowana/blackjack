// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Pit} from "../src/Pit.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {console} from "forge-std/console.sol";

contract DeployPit is Script {
    function run() external returns (address) {
        HelperConfig helperConfig = new HelperConfig();

        (
            address usdc,
            address vrfCoordinator,
            bytes32 vrfKeyHash,
            uint256 vrfSubscriptionId,
            uint32 vrfCallbackGasLimit
        ) = helperConfig.activeNetworkConfig();

        Pit proxy = Pit(payable(deployPit()));

        proxy.initialize(
            usdc,
            100,
            100,
            vrfCoordinator,
            vrfKeyHash,
            vrfSubscriptionId,
            vrfCallbackGasLimit
        );

        return address(proxy);
    }

    function deployPit() public returns (address) {
        vm.startBroadcast();
        Pit pit = new Pit();
        ERC1967Proxy proxy = new ERC1967Proxy(address(pit), "");
        vm.stopBroadcast();
        return address(proxy);
    }
}