// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IYieldFarm} from "../interfaces/IYieldFarm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title MockYieldFarm
/// @author Hash-Hokage
/// @notice Minimal ERC-4626 vault stub for local testing.
/// @dev - `asset()` returns the underlying token set at construction.
///      - `deposit()` pulls the underlying token and mints 1:1 "shares".
///      - `redeem()` burns shares and returns 1:1 underlying.
///      - `balanceOf()` returns the share balance so the optimizer can query
///        `IERC20(farm).balanceOf(optimizer)` for its share position.
contract MockYieldFarm is IYieldFarm {
    address public override asset;

    /// @dev Maps depositor → share balance (simple 1:1 tracking).
    mapping(address => uint256) public shares;

    constructor(address _asset) {
        asset = _asset;
    }

    function totalAssets() external view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function deposit(uint256 assets, address receiver) external override returns (uint256) {
        IERC20(asset).transferFrom(msg.sender, address(this), assets);
        shares[receiver] += assets; // 1:1 share minting
        return assets;
    }

    function redeem(uint256 _shares, address receiver, address _owner) external override returns (uint256) {
        require(shares[_owner] >= _shares, "MockYieldFarm: insufficient shares");
        shares[_owner] -= _shares;
        IERC20(asset).transfer(receiver, _shares); // 1:1 redemption
        return _shares;
    }

    /// @notice Returns the share balance for `account`, allowing
    ///         `IERC20(farm).balanceOf(account)` to work for the optimizer.
    function balanceOf(address account) external view returns (uint256) {
        return shares[account];
    }
}
