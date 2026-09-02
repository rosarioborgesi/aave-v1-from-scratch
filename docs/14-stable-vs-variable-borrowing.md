# Stable vs. Variable Borrowing in Aave V1

When a user borrows an asset in Aave V1, they choose how interest is calculated:

- **Stable rate:** the user receives a personal rate that normally stays the same.
- **Variable rate:** the user's debt follows the reserve's current variable rate.

Both types of debt grow over time. The difference is **which interest rate is applied to that growth**.

> In Aave V1, a user can have only one rate mode for the same borrowed asset at a time: stable or variable.

## The simple difference

| Rate mode | Does the rate change? | What the user gets |
|---|---|---|
| Variable | Yes, as pool conditions change | A debt that follows the reserve's variable rate |
| Stable | Usually no | A personal rate that makes costs more predictable |

The pool rates move when liquidity usage changes. For example, when a larger share of DAI in the pool is borrowed, borrowing DAI normally becomes more expensive.

## What changes the rates?
In Aave V1, both the reserve’s quoted variable and stable borrow rates are calculated by the reserve’s interest-rate strategy, mainly from utilization: how much liquidity is borrowed compared with the liquidity supplied. As utilization rises, the strategy raises borrowing rates to encourage repayments and new deposits; when utilization falls, rates decrease. 

The protocol recalculates these rates automatically whenever an action changes the reserve’s liquidity or debt, such as a deposit, redeem, borrow, or repayment. Governance does not choose each new rate manually: it decides the interest-rate strategy and its parameters, while the smart contracts apply that curve automatically. 

An existing variable borrower immediately follows the newly calculated variable rate. An existing stable borrower keeps their personal rate unless they borrow more—receiving a weighted-average rate—or their position is rebalanced under the protocol’s defined conditions.

## 1. Variable borrow: the rate follows the pool

Bob borrows **1,000 DAI** when the pool's variable rate is **4%**.

After six months, his debt has grown to approximately **1,020.20 DAI**.

| Period | Variable rate applied | Debt at the end |
|---|---:|---:|
| At borrow time | 4% | 1,000 DAI |
| First 6 months | 4% | ~1,020.20 DAI |

Now more people borrow from the pool. Utilization increases and the variable rate becomes **10%**.

For the next six months, Bob's debt grows using the new 10% rate:

| Period | Variable rate applied | Debt at the end |
|---|---:|---:|
| Next 6 months | 10% | ~1,071.23 DAI |

The new 10% rate applies only from the moment it changes onward. It does not recalculate the interest Bob already accrued at 4%.

### What Aave stores for a variable borrower

Aave does not give Bob a personal fixed rate. Instead, it uses the reserve's **variable-borrow index**:

1. The index grows over time using the current variable rate.
2. Bob's debt is calculated from his principal and his last saved index.
3. When Bob borrows again, repays, switches rate mode, or is rebalanced, Aave updates his stored debt and index checkpoint.

So Bob's debt always follows the pool's current variable conditions.

## 2. Stable borrow: the user receives a personal rate

Alice borrows **1,000 DAI** at a stable rate of **8%**.

After one year, with compounded interest, her debt is approximately **1,083.29 DAI**.

| Moment | Alice's stable rate | Debt |
|---|---:|---:|
| When borrowing | 8% | 1,000 DAI |
| After 1 year | 8% | ~1,083.29 DAI |

Suppose the pool's current stable rate later rises to **12%**. Alice still accrues at **8%** because 8% is her personal stored rate.

This makes stable borrowing easier to predict than variable borrowing.

## Stable does not mean permanently fixed

In Aave V1, stable borrowing is an approximation of fixed-rate borrowing for an open-ended loan. Aave can **rebalance** a stable position in specific situations.

For example, if Alice's 8% rate becomes too low compared with the return paid to depositors, Aave can:

1. Calculate all interest that Alice accrued so far at 8%.
2. Keep that accrued debt.
3. Set her stable rate to the current stable rate, for example 12%.
4. Apply 12% only to future interest.

Therefore, a stable rate is usually stable, but it is not guaranteed to remain unchanged forever.

## 3. Borrowing more at a stable rate

Alice's first 1,000 DAI borrow has grown to **1,083.29 DAI** at 8%. She now borrows another **500 DAI**, while the current stable rate is 12%.

First, Aave recognizes the interest already accrued. Her new debt principal becomes:

```text
1,083.29 DAI + 500 DAI = 1,583.29 DAI
```

Then Aave calculates one new weighted-average stable rate:

```text
(1,083.29 × 8% + 500 × 12%) / 1,583.29 ≈ 9.26%
```

| After borrowing the extra 500 DAI | Value |
|---|---:|
| New debt principal | ~1,583.29 DAI |
| New personal stable rate | ~9.26% |

Alice does not have two separate stable loans. She has one debt position with one updated personal stable rate.

## 4. Borrowing more at a variable rate

Bob's first variable borrow has grown to **1,020.20 DAI**. The current variable rate is now 10%, and he borrows another **500 DAI**.

First, Aave recognizes the interest already accrued:

```text
1,020.20 DAI + 500 DAI = 1,520.20 DAI
```

Then Aave saves the current variable-borrow index as Bob's new checkpoint.

Bob does **not** receive a weighted-average personal rate. From that point, his whole 1,520.20 DAI debt follows whatever the pool's variable rate is.

If the rate remains 10% for another six months, his debt becomes approximately **1,598.13 DAI**.

## How `getCompoundedBorrowBalance` calculates debt

`getCompoundedBorrowBalance` returns a borrower’s current debt, including interest accrued since the position was last updated. It handles stable- and variable-rate debt differently:

- **Stable-rate debt:** compounds the borrower’s stored principal using that borrower’s personal stable rate and the time since their last update.

  ```text
  debt = principal × compound(userStableRate, userLastUpdate)
  ```

  The borrower’s rate stays the same unless the position is rebalanced or otherwise changed.

- **Variable-rate debt:** scales the borrower’s stored principal by the growth of the reserve-wide variable-borrow index since the borrower’s last checkpoint. The index captures all variable-rate changes over time.

  ```text
  debt = principal × currentReserveIndex / userRecordedIndex
  ```

  If utilization changes and the variable rate changes, every variable borrower’s debt automatically reflects that shared rate history.

## Stable-borrowing Deprecation 
Stable borrowing was later deprecated in Aave V3.2. Stable debt had already been used very little, while supporting it required separate debt accounting, rate calculations, and rebalancing logic.

Variable-rate borrowing remains, with rates adapting automatically to reserve utilization.

## Key takeaway

- Choose **variable** when you accept that your borrowing cost can move with the pool.
- Choose **stable** when you want a more predictable borrowing cost.
- In both cases, interest accrues continuously and is recognized when Aave updates the position.
- Aave V1 stable borrowing is not a permanent fixed-rate loan: the protocol can rebalance the rate in defined cases.
