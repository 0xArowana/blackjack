// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Pit} from "../src/Pit.sol";
import {console} from "forge-std/console.sol";

contract ConfigHelper is Script {
    function getVrfConfig() public view returns (Pit.VrfConfig memory) {
        Pit.VrfConfig memory vrfConfig;

        if (block.chainid == 421614) {
            vrfConfig = Pit.VrfConfig({
                coordinator: 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61,
                keyHash: 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be,
                subscriptionId: 115678517865845314128708521410416585367502008983375723740453418397630079470798,
                callbackGasLimit: 2500000
            });
        } else if (block.chainid == 11155111) {
            vrfConfig = Pit.VrfConfig({
                coordinator: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
                keyHash: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
                subscriptionId: 36914015898050635157534080309617955626201460366891505809834490672915020740786,
                callbackGasLimit: 2500000
            });
        }

        return vrfConfig;
    }

    function getPoolAddressesProvider() public view returns (address) {
        address addressesProvider;
        
        if (block.chainid == 421614) {
            addressesProvider = 0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A;
        } else if (block.chainid == 11155111) {
            addressesProvider = 0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A;
        }
        
        return addressesProvider;
    }

    function getTokens() public view returns (address[] memory) {
        address[] memory tokens = new address[](1);
        
        if (block.chainid == 421614) {
            tokens[0] = 0xeC12Ffe943b53DF4884A55b14168553d43eA28c7;
        } else if (block.chainid == 11155111) {
            tokens[0] = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        }

        return tokens;
    }
}