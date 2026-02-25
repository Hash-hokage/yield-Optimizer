// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @title ISomniaReactivity
/// @author Hash-Hokage
/// @notice Interface for Somnia's native reactive callback system, enabling contracts to
///         subscribe to on-chain events and receive automatic callbacks when they fire.
/// @dev Somnia's reactivity layer allows smart contracts to register interest in specific
///      events emitted by other contracts. When the subscribed event is detected, the
///      network triggers a callback on the subscriber automatically.
///
///      This interface defines two concerns:
///      1. **Subscription** — Binding a listener to a specific contract + event pair.
///      2. **Callback**     — The handler that the subscribing contract must implement.
///
///      > [!CAUTION]
///      > **Security-Critical: `msg.sender` Verification in Callbacks**
///      >
///      > Implementing contracts **MUST** verify `msg.sender` inside every callback
///      > (e.g., `onYieldUpdated`) to ensure the call originates from the trusted Somnia
///      > reactivity runtime. Failing to do so allows any external account or contract to
///      > invoke the callback with arbitrary data, leading to **spoofed events** that could
///      > manipulate yield calculations, trigger unauthorized rebalances, or drain funds.
///      >
///      > Recommended pattern:
///      > ```solidity
///      > modifier onlyReactivityRuntime() {
///      >     require(msg.sender == SOMNIA_REACTIVITY_RUNTIME, "Unauthorized callback");
///      >     _;
///      > }
///      > ```
interface ISomniaReactivity {
    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a contract successfully subscribes to an event.
    /// @param subscriber The address of the contract that subscribed.
    /// @param source The address of the contract whose event is being monitored.
    /// @param eventSignature The `keccak256` hash of the event signature being tracked.
    event Subscribed(
        address indexed subscriber,
        address indexed source,
        bytes32 indexed eventSignature
    );

    /*//////////////////////////////////////////////////////////////
                         SUBSCRIPTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Subscribes the calling contract to a specific event emitted by `contractAddress`.
    /// @dev Once subscribed, the Somnia reactivity runtime will automatically invoke the
    ///      appropriate callback on `msg.sender` whenever `contractAddress` emits the event
    ///      matching `eventSignature`.
    ///
    ///      **Usage example — subscribing to yield-rate updates:**
    ///      ```solidity
    ///      reactivity.subscribe(
    ///          yieldFarmAddress,
    ///          keccak256("YieldUpdated(uint256,address)")
    ///      );
    ///      ```
    ///
    ///      After this call, whenever `yieldFarmAddress` emits `YieldUpdated`, the runtime
    ///      will call `onYieldUpdated(newAPY, tokenAddress)` on the subscriber.
    ///
    /// @param contractAddress The address of the source contract whose events to monitor.
    ///        Must be a deployed contract that emits the target event.
    /// @param eventSignature The `keccak256` hash of the full event signature to listen for
    ///        (e.g., `keccak256("YieldUpdated(uint256,address)")`).
    function subscribe(
        address contractAddress,
        bytes32 eventSignature
    ) external;

    /*//////////////////////////////////////////////////////////////
                          CALLBACK INTERFACE
    //////////////////////////////////////////////////////////////*/

    /// @notice Callback invoked by the Somnia reactivity runtime when a subscribed
    ///         yield-update event is detected.
    /// @dev This function is called automatically — it should NOT be called by users or
    ///      external contracts directly.
    ///
    ///      > [!WARNING]
    ///      > **Implementors MUST validate `msg.sender`** to confirm the call originates
    ///      > from the trusted Somnia reactivity runtime. Without this check, an attacker
    ///      > can spoof callbacks with fabricated `newAPY` values, potentially causing the
    ///      > optimizer to rebalance into unfavorable positions or execute swaps at
    ///      > manipulated prices — a direct vector for fund extraction.
    ///
    ///      Implementations should keep callback logic lightweight to avoid exceeding the
    ///      gas stipend provided by the reactivity runtime. Heavy operations (e.g., swaps)
    ///      should be deferred to a separate transaction triggered by state set in this callback.
    ///
    /// @param newAPY The updated annual percentage yield, expressed in basis points
    ///        (e.g., 500 = 5.00% APY). The Yield Optimizer uses this value to decide
    ///        whether to rebalance across available farming strategies.
    /// @param tokenAddress The address of the token whose yield was updated. Allows the
    ///        optimizer to identify which vault or farming position the update pertains to.
    function onYieldUpdated(uint256 newAPY, address tokenAddress) external;
}
