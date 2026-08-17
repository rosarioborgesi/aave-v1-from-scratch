# Lending Pool Liquidation Manager

`LendingPoolLiquidationManager` contains the protocol's liquidation logic. A liquidation lets a third party repay part of a borrower's debt once the borrower's health factor is below the liquidation threshold. In return, the liquidator receives the borrower's selected collateral plus that reserve's liquidation bonus. This reduces risky debt and helps protect the pool from bad debt.

Users do not call this contract directly. They call `LendingPool.liquidationCall`, which checks that both reserves are active and then executes this manager's `liquidationCall` with `delegatecall`. The manager returns an error code and message; `LendingPool` turns any non-zero error code into `LendingPool__LiquidationFailed`.

## Delegatecall and storage layout

`delegatecall` runs the manager's code in the `LendingPool` contract's context. Therefore:

- reads and writes use `LendingPool` storage;
- `msg.sender` remains the liquidator and `msg.value` remains the value supplied to `LendingPool`;
- events emitted by the manager are emitted from the `LendingPool` address.

For this to work, the first five manager storage variables must have the same order and types as the corresponding `LendingPool` variables:

```solidity
LendingPoolAddressesProvider private s_addressesProvider;
LendingPoolCore private s_core;
LendingPoolDataProvider private s_dataProvider;
LendingPoolParametersProvider private s_parametersProvider;
IFeeProvider private s_feeProvider;
```

They are not initialized in the manager: during a delegated call they resolve to the values already stored in `LendingPool`. This is why the manager has no constructor. The manager's later `s_ethereumAddress` slot does not overlap with a `LendingPool` slot used by this implementation and is not used by its liquidation logic.

## Liquidation flow

The manager's entry point is named `liquidationCall` (not `liquidateCall`). Its arguments select the collateral to seize, the debt reserve to repay, the borrower, the requested repayment, and whether the liquidator wants aTokens or underlying collateral.

It proceeds as follows:

1. It obtains the borrower's global data and requires the health factor to be below the liquidation threshold.
2. It verifies that the borrower owns the selected collateral and that the reserve is enabled as collateral globally and for that borrower.
3. It reads the borrower's compounded debt in the selected principal reserve. A debt reserve with no outstanding borrow cannot be liquidated.
4. It applies the 50% close factor: the requested repayment is capped at half of the borrower's compounded debt.
5. It calculates the collateral that repayment can seize. If the borrower lacks enough of that collateral, it instead reduces the repayment to the amount their collateral can support.
6. It separately tries to settle the borrower's outstanding origination fee using the collateral remaining after the liquidator's collateral has been reserved.
7. When the liquidator requests underlying collateral, it checks that the collateral reserve has enough available liquidity. This check is unnecessary when the liquidator receives aTokens, because the aTokens are transferred rather than redeemed.
8. It updates debt, reserve, user, and fee accounting through `LendingPoolCore`, transfers the selected collateral, collects the repaid debt from the liquidator, settles any fee collateral, and emits `LiquidationCall`. If a fee is settled, it also emits `OriginationFeeLiquidated`.

The manager reports these expected validation failures with a non-zero code rather than reverting itself: healthy position, no selected collateral, selected collateral unavailable for liquidation, no borrow in the selected debt reserve, and insufficient underlying collateral liquidity. A failed lower-level call still causes the outer `LendingPool` call to revert with `LendingPool__LiquidationCallFailed`.

## `liquidationCall`

```solidity
function liquidationCall(
    address _collateral,
    address _reserve,
    address _user,
    uint256 _purchaseAmount,
    bool _receiveAToken
) external payable returns (uint256, string memory)
```

This function performs one partial liquidation. `_purchaseAmount` is an upper bound, not necessarily the amount actually paid: the 50% close factor and the borrower's available collateral can reduce it. The actual repayment is sent from the liquidator to the principal reserve using `s_core.transferToReserve`; for an ERC-20 reserve, the liquidator must have approved the core, while an ETH reserve uses `msg.value`.

If `_receiveAToken` is `true`, the manager calls `transferOnLiquidation` to transfer the seized collateral aTokens from borrower to liquidator. If it is `false`, it burns the borrower's corresponding aTokens and transfers the underlying asset from the core to the liquidator. Any collateral taken to pay the origination fee is always burned and transferred as underlying collateral to the token distributor.

## `_calculateAvailableCollateralToLiquidate`

```solidity
function _calculateAvailableCollateralToLiquidate(
    address _collateral,
    address _principal,
    uint256 _purchaseAmount,
    uint256 _userCollateralBalance
) internal view returns (uint256 collateralAmount, uint256 principalAmountNeeded)
```

This helper converts a proposed debt repayment into collateral to seize using oracle prices and the collateral reserve's liquidation bonus. It returns both the collateral amount and the principal repayment that amount can support.

With sufficient collateral, it uses:

```text
collateralAmount = principalPrice × purchaseAmount ÷ collateralPrice
                   × liquidationBonus ÷ 100
principalAmountNeeded = purchaseAmount
```

For example, repaying `0.01 WETH` when DAI collateral costs `0.00025 ETH` and has a `105%` bonus seizes `42 DAI`: `0.01 / 0.00025 × 105 / 100`.

If this calculated amount exceeds `_userCollateralBalance`, the helper seizes the borrower's entire selected collateral balance and reverses the calculation:

```text
principalAmountNeeded = collateralPrice × collateralAmount ÷ principalPrice
                        × 100 ÷ liquidationBonus
```

The caller then lowers the actual repayment to `principalAmountNeeded`. This ensures the liquidator never pays more debt than the selected collateral, including its bonus, can cover. Integer division rounds down, so the supported repayment is conservatively rounded in the protocol's favour.
