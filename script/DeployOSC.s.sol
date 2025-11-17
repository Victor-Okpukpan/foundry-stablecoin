// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {OSCEngine} from "../src/OSCEngine.sol";
import {OracleStablecoin} from "../src/OracleStablecoin.sol";
import {Script} from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

contract DeployOSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (OracleStablecoin, OSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();

        ( address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast();
        OracleStablecoin oscToken = new OracleStablecoin();
        OSCEngine oscEngine = new OSCEngine(tokenAddresses, priceFeedAddresses, address(oscToken));
        oscToken.transferOwnership(address(oscEngine));
        vm.stopBroadcast();
        return (oscToken, oscEngine, config);
    }
}