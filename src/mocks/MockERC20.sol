// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @author Hash-Hokage
/// @notice A minimal ERC-20 token with an unrestricted `mint` function for local testing.
/// @dev Inherits the full OpenZeppelin ERC20 implementation. The `mint` function has **no
///      access control** and should NEVER be deployed to a live network. It exists solely
///      to simplify test setup by allowing any caller to create arbitrary token balances.
contract MockERC20 is ERC20 {
    /// @notice The number of decimals used by this token.
    uint8 private immutable _decimals;

    /// @notice Deploys the mock token with a custom name, symbol, and decimal precision.
    /// @param name_ The human-readable name of the token (e.g., "USD Coin").
    /// @param symbol_ The ticker symbol of the token (e.g., "USDC").
    /// @param decimals_ The number of decimal places (e.g., 6 for USDC, 18 for WETH).
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    /// @notice Returns the number of decimals used for display purposes.
    /// @return The decimal precision set at construction.
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Mints `amount` tokens to `to` without any access control.
    /// @dev FOR LOCAL TESTING ONLY — do NOT deploy to mainnet or testnets.
    ///      This function allows any caller to mint an unlimited supply, which is
    ///      intentional for test fixtures but catastrophic in production.
    /// @param to The address that will receive the newly minted tokens.
    /// @param amount The quantity of tokens to mint (in the token's smallest unit).
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
