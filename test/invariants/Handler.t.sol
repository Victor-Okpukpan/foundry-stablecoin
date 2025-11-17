// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {OracleStablecoin} from "../../src/OracleStablecoin.sol";
import {OSCEngine} from "../../src/OSCEngine.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    OracleStablecoin oscToken;
    OSCEngine oscEngine;
    address weth;
    address wbtc;

    uint256 MAX_DEPOSITS = type(uint96).max;

    constructor(address _oscToken, address _oscEngine, address _weth, address _wbtc) {
        oscToken = OracleStablecoin(_oscToken);
        oscEngine = OSCEngine(_oscEngine);
        weth = _weth;
        wbtc = _wbtc;
    }

    function depositCollateral(uint256 _collateralSeed, uint256 amount) external {
        ERC20Mock collateral = _getCollateralFromSeed(_collateralSeed);
        amount = bound(amount, 1, MAX_DEPOSITS);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(oscEngine), amount);
        oscEngine.depositCollateral(address(collateral), amount);
        vm.stopPrank();
    }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return ERC20Mock(weth);
        } else {
            return ERC20Mock(wbtc);
        }
    }

}
