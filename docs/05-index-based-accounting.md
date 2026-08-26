# Index-Based Accounting

Index-based accounting is one of the core design patterns of Aave.

Instead of updating every user's balance when interest accrues, the protocol:

```text
1. Updates one global reserve index
2. Stores a checkpoint index for each user
3. Calculates the user's current value only when needed
```

This produces the same financial result as continuously updating every balance, but it is much cheaper and more scalable.

The most important formula is:

```text
currentUserValue = storedUserValue * currentReserveIndex / userIndex
```

The reserve index tracks global growth.

The user index tracks when the user entered or was last updated.

The ratio between them determines how much interest belongs to that user.

# Lazy Interest Accrual

This technique is called lazy accounting.

The protocol does not continuously write accrued interest into every user's stored balance.

Instead, interest is calculated when the balance is needed.

For example:

```text
the user checks their balance
the user deposits again
the user redeems
the user transfers aTokens
the protocol updates the user's position
```

At that moment, the protocol calculates the current balance using the reserve index and the user index.

The accrued interest can then be materialized into the user's stored principal balance if necessary.

# The Problem With Updating Every Balance

Suppose a reserve has three depositors:

```text
Alice deposits 100 DAI
Bob deposits 200 DAI
Carol deposits 50 DAI
```

After some time, the reserve earns 5% interest.

Without an index, the protocol would need to update every user's stored balance:

```text
Alice: 100 DAI -> 105 DAI
Bob:   200 DAI -> 210 DAI
Carol:  50 DAI -> 52.5 DAI
```

The protocol would need logic similar to:

```solidity
for (uint256 i = 0; i < depositors.length; i++) {
    balances[depositors[i]] = balances[depositors[i]] * 105 / 100;
}
```

With only three users, this may look manageable.

However, a real protocol can have:

```text
100 users
10,000 users
1,000,000 users
```

Updating every balance would require one storage write for every user.

The gas cost would grow with the number of depositors:

```text
O(number of users)
```

Eventually, the transaction would exceed the block gas limit and become impossible to execute.

# The Global Liquidity Index

Instead of updating every user balance, Aave updates one global reserve value:

```text
lastLiquidityCumulativeIndex
```

This index represents the cumulative growth of deposits in the reserve.

At initialization:

```text
liquidity index = 1.00
```

In ray precision:

```text
liquidity index = 1e27
```

After the reserve accumulates 5% income:

```text
liquidity index = 1.05
```

# Comparison

## Updating Every User Balance

The protocol would need to:

```text
update Alice's balance
update Bob's balance
update Carol's balance
update every other depositor's balance
```

The work increases with the number of users:

```text
O(number of users)
```

It also requires many expensive storage writes.

## Using an Index

The protocol updates only one reserve-wide value:

```text
lastLiquidityCumulativeIndex
```

The reserve update cost does not depend on the number of depositors:

```text
O(1)
```

Each user's balance can also be calculated independently:

```text
O(1)
```

# Calculating User Balances

The general formula is:

```text
currentBalance = principalBalance * currentReserveIndex / userIndex
```

The `currentReserveIndex` represents the current reserve-wide growth.

The `userIndex` represents the reserve index when the user's balance was last updated.

Suppose all three users entered when the index was `1.00`, and the current reserve index is `1.05`.

## Alice

```text
Principal balance = 100 DAI
User index = 1.00
Current reserve index = 1.05
```

```text
currentBalance = 100 * 1.05 / 1.00
currentBalance = 105 DAI
```

## Bob

```text
Principal balance = 200 DAI
User index = 1.00
Current reserve index = 1.05
```

```text
currentBalance = 200 * 1.05 / 1.00
currentBalance = 210 DAI
```

## Carol

```text
Principal balance = 50 DAI
User index = 1.00
Current reserve index = 1.05
```

```text
currentBalance = 50 * 1.05 / 1.00
currentBalance = 52.5 DAI
```

The result is the same as updating every balance manually.

However, the protocol only updated one storage value:

```text
reserve index: 1.00 -> 1.05
```

# Users Entering at Different Times

Users do not all deposit at the same moment.

The user-specific index ensures that each user earns interest only from the moment they enter the reserve.

Suppose:

```text
Alice deposits 100 DAI when the index is 1.00
Bob deposits 200 DAI when the index is 1.02
Carol deposits 50 DAI when the index is 1.04
```

Later, the current reserve index becomes:

```text
1.05
```

## Alice

Alice participated in the full growth from `1.00` to `1.05`.

```text
currentBalance = 100 * 1.05 / 1.00
currentBalance = 105 DAI
```

Alice earned:

```text
5 DAI
```

## Bob

Bob entered when the reserve had already reached `1.02`.

```text
currentBalance = 200 * 1.05 / 1.02
currentBalance ≈ 205.88 DAI
```

Bob earned only from the growth between `1.02` and `1.05`.

He does not receive the interest accumulated before he deposited.

## Carol

Carol entered even later, when the reserve index was `1.04`.

```text
currentBalance = 50 * 1.05 / 1.04
currentBalance ≈ 50.48 DAI
```

Carol earns only from the growth between `1.04` and `1.05`.

# Reserve Index and User Index

The reserve index and user index record cumulative interest growth at two different points.

```text
Reserve index = the reserve's current cumulative interest growth
User index = the reserve growth level when the user's balance was last updated
```

For a user with an active balance:
```text
user index ≤ current reserve index
```
When the user's balance is updated, their user index is set to the current reserve index. Afterwards, the current reserve index can only stay the same or increase because interest growth is non-negative.

The ratio between the current reserve index and the user's index determines the growth that belongs to the user:

```text
growthFactor = currentReserveIndex / userIndex
```

For example:

```text
currentReserveIndex = 1.05
userIndex = 1.02
```

```text
growthFactor = 1.05 / 1.02
growthFactor ≈ 1.0294
```

The user's position grew by approximately 2.94% since their last checkpoint.


# Deposit-Side and Borrow-Side Indexes

Aave uses the same general technique on both sides of the protocol.

For suppliers:

```text
liquidity index
```

tracks the growth of deposited assets.

For variable-rate borrowers:

```text
variable borrow index
```

tracks the growth of variable debt.

The general idea is the same:

```text
currentValue = storedValue * currentGlobalIndex / userCheckpointIndex
```

This allows Aave to calculate both supplier balances and borrower debt without continuously updating every account.

This general global-index/user-checkpoint formula applies directly to supplier balances and variable-rate borrower debt. It does not directly apply to stable-rate debt: a stable borrower accrues interest using their individual `stableBorrowRate` and `lastUpdateTimestamp`, rather than global and user variable-borrow index checkpoints.

## `lastLiquidityCumulativeIndex` Checkpoints

`lastLiquidityCumulativeIndex` is the reserve's stored checkpoint for supplier income. It is not updated continuously: immediately before an action changes a reserve's liquidity, debt, or interest rates, the protocol calls `updateCumulativeIndexes()` to record the time-based supplier interest accrued since `lastUpdateTimestamp`:

```text
new liquidity index = old liquidity index × linear interest factor
```

This happens for deposits, redeems, borrows, repays, liquidations (for both the debt reserve and the collateral reserve), borrow-rate swaps, and stable-rate rebalances. The checkpoint is taken before the action changes the reserve, so the elapsed period receives the rate that applied during that period. `updateCumulativeIndexes()` leaves the index unchanged when the reserve has no outstanding borrows, because there is then no borrower-paid interest to distribute.

## `lastVariableBorrowCumulativeIndex` Checkpoints

The same operations also call `updateCumulativeIndexes()` for `lastVariableBorrowCumulativeIndex`. It is the reserve's stored checkpoint for **variable-rate debt**, so the same operation list and checkpoint-before-state-change rule apply. Its time-based update differs from the liquidity index: it applies compound interest at `currentVariableBorrowRate`:

```text
new variable-borrow index = old variable-borrow index × compound interest factor
```

A variable-rate borrower's current debt is calculated from their stored principal, the current variable-borrow index, and their personal variable-borrow checkpoint index. The two global indexes are checkpointed together, but they have different roles: `lastLiquidityCumulativeIndex` tracks supplier income with linear interest, while `lastVariableBorrowCumulativeIndex` tracks variable debt with compound interest. Stable-rate debt is tracked separately using the borrower's stable rate, not this index.

## Depositor Liquidity Checkpoint

For deposits, the reserve-wide stored checkpoint is `lastLiquidityCumulativeIndex`. The depositor's corresponding checkpoint is stored in the aToken contract, not in `LendingPoolCore.UserReserveData`:

```solidity
mapping(address user => uint256 lastNormalizedIncome) internal s_userIndexes;
```

`AToken.s_userIndexes[user]` records the reserve normalized income that has already been applied to that user's aToken balance. It is updated whenever the aToken materializes that user's accrued interest—for example, during a deposit, redeem, aToken transfer, or liquidation:

```solidity
s_userIndexes[_user] =
    i_core.getReserveNormalizedIncome(i_underlyingAssetAddress);
```

`getReserveNormalizedIncome()` is the current liquidity index used for balance calculation. It includes the stored checkpoint and the linear interest accrued since the reserve's last update:

```text
current normalized income =
    lastLiquidityCumulativeIndex
    × linear interest since lastUpdateTimestamp
```

Therefore, for a depositor:

```text
current reserve index = getReserveNormalizedIncome(reserve)
user index            = AToken.s_userIndexes[user]
stored principal      = stored aToken (ERC20) balance
```

The aToken calculates:

```text
current aToken balance =
    stored aToken balance
    × current reserve index
    / user index
```

The implementation is in [AToken.sol](../src/tokenization/AToken.sol#L319).

The public `AToken.getUserIndex(user)` function exposes this depositor checkpoint.

### Example: Materializing Interest and Updating the Checkpoint

Suppose a depositor has:

```text
stored aToken balance = 100 DAI
current reserve index = 1.05
user index = 1.00
```

Their current balance is `105 DAI`. When the aToken accumulates this balance, it mints the `5 DAI` interest into the stored aToken balance and updates the user's checkpoint to `1.05`:

```text
new stored aToken balance = 105 DAI
new user index = 1.05
```

Future interest is therefore calculated from index `1.05`, so the same 5 DAI is not counted twice.


## Variable-Rate Borrower Checkpoint

For a variable-rate borrower, the reserve-wide and user-specific checkpoints are:

```text
reserve global checkpoint = ReserveData.lastVariableBorrowCumulativeIndex
user checkpoint           = UserReserveData.lastVariableBorrowCumulativeIndex
stored value              = UserReserveData.principalBorrowBalance
```

The current variable debt is calculated by `getCompoundedBorrowBalance()`. In its variable-rate branch (`stableBorrowRate == 0`), it effectively computes:

```text
current global index =
    reserve.lastVariableBorrowCumulativeIndex
    × compounded interest since reserve.lastUpdateTimestamp

current variable debt =
    user.principalBorrowBalance
    × current global index
    / user.lastVariableBorrowCumulativeIndex
```

The implementation is in [CoreLibrary.sol](../src/libraries/CoreLibrary.sol#L497). The user checkpoint is refreshed to the reserve's checkpoint whenever the user's variable debt is materialized and updated—for example, after a variable-rate borrow, repayment, liquidation, or a rate swap into variable mode. It is reset to zero when the user has stable debt or no debt.


# Stable-Rate Debt: Lazy Accrual Without an Index

Stable-rate debt also uses lazy accrual: the protocol does not increase a stable borrower's stored debt every second. Instead, when the debt is read or the position is changed—for example on an additional borrow, repayment, liquidation, rate swap, or rebalance—it calculates the interest that accrued since the user's previous update and materializes it into the stored principal.

For an individual stable borrower, the relevant `UserReserveData` fields are:

```text
principalBorrowBalance = debt recorded at the user's last update
stableBorrowRate       = this borrower's personal stable rate
lastUpdateTimestamp    = time of this borrower's last debt update
```

The borrower-level calculation is performed by `getCompoundedBorrowBalance()` when `stableBorrowRate > 0`:

```text
current stable debt =
    principalBorrowBalance
    × compoundedInterest(stableBorrowRate, time since lastUpdateTimestamp)
```

When the debt is materialized, the accrued interest becomes principal and the user's timestamp is updated:

```text
new principalBorrowBalance = old principalBorrowBalance + accrued interest
new lastUpdateTimestamp    = now
```

The implementation is in [CoreLibrary.sol](../src/libraries/CoreLibrary.sol#L475).

The reserve keeps separate fields for reserve-level stable-debt accounting:

```text
totalBorrowsStable               = aggregate principal of stable loans
currentAverageStableBorrowRate   = weighted average of borrowers' stable rates
currentStableBorrowRate          = rate currently offered for a new stable loan
```

`currentStableBorrowRate` is calculated by the interest-rate strategy when the reserve is updated. It is copied into `user.stableBorrowRate` when a user borrows at a stable rate, swaps from variable to stable, or is rebalanced. Recalculating the reserve's offered rate alone does not change existing borrowers' personal rates; their debt continues to accrue at their own `stableBorrowRate` until their position is updated or rebalanced.

This differs from variable-rate debt: variable borrowers share a reserve-wide rate, so their debt can use `lastVariableBorrowCumulativeIndex` and a per-user index checkpoint. Stable borrowers can have different rates, so their lazy accrual uses each borrower's rate and timestamp instead of a shared debt index.
