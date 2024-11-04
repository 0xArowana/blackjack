// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address[] approvedTokens;
        address vrfCoordinator;
        bytes32 vrfKeyHash;
        uint256 vrfSubscriptionId; 
        uint32 vrfCallbackGasLimit;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 421614) {
            activeNetworkConfig = getSepoliaArbitrumConfig();
        } else if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        }
    }

    function getSepoliaArbitrumConfig() public pure returns (NetworkConfig memory) {
        address[] memory tokens;
        tokens[0] = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;

        return NetworkConfig({
            approvedTokens: tokens,
            vrfCoordinator: 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61,
            vrfKeyHash: 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be,
            vrfSubscriptionId: 115678517865845314128708521410416585367502008983375723740453418397630079470798,
            vrfCallbackGasLimit: 500000
        });
    }

    function getSepoliaConfig() public pure returns (NetworkConfig memory) {
        address[] memory tokens;
        tokens[0] = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        
        return NetworkConfig({
            approvedTokens: tokens,
            vrfCoordinator: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
            vrfKeyHash: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
            vrfSubscriptionId: 36914015898050635157534080309617955626201460366891505809834490672915020740786,
            vrfCallbackGasLimit: 500000
        });
    }
}