// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, StdInvariant} from "forge-std/Test.sol";
import {DeployOSC} from "../../script/DeployOSC.s.sol";
import {OracleStablecoin} from "../../src/OracleStablecoin.sol";
import {OSCEngine} from "../../src/OSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract Invariant is StdInvariant, Test {
    DeployOSC deployer;
    OracleStablecoin oscToken;
    OSCEngine oscEngine;
    HelperConfig config;
    address ethUsdPricefeed;
    address btcUsdPricefeed;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployOSC();
        (oscToken, oscEngine, config) = deployer.run();
        (ethUsdPricefeed, btcUsdPricefeed, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(address(oscToken), address(oscEngine), weth, wbtc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreCollateralValueThanTotalSupply() public view {
       uint256 totalSupply = oscToken.totalSupply();
       uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(oscEngine));
       uint256 totalWbtcDeposited = ERC20Mock(wbtc).balanceOf(address(oscEngine));

       uint256 totalWethValue = oscEngine.getUsdValue(weth, totalWethDeposited);
       uint256 totalWbtcValue = oscEngine.getUsdValue(wbtc, totalWbtcDeposited);

       assert(totalWethValue + totalWbtcValue >= totalSupply);
    }
}
