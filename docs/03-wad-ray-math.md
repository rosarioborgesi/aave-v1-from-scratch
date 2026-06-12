# WadRayMath

`WadRayMath` is a Solidity library used by Aave to perform fixed-point arithmetic.

Solidity does not support floating-point numbers. This means values like `0.5`, `1.25`, or `3.1415` cannot be represented directly.

Instead, DeFi protocols represent decimal numbers as integers using fixed decimal precision.

Aave uses two fixed-point units:

```text
WAD = 1e18
RAY = 1e27
```

The original Aave V1 `WadRayMath` library provides multiplication, division, exponentiation, and conversion helpers for both wad and ray values.

## WAD

A `wad` is a fixed-point number with 18 decimals.

```solidity
uint256 internal constant WAD = 1e18;
```

Example:

```text
1.0  = 1e18
0.5  = 5e17
2.25 = 225e16
```

In Solidity, these values are stored as integers:

```text
1.0  -> 1000000000000000000
0.5  -> 500000000000000000
2.25 -> 2250000000000000000
```

WAD precision is commonly used for token amounts, percentages, ratios, and values that need 18 decimal places.

## RAY

A `ray` is a fixed-point number with 27 decimals.

```solidity
uint256 internal constant RAY = 1e27;
```

Example:

```text
1.0 = 1e27
```

In Solidity:

```text
1 ray = 1000000000000000000000000000
```

RAY precision is used when more precision is required, especially for interest rates and indexes.

Examples of ray-based values in Aave include:

* liquidity indexes
* variable borrow indexes
* normalized income
* interest rates

## WAD and RAY Ratio

The relationship between WAD and RAY is:

```text
RAY = WAD * 1e9
```

So the conversion ratio is:

```solidity
uint256 internal constant WAD_RAY_RATIO = 1e9;
```

This means:

```text
1e18 * 1e9 = 1e27
```

## Main Constants

The original library defines these main constants:

```solidity
uint256 internal constant WAD = 1e18;
uint256 internal constant halfWAD = WAD / 2;

uint256 internal constant RAY = 1e27;
uint256 internal constant halfRAY = RAY / 2;

uint256 internal constant WAD_RAY_RATIO = 1e9;
```

`halfWAD` and `halfRAY` are used to round multiplication and division results to the nearest integer.

## wadMul

`wadMul` multiplies two wad values.

Formula:

```text
(a * b + halfWAD) / WAD
```

Without fixed-point scaling, multiplying two values with 18 decimals would produce a result with 36 decimals. Dividing by `WAD` brings the result back to 18 decimals.

Example:

```text
1.5 * 2.0 = 3.0
```

Using wad values:

```text
1.5e18 * 2e18 / 1e18 = 3e18
```

The `halfWAD` term is added before division to round the result.

## wadDiv

`wadDiv` divides two wad values.

Formula:

```text
(a * WAD + b / 2) / b
```

Multiplying by `WAD` before division preserves 18-decimal precision.

Example:

```text
3.0 / 2.0 = 1.5
```

Using wad values:

```text
3e18 * 1e18 / 2e18 = 1.5e18
```

The `b / 2` term is added before division to round the result.

## rayMul

`rayMul` multiplies two ray values.

Formula:

```text
(a * b + halfRAY) / RAY
```

It works like `wadMul`, but uses 27-decimal precision.

Example:

```text
1.5e27 * 2e27 / 1e27 = 3e27
```

The result remains in ray precision.

## rayDiv

`rayDiv` divides two ray values.

Formula:

```text
(a * RAY + b / 2) / b
```

It works like `wadDiv`, but uses 27-decimal precision.

Example:

```text
3e27 * 1e27 / 2e27 = 1.5e27
```

The result remains in ray precision.

## rayPow

`rayPow` calculates the power of a ray value.

Formula:

```text
x^n
```

where:

```text
x = base in ray precision
n = exponent
```

The result is returned in ray precision.

This function is useful for compounded interest calculations.

For example, interest over time can be represented as:

```text
(1 + ratePerSecond) ^ timeDelta
```

Because rates and indexes are stored in ray precision, the exponentiation must preserve ray precision.

The implementation uses exponentiation by squaring:

```solidity
function rayPow(uint256 x, uint256 n) internal pure returns (uint256 z) {
    z = n % 2 != 0 ? x : RAY;

    for (n /= 2; n != 0; n /= 2) {
        x = rayMul(x, x);

        if (n % 2 != 0) {
            z = rayMul(z, x);
        }
    }
}
```

This is more efficient than multiplying `x` by itself `n` times.

Instead of doing `n` multiplications, the function repeatedly:

```text
1. squares the base
2. divides the exponent by 2
3. multiplies the result only when the current exponent is odd
```

`RAY` is used as the fixed-point representation of `1`.

```text
RAY = 1e27 = 1.0 in ray precision
```

So:

```text
x^0 = RAY
```

because any number raised to the power of zero equals one.

## wadToRay

`wadToRay` converts a wad value to a ray value.

Formula:

```text
wadAmount * WAD_RAY_RATIO
```

Since:

```text
WAD_RAY_RATIO = 1e9
```

the conversion is:

```text
1e18 * 1e9 = 1e27
```

Example:

```text
1 wad -> 1 ray
1e18  -> 1e27
```

## rayToWad

`rayToWad` converts a ray value to a wad value.

Formula:

```text
(rayAmount + WAD_RAY_RATIO / 2) / WAD_RAY_RATIO
```

The `WAD_RAY_RATIO / 2` term is added to round the result.

Example:

```text
1 ray -> 1 wad
1e27  -> 1e18
```

## Why Rounding Is Used

Integer division in Solidity always rounds down.

Example:

```text
5 / 2 = 2
```

But mathematically:

```text
5 / 2 = 2.5
```

To reduce precision loss, `WadRayMath` adds half of the denominator before division.

Example:

```text
Without rounding:
5 / 2 = 2

With rounding:
(5 + 1) / 2 = 3
```

This is why the library uses:

```solidity
halfWAD = WAD / 2;
halfRAY = RAY / 2;
```

This rounding method is often called round half up.

## Example Usage

The library is usually used with Solidity's `using for` syntax:

```solidity
using WadRayMath for uint256;
```

This allows calling the library functions directly on `uint256` values.

Example:

```solidity
uint256 result = amount.wadMul(rate);
```

Instead of writing:

```solidity
uint256 result = WadRayMath.wadMul(amount, rate);
```

## Simplified Modern Version

The original Aave V1 version uses `SafeMath`, because it was written for an older Solidity version.

In Solidity `0.8.x`, overflow and underflow checks are built into the language.

A simplified modern version can use direct arithmetic and custom errors:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

library WadRayMath {
    error WadRayMath__DivisionByZero();

    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = WAD / 2;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = RAY / 2;

    uint256 internal constant WAD_RAY_RATIO = 1e9;

    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        return (a * b + HALF_WAD) / WAD;
    }

    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            revert WadRayMath__DivisionByZero();
        }

        return (a * WAD + b / 2) / b;
    }

    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        return (a * b + HALF_RAY) / RAY;
    }

    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            revert WadRayMath__DivisionByZero();
        }

        return (a * RAY + b / 2) / b;
    }

    function rayPow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? x : RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = rayMul(x, x);

            if (n % 2 != 0) {
                z = rayMul(z, x);
            }
        }
    }

    function rayToWad(uint256 a) internal pure returns (uint256) {
        return (a + WAD_RAY_RATIO / 2) / WAD_RAY_RATIO;
    }

    function wadToRay(uint256 a) internal pure returns (uint256) {
        return a * WAD_RAY_RATIO;
    }
}
```

## Summary

`WadRayMath` provides fixed-point arithmetic for Aave.

It defines two precision units:

```text
WAD = 1e18
RAY = 1e27
```

It provides helpers for:

* multiplying wad values
* dividing wad values
* multiplying ray values
* dividing ray values
* exponentiating ray values
* converting wad values to ray values
* converting ray values to wad values

The library allows Solidity contracts to work with decimal-style values while still using integers.
