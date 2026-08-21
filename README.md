# Aave V1 From Scratch

An educational, from-scratch rebuild of the core mechanics of the historical
[Aave V1](https://github.com/aave/aave-protocol) lending protocol. The aim is
to make a pool-based DeFi lending system understandable: each important
contract, formula, and user action is implemented in Solidity and explained in
the accompanying documentation.

> **Warning**
> This is a learning project, not a production protocol. It has not been
> audited and must never be used with real funds.

## What Aave Does

Aave is a decentralised lending protocol. Users supply crypto assets to shared
liquidity pools and receive interest-bearing **aTokens** in return. Other users
can borrow from those pools after depositing sufficient collateral.

Interest paid by borrowers contributes to supplier yield. The protocol protects
the pools by limiting borrowing according to collateral value, loan-to-value
(LTV) ratios, liquidation thresholds, and a user's health factor. If a position
becomes undercollateralised, a third party can repay part of its debt and
receive collateral through liquidation.

This repository focuses on the Aave V1 design: pooled reserves, aTokens,
interest indexes, stable and variable borrowing, reserve-rate updates,
liquidations, and atomic flash loans.

## What This Project Is About

Rather than presenting a lending protocol as a monolithic codebase, this
project builds it as a sequence of small, testable pieces. The docs trace how
an action travels through the user-facing `LendingPool`, reserve accounting in
`LendingPoolCore`, tokenisation, pricing, and risk checks.

By working through the code and tests, you can learn:

- how deposits are represented by aTokens and accrue interest efficiently;
- how liquidity and borrow indexes avoid updating every account continuously;
- how stable and variable debt are calculated and repriced;
- how collateral, LTV, health factor, and liquidation work together;
- how repayments, redemptions, origination fees, and rate-mode swaps change a
  reserve; and
- how a flash loan is borrowed and repaid atomically in a single transaction.

The tests are deliberately part of the teaching material: unit tests isolate
the arithmetic and accounting, while integration tests exercise complete user
flows across contracts.

## How It Differs From the Original Aave V1

This is a rewrite inspired by Aave V1, not a line-by-line copy and not a
drop-in-compatible replacement. It preserves the learning-critical economic
and accounting ideas while modernising or omitting historical complexity.

| Area | Original Aave V1 | This project |
| --- | --- | --- |
| Deployment | Upgradeable contracts initialised through proxies | Direct constructor-based deployment to make relationships easier to follow |
| Solidity and tooling | Older Solidity-era toolchain | Solidity `0.8.30` and Foundry |
| Arithmetic | `SafeMath` for overflow protection | Solidity 0.8 native checked arithmetic |
| Errors | Predominantly `require` with revert strings | Explicit checks with custom errors where appropriate |
| Dependencies | Historical OpenZeppelin APIs | Modern OpenZeppelin Contracts APIs |
| aToken interest redirection | Supported redirecting accrued interest to another address | Omitted to keep aToken accounting focused and approachable |

Stable-rate borrowing remains included because it is useful for studying debt
accounting and borrow-rate swaps. Consequently, names, interfaces, deployment
behaviour, and internal implementation details may differ from the original
repository; this codebase and its tests are the source of truth here.

It also does not try to reproduce the architecture or full feature set of
current Aave deployments. Production concerns such as governance operations,
complete deployment infrastructure, exhaustive asset support, formal
verification, and a security audit are outside this project's scope.

## Documentation

The documentation is organised as a learning path. It starts with the protocol
architecture and fixed-point math, builds through reserve and interest
accounting, and then applies those foundations to user flows such as deposits,
borrowing, repayments, liquidations, rate swaps, and flash loans. Each page
connects the underlying concept to the relevant contracts and tests.

The full documentation can be found in the [docs](docs/) folder.

## Project Setup

For installation, dependency setup, and the first build and test commands, see
[Project Setup](docs/01-project-setup.md).

## Connect With Me

<p align="left">
  <a href="https://x.com/rosarioborgesi">
    <img src="https://img.shields.io/badge/twitter-000000?style=for-the-badge&logo=x&logoColor=white"/>
  </a>
  <a href="https://www.linkedin.com/in/rosarioborgesi/">
    <img src="https://img.shields.io/badge/LinkedIn-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white"/>
  </a>
  <a href="mailto:borgesiros@gmail.com">
    <img src="https://img.shields.io/badge/Email-D14836?style=for-the-badge&logo=gmail&logoColor=white"/>
  </a>
  <a href="https://www.youtube.com/@rosarioborgesi">
    <img src="https://img.shields.io/badge/YouTube-FF0000?style=for-the-badge&logo=youtube&logoColor=white"/>
  </a>
  <a href="https://farcaster.xyz/rosarioborgesi">
    <img src="https://img.shields.io/badge/Farcaster-855DCD?style=for-the-badge"/>
  </a>
  <a href="https://medium.com/@rosarioborgesi/">
    <img src="https://img.shields.io/badge/Medium-000000?style=for-the-badge&logo=medium&logoColor=white"/>
  </a>
</p>
