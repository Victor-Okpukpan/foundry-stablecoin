// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {OracleStablecoin} from "./OracleStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OSCEngine
 * @author Victor_TheOracle
 * @notice The main engine foe the OSC token. COntains all core logic
 */
contract OSCEngine is ReentrancyGuard {
    error OSCEngine__MustBeGreaterThanZero();
    error OSCEngine__MustHaveTheSameLength();
    error OSCEngine__CollateralNotAllowed();
    error OSCEngine__TransferFailed();
    error OSCEngine__BrokenHealthFactor(uint256 _healthFactor);
    error OSCEngine__MintFailed();
    error OSCEngine__HealthFactorNotImproved();
    error OSCEngine__UserHasNoDebt();
    error OSCEngine__HealthFactorOk();

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    uint256 private constant ADDITIONAL_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address pricefeed) private s_pricefeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_oscMinted;

    OracleStablecoin private immutable i_oscToken;
    address[] private s_collateralTokens;

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert OSCEngine__MustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_pricefeeds[_token] == address(0)) {
            revert OSCEngine__CollateralNotAllowed();
        }
        _;
    }

    constructor(address[] memory _tokenAddresses, address[] memory _pricefeedAddresses, address _oscToken) {
        if (_tokenAddresses.length != _pricefeedAddresses.length) {
            revert OSCEngine__MustHaveTheSameLength();
        }
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_pricefeeds[_tokenAddresses[i]] = _pricefeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        i_oscToken = OracleStablecoin(_oscToken);
    }

    function depositCollateralAndMintOsc(
        address _tokenCollateralAddress,
        uint256 _collateralAmount,
        uint256 _amountToMint
    ) external {
        depositCollateral(_tokenCollateralAddress, _collateralAmount);
        mintOsc(_amountToMint);
    }

    function depositCollateral(address _tokenCollateralAddress, uint256 _collateralAmount)
        public
        moreThanZero(_collateralAmount)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _collateralAmount;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _collateralAmount);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _collateralAmount);
        if (!success) {
            revert OSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForOsc(address _tokenToRedeem, uint256 _amountToRedeem, uint256 _amountToBurn)
        external
        moreThanZero(_amountToRedeem)
    {
        burnOsc(_amountToBurn);
        redeemCollateral(_tokenToRedeem, _amountToRedeem);
    }

    function redeemCollateral(address _tokenToRedeem, uint256 _amountToRedeem)
        public
        moreThanZero(_amountToRedeem)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, _tokenToRedeem, _amountToRedeem);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnOsc(uint256 _amountToBurn) public moreThanZero(_amountToBurn) nonReentrant {
        _burnOsc(msg.sender, _amountToBurn, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintOsc(uint256 _amountToMint) public moreThanZero(_amountToMint) nonReentrant {
        s_oscMinted[msg.sender] += _amountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_oscToken.mint(msg.sender, _amountToMint);
        if (!minted) {
            revert OSCEngine__MintFailed();
        }
    }

    function liquidate(address _collateral, address _user, uint256 _debtToCover)
        external
        moreThanZero(_debtToCover)
        nonReentrant
    {
        uint256 userDebt = s_oscMinted[_user];
        if (userDebt == 0) {
            revert OSCEngine__UserHasNoDebt();
        }
        uint256 startingUserHealthFactor = _healthFactor(_user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert OSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsdValue(_collateral, _debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(_user, msg.sender, _collateral, totalCollateralToRedeem);
        _burnOsc(_user, _debtToCover, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(_user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert OSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function _burnOsc(address _onBehalfOf, uint256 _amountToBurn, address _oscFrom) private {
        s_oscMinted[_onBehalfOf] -= _amountToBurn;
        bool success = i_oscToken.transferFrom(_oscFrom, address(this), _amountToBurn);
        if (!success) {
            revert OSCEngine__TransferFailed();
        }
        i_oscToken.burn(_amountToBurn);
    }

    function _redeemCollateral(address _from, address _to, address _tokenToRedeem, uint256 _amountToRedeem) private {
        s_collateralDeposited[_from][_tokenToRedeem] -= _amountToRedeem;
        emit CollateralRedeemed(_from, _to, _tokenToRedeem, _amountToRedeem);
        bool success = IERC20(_tokenToRedeem).transfer(_to, _amountToRedeem);
        if (!success) {
            revert OSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address _user)
        private
        view
        returns (uint256 totalOscMinted, uint256 totalCollateralValueInUsd)
    {
        totalOscMinted = s_oscMinted[_user];
        totalCollateralValueInUsd = getAccountCollateralValueInUsd(_user);
    }

    function _healthFactor(address _user) private view returns (uint256) {
        (uint256 totalOscMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(_user);
        if (totalOscMinted == 0) return type(uint256).max;

        uint256 collateralAdjustedForThreshold =
            (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalOscMinted;
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert OSCEngine__BrokenHealthFactor(userHealthFactor);
        }
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getTokenAmountFromUsdValue(address _token, uint256 _usdValue) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_pricefeeds[_token]);

        (, int256 price,,,) = priceFeed.latestRoundData();

        return (_usdValue * PRECISION) / (uint256(price) * ADDITIONAL_PRECISION);
    }

    function getAccountCollateralValueInUsd(address _user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address _token, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_pricefeeds[_token]);

        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_PRECISION) * _amount) / PRECISION;
    }

    function getAccountInformation(address _user)
        external
        view
        returns (uint256 totalOscMinted, uint256 totalCollateralValueInUsd)
    {
        return _getAccountInformation(_user);
    }

    function getHealthFactor() external view returns (uint256) {
        return _healthFactor(msg.sender);
    }
}
