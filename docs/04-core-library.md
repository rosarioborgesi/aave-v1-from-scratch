# CoreLibrary

`CoreLibrary` contains helper functions used to manage reserve data.

In Aave, a reserve represents one asset supported by the protocol, such as DAI, USDC, or WETH.

Each reserve stores information such as:

* current liquidity rate
* last update timestamp
* liquidity cumulative index

In this first version, we focus on two functions:

```solidity
calculateLinearInterest()
getNormalizedIncome()
```

These functions are used to calculate how much the reserve index has grown over time.

## ReserveData

A simplified `ReserveData` struct can look like this:

```solidity
struct ReserveData {
    uint256 currentLiquidityRate;
    uint40 lastUpdateTimestamp;
    uint256 lastLiquidityCumulativeIndex;
}
```

### currentLiquidityRate

`currentLiquidityRate` is the current deposit interest rate of the reserve.

It is expressed in ray precision:

```text
1 ray = 1e27
```

Example:

```text
5% annual rate = 0.05 ray = 5e25
```

### lastUpdateTimestamp

`lastUpdateTimestamp` is the last time the reserve data was updated.

It is used to calculate how much time has passed since the previous update.

### lastLiquidityCumulativeIndex

`lastLiquidityCumulativeIndex` is the previous liquidity index of the reserve.

It represents how much the reserve had already grown before the current calculation.

At the beginning, this value is usually initialized to:

```text
1e27
```

That means:

```text
1.0 in ray precision
```
Then it grows over time as the reserve earns interest.


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

It returns the linear interest accumulated during the elapsed time, also in ray.

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
return _rate.rayMul(timeDelta) + RAY;
```

or equivalently:

```solidity
return (_rate * timePassed) / SECONDS_PER_YEAR + RAY;
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
1. calculate how much interest accrued since the last update
2. multiply that by the previous liquidity cumulative index
3. return the current normalized income
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

