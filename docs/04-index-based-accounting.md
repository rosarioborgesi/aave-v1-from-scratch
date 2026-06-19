# Index-Based Accounting

Aave does not update every user's balance whenever interest accrues.

Instead, it uses global reserve indexes and user-specific indexes to calculate balances only when needed.

This design is essential because updating every depositor or borrower individually would be too expensive and would not scale.

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

The users' stored principal balances do not need to be changed:

```text
Alice stored principal = 100 DAI
Bob stored principal   = 200 DAI
Carol stored principal = 50 DAI
```

Their current balances are calculated when needed.

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

A useful mental model is to think of the reserve index as an interest clock.

```text
Reserve index = current position of the interest clock
User index = position of the clock when the user entered or was last updated
```

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

# Example in AToken

In Aave V1, an aToken can calculate the user's current balance using a formula like:

```solidity
return _balance
    .wadToRay()
    .rayMul(i_core.getReserveNormalizedIncome(i_underlyingAssetAddress))
    .rayDiv(s_userIndexes[_user])
    .rayToWad();
```

Conceptually, this is:

```text
currentBalance = storedPrincipalBalance * currentNormalizedIncome / userIndex
```

Suppose:

```text
storedPrincipalBalance = 100 DAI
currentNormalizedIncome = 1.05
userIndex = 1.00
```

Then:

```text
currentBalance = 100 * 1.05 / 1.00
currentBalance = 105 DAI
```

# Updating the User Checkpoint

When the user's balance is accumulated, the protocol can mint the accrued interest into the stored principal balance.

Suppose:

```text
Stored principal balance = 100 DAI
Calculated current balance = 105 DAI
```

The balance increase is:

```text
balanceIncrease = 105 - 100
balanceIncrease = 5 DAI
```

The protocol can mint the 5 DAI of accrued interest:

```text
New stored principal balance = 105 DAI
```

Then the user's index is updated to the current reserve index:

```text
Old user index = 1.00
Current reserve index = 1.05
New user index = 1.05
```

From that point onward, future interest is calculated starting from `1.05`.

This prevents the same interest from being counted twice.

# Why the Liquidity Index Only Grows

The liquidity cumulative index is updated using the interest factor accumulated since the previous reserve update:

```solidity
uint256 cumulatedLiquidityInterest =
    calculateLinearInterest(
        _self.currentLiquidityRate,
        _self.lastUpdateTimestamp
    );

_self.lastLiquidityCumulativeIndex =
    cumulatedLiquidityInterest.rayMul(
        _self.lastLiquidityCumulativeIndex
    );
```

`calculateLinearInterest()` returns:

```text
linearInterest =
    1 + rate * elapsedTime
```

As long as:

```text
rate >= 0
elapsedTime >= 0
```

the interest factor is always greater than or equal to `1.0`.

Therefore:

```text
newIndex = oldIndex * valueGreaterThanOrEqualTo1
```

The index can only:

```text
stay the same
```

or:

```text
increase
```

It cannot decrease unless the protocol supports negative liquidity rates, which this design does not.

This is different from available liquidity.

Available liquidity can decrease when users borrow or redeem assets.

The liquidity index only tracks accumulated interest growth.

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

# Advantages

## No Loops Over Users

The protocol never needs to iterate over every depositor or borrower.

This avoids unbounded loops that could exceed the block gas limit.

## Lower Gas Costs

Updating one reserve index is much cheaper than updating thousands of user balances.

Storage writes are among the most expensive EVM operations.

## Scalability

The reserve can support a very large number of users without making interest updates more expensive.

The cost of updating the reserve does not grow with the number of users.

## Fair Interest Distribution

Each user stores their own checkpoint index.

This ensures that users earn interest only from the moment they enter or last update their position.

## No Continuous Updates

The protocol does not need a transaction every second to distribute interest.

Interest exists mathematically through the index and is calculated only when required.

## Shared Accounting

One global index represents the reserve-wide growth for every supplier.

The protocol does not need separate interest accumulation logic for each account.

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

# Summary

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
