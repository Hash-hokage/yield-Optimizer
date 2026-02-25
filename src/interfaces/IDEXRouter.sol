// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @title IDEXRouter
/// @author Hash-Hokage
/// @notice Interface for a Uniswap V2-style DEX router used by the Yield Optimizer.
/// @dev All swap functions enforce strict slippage protection via `amountOutMin` to mitigate
///      sandwich attacks and front-running. Callers should compute `amountOutMin` off-chain
///      using a trusted price oracle or recent on-chain TWAP before submitting a transaction.
interface IDEXRouter {
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the address of the Uniswap V2-style factory used by this router.
    /// @dev Used to query `getPair(tokenA, tokenB)` for routing decisions.
    /// @return factoryAddress The address of the DEX factory contract.
    function factory() external view returns (address factoryAddress);

    /// @notice Calculates the expected output amounts for a given input amount along a token swap path.
    /// @dev Uses the constant-product formula (x * y = k) at each hop to determine intermediate
    ///      and final output amounts. The returned array length equals `path.length`.
    ///      - `amounts[0]` is always equal to `amountIn`.
    ///      - `amounts[path.length - 1]` is the final output amount.
    ///      Callers should use the final value to derive a safe `amountOutMin` that accounts for
    ///      slippage tolerance, protecting against sandwich attacks.
    /// @param amountIn The exact amount of the input token to swap.
    /// @param path An ordered array of token addresses representing the swap route.
    ///        For a direct swap: `[tokenA, tokenB]`.
    ///        For a multi-hop swap: `[tokenA, intermediateToken, ..., tokenB]`.
    /// @return amounts An array of uint256 values representing the output amount at each hop.
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);

    /*//////////////////////////////////////////////////////////////
                           SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible,
    ///         along the specified path, enforcing a minimum output to protect against slippage.
    /// @dev This function is the primary mechanism for token swaps within the Yield Optimizer.
    ///
    ///      **Slippage & Sandwich Attack Protection:**
    ///      - `amountOutMin` MUST be set to a value derived from a trusted price source (e.g.,
    ///        an on-chain TWAP oracle or a recent `getAmountsOut` call with an applied tolerance).
    ///      - Setting `amountOutMin` to 0 disables slippage protection entirely and leaves the
    ///        transaction vulnerable to sandwich attacks. This MUST be avoided in production.
    ///      - The `deadline` parameter prevents stale transactions from being executed at
    ///        unfavorable prices if they remain in the mempool for too long.
    ///
    ///      **Execution Flow:**
    ///      1. The caller must have approved this router to spend at least `amountIn` of `path[0]`.
    ///      2. The router pulls `amountIn` of `path[0]` from `msg.sender`.
    ///      3. Tokens are swapped sequentially through each pair in `path`.
    ///      4. The final output tokens are sent to the `to` address.
    ///      5. Reverts if the final output amount is less than `amountOutMin`.
    ///
    /// @param amountIn The exact amount of input tokens to send.
    /// @param amountOutMin The minimum amount of output tokens that must be received for the
    ///        transaction to succeed. Acts as the primary defense against sandwich attacks and
    ///        excessive slippage. MUST NOT be set to 0 in production.
    /// @param path An ordered array of token addresses defining the swap route.
    ///        - `path[0]` is the input token.
    ///        - `path[path.length - 1]` is the desired output token.
    ///        - Intermediate entries define multi-hop routes through liquidity pools.
    /// @param to The recipient address that will receive the output tokens.
    ///        Should be validated to avoid sending tokens to the zero address.
    /// @param deadline The Unix timestamp after which the transaction will revert. Protects
    ///        against long-pending transactions being executed at stale, unfavorable prices —
    ///        a common vector in sandwich attack strategies.
    /// @return amounts An array of uint256 values representing the actual amounts at each hop,
    ///         where `amounts[amounts.length - 1]` is the final amount received by `to`.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
