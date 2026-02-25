// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IUniswapV2Factory} from "../interfaces/IUniswapV2Factory.sol";

/// @title MockUniswapV2Factory
/// @author Hash-Hokage
/// @notice Minimal factory stub that returns a configurable pair address for `getPair()`.
/// @dev Used to make the optimizer's routing logic see a "direct pool" for the token pair.
contract MockUniswapV2Factory is IUniswapV2Factory {
    /// @dev Mapping: sorted pair hash → registered pair address.
    mapping(bytes32 => address) private _pairs;

    /// @notice Register a pair address for (tokenA, tokenB).
    function setPair(address tokenA, address tokenB, address pair) external {
        (address t0, address t1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        _pairs[keccak256(abi.encodePacked(t0, t1))] = pair;
    }

    /// @inheritdoc IUniswapV2Factory
    function getPair(
        address tokenA,
        address tokenB
    ) external view override returns (address) {
        (address t0, address t1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        return _pairs[keccak256(abi.encodePacked(t0, t1))];
    }
}
