// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {IPoolAddressesProvider} from "@aave/contracts/interfaces/IPoolAddressesProvider.sol";

contract Aave is Script {
    function getPool(address _addressesProvider) external view returns (address) {
        return IPoolAddressesProvider(_addressesProvider).getPool();
    }
}