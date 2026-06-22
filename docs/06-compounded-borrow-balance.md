# Compounded Borrow Balance

`getCompoundedBorrowBalance()` calculates the amount a user currently owes, including the interest accrued since the borrow position was last updated.

The function is necessary because `principalBorrowBalance` does not always represent the user's current debt. It only stores the debt recorded at the user's last state update.

```solidity
function getCompoundedBorrowBalance(
    CoreLibrary.UserReserveData storage _self,
    CoreLibrary.ReserveData storage _reserve
) internal view returns (uint256) {
    if (_self.principalBorrowBalance == 0) {
        return 0;
    }

    uint256 principalBorrowBalanceRay = _self.principalBorrowBalance.wadToRay();
    uint256 compoundedBalance = 0;
    uint256 cumulatedInterest = 0;

    if (_self.stableBorrowRate > 0) {
        cumulatedInterest = calculateCompoundedInterest(
            _self.stableBorrowRate,
            _self.lastUpdateTimestamp
        );
    } else {
        cumulatedInterest = calculateCompoundedInterest(
            _reserve.currentVariableBorrowRate,
            _reserve.lastUpdateTimestamp
        )
            .rayMul(_reserve.lastVariableBorrowCumulativeIndex)
            .rayDiv(_self.lastVariableBorrowCumulativeIndex);
    }

    compoundedBalance = principalBorrowBalanceRay
        .rayMul(cumulatedInterest)
        .rayToWad();

    if (compoundedBalance == _self.principalBorrowBalance) {
        if (_self.lastUpdateTimestamp != block.timestamp) {
            return _self.principalBorrowBalance + 1;
        }
    }

    return compoundedBalance;
}
```

# Why the Compounded Borrow Balance Is Needed

Suppose Alice borrows:

```text
1,000 DAI
```

At the moment of borrowing:

```text
principalBorrowBalance = 1,000 DAI
current debt = 1,000 DAI
```

As time passes, interest accrues. However, Aave does not continuously update Alice's stored principal.

Her stored state may still contain:

```text
principalBorrowBalance = 1,000 DAI
```

while her real current debt may be:

```text
current compounded debt = 1,051.27 DAI
```

The protocol therefore needs a function that derives the current debt from the stored principal and the interest accumulated since the last update.

Conceptually:

```text
currentDebt =
    principalBorrowBalance
    * accumulatedInterestFactor
```

The compounded borrow balance is needed when the protocol determines:

- how much the user must repay;
- whether the user's position is healthy;
- whether the user can borrow more;
- whether the position can be liquidated;
- how much debt must be stored when the user's state is updated.

Without this calculation, the protocol would continue treating the debt as the original principal even after interest had accrued.

# Why Aave Does Not Update Every Borrower Continuously

A blockchain cannot automatically update every borrower's balance every second.

Doing so would require the protocol to:

```text
iterate over every borrower
calculate each borrower's new debt
write every updated balance to storage
```

The cost would increase with the number of borrowers and would eventually exceed the block gas limit.

Aave instead uses lazy accounting:

```text
1. Store the debt at the user's last update.
2. Store interest rates, indexes, and timestamps.
3. Calculate the current debt only when it is needed.
```

This makes the cost of reading or updating one user's debt independent of the total number of borrowers.

# Why Borrow Interest Is Compounded

Borrow interest is compounded because accrued interest becomes part of the outstanding debt.

Future interest is therefore charged on:

```text
original principal + previously accrued interest
```

With simple interest, interest is always calculated only on the original principal.

For example, with a 10% annual rate:

```text
Initial debt: 1,000 DAI

After year 1:
1,000 + 100 = 1,100 DAI

After year 2:
1,100 + another 100 based on the original principal
= 1,200 DAI
```

With compound interest:

```text
Initial debt: 1,000 DAI

After year 1:
1,000 * 1.10 = 1,100 DAI

After year 2:
1,100 * 1.10 = 1,210 DAI
```

During the second year, interest is also charged on the 100 DAI of interest accumulated during the first year.

The general formula is:

```text
currentDebt =
    principal
    * (1 + ratePerPeriod) ^ numberOfPeriods
```

In Aave V1, the period used by `calculateCompoundedInterest()` is one second:

```solidity
uint256 ratePerSecond = _rate / SECONDS_PER_YEAR;

return (ratePerSecond + WadRayMath.ray())
    .rayPow(timeDifference);
```

Conceptually:

```text
compoundedInterest =
    (1 + annualRate / secondsPerYear) ^ elapsedSeconds
```

# Principal Balance Versus Current Debt

`principalBorrowBalance` is a stored checkpoint.

It represents the user's debt when their borrow state was last updated.

`getCompoundedBorrowBalance()` derives the debt at the current block.

```text
principalBorrowBalance = debt at the previous checkpoint

compoundedBorrowBalance = debt now
```

For example:

```text
Principal borrow balance: 1,000 DAI
Accumulated interest factor: 1.05127
```

```text
Current debt:
1,000 * 1.05127 = 1,051.27 DAI
```

The principal remains unchanged in storage until a state-changing operation updates the user's position.

# Zero-Debt Case

The function first checks whether the user has any principal debt:

```solidity
if (_self.principalBorrowBalance == 0) {
    return 0;
}
```

A user with no borrowed principal cannot have accrued borrow interest.

This early return also avoids unnecessary calculations.

# Converting the Principal From Wad to Ray

```solidity
uint256 principalBorrowBalanceRay =
    _self.principalBorrowBalance.wadToRay();
```

Token balances are normally represented in wad precision:

```text
1 wad = 1e18
```

Interest rates and cumulative indexes are represented in ray precision:

```text
1 ray = 1e27
```

Because the principal is multiplied by a ray interest factor, it is converted to ray before the multiplication.

Example:

```text
1,000 DAI in wad = 1,000e18
1,000 DAI converted to ray = 1,000e27
```

After the calculation, the result is converted back to wad.

# Stable-Rate Borrow

A stable-rate position is identified by:

```solidity
_self.stableBorrowRate > 0
```

For a stable borrow, the function uses the user's own stored stable rate and timestamp:

```solidity
cumulatedInterest = calculateCompoundedInterest(
    _self.stableBorrowRate,
    _self.lastUpdateTimestamp
);
```

Conceptually:

```text
stableInterestFactor =
    (1 + userStableRatePerSecond) ^ timeSinceUserUpdate
```

The current debt is then:

```text
currentStableDebt =
    principalBorrowBalance
    * stableInterestFactor
```

## Stable-Rate Example

Suppose Alice has:

```text
principalBorrowBalance = 1,000 DAI
stableBorrowRate = 5%
lastUpdateTimestamp = one year ago
```

After one year, the compounded factor is approximately:

```text
1.05127
```

Therefore:

```text
currentDebt =
    1,000 * 1.05127

currentDebt ≈ 1,051.27 DAI
```

The stable-rate branch does not use the reserve variable borrow index. The position grows using the stable rate stored specifically for the user.

# Variable-Rate Borrow

When:

```solidity
_self.stableBorrowRate == 0
```

the function treats the position as variable-rate debt.

The variable interest factor is calculated with:

```solidity
cumulatedInterest = calculateCompoundedInterest(
    _reserve.currentVariableBorrowRate,
    _reserve.lastUpdateTimestamp
)
    .rayMul(_reserve.lastVariableBorrowCumulativeIndex)
    .rayDiv(_self.lastVariableBorrowCumulativeIndex);
```

This calculation has three stages.

## 1. Accrue Interest Since the Reserve's Last Update

```solidity
calculateCompoundedInterest(
    _reserve.currentVariableBorrowRate,
    _reserve.lastUpdateTimestamp
)
```

The stored reserve variable borrow index only contains interest accumulated up to the reserve's last update.

This calculation derives the additional interest accumulated between:

```text
reserve.lastUpdateTimestamp
```

and:

```text
block.timestamp
```

Conceptually:

```text
interestSinceReserveUpdate =
    (1 + currentVariableRatePerSecond) ^ elapsedSeconds
```

## 2. Calculate the Current Reserve Variable Borrow Index

The new interest factor is multiplied by the previously stored reserve index:

```text
currentReserveVariableIndex =
    interestSinceReserveUpdate
    * storedReserveVariableIndex
```

Example:

```text
Stored reserve variable index = 1.08
Interest since reserve update = 1.02
```

```text
Current reserve variable index =
    1.08 * 1.02

Current reserve variable index = 1.1016
```

This preserves all previously accumulated variable interest and adds the interest accrued since the last reserve update.

## 3. Compare the Reserve Index With the User Checkpoint

The user's `lastVariableBorrowCumulativeIndex` records the reserve variable borrow index when the user's debt was last updated.

The user's growth factor is:

```text
userGrowthFactor =
    currentReserveVariableIndex
    / userLastVariableBorrowIndex
```

This ensures that the user pays interest only for the growth that occurred after their own checkpoint.

## Variable-Rate Example

Suppose Bob has:

```text
principalBorrowBalance = 1,000 DAI
user variable borrow index = 1.05
current reserve variable borrow index = 1.10
```

The growth factor is:

```text
1.10 / 1.05 ≈ 1.047619
```

Bob's current debt is:

```text
1,000 * 1.047619 ≈ 1,047.62 DAI
```

Bob is not charged for the reserve index growth from `1.00` to `1.05`, because that growth happened before his checkpoint.

# Applying the Interest Factor

After calculating the stable or variable interest factor, the function applies it to the principal:

```solidity
compoundedBalance = principalBorrowBalanceRay
    .rayMul(cumulatedInterest)
    .rayToWad();
```

Conceptually:

```text
currentDebt =
    principalBorrowBalance
    * cumulatedInterest
```

For example:

```text
Principal debt = 1,000 DAI
Cumulated interest factor = 1.10
```

```text
Current debt = 1,100 DAI
```

The calculation is performed in ray precision and then converted back to wad so the result can be used as a token amount.

# The One-Wei Rounding Protection

Very small balances, very low rates, or very short periods can produce interest smaller than one token wei.

Because Solidity uses integer arithmetic, the calculated value can round back to the original principal.

Example:

```text
Principal = 1 wei
Mathematical debt = 1.000000001 wei
Integer result = 1 wei
```

The function detects this case:

```solidity
if (compoundedBalance == _self.principalBorrowBalance) {
    if (_self.lastUpdateTimestamp != block.timestamp) {
        return _self.principalBorrowBalance + 1;
    }
}
```

If time has passed but the calculated interest disappears because of rounding, the function returns:

```text
principalBorrowBalance + 1 wei
```

This prevents very small borrow positions from becoming interest-free because of integer truncation.

The additional wei is not added when no time has passed.

# Stable and Variable Debt Compared

## Stable Debt

Stable debt uses:

```text
user stable borrow rate
user last update timestamp
```

The growth factor is:

```text
compounded user stable rate since the user's last update
```

## Variable Debt

Variable debt uses:

```text
current reserve variable borrow rate
reserve last update timestamp
stored reserve variable borrow index
user variable borrow checkpoint
```

The growth factor is:

```text
current reserve variable index
/
user variable borrow index
```

Both branches ultimately calculate:

```text
currentDebt =
    storedPrincipal
    * growthFactor
```

# Complete Mental Model

The function can be understood as:

```text
If the user has no principal:
    return 0

If the position is stable:
    calculate compounded interest using
    the user's stable rate and timestamp

If the position is variable:
    calculate the current reserve variable index
    divide it by the user's checkpoint index

Multiply the principal by the resulting growth factor

If interest accrued but rounded to zero:
    return principal + 1 wei

Otherwise:
    return the calculated current debt
```

The central distinction is:

```text
principalBorrowBalance
    = debt stored at the last user update

getCompoundedBorrowBalance()
    = debt owed at the current block
```

# Summary

`getCompoundedBorrowBalance()` is necessary because Aave uses lazy accounting.

The protocol does not update every borrower's debt continuously. Instead, it stores the principal at the last checkpoint and derives the current debt from interest rates, indexes, and elapsed time.

Compound interest is used because accrued interest becomes part of the outstanding debt and future interest accrues on top of it.

For stable positions:

```text
currentDebt =
    principal
    * compounded user stable interest
```

For variable positions:

```text
currentDebt =
    principal
    * current reserve variable index
    / user variable index
```

This design gives Aave accurate current debt calculations without iterating over every borrower or continuously writing balances to storage.
