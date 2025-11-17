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
    address[] public usersWithCollateral;

    uint256 MAX_DEPOSITS = type(uint96).max;

    constructor(address _oscToken, address _oscEngine, address _weth, address _wbtc) {
        oscToken = OracleStablecoin(_oscToken);
        oscEngine = OSCEngine(_oscEngine);
        weth = _weth;
        wbtc = _wbtc;
    }

    function depositCollateral(uint256 _collateralSeed, uint256 _amount) external {
        ERC20Mock collateral = _getCollateralFromSeed(_collateralSeed);
        _amount = bound(_amount, 1, MAX_DEPOSITS);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, _amount);
        collateral.approve(address(oscEngine), _amount);
        oscEngine.depositCollateral(address(collateral), _amount);
        usersWithCollateral.push(msg.sender);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 _collateralSeed, uint256 _amount) external {
        ERC20Mock collateral = _getCollateralFromSeed(_collateralSeed);
        uint256 maxRedeemable = oscEngine.getUserCollateralDeposited(msg.sender, address(collateral));
        _amount = bound(_amount, 0, maxRedeemable);

        if (_amount == 0) {
            return;
        }

        // Calculate how much collateral can actually be redeemed without breaking health factor
        (uint256 totalOscMinted, uint256 totalCollateralAmountInUsd) = oscEngine.getAccountInformation(msg.sender);

        if (totalOscMinted > 0) {
            // User has minted OSC, need to maintain health factor
            uint256 collateralValueToRedeem = oscEngine.getUsdValue(address(collateral), _amount);
            uint256 newCollateralValue = totalCollateralAmountInUsd - collateralValueToRedeem;

            // Need to maintain 200% overcollateralization (health factor >= 1)
            // This means collateral value must be at least 2x the minted OSC
            uint256 minRequiredCollateral = totalOscMinted * 2;

            if (newCollateralValue < minRequiredCollateral) {
                // Adjust amount to maintain health factor
                uint256 maxRedeemableValue = totalCollateralAmountInUsd > minRequiredCollateral
                    ? totalCollateralAmountInUsd - minRequiredCollateral
                    : 0;
                _amount = oscEngine.getTokenAmountFromUsdValue(address(collateral), maxRedeemableValue);
                _amount = _amount > maxRedeemable ? maxRedeemable : _amount;
            }

            if (_amount == 0) {
                return;
            }
        }

        vm.startPrank(msg.sender);
        oscEngine.redeemCollateral(address(collateral), _amount);
        vm.stopPrank();
    }

    function mintOsc(uint256 _amountToMint, uint256 _addressSeed) external {
        if (usersWithCollateral.length == 0) {
            return;
        }
        address sender = usersWithCollateral[_addressSeed % usersWithCollateral.length];
        (uint256 totalOscMinted, uint256 totalCollateralAmountInUsd) = oscEngine.getAccountInformation(sender);
        int256 maxMintable = (int256(totalCollateralAmountInUsd) / 2) - int256(totalOscMinted);

        if (maxMintable <= 0) {
            return;
        }

        _amountToMint = bound(_amountToMint, 0, uint256(maxMintable));

        if (_amountToMint == 0) {
            return;
        }

        vm.startPrank(sender);
        oscEngine.mintOsc(_amountToMint);
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
