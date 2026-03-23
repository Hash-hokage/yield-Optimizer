// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ISomniaReactivityPrecompile
/// @notice Interface for the Somnia Reactivity Precompile at 0x0000000000000000000000000000000000000100.
/// @dev Contracts call subscribe(SubscriptionData) to register a handler that the precompile
///      will invoke whenever a matching event is emitted. The subscription owner must hold >= 32 STT.
interface ISomniaReactivityPrecompile {
    /// @notice Full subscription configuration passed to subscribe().
    struct SubscriptionData {
        bytes32[4] eventTopics;          // Topic filters; bytes32(0) = wildcard
        address origin;                  // tx.origin filter (address(0) = wildcard)
        address caller;                  // msg.sender filter (address(0) = wildcard)
        address emitter;                 // Contract whose events to watch (address(0) = wildcard)
        address handlerContractAddress;  // Contract with onEvent() to invoke
        bytes4  handlerFunctionSelector; // Selector — always use onEvent.selector
        uint64  priorityFeePerGas;       // Validator tip in wei. Minimum: 2_000_000_000 (2 gwei)
        uint64  maxFeePerGas;            // Fee ceiling in wei. Minimum: 10_000_000_000 (10 gwei)
        uint64  gasLimit;                // Max gas per invocation. Use 3_000_000 for complex handlers
        bool    isGuaranteed;            // true = retry if block is full
        bool    isCoalesced;             // true = batch multiple events per block
    }

    /// @notice Creates a subscription. Returns the subscription ID.
    /// @dev Caller (subscription owner) must hold >= 32 STT.
    function subscribe(SubscriptionData calldata data) external returns (uint256 subscriptionId);

    /// @notice Cancels a subscription. Only callable by the subscription owner.
    function unsubscribe(uint256 subscriptionId) external;

    /// @notice Returns the SubscriptionData and owner for a given subscription ID.
    function getSubscriptionInfo(uint256 subscriptionId)
        external view returns (SubscriptionData memory, address owner);
}
