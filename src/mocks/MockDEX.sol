// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IDEXRouter} from "../interfaces/IDEXRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MockDEX
/// @author Hash-Hokage
/// @notice A mock Uniswap V2-style DEX router for local testing of the Yield Optimizer.
/// @dev Implements the `IDEXRouter` interface with:
///      - **0.3% swap fee** (matching Uniswap V2)
///      - **Constant-product (x × y = k) slippage** using configurable mock reserves
///      - **Strict `amountOutMin` enforcement** to validate sandwich-attack protection logic
///
///      ⚠️  FOR LOCAL TESTING ONLY — no real liquidity pools are involved.
///      Reserves are set manually via `setReserves` and token transfers use `transferFrom`.
contract MockDEX is IDEXRouter {
    using SafeERC20 for IERC20;
    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Reverted when the swap path has fewer than 2 addresses.
    error MockDEX__InvalidPath();

    /// @dev Reverted when no reserves have been configured for a token pair.
    error MockDEX__NoReservesSet();

    /// @dev Reverted when the computed output amount is below `amountOutMin`.
    ///      This is the slippage / sandwich-attack protection check.
    error MockDEX__InsufficientOutputAmount();

    /// @dev Reverted when `block.timestamp` exceeds the caller-supplied deadline.
    error MockDEX__Expired();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Mock reserves for each token pair, keyed by the sorted pair hash.
    /// @dev `reserves[pairKey][tokenAddress]` → reserve amount.
    ///      Use `setReserves` to configure before running swaps.
    mapping(bytes32 => mapping(address => uint256)) public reserves;

    /// @notice Mock factory address returned by `factory()`.
    /// @dev Set via `setFactory` before tests that query routing paths.
    address public mockFactory;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Uniswap V2 fee: 0.3% expressed as (1000 - 3) = 997 parts per 1000.
    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant FEE_DENOMINATOR = 1000;

    /*//////////////////////////////////////////////////////////////
                          ADMIN (TEST HELPERS)
    //////////////////////////////////////////////////////////////*/

    /// @notice Configures mock reserves for a token pair.
    /// @dev Must be called before any swap involving this pair. Order of `tokenA` / `tokenB`
    ///      does not matter — the pair key is derived from the sorted addresses.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param reserveA Reserve amount for `tokenA`.
    /// @param reserveB Reserve amount for `tokenB`.
    function setReserves(
        address tokenA,
        address tokenB,
        uint256 reserveA,
        uint256 reserveB
    ) external {
        bytes32 pairKey = _pairKey(tokenA, tokenB);
        reserves[pairKey][tokenA] = reserveA;
        reserves[pairKey][tokenB] = reserveB;
    }

    /// @notice Sets the mock factory address returned by `factory()`.
    /// @param _factory The address to return from `factory()`.
    function setFactory(address _factory) external {
        mockFactory = _factory;
    }

    /*//////////////////////////////////////////////////////////////
                        IDEXRouter — VIEW
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDEXRouter
    function factory() external view override returns (address) {
        return mockFactory;
    }

    /// @inheritdoc IDEXRouter
    /// @dev Applies the constant-product formula with a 0.3% fee at each hop:
    ///      `amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)`
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view override returns (uint256[] memory amounts) {
        if (path.length < 2) revert MockDEX__InvalidPath();

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < path.length - 1; i++) {
            amounts[i + 1] = _getAmountOut(amounts[i], path[i], path[i + 1]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        IDEXRouter — SWAP
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDEXRouter
    /// @dev Execution flow:
    ///      1. Validates deadline and path length.
    ///      2. Computes output amounts through each hop using `_getAmountOut`.
    ///      3. **Reverts if final output < `amountOutMin`** (sandwich protection test).
    ///      4. Pulls input tokens from `msg.sender` via `transferFrom`.
    ///      5. Sends output tokens to `to` via `transfer` (tokens must be pre-funded to this contract).
    ///      6. Updates mock reserves to reflect the trade.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        if (block.timestamp > deadline) revert MockDEX__Expired();
        if (path.length < 2) revert MockDEX__InvalidPath();

        // --- Compute amounts through each hop ---
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < path.length - 1; i++) {
            amounts[i + 1] = _getAmountOut(amounts[i], path[i], path[i + 1]);
        }

        // --- Slippage / sandwich-attack protection ---
        uint256 finalAmountOut = amounts[amounts.length - 1];
        if (finalAmountOut < amountOutMin) {
            revert MockDEX__InsufficientOutputAmount();
        }

        // --- Execute token transfers ---
        // Pull input tokens from caller
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);

        // Transfer output tokens to recipient
        IERC20(path[path.length - 1]).safeTransfer(to, finalAmountOut);

        // --- Update reserves for each hop ---
        for (uint256 i = 0; i < path.length - 1; i++) {
            bytes32 pairKey = _pairKey(path[i], path[i + 1]);
            reserves[pairKey][path[i]] += amounts[i];
            reserves[pairKey][path[i + 1]] -= amounts[i + 1];
        }
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Computes the output amount for a single hop using the constant-product formula
    ///      with a 0.3% fee.
    ///
    ///      Formula: amountOut = (amountIn × 997 × reserveOut) / (reserveIn × 1000 + amountIn × 997)
    ///
    ///      This naturally produces price slippage — larger trades relative to reserves
    ///      receive worse rates, faithfully simulating real AMM behaviour.
    ///
    /// @param amountIn The input amount for this hop.
    /// @param tokenIn  The input token address.
    /// @param tokenOut The output token address.
    /// @return amountOut The computed output amount after fee and slippage.
    function _getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256 amountOut) {
        bytes32 pairKey = _pairKey(tokenIn, tokenOut);
        uint256 reserveIn = reserves[pairKey][tokenIn];
        uint256 reserveOut = reserves[pairKey][tokenOut];

        if (reserveIn == 0 || reserveOut == 0) revert MockDEX__NoReservesSet();

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;

        amountOut = numerator / denominator;
    }

    /// @dev Derives a deterministic key for a token pair by sorting addresses.
    ///      Ensures `(A, B)` and `(B, A)` map to the same reserves.
    function _pairKey(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        return keccak256(abi.encodePacked(token0, token1));
    }
}
