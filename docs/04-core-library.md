# CoreLibrary

`CoreLibrary` contains the core data structures and accounting helper functions used by `LendingPoolCore`.

In Aave V1, a reserve represents one asset supported by the protocol, such as DAI, USDC, or WETH.

Each reserve stores information about:

* liquidity indexes
* borrow indexes
* interest rates
* total borrows
* collateral configuration
* reserve status
* aToken address
* interest rate strategy address

`CoreLibrary` is not a standalone protocol contract.

It is a library used by `LendingPoolCore` to keep reserve and user accounting logic separated from the main storage contract.

## Main Responsibilities

`CoreLibrary` is responsible for:

```text
1. Defining ReserveData
2. Defining UserReserveData
3. Initializing a reserve
4. Updating cumulative indexes
5. Calculating normalized income
6. Calculating linear interest
7. Calculating compounded interest
8. Calculating total borrows
9. Calculating a user's compounded borrow balance
```

# ReserveData

`ReserveData` stores the global state of a reserve.

A reserve is the protocol representation of one supported asset.

Example:

```text
DAI reserve
USDC reserve
WETH reserve
```

Each reserve has its own `ReserveData`.

A simplified mental model is:

```solidity
mapping(address asset => ReserveData reserveData) internal s_reserves;
```

This means:

```text
asset address => reserve data
```

Example:

```text
s_reserves[DAI] returns the global DAI reserve state
```

## Struct

```solidity
struct ReserveData {
    uint256 lastLiquidityCumulativeIndex;
    uint256 currentLiquidityRate;

    uint256 totalBorrowsStable;
    uint256 totalBorrowsVariable;

    uint256 currentVariableBorrowRate;
    uint256 currentStableBorrowRate;
    uint256 currentAverageStableBorrowRate;

    uint256 lastVariableBorrowCumulativeIndex;

    uint256 baseLTVasCollateral;
    uint256 liquidationThreshold;
    uint256 liquidationBonus;

    uint256 decimals;

    address aTokenAddress;
    address interestRateStrategyAddress;

    uint40 lastUpdateTimestamp;

    bool borrowingEnabled;
    bool usageAsCollateralEnabled;
    bool isStableBorrowRateEnabled;
    bool isActive;
    bool isFreezed;
}
```

## Important Fields

### lastLiquidityCumulativeIndex

`lastLiquidityCumulativeIndex` is the liquidity index of the reserve.

It tracks how much the deposited liquidity has grown over time.

It is expressed in ray precision:

```text
1 ray = 1e27
```

At initialization, this value starts at:

```text
1e27
```

That means:

```text
1.0 in ray precision
```

Then it grows over time as the reserve earns interest.

Example:

```text
1.00 ray = no income
1.05 ray = reserve grew by 5%
1.10 ray = reserve grew by 10%
```

If Alice deposited 100 DAI when the index was 1.00, and later the normalized income is 1.05, her position is worth around:

```text
100 * 1.05 = 105 DAI
```

So the index tracks growth due to interest.

### currentLiquidityRate

`currentLiquidityRate` is the current supply rate of the reserve.

It is expressed in ray precision.

Example:

```text
5% annual liquidity rate = 0.05 ray = 5e25
```

This rate is used to calculate how much liquidity providers earn over time.

### totalBorrowsStable

`totalBorrowsStable` is the total amount borrowed from the reserve at a stable rate.

It is expressed in the reserve asset decimals.

Example:

```text
If DAI has 18 decimals, totalBorrowsStable is expressed with 18 decimals.
```

### totalBorrowsVariable

`totalBorrowsVariable` is the total amount borrowed from the reserve at a variable rate.

It is also expressed in the reserve asset decimals.

### currentVariableBorrowRate

`currentVariableBorrowRate` is the current variable borrow rate of the reserve.

It is expressed in ray precision.

### currentStableBorrowRate

`currentStableBorrowRate` is the current stable borrow rate of the reserve.

It is expressed in ray precision.

### currentAverageStableBorrowRate

`currentAverageStableBorrowRate` is the weighted average stable rate of all stable borrows in the reserve.

It is expressed in ray precision.

### lastVariableBorrowCumulativeIndex

`lastVariableBorrowCumulativeIndex` is the variable borrow index of the reserve.

It tracks how much variable debt has grown over time.

It is expressed in ray precision and starts at:

```text
1e27
```

### baseLTVasCollateral

`baseLTVasCollateral` defines how much a user can borrow against this asset.

Example:

```text
baseLTVasCollateral = 75
```

means the user can borrow up to 75% of the collateral value.

### liquidationThreshold

`liquidationThreshold` defines the threshold at which a user can be liquidated.

Example:

```text
liquidationThreshold = 80
```

means the user becomes liquidatable when the borrow position exceeds 80% of the collateral value.

### liquidationBonus

`liquidationBonus` is the extra collateral discount given to liquidators.

### decimals

`decimals` stores the number of decimals of the underlying reserve asset.

Example:

```text
DAI = 18 decimals
USDC = 6 decimals
```

### aTokenAddress

`aTokenAddress` is the address of the aToken linked to the reserve.

Example:

```text
DAI reserve -> aDAI
USDC reserve -> aUSDC
```

When a user deposits the underlying asset, the corresponding aToken is minted.

### interestRateStrategyAddress

`interestRateStrategyAddress` is the address of the interest rate strategy contract used by the reserve.

The interest rate strategy calculates:

```text
liquidity rate
stable borrow rate
variable borrow rate
```

### lastUpdateTimestamp

`lastUpdateTimestamp` stores the last time the reserve state was updated.

It is used to calculate how much time has passed since the previous update.

### borrowingEnabled

If `borrowingEnabled` is true, users can borrow this asset.

### usageAsCollateralEnabled

If `usageAsCollateralEnabled` is true, users can use this asset as collateral.

### isStableBorrowRateEnabled

If `isStableBorrowRateEnabled` is true, users can borrow this asset at a stable rate.

### isActive

If `isActive` is true, the reserve has been initialized and can be used.

### isFreezed

If `isFreezed` is true, the reserve is frozen.

In Aave V1, a frozen reserve allows limited actions such as repayments and redemptions, but does not allow new deposits or new borrows.

# UserReserveData

`UserReserveData` stores the state of one user for one specific reserve.

A simplified mental model is:

```solidity
mapping(address user => mapping(address reserve => UserReserveData userReserveData))
    internal s_usersReserveData;
```

This means:

```text
user address => reserve address => user reserve data
```

Example:

```text
s_usersReserveData[Alice][DAI] returns Alice's DAI reserve data
```

## Struct

```solidity
struct UserReserveData {
    uint256 principalBorrowBalance;
    uint256 lastVariableBorrowCumulativeIndex;
    uint256 originationFee;
    uint256 stableBorrowRate;
    uint40 lastUpdateTimestamp;
    bool useAsCollateral;
}
```

## Important Fields

### principalBorrowBalance

`principalBorrowBalance` is the amount borrowed by the user before adding newly accrued interest.

If the user has no borrow position, this value is zero.

### lastVariableBorrowCumulativeIndex

`lastVariableBorrowCumulativeIndex` stores the variable borrow index applied to the user the last time their borrow state was updated.

It is used to calculate how much variable debt has grown since the last user update.

### originationFee

`originationFee` is the fee accumulated by the user when borrowing.

### stableBorrowRate

`stableBorrowRate` is the stable rate at which the user borrowed.

If this value is greater than zero, the user has a stable borrow position.

If this value is zero, the user is treated as having a variable borrow position.

### lastUpdateTimestamp

`lastUpdateTimestamp` is the last time the user's reserve data was updated.

### useAsCollateral

`useAsCollateral` defines whether the user's deposit in this reserve is enabled as collateral.

For example, after a user's first deposit, the protocol can mark the reserve as collateral:

```text
useAsCollateral = true
```

# init

`init` initializes a reserve.

```solidity
function init(
    ReserveData storage _self,
    address _aTokenAddress,
    uint256 _decimals,
    address _interestRateStrategyAddress
) external
```

The function receives:

```text
_self = reserve data being initialized
_aTokenAddress = address of the aToken linked to the reserve
_decimals = decimals of the underlying asset
_interestRateStrategyAddress = address of the interest rate strategy
```

## What It Does

The function does four important things:

```text
1. Checks that the reserve was not already initialized
2. Initializes the liquidity index to 1 ray
3. Initializes the variable borrow index to 1 ray
4. Stores the aToken, decimals, interest rate strategy, and reserve status
```

## Initialization Check

The reserve is considered already initialized if it already has an aToken address:

```solidity
if (_self.aTokenAddress != address(0)) {
    revert CoreLibrary__ReserveAlreadyInitialized();
}
```

This prevents initializing the same reserve twice.

## Initial Liquidity Index

If the liquidity index is zero, it is initialized to one ray:

```solidity
_self.lastLiquidityCumulativeIndex = WadRayMath.ray();
```

This means:

```text
lastLiquidityCumulativeIndex = 1e27
```

The reserve starts with an index of `1.0`.

## Initial Variable Borrow Index

If the variable borrow index is zero, it is also initialized to one ray:

```solidity
_self.lastVariableBorrowCumulativeIndex = WadRayMath.ray();
```

This means variable debt also starts from an index of `1.0`.

## Reserve Activation

The function then stores the configuration:

```solidity
_self.aTokenAddress = _aTokenAddress;
_self.decimals = _decimals;
_self.interestRateStrategyAddress = _interestRateStrategyAddress;
_self.isActive = true;
_self.isFreezed = false;
```

After this, the reserve is active and ready to be used by the protocol.

# updateCumulativeIndexes

`updateCumulativeIndexes` updates the liquidity cumulative index and the variable borrow cumulative index.

```solidity
function updateCumulativeIndexes(
    ReserveData storage _self
) internal
```

## What It Does

The function first calculates total borrows:

```solidity
uint256 totalBorrows = getTotalBorrows(_self);
```

Then it updates indexes only if there are active borrows:

```solidity
if (totalBorrows > 0) {
    ...
}
```

This is important because if nobody is borrowing, there is no borrow interest being generated.

## Liquidity Index Update

The liquidity index is updated using linear interest:

```solidity
uint256 cumulatedLiquidityInterest =
    calculateLinearInterest(_self.currentLiquidityRate, _self.lastUpdateTimestamp);

_self.lastLiquidityCumulativeIndex =
    cumulatedLiquidityInterest.rayMul(_self.lastLiquidityCumulativeIndex);
```

The idea is:

```text
newLiquidityIndex = linearInterest * previousLiquidityIndex
```

## Variable Borrow Index Update

The variable borrow index is updated using compounded interest:

```solidity
uint256 cumulatedVariableBorrowInterest =
    calculateCompoundedInterest(_self.currentVariableBorrowRate, _self.lastUpdateTimestamp);

_self.lastVariableBorrowCumulativeIndex =
    cumulatedVariableBorrowInterest.rayMul(_self.lastVariableBorrowCumulativeIndex);
```

The idea is:

```text
newVariableBorrowIndex = compoundedVariableBorrowInterest * previousVariableBorrowIndex
```

# calculateLinearInterest

`calculateLinearInterest` calculates the interest accumulated between the last update timestamp and the current block timestamp.

```solidity
function calculateLinearInterest(
    uint256 _rate,
    uint40 _lastUpdateTimestamp
) internal view returns (uint256)
```

The function receives:

```text
_rate = annual liquidity rate, in ray
_lastUpdateTimestamp = timestamp of the last reserve update
```

It returns the linear interest factor accumulated during the elapsed time, also in ray.

## Formula

The idea is:

```text
linearInterest = 1 + rate * timeDelta
```

Where:

```text
timeDelta = timePassed / secondsPerYear
```

So the full formula is:

```text
linearInterest = 1 + rate * (timePassed / secondsPerYear)
```

In ray precision, `1` is represented as:

```text
1e27
```

So in Solidity, the result is:

```solidity
return _rate.rayMul(timeDelta) + WadRayMath.ray();
```

## Example: No Time Passed

Suppose:

```text
rate = 5% = 5e25
timePassed = 0
```

Then:

```text
linearInterest = 1 + 0.05 * 0
linearInterest = 1
```

In ray precision:

```text
linearInterest = 1e27
```

So if no time has passed, the interest multiplier is still `1.0`.

## Example: One Year at 5%

Suppose:

```text
rate = 5% = 5e25
timePassed = 1 year
```

Then:

```text
linearInterest = 1 + 0.05 * 1
linearInterest = 1.05
```

In ray precision:

```text
linearInterest = 1.05e27
```

So after one full year at a 5% liquidity rate, the reserve grows by 5%.

## Example: Half Year at 5%

Suppose:

```text
rate = 5% = 5e25
timePassed = 0.5 years
```

Then:

```text
linearInterest = 1 + 0.05 * 0.5
linearInterest = 1.025
```

In ray precision:

```text
linearInterest = 1.025e27
```

So after half a year at a 5% annual rate, the reserve grows by 2.5%.

# getNormalizedIncome

`getNormalizedIncome` calculates the current normalized income of a reserve.

```solidity
function getNormalizedIncome(
    CoreLibrary.ReserveData storage _reserve
) internal view returns (uint256)
```

The function uses:

```text
currentLiquidityRate
lastUpdateTimestamp
lastLiquidityCumulativeIndex
```

to calculate the current reserve income.

## Formula

The idea is:

```text
normalizedIncome = linearInterest * lastLiquidityCumulativeIndex
```

In Solidity:

```solidity
uint256 cumulated = calculateLinearInterest(
    _reserve.currentLiquidityRate,
    _reserve.lastUpdateTimestamp
).rayMul(_reserve.lastLiquidityCumulativeIndex);
```

This means:

```text
1. Calculate how much interest accrued since the last update
2. Multiply that by the previous liquidity cumulative index
3. Return the current normalized income
```

## Example: Initial Index, One Year at 5%

Suppose the reserve starts with:

```text
lastLiquidityCumulativeIndex = 1.0
currentLiquidityRate = 5%
timePassed = 1 year
```

In ray precision:

```text
lastLiquidityCumulativeIndex = 1e27
currentLiquidityRate = 5e25
```

First, calculate linear interest:

```text
linearInterest = 1.05
```

Then apply it to the previous index:

```text
normalizedIncome = 1.05 * 1.0
normalizedIncome = 1.05
```

In ray precision:

```text
normalizedIncome = 1.05e27
```

This means the reserve index grew from `1.0` to `1.05`.

## Example: Previous Index Already Grew

Suppose the reserve already had a liquidity index of `1.10`.

```text
lastLiquidityCumulativeIndex = 1.10
currentLiquidityRate = 5%
timePassed = 1 year
```

First, calculate linear interest:

```text
linearInterest = 1.05
```

Then apply it to the previous index:

```text
normalizedIncome = 1.05 * 1.10
normalizedIncome = 1.155
```

In ray precision:

```text
normalizedIncome = 1.155e27
```

This means the reserve had already grown by 10%, and then it grew by another 5%.

# calculateCompoundedInterest

`calculateCompoundedInterest` calculates compounded interest from the last update timestamp until the current block timestamp.

```solidity
function calculateCompoundedInterest(
    uint256 _rate,
    uint40 _lastUpdateTimestamp
) internal view returns (uint256)
```

The function receives:

```text
_rate = annual interest rate, in ray
_lastUpdateTimestamp = timestamp of the last update
```

It returns the compounded interest factor in ray.

## Formula

The idea is:

```text
compoundedInterest = (1 + ratePerSecond) ^ timePassed
```

Where:

```text
ratePerSecond = annualRate / secondsPerYear
```

In Solidity:

```solidity
uint256 ratePerSecond = _rate / SECONDS_PER_YEAR;

return (ratePerSecond + WadRayMath.ray()).rayPow(timeDifference);
```

`WadRayMath.ray()` represents `1.0` in ray precision.

## Example: One Year at 5%

Suppose:

```text
rate = 5% = 5e25
timePassed = 1 year
```

The result is approximately:

```text
1.05127e27
```

This is slightly higher than linear interest because interest compounds over time.

Linear interest gives:

```text
1.05e27
```

Compounded interest gives approximately:

```text
1.05127e27
```

# getTotalBorrows

`getTotalBorrows` returns the total borrows of a reserve.

```solidity
function getTotalBorrows(
    CoreLibrary.ReserveData storage _reserve
) internal view returns (uint256)
```

## What It Does

It adds:

```text
totalBorrowsStable
totalBorrowsVariable
```

In Solidity:

```solidity
return _reserve.totalBorrowsStable + _reserve.totalBorrowsVariable;
```

## Example

```text
totalBorrowsStable = 100 DAI
totalBorrowsVariable = 50 DAI

totalBorrows = 150 DAI
```

This value is used when updating cumulative indexes.

If total borrows are zero, there is no borrow-generated income, so reserve indexes do not need to be updated.

# getCompoundedBorrowBalance

`getCompoundedBorrowBalance` calculates the current borrow balance of a user, including accrued interest.

```solidity
function getCompoundedBorrowBalance(
    CoreLibrary.UserReserveData storage _self,
    CoreLibrary.ReserveData storage _reserve
) internal view returns (uint256)
```

The function receives:

```text
_self = user reserve data
_reserve = reserve data
```

It returns the user's current borrow balance.

## No Borrow Case

If the user has no borrow balance, it returns zero:

```solidity
if (_self.principalBorrowBalance == 0) {
    return 0;
}
```

## Stable Borrow Path

If the user borrowed at a stable rate, the function uses the user's `stableBorrowRate`:

```solidity
if (_self.stableBorrowRate > 0) {
    cumulatedInterest = calculateCompoundedInterest(
        _self.stableBorrowRate,
        _self.lastUpdateTimestamp
    );
}
```

The idea is:

```text
currentDebt = principalDebt * compoundedStableInterest
```

Example:

```text
principalBorrowBalance = 100 DAI
stableBorrowRate = 5%
timePassed = 1 year

currentDebt ≈ 105.127 DAI
```

## Variable Borrow Path

If the user does not have a stable borrow rate, the function treats the position as variable debt.

In that case, it uses:

```text
reserve current variable borrow rate
reserve last variable borrow cumulative index
user last variable borrow cumulative index
```

The formula is:

```text
cumulatedInterest =
    compoundedVariableInterest
    * reserveLastVariableBorrowIndex
    / userLastVariableBorrowIndex
```

In Solidity:

```solidity
cumulatedInterest = calculateCompoundedInterest(
    _reserve.currentVariableBorrowRate,
    _reserve.lastUpdateTimestamp
)
.rayMul(_reserve.lastVariableBorrowCumulativeIndex)
.rayDiv(_self.lastVariableBorrowCumulativeIndex);
```

Then the current borrow balance is:

```text
currentDebt = principalDebt * cumulatedInterest
```

In Solidity:

```solidity
compoundedBalance =
    principalBorrowBalanceRay.rayMul(cumulatedInterest).rayToWad();
```

## Rounding Protection

The function contains a small rounding protection:

```solidity
if (compoundedBalance == _self.principalBorrowBalance) {
    if (_self.lastUpdateTimestamp != block.timestamp) {
        return _self.principalBorrowBalance + 1;
    }
}
```

This means:

```text
If time passed but rounding caused the debt to appear unchanged,
add 1 wei of debt.
```

The reason is to avoid interest-free loans caused by rounding.

