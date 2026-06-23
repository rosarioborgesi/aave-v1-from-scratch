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

Suppose Alice has a stable-rate borrow position.

At the moment Alice's debt was last updated:

```text
principalBorrowBalance = 1,000 DAI
stableBorrowRate = 5%
lastUpdateTimestamp = one year ago
```

The function detects that Alice has stable-rate debt because:

```solidity
_self.stableBorrowRate > 0
```

It therefore executes:

```solidity
cumulatedInterest = calculateCompoundedInterest(
    _self.stableBorrowRate,
    _self.lastUpdateTimestamp
);
```

### Step 1: Calculate the Elapsed Time

The function measures the time between Alice's last debt update and the current block:

```text
elapsedSeconds =
    block.timestamp
    - Alice's lastUpdateTimestamp
```

In this example:

```text
elapsedSeconds = one year
elapsedSeconds = 31,536,000 seconds
```

### Step 2: Convert the Annual Stable Rate Into a Per-Second Rate

Alice's annual stable rate is:

```text
5% = 0.05
```

The protocol converts it into a per-second rate:

```text
ratePerSecond =
    stableBorrowRate
    / SECONDS_PER_YEAR
```

Conceptually:

```text
ratePerSecond =
    0.05
    / 31,536,000
```

This produces a very small interest rate for one second.

### Step 3: Compound the Rate for Every Elapsed Second

The compounded-interest factor is:

```text
compoundedStableInterest =
    (1 + ratePerSecond) ^ elapsedSeconds
```

Using the example:

```text
compoundedStableInterest =
    (1 + 0.05 / 31,536,000) ^ 31,536,000
```

The result is approximately:

```text
1.05127
```

This is a growth factor, not the interest percentage itself.

```text
1.05127 = 1.00 + 0.05127
```

Where:

```text
1.00 represents Alice's original debt
0.05127 represents approximately 5.127% accrued interest
```

### Step 4: Apply the Growth Factor to Alice's Principal

Alice's stored principal is:

```text
1,000 DAI
```

The growth factor is:

```text
1.05127
```

Therefore:

```text
currentDebt =
    principalBorrowBalance
    * compoundedStableInterest
```

```text
currentDebt =
    1,000 * 1.05127
```

```text
currentDebt ≈ 1,051.27 DAI
```

Alice has therefore accrued approximately:

```text
1,051.27 - 1,000 = 51.27 DAI
```

of interest.

### Mapping the Example to the Code

The stable-rate branch calculates:

```solidity
cumulatedInterest = calculateCompoundedInterest(
    _self.stableBorrowRate,
    _self.lastUpdateTimestamp
);
```

Using the example:

```text
cumulatedInterest =
    calculateCompoundedInterest(
        5%,
        one year ago
    )
```

```text
cumulatedInterest ≈ 1.05127
```

The function then applies this factor to the principal:

```solidity
compoundedBalance =
    principalBorrowBalanceRay
        .rayMul(cumulatedInterest)
        .rayToWad();
```

Conceptually:

```text
compoundedBalance =
    1,000 * 1.05127
```

```text
compoundedBalance ≈ 1,051.27 DAI
```



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

Suppose Bob has a variable-rate borrow position.

At the moment Bob's debt was last updated:

```text
principalBorrowBalance = 1,000 DAI
user variable borrow index = 1.05
```

The user variable borrow index is Bob's checkpoint. It records the reserve variable borrow index when Bob's debt was last updated.

At the reserve's last update:

```text
stored reserve variable borrow index = 1.08
current variable borrow rate = 10% annually
```

Assume that, since the reserve's last update, the compounded variable interest factor has grown by 2%:

```text
interest since reserve update = 1.02
```

The protocol now needs to calculate how much Bob owes at the current block.

### Step 1: Calculate the Interest Since the Reserve's Last Update

The function first calculates the compounded interest accumulated since the reserve was last updated:

```solidity
calculateCompoundedInterest(
    _reserve.currentVariableBorrowRate,
    _reserve.lastUpdateTimestamp
)
```

In this example, the result is:

```text
1.02
```

This means variable debt in the reserve has grown by another 2% since the stored reserve index was last updated. (1.02 ray is equal to 2%)

Remember that `calculateCompoundedInterest` calculates the compounded interest factor accumulated during this interval:

```text
_reserve.lastUpdateTimestamp → block.timestamp
```

### Step 2: Calculate the Current Reserve Variable Borrow Index

The stored reserve variable borrow index is:

```text
1.08
```

The new compounded interest factor is:

```text
1.02
```

The protocol multiplies them:

```text
currentReserveVariableIndex =
    storedReserveVariableIndex
    * interestSinceReserveUpdate
```

```text
currentReserveVariableIndex =
    1.08 * 1.02
```

```text
currentReserveVariableIndex = 1.1016
```

This value includes both:

```text
the variable interest accumulated before the reserve's last update
+
the variable interest accumulated since the reserve's last update
```

### Step 3: Compare the Reserve Index With Bob's Checkpoint

Bob's user variable borrow index is:

```text
1.05
```

The current reserve variable borrow index is:

```text
1.1016
```

The protocol calculates Bob's personal growth factor:

```text
userGrowthFactor =
    currentReserveVariableIndex
    / userVariableBorrowIndex
```

```text
userGrowthFactor =
    1.1016 / 1.05
```

```text
userGrowthFactor ≈ 1.04914
```

This means Bob's debt has grown by approximately:

```text
4.914%
```

since his last checkpoint.


### Why Not Use `1.1016` Directly?

The current reserve variable borrow index is:

```text
1.1016
```

However, this value includes all the variable-interest growth accumulated since the reserve index started at:

```text
1.00
```

Bob's debt was last updated later, when the reserve index was already:

```text
1.05
```

So the timeline is:

```text
Reserve starts:          1.00
Bob's checkpoint:        1.05
Current reserve index:   1.1016
```

The growth from:

```text
1.00 -> 1.05
```

happened before Bob's checkpoint.

Bob must not be charged for that earlier growth. He should only be charged for the growth that occurred after his checkpoint:

```text
1.05 -> 1.1016
```

Because indexes are multiplicative growth factors, the protocol uses division to calculate the growth since Bob's checkpoint:

```text
userGrowthFactor =
    currentReserveVariableIndex
    / userVariableBorrowIndex
```

Using the example:

```text
userGrowthFactor =
    1.1016 / 1.05
```

```text
userGrowthFactor ≈ 1.04914
```

Dividing by `1.05` effectively resets Bob's starting point to `1.00`.

The result:

```text
1.04914
```

means Bob's debt has grown by approximately:

```text
4.914%
```

since his last checkpoint.

The key idea is:

```text
current reserve index / user checkpoint index
=
growth since the user's checkpoint
```

The protocol cannot use `1.1016` directly because that would charge Bob for interest accumulated before his debt checkpoint.


### Step 4: Apply the Growth Factor to Bob's Principal

Bob's stored principal is:

```text
1,000 DAI
```

The growth factor is:

```text
1.04914
```

Therefore:

```text
currentDebt =
    principalBorrowBalance
    * userGrowthFactor
```

```text
currentDebt =
    1,000 * 1.04914
```

```text
currentDebt ≈ 1,049.14 DAI
```

This is Bob's current compounded borrow balance.

### Mapping the Example to the Code

The variable-rate calculation is:

```solidity
cumulatedInterest = calculateCompoundedInterest(
    _reserve.currentVariableBorrowRate,
    _reserve.lastUpdateTimestamp
)
    .rayMul(_reserve.lastVariableBorrowCumulativeIndex)
    .rayDiv(_self.lastVariableBorrowCumulativeIndex);
```

Using the values from the example:

```text
cumulatedInterest =
    1.02
    * 1.08
    / 1.05
```

```text
cumulatedInterest =
    1.1016
    / 1.05
```

```text
cumulatedInterest ≈ 1.04914
```

The function then applies this factor to the user's principal:

```solidity
compoundedBalance =
    principalBorrowBalanceRay
        .rayMul(cumulatedInterest)
        .rayToWad();
```

Using Bob's principal:

```text
compoundedBalance =
    1,000
    * 1.04914
```

```text
compoundedBalance ≈ 1,049.14 DAI
```

The calculation therefore performs three important operations:

```text
1. Brings the reserve variable borrow index up to the current block.
2. Preserves all variable interest accumulated before the reserve's last update.
3. Charges Bob only for the index growth that occurred after his own checkpoint.
```

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

