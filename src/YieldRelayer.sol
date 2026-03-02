// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title YieldRelayer
/// @author Hash-hokage
/// @notice Secure on-chain bridge that accepts off-chain APY calculations and
///         triggers Somnia's native reactive infrastructure.
/// @dev This contract serves as the translation layer between off-chain Node.js
///      Keepers and Somnia's reactive node infrastructure. The Keeper service
///      continuously monitors DeFi farm APY data from external sources, computes
///      optimal yield strategies off-chain, and then pushes the resulting APY
///      figures on-chain through this relayer.
///
///      Once the `YieldUpdated` event is emitted, Somnia's reactive nodes detect
///      the event and automatically route it to downstream consumer contracts
///      (e.g., `YieldOptimizer`) via their `onYieldUpdated` callback, enabling a
///      fully automated, event-driven rebalancing pipeline.
///
///      Access is restricted to the contract owner (the deployer / Keeper EOA)
///      via OpenZeppelin's `Ownable` modifier, ensuring that only authorised
///      off-chain infrastructure can relay yield data on-chain.
contract YieldRelayer is Ownable {
    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    /// @notice Emitted every time a new APY figure is pushed for a target farm.
    /// @param newAPY   The latest annualised percentage yield (scaled by 1e18).
    /// @param targetFarm The address of the farm / vault this APY relates to.
    event YieldUpdated(uint256 newAPY, address targetFarm);

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    /// @notice Maps each farm address to its most recently relayed APY value.
    /// @dev Values are expected to be scaled by 1e18 (e.g., 5 % = 5e16).
    mapping(address => uint256) public currentFarmYields;

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    /// @notice Deploys the relayer and sets the initial owner.
    /// @dev The owner is typically the Keeper EOA or a multisig that the
    ///      off-chain Node.js service controls.
    /// @param _initialOwner Address that will own the relayer and be allowed
    ///                      to push yield updates.
    constructor(address _initialOwner) Ownable(_initialOwner) {}

    // ──────────────────────────────────────────────
    //  External Functions
    // ──────────────────────────────────────────────

    /// @notice Pushes a new APY update for the specified farm on-chain.
    /// @dev Only callable by the contract owner (the off-chain Keeper).
    ///      Updates the `currentFarmYields` mapping and emits a `YieldUpdated`
    ///      event that Somnia's reactive nodes will pick up to trigger
    ///      downstream rebalancing logic in consumer contracts.
    /// @param _newAPY     The latest computed APY for the target farm (1e18 scaled).
    /// @param _targetFarm The address of the farm / vault to update.
    function pushYieldUpdate(uint256 _newAPY, address _targetFarm) external onlyOwner {
        currentFarmYields[_targetFarm] = _newAPY;
        emit YieldUpdated(_newAPY, _targetFarm);
    }
}
