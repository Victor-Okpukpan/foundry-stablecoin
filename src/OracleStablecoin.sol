// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OracleStablecoin, OSC
 * @author Victor_TheOracle
 * @notice A stablecoin
 */
contract OracleStablecoin is ERC20Burnable, Ownable {
    constructor() ERC20("OracleStablecoin", "OSC") Ownable(msg.sender) {}

    error OracleStablecoin__MustBeGreaterThanZero();
    error OracleStablecoin__BurnAmountExceedsBalance();
    error OracleStablecoin__CannotBeAddressZero();

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert OracleStablecoin__MustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert OracleStablecoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool) {
        if (_to == address(0)) {
            revert OracleStablecoin__CannotBeAddressZero();
        }
         if (_amount <= 0) {
            revert OracleStablecoin__MustBeGreaterThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
