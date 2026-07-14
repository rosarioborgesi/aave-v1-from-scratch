# Borrow Flow

## Overview

The `borrow` function allows a user to withdraw an asset from an Aave reserve by using their existing deposits as collateral.

The collateral is not transferred during the borrow. It remains deposited in the protocol, but the user cannot redeem or transfer an amount that would make the position unsafe.

The user chooses either a stable or variable interest rate. The borrow has no fixed duration or repayment schedule.

## Function

```solidity
function borrow(
    address _reserve,
    uint256 _amount,
    uint256 _interestRateMode,
    uint16 _referralCode
) external;
```

- `_reserve`: asset the user wants to borrow.
- `_amount`: amount of the asset to borrow.
- `_interestRateMode`: `1` for stable or `2` for variable.
- `_referralCode`: identifies the integration that originated the borrow.

## High-Level Flow

### 1. Validate the Borrow Request

The `LendingPool` verifies that:

- the reserve is active, not frozen, and enabled for borrowing;
- the amount is greater than zero;
- the selected interest-rate mode is valid;
- the reserve has enough available liquidity.

### 2. Validate the User Position

The `LendingPoolDataProvider` calculates the user's global position across all reserves, including:

- total collateral;
- existing borrows and fees;
- weighted average LTV;
- health factor.

The borrow is rejected if the user has no collateral, is already below the liquidation threshold, or does not have enough collateral to cover the new debt and origination fee.

### 3. Apply Stable-Rate Restrictions

For a stable-rate borrow, the protocol also verifies that:

- stable borrowing is enabled for the reserve;
- the user is not borrowing against the same asset in a way that could be abused;
- the requested amount does not exceed the configured percentage of the reserve's available liquidity.

### 4. Update the Borrow State

The `LendingPoolCore`:

- accrues interest accumulated since the previous reserve update;
- adds the new debt to the reserve's stable or variable total borrows;
- adds accrued interest to the user's previous borrow balance;
- adds the new amount and origination fee to the user's position;
- stores the user's stable rate or variable borrow index;
- recalculates reserve interest rates and updates the timestamp.

### 5. Transfer the Asset

After all checks and state updates succeed, the `LendingPoolCore` transfers the borrowed underlying asset to the user.

The `LendingPool` then emits the `Borrow` event.

## Contracts Involved

### `LendingPool`

Entry point for the borrow. It validates the request, coordinates the other contracts, transfers the asset, and emits the event.

### `LendingPoolDataProvider`

Calculates the user's collateral, debt, LTV, health factor, and collateral required for the new borrow.

### `FeeProvider`

Calculates the loan origination fee.

### `LendingPoolParametersProvider`

Provides the maximum percentage of available liquidity that can be borrowed at a stable rate.

### `LendingPoolCore`

Stores the reserve and user borrow state, updates indexes and rates, and sends the underlying asset to the borrower.

## Result

After a successful borrow:

- the user receives the requested underlying asset;
- the user's debt and origination fee increase;
- the reserve's available liquidity decreases;
- the reserve's total borrows increase;
- interest rates are recalculated based on the new utilization.

## References

- Aave Protocol Whitepaper V1.0, section 3.3: Borrow
- Aave V1 `LendingPool.borrow`: https://github.com/aave/aave-protocol/blob/master/contracts/lendingpool/LendingPool.sol
- Aave V1 `LendingPoolCore.updateStateOnBorrow`: https://github.com/aave/aave-protocol/blob/master/contracts/lendingpool/LendingPoolCore.sol
