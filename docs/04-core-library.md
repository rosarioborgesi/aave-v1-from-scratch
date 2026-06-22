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

Deeper explanation of this field has been provided into [Aave index based accounting](./05-index-based-accounting.md).

`lastLiquidityCumulativeIndex` is the liquidity index of the reserve.

It tracks the cumulative interest earned by suppliers in a reserve.


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

So, instead of updating every depositor’s balance every second, Aave updates one global number for the reserve.

Then each user’s current balance can be derived from:

```text
userBalance = userPrincipal * currentIndex / userIndex
```

Suppose Alice deposited 100 DAI when the relevant index was `1.00`, and the current normalized income later becomes `1.05`.

Her balance is worth approximately:

```text
100 DAI * 1.05 / 1.00 = 105 DAI
```

The additional 5 DAI represents accrued interest.

So another way to describe it is:

lastLiquidityCumulativeIndex is the reserve-wide multiplier that records how much suppliers’ deposits have grown from accumulated interest.


### currentLiquidityRate

`currentLiquidityRate` is the current annual rate earned by liquidity providers.

It is expressed in ray precision.

Example:

```text
5% annual liquidity rate = 0.05 ray = 5e25
```

Suppose Alice supplies 1,000 DAI and the liquidity rate remains at 5% for one year.

Using linear interest, her position would grow approximately to:

```text
1,000 DAI * 1.05 = 1,050 DAI
```

The rate can change whenever the reserve state changes because it depends on factors such as available liquidity and total borrowed liquidity.

---

### totalBorrowsStable

`totalBorrowsStable` is the total principal borrowed from the reserve using stable interest rates.

It is expressed using the decimals of the underlying asset.

Suppose three users have stable DAI loans:

```text
Alice = 100 DAI
Bob = 250 DAI
Carol = 150 DAI
```

Then:

```text
totalBorrowsStable = 100 + 250 + 150
totalBorrowsStable = 500 DAI
```

Because DAI has 18 decimals, the stored value is:

```text
500e18
```

This value represents the aggregate stable debt of the reserve, not the debt of a single user.

---

### totalBorrowsVariable

`totalBorrowsVariable` is the total principal borrowed from the reserve using variable interest rates.

It is also expressed using the decimals of the underlying asset.

Suppose:

```text
Alice variable debt = 200 DAI
Bob variable debt = 300 DAI
```

Then:

```text
totalBorrowsVariable = 500 DAI
```

For an 18-decimal token, the stored value is:

```text
500e18
```

The total amount borrowed from the reserve is:

```text
totalBorrows = totalBorrowsStable + totalBorrowsVariable
```

For example:

```text
totalBorrowsStable = 500 DAI
totalBorrowsVariable = 500 DAI

totalBorrows = 1,000 DAI
```

---

### currentVariableBorrowRate

`currentVariableBorrowRate` is the current annual interest rate applied to variable-rate borrowers.

It is expressed in ray precision.

Example:

```text
8% annual variable borrow rate = 0.08 ray = 8e25
```

Suppose Alice has 1,000 DAI of variable debt and the variable rate remains at 8% for one year.

With compounded interest, her debt would become approximately:

```text
1,000 DAI * 1.0833 = 1,083.3 DAI
```

The exact result depends on the compounded-interest implementation and rounding.

The variable rate can change over time as reserve utilization changes.

---

### currentStableBorrowRate

`currentStableBorrowRate` is the current stable rate offered to users who open a new stable-rate borrow position.

It is expressed in ray precision.

Example:

```text
7% annual stable borrow rate = 0.07 ray = 7e25
```

Suppose Alice borrows 1,000 DAI when the current stable borrow rate is 7%.

Her stable borrow position records approximately:

```text
stableBorrowRate = 7%
```

If the reserve later offers a stable rate of 9%, Alice's existing position does not automatically become 9%. Her user-specific stable borrow rate remains the rate associated with her position unless the protocol updates or rebalances it.

---

### currentAverageStableBorrowRate

`currentAverageStableBorrowRate` is the weighted average rate of all stable-rate loans in the reserve.

It is expressed in ray precision.

It is weighted by the size of each stable borrow.

Suppose:

```text
Alice borrowed 100 DAI at 5%
Bob borrowed 300 DAI at 9%
```

The weighted average is:

```text
averageStableRate =
    (100 * 5% + 300 * 9%)
    / (100 + 300)
```

```text
averageStableRate =
    (5 + 27) / 400
    = 8%
```

In ray precision:

```text
currentAverageStableBorrowRate = 8e25
```

Bob's loan has a larger effect on the average because Bob borrowed more.

This rate is used when calculating reserve-level interest rates and stable debt accounting.

---

### lastVariableBorrowCumulativeIndex

`lastVariableBorrowCumulativeIndex` is the stored variable borrow index of the reserve.

It tracks the cumulative growth of variable-rate debt.

It is expressed in ray precision and starts at:

```text
1e27
```

That represents:

```text
1.0
```

Example:

```text
1.00 ray = no variable interest accumulated
1.08 ray = variable debt has grown by approximately 8%
1.15 ray = variable debt has grown by approximately 15%
```

Suppose Alice borrowed 1,000 DAI when her user variable borrow index was `1.00`.

Later, the reserve variable borrow index becomes `1.08`.

Her current debt is approximately:

```text
1,000 DAI * 1.08 / 1.00 = 1,080 DAI
```

If Alice instead entered when the index was `1.04`, and the current index is `1.08`, her debt is approximately:

```text
1,000 DAI * 1.08 / 1.04
≈ 1,038.46 DAI
```

Only the growth since Alice's borrow checkpoint is applied to her position.

---

### baseLTVasCollateral

`baseLTVasCollateral` defines the maximum amount that can normally be borrowed against the value of this collateral.

It is expressed as a percentage.

Example:

```text
baseLTVasCollateral = 75
```

Suppose Alice deposits collateral worth $1,000.

The maximum borrow value based on the LTV is:

```text
$1,000 * 75% = $750
```

Alice can therefore borrow up to approximately $750, subject to the other protocol checks.

Another example:

```text
Collateral value = $2,000
Base LTV = 60%

Maximum borrowing power = $1,200
```

The LTV is used to determine borrowing capacity. It is not the same as the liquidation threshold.

---

### liquidationThreshold

`liquidationThreshold` determines when a borrow position becomes undercollateralized and eligible for liquidation.

It is expressed as a percentage of the collateral value.

Example:

```text
liquidationThreshold = 80
```

Suppose Alice has collateral worth $1,000.

The liquidation-adjusted collateral value is:

```text
$1,000 * 80% = $800
```

If Alice's debt reaches or exceeds the relevant liquidation limit, her health factor can fall to `1` or below and the position can become liquidatable.

For example:

```text
Collateral value = $1,000
Liquidation threshold = 80%
Debt value = $700
```

The position is still above the liquidation boundary.

But if the collateral value falls to $850:

```text
$850 * 80% = $680
```

With debt still worth $700, the position is now under the liquidation threshold.

The liquidation threshold is normally higher than the base LTV:

```text
Base LTV = 75%
Liquidation threshold = 80%
```

This creates a safety margin between the maximum normal borrowing capacity and liquidation.

---

### liquidationBonus

`liquidationBonus` defines the extra collateral received by a liquidator as an incentive for repaying part of an unhealthy user's debt.

The exact stored representation depends on the percentage convention used by the protocol.

Conceptually, suppose the liquidation bonus is 5%.

A liquidator repays:

```text
100 DAI of debt
```

Without a bonus, the liquidator would receive collateral worth:

```text
$100
```

With a 5% liquidation bonus, the liquidator receives collateral worth:

```text
$100 * 1.05 = $105
```

The additional $5 is the liquidation incentive.

If your implementation stores the bonus as the complete multiplier, it may be represented as:

```text
105 = 105%
```

If it stores only the additional percentage, it may be represented as:

```text
5 = 5%
```

The functions using this field must follow the same convention consistently.

---

### decimals

`decimals` stores the number of decimal places used by the underlying reserve asset.

Examples:

```text
DAI = 18 decimals
USDC = 6 decimals
WBTC = 8 decimals
```

One DAI is represented as:

```text
1 DAI = 1e18
```

One USDC is represented as:

```text
1 USDC = 1e6
```

Suppose a user deposits 100 units.

For DAI, the raw amount is:

```text
100e18
```

For USDC, the raw amount is:

```text
100e6
```

The protocol needs this information when converting and comparing amounts from assets with different decimal precision.

---

### aTokenAddress

`aTokenAddress` is the address of the aToken associated with the reserve.

Example:

```text
DAI reserve -> aDAI
USDC reserve -> aUSDC
WETH reserve -> aWETH
```

Suppose Alice deposits:

```text
100 DAI
```

The protocol mints approximately:

```text
100 aDAI
```

The aToken represents Alice's deposit position and its accrued income.

---

### interestRateStrategyAddress

`interestRateStrategyAddress` is the address of the strategy contract responsible for calculating the reserve's interest rates.

The strategy calculates values such as:

```text
currentLiquidityRate
currentStableBorrowRate
currentVariableBorrowRate
```

For example, suppose a reserve has:

```text
Available liquidity = 200 DAI
Total borrows = 800 DAI
Total liquidity = 1,000 DAI
```

The utilization rate is approximately:

```text
800 / 1,000 = 80%
```

The strategy can use this utilization rate to produce higher borrowing rates because most of the reserve liquidity is being used.

A different reserve with only 20% utilization would generally receive lower borrowing rates.

The precise relationship depends on the implementation of the interest rate strategy.

---

### lastUpdateTimestamp

`lastUpdateTimestamp` stores the timestamp of the last reserve state update.

It is used to calculate the elapsed time for interest accumulation.

Example:

```text
lastUpdateTimestamp = 1,700,000,000
current block timestamp = 1,700,086,400
```

The elapsed time is:

```text
1,700,086,400 - 1,700,000,000
= 86,400 seconds
= 1 day
```

The protocol then uses this elapsed time when calculating linear or compounded interest.

For example:

```text
annual rate = 5%
elapsed time = 1 day
```

The approximate linear interest factor is:

```text
1 + 5% * (1 / 365)
≈ 1.000136986
```

The timestamp itself is not an economic amount, but it determines how much interest has accumulated.

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

`principalBorrowBalance` is the user's borrowed principal before adding newly accrued interest.

It represents the amount of debt stored in the protocol at the user's last update.

Example:

```text
Alice borrows 1,000 DAI
```

Immediately after the borrow:

```text
principalBorrowBalance = 1,000 DAI
```

If interest accrues and Alice's current debt later becomes 1,050 DAI, the stored principal may still be:

```text
principalBorrowBalance = 1,000 DAI
```

while the current compounded borrow balance is:

```text
1,050 DAI
```

The current debt is calculated from the principal plus the interest accumulated since the last user update.

Conceptually:

```text
currentBorrowBalance = principalBorrowBalance * accumulatedInterestFactor
```

When Alice performs another action, such as borrowing again or repaying, the protocol can update the stored principal to include the accrued interest.

For example:

```text
Previous principal = 1,000 DAI
Accrued interest = 50 DAI
New stored principal = 1,050 DAI
```

If the user has no borrow position:

```text
principalBorrowBalance = 0
```

---

### lastVariableBorrowCumulativeIndex

`lastVariableBorrowCumulativeIndex` is the reserve variable borrow index recorded for the user when their variable debt was last updated.

It acts as the user's checkpoint.

The reserve has a global variable borrow index that grows as variable interest accrues. The user stores the value of that index at the moment their position is created or updated.

The current variable debt can then be calculated using:

```text
currentDebt = principalBorrowBalance * currentReserveVariableBorrowIndex / userLastVariableBorrowIndex
```

Example:

```text
Alice principal debt = 1,000 DAI
Alice last variable borrow index = 1.00
Current reserve variable borrow index = 1.08
```

Then:

```text
currentDebt = 1,000 * 1.08 / 1.00
```

```text
currentDebt = 1,080 DAI
```

Alice accumulated 80 DAI of variable interest.

Suppose Bob borrowed later, when the reserve variable borrow index was already `1.04`:

```text
Bob principal debt = 1,000 DAI
Bob last variable borrow index = 1.04
Current reserve variable borrow index = 1.08
```

Then:

```text
currentDebt = 1,000 * 1.08 / 1.04
```

```text
currentDebt ≈ 1,038.46 DAI
```

Bob only pays interest for the growth that occurred after he borrowed.

This field prevents users from being charged interest that accumulated before their position existed.

---

### originationFee

`originationFee` is the borrowing fee charged when the user opens or increases a borrow position.

It is stored separately from the principal borrow balance.

Example:

```text
Alice borrows 1,000 DAI
Origination fee = 0.25%
```

The fee is:

```text
1,000 DAI * 0.25% = 2.5 DAI
```

The user's data could then contain:

```text
principalBorrowBalance = 1,000 DAI
originationFee = 2.5 DAI
```

The user's total obligation is therefore not only the borrowed principal and accrued interest, but also the outstanding origination fee.

Conceptually:

```text
totalAmountOwed = compoundedBorrowBalance + originationFee
```

For example:

```text
Compounded borrow balance = 1,050 DAI
Origination fee = 2.5 DAI
```

```text
Total obligation = 1,052.5 DAI
```

The exact fee percentage is defined by the protocol configuration.

---

### stableBorrowRate

`stableBorrowRate` is the annual rate associated with the user's stable borrow position.

It is expressed in ray precision.

Example:

```text
7% annual stable borrow rate = 0.07 ray = 7e25
```

Suppose Alice borrows:

```text
1,000 DAI at a stable rate of 7%
```

Her user data stores:

```text
principalBorrowBalance = 1,000 DAI
stableBorrowRate = 7e25
```

After one year, her debt is calculated using compounded interest:

```text
currentDebt ≈ 1,000 DAI * 1.0725
```

```text
currentDebt ≈ 1,072.5 DAI
```

The exact result depends on the compounding formula and rounding.

The stable borrow rate is user-specific. Two users can have different stable rates for the same reserve.

Example:

```text
Alice borrowed earlier at 5%
Bob borrowed later at 8%
```

Their positions may contain:

```text
Alice stableBorrowRate = 5e25
Bob stableBorrowRate = 8e25
```

Even though they borrowed the same asset, their debt grows using different rates.

In this implementation:

```text
stableBorrowRate > 0
```

means the user has a stable-rate position.

If:

```text
stableBorrowRate = 0
```

the borrow balance is treated as variable-rate debt, and the protocol uses the reserve and user variable borrow indexes instead.

---

### lastUpdateTimestamp

`lastUpdateTimestamp` records the last time the user's reserve data was updated.

It is used to determine how much time has passed when calculating stable compounded interest.

---

### useAsCollateral

`useAsCollateral` defines whether the user's deposit in this reserve is enabled as collateral.

For example, after a user's first deposit:

```text
useAsCollateral = true
```

This means the deposited asset can contribute to the user's borrowing power.


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

For a deeper explanation of how current user debt is calculated, see [Compounded Borrow Balance](./06-compounded-borrow-balance.md).

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
cumulatedInterest = compoundedVariableInterest * reserveLastVariableBorrowIndex / userLastVariableBorrowIndex
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
compoundedBalance = principalBorrowBalanceRay.rayMul(cumulatedInterest).rayToWad();
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

