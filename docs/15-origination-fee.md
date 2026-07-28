# Origination Fee

## Overview

In Aave V1, the **origination fee** is a one-time protocol fee charged when a user borrows an asset.

It is different from borrow interest:

- **Borrow interest** accrues over time while the debt remains open.
- **Origination fee** is calculated from the newly borrowed amount and is charged when the borrow is opened or increased.

The borrower receives the full requested borrow amount. The fee is instead recorded as an additional liability that must be paid when the position is repaid.

## Example

Assume a user borrows `1,000 DAI` and the configured origination-fee rate is `0.1%`.

```text
Amount received by the user: 1,000 DAI
Origination fee owed:            1 DAI
```

The user receives `1,000 DAI`, while their position records:

```text
Principal borrow balance: 1,000 DAI
Origination fee:             1 DAI
```

The fee is not added to `principalBorrowBalance`; Aave V1 stores it separately.

## Fee Calculation

`LendingPool` asks `FeeProvider` to calculate the fee before validating and executing the borrow.

Conceptually:

```text
origination fee = borrowed amount * configured fee percentage
```

The percentage is a protocol configuration. Users cannot choose it.

In the V1 architecture, the protocol administrator/governance controls the configuration contracts, while `FeeProvider` exposes the fee calculation used by the lending pool.

## Borrow Flow

When a user calls `borrow`, the relevant flow is:

1. `LendingPool` requests the fee from `FeeProvider`.
2. `LendingPoolDataProvider` includes the new fee when checking whether the user has enough collateral.
3. `LendingPoolCore` records the new borrow and fee on the user's reserve position.
4. `LendingPoolCore` transfers the full requested underlying amount to the user.

At the user-accounting level, the fee is stored separately:

```solidity
user.principalBorrowBalance += _amountBorrowed + _balanceIncrease;
user.originationFee += _fee;
```

`_balanceIncrease` is the interest accrued on the user's previous debt since their last update. The fee does not become part of the principal and does not itself accrue borrow interest.

## Effect on Borrowing Capacity

The fee is included in the debt that must be covered by collateral. Therefore, it slightly reduces the amount a user can borrow.

For a new borrow, the collateral requirement is conceptually:

```text
required collateral =
    (existing debt + existing fees + new borrow + new fee)
    / current LTV
```

### Example

Suppose a user has:

- existing debt: `0.50 ETH`;
- existing fees: `0.05 ETH`;
- new borrow plus fee: `0.505 ETH`;
- current LTV: `75%`.

Their total debt exposure after the new borrow is:

```text
0.50 + 0.05 + 0.505 = 1.055 ETH
```

The collateral required is:

```text
1.055 / 0.75 = 1.4066 ETH
```

Without including the fee, the protocol would allow slightly more borrowing than the collateral actually covers.

## Effect on the Health Factor

Aave V1 includes origination fees in the health-factor denominator:

```text
Health factor =
    adjusted collateral
    / (total borrow balance + total origination fees)
```

Equivalently:

```text
Health factor =
    (total collateral in ETH * weighted liquidation threshold / 100)
    / (total debt in ETH + total fees in ETH)
```

As a result, an origination fee lowers the health factor slightly. If the health factor falls below `1`, the position becomes liquidatable.

## Repayment

To fully close a borrow position, the user repays:

```text
principal debt
+ accrued interest
+ outstanding origination fee
```

The origination fee is a protocol fee rather than interest paid to depositors. In the V1 flow, it is settled during repayment and sent to the configured protocol fee-collection address.

## Key Distinctions

| Item | Borrow interest | Origination fee |
| --- | --- | --- |
| When it is charged | Accrues over time | Calculated for each new borrow amount |
| Stored in | `principalBorrowBalance` after interest is materialized | `originationFee` |
| Changes with time | Yes | No, after it is recorded |
| Included in health factor debt | Yes | Yes |
| Paid on repayment | Yes | Yes |

## References

- Aave Protocol Whitepaper V1.0, section 3.4: Repay. A repayment covers the borrowed amount, accrued interest, and origination fee.
- Aave V1 `LendingPool`: https://github.com/aave/aave-protocol/blob/master/contracts/lendingpool/LendingPool.sol
- Aave V1 `LendingPoolCore`: https://github.com/aave/aave-protocol/blob/master/contracts/lendingpool/LendingPoolCore.sol
- Aave V1 `FeeProvider`: https://github.com/aave/aave-protocol/tree/master/contracts/fees
