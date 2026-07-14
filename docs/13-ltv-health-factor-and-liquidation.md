# Loan-to-Value, Health Factor, and Liquidation

## Overview

Aave V1 uses two different collateral parameters:

- **Loan-to-Value (LTV)** determines how much a user is allowed to borrow.
- **Liquidation threshold** determines when the position becomes undercollateralized.

The **health factor** compares the collateral available at the liquidation threshold with the user's debt and fees.

These concepts are related, but they answer different questions:

| Metric | Question |
| --- | --- |
| LTV | How much can the user borrow? |
| Liquidation threshold | How much collateral value protects the debt from liquidation? |
| Health factor | How close is the complete position to liquidation? |

All balances are converted into their ETH-equivalent value by the price oracle before these calculations are performed.

## Collateral Requirements

A deposit contributes to the calculations only when:

- the reserve is enabled for use as collateral; and
- the user has enabled that deposit as collateral.

A deposit that does not satisfy both conditions is part of the user's liquidity, but it does not increase their borrowing power or health factor.

## Loan-to-Value

The LTV is the percentage of collateral value that can support borrowing.

$$
\text{Loan-to-Value}
=
\frac{\text{Debt}}{\text{Collateral}}
\times 100
$$

In other words LTV determines the maximum amount you can borrow against your collateral.

If a collateral has an LTV of `75%`, every `1 ETH` of collateral value supports up to `0.75 ETH` of debt.

For one collateral:

```text
Maximum debt plus fees = collateral value * LTV / 100
```

### Example: One Collateral

Suppose a user has:

- collateral value: `10 ETH`;
- LTV: `75%`;
- current debt: `6 ETH`;
- fees: `0 ETH`.

The maximum total debt allowed by the LTV is:

```text
10 ETH * 75% = 7.5 ETH
```

The user can therefore borrow approximately another:

```text
7.5 ETH - 6 ETH = 1.5 ETH
```

The exact amount is slightly lower when the origination fee for the new borrow is included.

## Weighted Average LTV

Every reserve can have a different LTV. When a user has several collateral assets, Aave V1 calculates an average weighted by the ETH value of each collateral.

```text
Weighted LTV = sum(collateral value * collateral LTV) / total collateral value
```

### Example: Two Collaterals

Suppose a user has:

| Collateral | ETH value | LTV |
| --- | ---: | ---: |
| Asset A | 5 ETH | 75% |
| Asset B | 5 ETH | 50% |

The weighted LTV is:

```text
(5 * 75 + 5 * 50) / 10 = 62.5%
```

The maximum total debt is:

```text
10 ETH * 62.5% = 6.25 ETH
```

Asset A provides more borrowing power because it has a higher LTV.

## Liquidation Threshold

The liquidation threshold is the percentage of collateral value that counts when deciding whether the position is undercollateralized.

It is normally higher than the LTV. The difference creates a safety margin between the maximum permitted borrow and liquidation.

For example, a collateral could have:

- LTV: `75%`;
- liquidation threshold: `80%`.

With `10 ETH` of collateral:

- borrowing capacity: `7.5 ETH`;
- collateral value at the liquidation threshold: `8 ETH`.

The first value limits new borrowing. The second value is used in the health factor.

## Weighted Liquidation Threshold

Like the LTV, the liquidation threshold is weighted by the ETH value of every collateral asset.

```text
Weighted liquidation threshold =
    sum(collateral value * liquidation threshold)
    / total collateral value
```

Using two collateral assets:

| Collateral | ETH value | Liquidation threshold |
| --- | ---: | ---: |
| Asset A | 5 ETH | 80% |
| Asset B | 5 ETH | 65% |

The weighted liquidation threshold is:

```text
(5 * 80 + 5 * 65) / 10 = 72.5%
```

## Health Factor

The definition of health factor is:

$$
\text{Health Factor}
=
\frac{
\text{Collateral} \times \text{Liquidation Threshold}
}{
\text{Debt}
}
$$

Aave V1 calculates the health factor as:

```text
Health factor =
    (total collateral in ETH * weighted liquidation threshold / 100)
    / (total debt in ETH + total fees in ETH)
```

The contract represents the result as a wad:

```text
1e18 = health factor of 1.0
```

An equivalent and often easier way to understand the numerator is:

```text
Adjusted collateral =
    sum(each collateral value * its liquidation threshold)

Health factor = adjusted collateral / (debt + fees)
```

The LTV does not appear in the health-factor formula. LTV limits new borrowing, while the liquidation threshold determines liquidation risk. A position can therefore have a health factor above `1` and still be unable to borrow more because it has already reached its LTV limit.

For example, if a user borrows the maximum `7.5 ETH` against `10 ETH` of collateral with a `75%` LTV and an `80%` liquidation threshold:

```text
Health factor = 8 ETH / 7.5 ETH = 1.0667
```

The position is not liquidatable, but it has no remaining borrowing capacity.

### Interpreting the Health Factor

| Health factor | Position state |
| ---: | --- |
| Greater than `1` | The position is not liquidatable. |
| Equal to `1` | The position is exactly at the boundary but is not yet liquidatable in Aave V1. |
| Less than `1` | The position is undercollateralized and can be liquidated. |

If the user has no borrowed principal, Aave V1 returns the maximum `uint256` value because there is no debt to liquidate.

## When Is a Position Liquidatable?

A position becomes liquidatable when:

```text
adjusted collateral < debt + fees
```

This is equivalent to:

```text
health factor < 1
```

The health factor can fall because:

- collateral prices decrease;
- the borrowed asset's price increases;
- borrow interest increases the debt;
- fees increase the denominator;
- collateral is removed, transferred, or disabled;
- the user borrows more.

The health factor can improve because:

- the user deposits and enables more collateral;
- collateral prices increase;
- the borrowed asset's price decreases;
- the user repays debt or fees.

In Aave V1, once the health factor falls below `1`, an external liquidator can repay part of the debt and receive collateral at a discount. The whitepaper specifies that a maximum of `50%` of the loan can be liquidated in one liquidation event.


## Base Example

Suppose a user has:

- collateral value: `10 ETH`;
- LTV: `75%`;
- liquidation threshold: `80%`;
- debt: `6 ETH`;
- fees: `0 ETH`.

Adjusted collateral:

```text
10 ETH * 80% = 8 ETH
```

Health factor:

```text
8 ETH / 6 ETH = 1.3333
```

The position is not liquidatable because its health factor is greater than `1`.

## Depositing More Collateral

Suppose the user deposits another `2 ETH` of value with the same `80%` liquidation threshold.

New collateral value:

```text
10 ETH + 2 ETH = 12 ETH
```

New adjusted collateral:

```text
12 ETH * 80% = 9.6 ETH
```

New health factor:

```text
9.6 ETH / 6 ETH = 1.6
```

Depositing enabled collateral improves the health factor because it increases the adjusted collateral while the debt remains unchanged.

It also increases borrowing capacity:

```text
12 ETH * 75% = 9 ETH maximum debt
```

## Withdrawing Collateral

Starting again from the base example, suppose the user withdraws `1 ETH` of collateral value.

Remaining collateral:

```text
10 ETH - 1 ETH = 9 ETH
```

Adjusted collateral:

```text
9 ETH * 80% = 7.2 ETH
```

New health factor:

```text
7.2 ETH / 6 ETH = 1.2
```

The withdrawal is allowed because the resulting health factor remains greater than `1`.

### Maximum Theoretical Withdrawal

The health factor reaches exactly `1` when adjusted collateral equals debt:

```text
remaining collateral * 80% = 6 ETH
remaining collateral = 7.5 ETH
```

Starting with `10 ETH`, this corresponds to withdrawing `2.5 ETH`.

However, Aave V1's `balanceDecreaseAllowed()` requires:

```solidity
healthFactorAfterDecrease > 1e18
```

Therefore, withdrawing exactly `2.5 ETH` is rejected. The user must withdraw slightly less so the resulting health factor remains strictly greater than `1`.

This check also protects aToken transfers and disabling a reserve as collateral, because those actions can reduce the collateral supporting the debt.

## Borrowing More

Starting from the base example, suppose the user borrows another `1 ETH` of value and we ignore the fee for simplicity.

New debt:

```text
6 ETH + 1 ETH = 7 ETH
```

New health factor:

```text
8 ETH / 7 ETH = 1.1429
```

Borrowing more lowers the health factor because it increases the denominator.

The borrow is still inside the LTV limit:

```text
7 ETH < 7.5 ETH maximum debt
```

## Repaying Debt

Starting from the base example, suppose the user repays `2 ETH`.

New debt:

```text
6 ETH - 2 ETH = 4 ETH
```

New health factor:

```text
8 ETH / 4 ETH = 2
```

Repayment improves the health factor because it reduces the denominator.

## Accrued Interest and Fees

Debt grows as borrow interest accrues. Origination fees are also included in the health-factor denominator.

Suppose the base position has:

- debt: `6 ETH`;
- fees: `0.2 ETH`;
- adjusted collateral: `8 ETH`.

The health factor becomes:

```text
8 ETH / (6 ETH + 0.2 ETH) = 1.2903
```

Even without withdrawing collateral or borrowing again, accrued interest can gradually move a position closer to liquidation.

## Collateral Price Decrease

Suppose the collateral from the base example falls in value from `10 ETH` to `7.4 ETH`, while the debt remains worth `6 ETH`.

Adjusted collateral:

```text
7.4 ETH * 80% = 5.92 ETH
```

Health factor:

```text
5.92 ETH / 6 ETH = 0.9867
```

The position is now liquidatable because its health factor is below `1`.

The exact price boundary in this example is a collateral value of `7.5 ETH`:

```text
7.5 ETH * 80% / 6 ETH = 1
```

At exactly `1`, the position is not yet liquidatable. Any further collateral-price decrease moves it below the threshold.

A rise in the price of the borrowed asset can produce the same result because it increases the ETH value of the debt.

## Multiple Collaterals

Suppose a user has:

| Collateral | ETH value | LTV | Liquidation threshold |
| --- | ---: | ---: | ---: |
| Asset A | 5 ETH | 75% | 80% |
| Asset B | 5 ETH | 50% | 65% |

The weighted LTV is:

```text
(5 * 75 + 5 * 50) / 10 = 62.5%
```

The weighted liquidation threshold is:

```text
(5 * 80 + 5 * 65) / 10 = 72.5%
```

Adjusted collateral:

```text
(5 ETH * 80%) + (5 ETH * 65%) = 7.25 ETH
```

If the user has `5 ETH` of debt and no fees:

```text
Health factor = 7.25 ETH / 5 ETH = 1.45
```

The maximum total debt allowed by the weighted LTV is:

```text
10 ETH * 62.5% = 6.25 ETH
```

## Depositing Collateral with a Lower Threshold

Suppose the user deposits another `5 ETH` of Asset B, whose liquidation threshold is only `65%`.

The weighted liquidation threshold decreases:

```text
(5 * 80 + 10 * 65) / 15 = 70%
```

However, the adjusted collateral still increases:

```text
(5 ETH * 80%) + (10 ETH * 65%) = 10.5 ETH
```

The new health factor is:

```text
10.5 ETH / 5 ETH = 2.1
```

The average liquidation threshold fell from `72.5%` to `70%`, but the health factor improved from `1.45` to `2.1` because the user added more collateral.

This demonstrates why the weighted percentage should never be interpreted without also considering the total collateral value.

## Withdrawing Different Collateral Assets

Return to the two-collateral position with `7.25 ETH` of adjusted collateral and `5 ETH` of debt.

Withdrawing `1 ETH` of Asset A removes:

```text
1 ETH * 80% = 0.8 ETH of adjusted collateral
```

The new health factor is:

```text
(7.25 - 0.8) / 5 = 1.29
```

Withdrawing `1 ETH` of Asset B removes:

```text
1 ETH * 65% = 0.65 ETH of adjusted collateral
```

The new health factor is:

```text
(7.25 - 0.65) / 5 = 1.32
```

Withdrawing the collateral with the higher liquidation threshold damages the health factor more, even when the two withdrawals have the same ETH value.


## Code Mapping

`LendingPoolDataProvider.calculateUserGlobalData()`:

1. Converts every user balance into ETH using the price oracle.
2. Includes only deposits enabled as collateral.
3. Calculates weighted LTV and weighted liquidation threshold.
4. Adds compounded debt and origination fees.
5. Calculates the health factor.

The health-factor calculation is:

```solidity
if (borrowBalanceETH == 0) return type(uint256).max;

return ((collateralBalanceETH * liquidationThreshold) / 100).wadDiv(
    borrowBalanceETH + totalFeesETH
);
```

The liquidation condition is:

```solidity
healthFactor < 1e18
```

The collateral-decrease condition is intentionally stricter:

```solidity
healthFactorAfterDecrease > 1e18
```

## Final Mental Model

Remember the flow in this order:

1. **LTV limits the debt the user is allowed to create.**
2. **The liquidation threshold determines the collateral protecting that debt.**
3. **The health factor compares protected collateral with debt and fees.**
4. **Below `1`, the position can be liquidated.**

## References

- Aave Protocol Whitepaper V1.0, sections 1.1 and 3.6
- Aave V1 `LendingPoolDataProvider`: https://github.com/aave/aave-protocol/blob/master/contracts/lendingpool/LendingPoolDataProvider.sol
- Aave V1 `LendingPoolLiquidationManager`: https://github.com/aave/aave-protocol/blob/master/contracts/lendingpool/LendingPoolLiquidationManager.sol
