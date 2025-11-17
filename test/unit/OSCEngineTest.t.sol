// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployOSC} from "../../script/DeployOSC.s.sol";
import {OracleStablecoin} from "../../src/OracleStablecoin.sol";
import {OSCEngine} from "../../src/OSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract OSCEngineTest is Test {
    DeployOSC deployer;
    OracleStablecoin oscToken;
    OSCEngine oscEngine;
    HelperConfig config;
    address ethUsdPricefeed;
    address btcUsdPricefeed;
    address weth;

    address public user = makeAddr("user");
    address liquidator = makeAddr("liquidator");

    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant STARTING_USER_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployOSC();
        (oscToken, oscEngine, config) = deployer.run();
        (ethUsdPricefeed, btcUsdPricefeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(address(user), STARTING_USER_BALANCE);
    }

    /// modifiers

    modifier depositCollateral(address _user, address _token, uint256 _amount) {
        vm.startPrank(_user);
        ERC20Mock(_token).approve(address(oscEngine), _amount);
        oscEngine.depositCollateral(_token, _amount);
        vm.stopPrank();
        _;
    }

    /// Constructor Tests

    function testRevertIfArraysHaveDifferentLengths() public {
        address[] memory tokenAddresses = new address[](2);
        address[] memory pricefeedAddresses = new address[](1);
        vm.expectRevert(OSCEngine.OSCEngine__MustHaveTheSameLength.selector);
        new OSCEngine(tokenAddresses, pricefeedAddresses, address(oscToken));
    }

    /// Deposit Collateral Tests

    function testDepositCollateralRevertsIfZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(oscEngine), COLLATERAL_AMOUNT);
        vm.expectRevert(OSCEngine.OSCEngine__MustBeGreaterThanZero.selector);
        oscEngine.depositCollateral(address(weth), 0);
        vm.stopPrank();
    }

    function testRevertIfNotAllowedToken() public {
        ERC20Mock fakeToken = new ERC20Mock("FAKE", "FAKE", user, COLLATERAL_AMOUNT);
        vm.startPrank(user);
        fakeToken.approve(address(oscEngine), COLLATERAL_AMOUNT);
        vm.expectRevert(OSCEngine.OSCEngine__CollateralNotAllowed.selector);
        oscEngine.depositCollateral(address(fakeToken), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testDepositCollateralUpdatesMapping() public depositCollateral(user, weth, COLLATERAL_AMOUNT) {
        (uint256 totalOscMinted, uint256 totalCollateralValueInUsd) = oscEngine.getAccountInformation(user);
        uint256 expected = oscEngine.getUsdValue(weth, COLLATERAL_AMOUNT);
        assertEq(totalCollateralValueInUsd, expected);
        assertEq(totalOscMinted, 0);
    }

    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(oscEngine), COLLATERAL_AMOUNT);
        vm.expectEmit(true, true, true, false, address(oscEngine));
        emit OSCEngine.CollateralDeposited(user, address(weth), COLLATERAL_AMOUNT);
        oscEngine.depositCollateral(address(weth), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    /// Minting Tests

    function testMintOscRevertsIfZero() public {
        vm.startPrank(user);
        vm.expectRevert(OSCEngine.OSCEngine__MustBeGreaterThanZero.selector);
        oscEngine.mintOsc(0);
        vm.stopPrank();
    }

    function testMintOscUpdatesMappingAndTotalSupply() public depositCollateral(user, weth, COLLATERAL_AMOUNT) {
        uint256 amountToMint = 1000e18;
        vm.startPrank(user);
        oscEngine.mintOsc(amountToMint);
        (uint256 userOscMinted,) = oscEngine.getAccountInformation(user);
        uint256 totalSupply = oscToken.totalSupply();
        assertEq(userOscMinted, amountToMint);
        assertEq(totalSupply, amountToMint);
        vm.stopPrank();
    }

    function testMintOscRevertsIfHealthFactorTooLow() public depositCollateral(user, weth, COLLATERAL_AMOUNT) {
        uint256 amountToMint = 100000e18;
        uint256 collateralValueInUsd = oscEngine.getUsdValue(weth, COLLATERAL_AMOUNT);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * 50) / 100;
        uint256 expectedHealthFactor = (collateralAdjustedForThreshold * 1e18) / amountToMint;

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OSCEngine.OSCEngine__BrokenHealthFactor.selector, expectedHealthFactor));
        oscEngine.mintOsc(amountToMint);
        vm.stopPrank();
    }

    function testDepositAndMint() public {
        uint256 amountToMint = 1000e18;
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(oscEngine), COLLATERAL_AMOUNT);
        oscEngine.depositCollateralAndMintOsc(address(weth), COLLATERAL_AMOUNT, amountToMint);
        (uint256 userOscMinted, uint256 userCollateralValueInUsd) = oscEngine.getAccountInformation(user);
        uint256 expected = oscEngine.getUsdValue(weth, COLLATERAL_AMOUNT);
        uint256 totalSupply = oscToken.totalSupply();
        assertEq(userOscMinted, amountToMint);
        assertEq(totalSupply, amountToMint);
        assertEq(userCollateralValueInUsd, expected);
        vm.stopPrank();
    }

    /// Redeeming Tests

    function testRedeemCollateralRevertsIfZero() public {
        vm.startPrank(user);
        vm.expectRevert(OSCEngine.OSCEngine__MustBeGreaterThanZero.selector);
        oscEngine.redeemCollateral(address(weth), 0);
        vm.stopPrank();
    }

    function testRedeemCollateralReducesMapping() public depositCollateral(user, weth, COLLATERAL_AMOUNT) {
        uint256 redeemAmount = 5 ether;
        vm.startPrank(user);
        oscEngine.redeemCollateral(address(weth), redeemAmount);
        (, uint256 collateralDepositedInUsd) = oscEngine.getAccountInformation(user);
        uint256 remainingCollateral = COLLATERAL_AMOUNT - redeemAmount;
        uint256 expected = oscEngine.getUsdValue(weth, remainingCollateral);
        assertEq(collateralDepositedInUsd, expected);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfHealthFactorBroken()
        public
        depositCollateral(user, weth, COLLATERAL_AMOUNT)
    {
        uint256 amountToMint = 5000e18;
        uint256 redeemAmount = 7 ether;
        uint256 collateralValueInUsd = oscEngine.getUsdValue(weth, COLLATERAL_AMOUNT - redeemAmount);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * 50) / 100;
        uint256 expectedHealthFactor = (collateralAdjustedForThreshold * 1e18) / amountToMint;

        vm.startPrank(user);
        oscEngine.mintOsc(amountToMint);
        vm.expectRevert(abi.encodeWithSelector(OSCEngine.OSCEngine__BrokenHealthFactor.selector, expectedHealthFactor));
        oscEngine.redeemCollateral(address(weth), redeemAmount);
        vm.stopPrank();
    }

    /// burn tests

    function testBurnOscRevertsIfZero() public {
        vm.startPrank(user);
        vm.expectRevert(OSCEngine.OSCEngine__MustBeGreaterThanZero.selector);
        oscEngine.burnOsc(0);
        vm.stopPrank();
    }

    function testBurnOscReducesMappingAndTotalSupply() public depositCollateral(user, weth, COLLATERAL_AMOUNT) {
        uint256 amountToMint = 1000e18;
        uint256 amountToBurn = 400e18;

        vm.startPrank(user);
        oscEngine.mintOsc(amountToMint);
        oscToken.approve(address(oscEngine), amountToBurn);
        oscEngine.burnOsc(amountToBurn);
        (uint256 userOscMinted,) = oscEngine.getAccountInformation(user);
        uint256 totalSupply = oscToken.totalSupply();
        assertEq(userOscMinted, amountToMint - amountToBurn);
        assertEq(totalSupply, amountToMint - amountToBurn);
        vm.stopPrank();
    }

    function testRedeemCollateralForOsc() public {
        uint256 amountToMint = 1000e18;
        uint256 amountToBurn = 400e18;
        uint256 amountToRedeem = 5 ether;

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(oscEngine), COLLATERAL_AMOUNT);
        oscEngine.depositCollateralAndMintOsc(address(weth), COLLATERAL_AMOUNT, amountToMint);
        oscToken.approve(address(oscEngine), amountToBurn);
        oscEngine.redeemCollateralForOsc(address(weth), amountToRedeem, amountToBurn);
        (uint256 userOscMinted, uint256 collateralDepositedInUsd) = oscEngine.getAccountInformation(user);
        uint256 expectedCollateral = oscEngine.getUsdValue(weth, COLLATERAL_AMOUNT - amountToRedeem);
        uint256 totalSupply = oscToken.totalSupply();
        assertEq(userOscMinted, amountToMint - amountToBurn);
        assertEq(totalSupply, amountToMint - amountToBurn);
        assertEq(collateralDepositedInUsd, expectedCollateral);
        vm.stopPrank();
    }

    function testRedeemCollateralForOscRevertsIfHealthFactorBroken()
        public
        depositCollateral(user, weth, COLLATERAL_AMOUNT)
    {
        uint256 amountToMint = 5000e18;
        uint256 amountToBurn = 1000e18;
        uint256 amountToRedeem = 7 ether;
        uint256 collateralValueInUsd = oscEngine.getUsdValue(weth, COLLATERAL_AMOUNT - amountToRedeem);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * 50) / 100;
        uint256 expectedHealthFactor = (collateralAdjustedForThreshold * 1e18) / (amountToMint - amountToBurn);

        vm.startPrank(user);
        oscEngine.mintOsc(amountToMint);
        oscToken.approve(address(oscEngine), amountToBurn);
        vm.expectRevert(abi.encodeWithSelector(OSCEngine.OSCEngine__BrokenHealthFactor.selector, expectedHealthFactor));
        oscEngine.redeemCollateralForOsc(address(weth), amountToRedeem, amountToBurn);
        vm.stopPrank();
    }

    function testRedeemCollateralForOscRevertsIfZeroRedeemAmount()
        public
        depositCollateral(user, weth, COLLATERAL_AMOUNT)
    {
        uint256 amountToMint = 1000e18;
        uint256 amountToBurn = 400e18;
        uint256 amountToRedeem = 0;

        vm.startPrank(user);
        oscEngine.mintOsc(amountToMint);
        oscToken.approve(address(oscEngine), amountToBurn);
        vm.expectRevert(OSCEngine.OSCEngine__MustBeGreaterThanZero.selector);
        oscEngine.redeemCollateralForOsc(address(weth), amountToRedeem, amountToBurn);
        vm.stopPrank();
    }

    /// liquidation Tests

    // function testLiquidation() public depositCollateral(user, weth, COLLATERAL_AMOUNT) {
    //     uint256 amountToMint = 5000e18;
    //     uint256 amountToBurnByLiquidator = 1000e18;

    //     vm.startPrank(user);
    //     oscEngine.mintOsc(amountToMint);
    //     vm.stopPrank();

    //     // manipulate price feed to drop health factor
    //     // for simplicity in this test, we will just assume the health factor is now below the minimum

    //     vm.startPrank(liquidator);
    //     oscToken.approve(address(oscEngine), amountToBurnByLiquidator);
    //     oscEngine.liquidate(address(weth), user, amountToBurnByLiquidator);
    //     vm.stopPrank();

    //     (uint256 userOscMinted,) = oscEngine.getAccountInformation(user);
    //     assertEq(userOscMinted, amountToMint - amountToBurnByLiquidator);
    // }

    function testLiquidationRevertsIfUserDoesNotExist() public {
        address nonExistentUser = makeAddr("nonExistentUser");
        uint256 amountToBurnByLiquidator = 1000e18;

        vm.startPrank(liquidator);
        ERC20Mock(weth).mint(liquidator, COLLATERAL_AMOUNT);
        ERC20Mock(weth).approve(address(oscEngine), COLLATERAL_AMOUNT);
        oscEngine.depositCollateralAndMintOsc(weth, COLLATERAL_AMOUNT, amountToBurnByLiquidator);

        oscToken.approve(address(oscEngine), amountToBurnByLiquidator);
        vm.expectRevert(OSCEngine.OSCEngine__UserHasNoDebt.selector);
        oscEngine.liquidate(weth, nonExistentUser, amountToBurnByLiquidator);
        vm.stopPrank();
    }

    function testLiquidationRevertsIfHealthFactorOk() public depositCollateral(user, weth, COLLATERAL_AMOUNT) {
        uint256 amountToMint = 1000e18;
        vm.startPrank(user);
        oscEngine.mintOsc(amountToMint);
        vm.stopPrank();

        vm.startPrank(liquidator);
        oscToken.approve(address(oscEngine), amountToMint);
        vm.expectRevert(OSCEngine.OSCEngine__HealthFactorOk.selector);
        oscEngine.liquidate(address(weth), user, amountToMint);
        vm.stopPrank();
    }

    // function testLiquidatorGetsBonus() public depositCollateral(user, weth, COLLATERAL_AMOUNT) {
    //     uint256 amountToMint = 5000e18;
    //     uint256 amountToBurnByLiquidator = 1000e18;

    //     vm.startPrank(user);
    //     oscEngine.mintOsc(amountToMint);
    //     vm.stopPrank();

    //     // manipulate price feed to drop health factor
    //     // for simplicity in this test, we will just assume the health factor is now below the minimum


    //     uint256 liquidatorInitialWethBalance = ERC20Mock(weth).balanceOf(liquidator);

    //     vm.startPrank(liquidator);
    //     oscToken.approve(address(oscEngine), amountToBurnByLiquidator);
    //     oscEngine.liquidate(address(weth), user, amountToBurnByLiquidator);
    //     vm.stopPrank();

    //     uint256 liquidatorFinalWethBalance = ERC20Mock(weth).balanceOf(liquidator);
    //     assert(liquidatorFinalWethBalance > liquidatorInitialWethBalance);
    // }

    function testLiquidationRevertsIfDebtToCoverIsZero() public {
        vm.startPrank(liquidator);
        vm.expectRevert(OSCEngine.OSCEngine__MustBeGreaterThanZero.selector);
        oscEngine.liquidate(address(weth), user, 0);
        vm.stopPrank();
    }

    /// getter tests

    function testGetAccountInformation() public depositCollateral(user, weth, COLLATERAL_AMOUNT) {
        uint256 amountToMint = 1000e18;
        vm.startPrank(user);
        oscEngine.mintOsc(amountToMint);
        (uint256 userOscMinted, uint256 userCollateralValueInUsd) = oscEngine.getAccountInformation(user);
        uint256 expectedCollateralValue = oscEngine.getUsdValue(weth, COLLATERAL_AMOUNT);
        assertEq(userOscMinted, amountToMint);
        assertEq(userCollateralValueInUsd, expectedCollateralValue);
        vm.stopPrank();
    }

    function testGetHealthFactor() public depositCollateral(user, weth, COLLATERAL_AMOUNT) {
        uint256 amountToMint = 1000e18;
        vm.startPrank(user);
        oscEngine.mintOsc(amountToMint);
        uint256 healthFactor = oscEngine.getHealthFactor();
        uint256 collateralValueInUsd = oscEngine.getUsdValue(weth, COLLATERAL_AMOUNT);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * 50) / 100;
        uint256 expectedHealthFactor = (collateralAdjustedForThreshold * 1e18) / amountToMint;
        assertEq(healthFactor, expectedHealthFactor);
        vm.stopPrank();
    }

    function testGetUsdValue() public view {
        uint256 tokenAmount = 10e18;
        uint256 expectedAmount = 20000e18;
        uint256 usd = oscEngine.getUsdValue(weth, tokenAmount);
        assertEq(expectedAmount, usd);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = oscEngine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetAccountCollateralValueInUsd() public depositCollateral(user, weth, COLLATERAL_AMOUNT) {
        vm.startPrank(user);
        uint256 collateralValueInUsd = oscEngine.getAccountCollateralValueInUsd(user);
        uint256 expected = oscEngine.getUsdValue(weth, COLLATERAL_AMOUNT);
        assertEq(collateralValueInUsd, expected);
        vm.stopPrank();
    }

    function testGetTokenAmountFromUsdValue() public view {
        uint256 usdValue = 20000e18;
        uint256 expectedTokenAmount = 10e18;
        uint256 tokenAmount = oscEngine.getTokenAmountFromUsdValue(weth, usdValue);
        assertEq(tokenAmount, expectedTokenAmount);
    }
}
