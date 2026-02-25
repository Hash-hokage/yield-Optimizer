// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @title IYieldFarm
/// @author Hash-Hokage
/// @notice Interface for an ERC-4626 compliant single-asset yield vault.
/// @dev This interface follows the ERC-4626 "Tokenized Vault Standard" (EIP-4626), which
///      standardises the deposit / withdrawal lifecycle for yield-bearing vaults.
///      The underlying asset is dynamically denominated in **USDC**; all `assets` values
///      therefore represent amounts in USDC's native decimals (typically 6).
///
///      **ERC-4626 Overview:**
///      - Depositors supply the underlying asset (USDC) and receive vault shares in return.
///      - Shares represent a pro-rata claim on the vault's total holdings, which grow as
///        the vault earns yield from the connected farming strategy.
///      - Redemption burns shares and returns the proportional amount of the underlying asset.
///
///      Integrators should always check `asset()` at runtime to confirm the denomination
///      token, as the vault may be redeployed against a different stablecoin in the future.
interface IYieldFarm {
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the address of the underlying ERC-20 asset managed by the vault.
    /// @dev Per ERC-4626, this MUST be an ERC-20 token contract. For this Yield Optimizer
    ///      the asset is dynamically denominated in USDC. Callers should verify this address
    ///      on-chain rather than hard-coding it, to remain resilient to vault migrations.
    /// @return assetAddress The address of the underlying USDC token contract.
    function asset() external view returns (address assetAddress);

    /// @notice Returns the total amount of the underlying asset currently held by the vault.
    /// @dev This includes both idle assets sitting in the vault contract and assets actively
    ///      deployed into the yield-farming strategy. The value is denominated in USDC
    ///      (typically 6 decimals).
    ///
    ///      Integrators can use this value alongside `totalSupply()` to compute the current
    ///      share price:  `pricePerShare = totalAssets() / totalSupply()`.
    /// @return totalManagedAssets The total quantity of the underlying asset under management.
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT / REDEEM FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits an exact amount of the underlying asset (USDC) into the vault and
    ///         mints the corresponding number of vault shares to `receiver`.
    /// @dev Follows the ERC-4626 `deposit` specification:
    ///      1. The caller MUST have approved this vault to spend at least `assets` of the
    ///         underlying token.
    ///      2. The vault pulls `assets` USDC from `msg.sender`.
    ///      3. The vault mints shares to `receiver` based on the current exchange rate:
    ///         `shares = assets * totalSupply / totalAssets` (rounded down per ERC-4626).
    ///      4. Emits an ERC-4626 `Deposit` event.
    ///
    ///      **Security note:** Because the share price is derived from on-chain state,
    ///      depositors should be aware of potential donation / inflation attacks on
    ///      low-liquidity vaults. First-depositor protections are recommended in the
    ///      concrete implementation.
    ///
    /// @param assets The exact amount of underlying USDC to deposit.
    /// @param receiver The address that will receive the minted vault shares.
    /// @return shares The number of vault shares minted to `receiver`.
    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);

    /// @notice Burns an exact number of vault shares from `owner` and sends the proportional
    ///         amount of the underlying asset (USDC) to `receiver`.
    /// @dev Follows the ERC-4626 `redeem` specification:
    ///      1. If `msg.sender` is not `owner`, the caller MUST have sufficient ERC-20
    ///         `allowance` on the vault shares from `owner`.
    ///      2. The vault burns `shares` from `owner`.
    ///      3. The vault transfers the proportional USDC to `receiver`:
    ///         `assets = shares * totalAssets / totalSupply` (rounded down per ERC-4626).
    ///      4. Emits an ERC-4626 `Withdraw` event.
    ///
    ///      **Security note:** Large redemptions may require the vault to unwind positions
    ///      from the farming strategy, which could be subject to slippage. Implementations
    ///      should enforce withdrawal caps or queuing mechanisms where appropriate.
    ///
    /// @param shares The exact number of vault shares to redeem (burn).
    /// @param receiver The address that will receive the underlying USDC.
    /// @param owner The address whose shares are being redeemed. If different from
    ///        `msg.sender`, the caller must have approval via the ERC-20 allowance mechanism.
    /// @return assets The amount of underlying USDC sent to `receiver`.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);
}
