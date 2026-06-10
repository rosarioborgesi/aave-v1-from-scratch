# Aave V1 From Scratch

The goal of this project is to rebuild the core ideas of Aave V1 from scratch using Solidity and Foundry.

This is not a production-ready implementation. The goal is educational: to understand how a lending protocol works by implementing one feature at a time and writing tests for each step.

Aave V1 is based on a pool-based lending model. Users deposit assets into a shared pool, and other users can borrow from that pool by providing collateral.

In the original Aave V1 architecture, the main user-facing contract is the `LendingPool`. Users interact with it to deposit, redeem, borrow, repay, swap rates, liquidate positions, and use flash loans.

In this project, we will start with the simplest possible flow:

```text
User deposits ERC20 tokens
User receives aTokens
```

## First Milestone

The first milestone is to implement a simple deposit flow:

```text
DAI deposit -> receive aDAI
```

For now, we will ignore:

- borrowing
- repay
- collateral
- health factor
- liquidations
- flash loans
- interest accrual
- stable and variable rates

We will introduce these concepts later, one by one.

## Why Start With Deposit?

Deposit is the simplest action in the protocol.

When a user deposits an underlying asset into Aave, the protocol mints a corresponding amount of aTokens to the user.

Example:

```text
User deposits 100 DAI
User receives 100 aDAI
```

The aToken represents the user's position in the pool.

In the full Aave protocol, aTokens accrue interest over time. In our first version, we will keep the model simple and mint aTokens 1:1 with the deposited amount:

```math
aTokensMinted = underlyingDeposited
```
