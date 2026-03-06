// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IYieldFarm} from "../interfaces/IYieldFarm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockYieldFarm
/// @author Hash-Hokage
/// @notice Minimal ERC-4626 vault stub for local testing.
/// @dev - `asset()` returns the underlying token set at construction.
///      - `deposit()` pulls the underlying token and mints 1:1 "shares" using ERC20 _mint.
///      - `redeem()` burns shares using ERC20 _burn and returns 1:1 underlying.
contract MockYieldFarm is IYieldFarm, ERC20 {
    address public override asset;

    constructor(address _asset) ERC20("Mock Target Vault", "mTV") {
        asset = _asset;
    }

    function totalAssets() external view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function deposit(uint256 assets, address receiver) external override returns (uint256) {
        IERC20(asset).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, assets); // 1:1 share minting
        return assets;
    }

    function redeem(uint256 _shares, address receiver, address _owner) external override returns (uint256) {
        if (msg.sender != _owner) {
            _spendAllowance(_owner, msg.sender, _shares);
        }

        _burn(_owner, _shares);
        IERC20(asset).transfer(receiver, _shares); // 1:1 redemption
        return _shares;
    }

    /// @notice Converts shares to underlying assets (1:1 in this mock).
    /// @dev Implements the ERC-4626 `convertToAssets` standard method.
    function convertToAssets(uint256 _shares) external pure returns (uint256) {
        return _shares; // 1:1 ratio
    }
}
