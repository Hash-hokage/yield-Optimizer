// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @title MockOracle
/// @author Hash-Hokage
/// @notice A mock yield oracle that simulates APY updates for local testing.
/// @dev This contract acts as the event source that the Yield Optimizer subscribes to
///      via Somnia's reactivity layer. Calling `setYield` updates the stored APY and
///      emits a `YieldUpdated` event, which triggers the optimizer's `onYieldUpdated`
///      callback in a reactive environment.
///
///      FOR LOCAL TESTING ONLY — no access control is enforced on `setYield`.
contract MockOracle {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The most recently reported annual percentage yield, in basis points.
    /// @dev 500 = 5.00% APY. Updated each time `setYield` is called.
    uint256 public currentAPY;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted whenever the yield rate is updated.
    /// @param newAPY The updated annual percentage yield in basis points.
    /// @param tokenAddress The address of the token whose yield was updated.
    event YieldUpdated(uint256 newAPY, address tokenAddress);

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets a new APY value and emits a `YieldUpdated` event.
    /// @dev In a live Somnia reactive environment, the emitted event would automatically
    ///      trigger `onYieldUpdated` on all subscribed contracts. In local Foundry tests,
    ///      you can call this function and then manually invoke the callback to simulate
    ///      the reactive flow.
    ///
    ///      **No access control** — any caller can update the yield. This is intentional
    ///      for testing flexibility but must not be used in production.
    ///
    /// @param _newAPY The new annual percentage yield in basis points (e.g., 750 = 7.50%).
    /// @param _token The address of the token whose yield is being updated.
    function setYield(uint256 _newAPY, address _token) external {
        currentAPY = _newAPY;
        emit YieldUpdated(_newAPY, _token);
    }
}
