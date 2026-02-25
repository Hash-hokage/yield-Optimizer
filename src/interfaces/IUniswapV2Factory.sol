// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @title IUniswapV2Factory
/// @author Hash-Hokage
/// @notice Minimal interface for a Uniswap V2-style factory, used for pair-existence queries.
/// @dev The Yield Optimizer uses `getPair` to determine whether a direct swap route exists
///      between two tokens, or whether multi-hop routing through USDC is needed.
interface IUniswapV2Factory {
    /// @notice Returns the address of the liquidity pair for `tokenA` and `tokenB`.
    /// @dev Returns `address(0)` if no pair has been created for this token combination.
    ///      Token order does not matter — `getPair(A, B)` == `getPair(B, A)`.
    /// @param tokenA The first token in the pair.
    /// @param tokenB The second token in the pair.
    /// @return pair The address of the pair contract, or `address(0)` if none exists.
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
}
