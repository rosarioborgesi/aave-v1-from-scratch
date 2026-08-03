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
// TODO complete