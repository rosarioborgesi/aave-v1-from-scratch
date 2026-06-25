# Reserve Interest Rates in Aave V1

Aave V1 stores three current interest rates for every reserve:

```text
currentLiquidityRate
currentStableBorrowRate
currentVariableBorrowRate
```

These values describe the reserve's current economic state. They are recalculated whenever an operation changes available liquidity, total borrows, or the composition of stable and variable debt.

A useful mental model is:

```text
reserve state changes
        ↓
utilization changes
        ↓
interest-rate strategy calculates new rates
        ↓
LendingPoolCore stores the new rates
```

# The Three Reserve Rates

## Current Liquidity Rate

```solidity
reserve.currentLiquidityRate
```

This is the annual rate earned by depositors.

It determines how quickly the reserve liquidity index grows:

```text
currentLiquidityRate
        ↓
linear interest over time
        ↓
liquidity index growth
        ↓
aToken balance growth
```

Example:

```text
starting liquidity index = 1.00 ray
liquidity rate = 5%
elapsed time = 1 year

new liquidity index = 1.00 × 1.05
new liquidity index = 1.05 ray
```

## Current Stable Borrow Rate

```solidity
reserve.currentStableBorrowRate
```

This is the stable rate currently offered to users opening a new stable-rate borrow position.

When a user borrows at a stable rate, the reserve rate is copied into the user's own data:

```text
user.stableBorrowRate =
    reserve.currentStableBorrowRate
```

The distinction is:

```text
reserve.currentStableBorrowRate
    = rate currently offered to new stable borrowers

user.stableBorrowRate
    = rate currently applied to that user's stable debt
```

Changing the reserve's current stable rate does not automatically change every existing stable-rate position.

## Current Variable Borrow Rate

```solidity
reserve.currentVariableBorrowRate
```

This is the annual rate currently applied to variable-rate debt.

It determines how quickly the variable borrow index grows:

```text
currentVariableBorrowRate
        ↓
compounded interest over time
        ↓
variable borrow index growth
        ↓
variable borrower debt growth
```

Example:

```text
starting variable borrow index = 1.00 ray
variable borrow rate = 10%
elapsed time = 1 year

new variable borrow index ≈ 1.10517 ray
```

# Where the Rates Come From

`LendingPoolCore` does not calculate the rates itself.

Each reserve stores an interest-rate strategy address:

```solidity
reserve.interestRateStrategyAddress
```

The core calls that strategy:

```solidity
IReserveInterestRateStrategy(
    reserve.interestRateStrategyAddress
).calculateInterestRates(...)
```

The strategy returns:

```solidity
(
    uint256 newLiquidityRate,
    uint256 newStableRate,
    uint256 newVariableRate
)
```

The core stores the returned values:

```solidity
reserve.currentLiquidityRate = newLiquidityRate;
reserve.currentStableBorrowRate = newStableRate;
reserve.currentVariableBorrowRate = newVariableRate;
```

This separation keeps storage and accounting in `LendingPoolCore`, while the rate formulas remain inside the strategy contract.

# Inputs Used to Calculate the Rates

The strategy receives:

```solidity
calculateInterestRates(
    _reserve,
    getReserveAvailableLiquidity(_reserve)
        + _liquidityAdded
        - _liquidityTaken,
    reserve.totalBorrowsStable,
    reserve.totalBorrowsVariable,
    reserve.currentAverageStableBorrowRate
);
```

## Reserve Address

```solidity
_reserve
```

This identifies the asset whose rates are being calculated.

Examples:

```text
DAI
USDC
ETH
```

## Projected Available Liquidity

```solidity
getReserveAvailableLiquidity(_reserve)
    + _liquidityAdded
    - _liquidityTaken
```

This is the liquidity expected to remain after the current action.

The adjustment is needed because the rate update may happen before the actual token transfer.

### Deposit Example

```text
current available liquidity = 1,000 DAI
deposit amount = 200 DAI

projected available liquidity =
    1,000 + 200 - 0
    = 1,200 DAI
```

### Borrow Example

```text
current available liquidity = 1,000 DAI
borrow amount = 300 DAI

projected available liquidity =
    1,000 + 0 - 300
    = 700 DAI
```

## Total Stable Borrows

```solidity
reserve.totalBorrowsStable
```

This is the total principal borrowed at stable rates.

It contributes to:

```text
total reserve debt
utilization
overall borrow rate
liquidity rate
```

## Total Variable Borrows

```solidity
reserve.totalBorrowsVariable
```

This is the total principal borrowed at variable rates.

Together:

```text
totalBorrows =
    totalBorrowsStable
    + totalBorrowsVariable
```

## Current Average Stable Borrow Rate

```solidity
reserve.currentAverageStableBorrowRate
```

Different stable borrowers may have different user-specific rates.

Example:

```text
Alice borrowed 400 DAI at 5%
Bob borrowed 600 DAI at 8%
```

The reserve stores one weighted average stable rate to represent all stable-rate debt.

# Utilization and Why Rates Change

Rates are mainly driven by utilization:

```text
utilization =
    total borrows
    / total liquidity
```

where:

```text
total liquidity =
    available liquidity
    + total borrows
```

## Low Utilization

```text
available liquidity = 800 DAI
total borrows = 200 DAI

utilization = 200 / 1,000 = 20%
```

Liquidity is abundant, so borrow rates can remain relatively low.

## High Utilization

```text
available liquidity = 200 DAI
total borrows = 800 DAI

utilization = 800 / 1,000 = 80%
```

Liquidity is scarce, so borrow rates rise to:

```text
discourage more borrowing
encourage repayments
attract new deposits
protect withdrawal liquidity
```

# When the Rates Are Updated

The rates are recalculated whenever reserve conditions change.

Typical operations include:

```text
deposit
redeem
borrow
repay
liquidation
rate swap
stable-rate rebalance
flash-loan income
```

Typical liquidity adjustments are:

```text
deposit:
    liquidityAdded = deposit amount
    liquidityTaken = 0

repay:
    liquidityAdded = repayment amount
    liquidityTaken = 0

borrow:
    liquidityAdded = 0
    liquidityTaken = borrowed amount

redeem:
    liquidityAdded = 0
    liquidityTaken = redeemed amount
```

Some operations may pass zero for both values while still changing borrow composition or average rates.

# The Importance of Update Order

A reserve update follows this order:

```solidity
reserve.updateCumulativeIndexes();

_updateReserveInterestRatesAndTimestamp(
    _reserve,
    _liquidityAdded,
    _liquidityTaken
);
```

This order is essential.

## Step 1: Apply the Old Rates to the Elapsed Period

The time before the current action belongs to the previous reserve state.

Therefore, the indexes must first grow using the old rates.

Example:

```text
old liquidity rate = 5%
old variable rate = 10%
elapsed time = 1 year
```

The liquidity and variable borrow indexes are updated with those rates.

## Step 2: Calculate and Store the New Rates

After the old period is accounted for, the strategy calculates rates for the reserve state after the current action.

Example after a large deposit:

```text
new liquidity rate = 3%
new stable borrow rate = 6%
new variable borrow rate = 7%
```

## Step 3: Store the New Timestamp

```solidity
reserve.lastUpdateTimestamp =
    uint40(block.timestamp);
```

The current block becomes the checkpoint for the next interest period.

The result is:

```text
old rates
    → apply to the period before the action

new rates
    → apply from the current action onward
```

# Why New Rates Do Not Apply Retroactively

Suppose the reserve had:

```text
old liquidity rate = 5%
old variable rate = 10%
```

After one year, a deposit causes the strategy to return:

```text
new liquidity rate = 3%
new variable rate = 7%
```

The elapsed year must still use the old `5%` and `10%` rates.

The new `3%` and `7%` rates start only after the deposit.

Otherwise, the protocol would apply rates to a period during which those rates did not exist.

# Example: First Deposit Into a New Reserve

After initialization:

```text
liquidity index = 1 ray
variable borrow index = 1 ray

current liquidity rate = 0
current stable borrow rate = 0
current variable borrow rate = 0
```

Suppose 30 days pass before the first deposit.

Because the old rates are zero:

```text
linear interest factor =
    1 + 0 × 30 days / 365 days
    = 1 ray

compounded variable interest factor =
    (1 + 0) ^ 30 days
    = 1 ray
```

Therefore:

```text
new liquidity index =
    1 ray × 1 ray
    = 1 ray

new variable borrow index =
    1 ray × 1 ray
    = 1 ray
```

The strategy may then return:

```text
liquidity rate = 5%
stable borrow rate = 8%
variable borrow rate = 10%
```

Those rates are stored and begin applying from the current timestamp onward.

# Example: Deposit Into an Active Reserve

Suppose the reserve already has:

```text
liquidity index = 1.00 ray
variable borrow index = 1.00 ray

current liquidity rate = 5%
current variable rate = 10%

elapsed time = 1 year
```

Before storing the new rates, the protocol updates the indexes.

## Liquidity Index

```text
linear interest =
    1 + 5% × 1 year
    = 1.05

new liquidity index =
    1.00 × 1.05
    = 1.05 ray
```

## Variable Borrow Index

```text
rate per second =
    10% / 31,536,000

compounded interest =
    (1 + rate per second) ^ 31,536,000
    ≈ 1.10517

new variable borrow index =
    1.00 × 1.10517
    ≈ 1.10517 ray
```

The deposit may lower utilization, causing the strategy to return:

```text
new liquidity rate = 3%
new stable borrow rate = 6%
new variable borrow rate = 7%
```

The final state becomes:

```text
liquidity index = 1.05 ray
variable borrow index ≈ 1.10517 ray

current liquidity rate = 3%
current stable borrow rate = 6%
current variable borrow rate = 7%

lastUpdateTimestamp = current block timestamp
```

# How Each Rate Is Used Later

## `currentLiquidityRate`

Used for:

```text
linear supplier interest
liquidity index growth
reserve normalized income
aToken balance growth
```

## `currentStableBorrowRate`

Used as the rate offered when a new stable-rate position is opened.

It may be copied into:

```solidity
user.stableBorrowRate
```

## `currentVariableBorrowRate`

Used for:

```text
compounded variable interest
variable borrow index growth
current variable debt
```


# Summary

```text
currentLiquidityRate
    = current supplier earning rate

currentStableBorrowRate
    = current rate offered to new stable borrowers

currentVariableBorrowRate
    = current rate applied to variable debt
```

The protocol always:

```text
1. accumulates interest using the old rates;
2. calculates new rates from the updated reserve state;
3. stores the new rates;
4. stores the current timestamp as the next checkpoint.
```

This ensures that every time interval is accounted for using the rates that were actually active during that interval.
