# Aave V1 From Scratch

This project is an educational rebuild of the core ideas behind Aave V1. Its
purpose is to make the internal mechanics of a lending protocol easier to
understand by implementing them one component and one user flow at a time.

It is not a line-by-line copy of the original contracts. The original Aave V1
code is used as a reference, while this repository rewrites and documents the
important concepts with modern Solidity, Foundry, and extensive tests.

> **Warning:** This is a learning project, not a production-ready lending
> protocol. It has not been audited and must not be used with real funds.

## What This Project Is Trying to Teach

A lending protocol can look like a large collection of contracts, formulas,
indexes, and token transfers. The goal of this repository is to show how those
pieces work together by answering questions such as:

- Where do deposited assets go?
- Why does a depositor receive aTokens?
- How does an aToken balance earn interest without updating every account?
- How are stable and variable borrow balances calculated over time?
- How do LTV, liquidation thresholds, and health factors limit borrowing?
- What happens to the reserve when a user deposits, borrows, repays, or
  redeems?
- How does liquidation reduce an unhealthy position?
- How can a flash loan be issued and repaid within one transaction?

## How the Repository Approaches Learning

The project is built in layers. It begins with fixed-point arithmetic and
reserve data structures, then introduces index-based interest accounting,
aTokens, account valuation, and complete lending operations.

There are two complementary kinds of tests:

- **Unit tests** isolate formulas and individual state transitions so that each
  function can be understood independently.
- **Integration tests** execute complete flows across several contracts and
  verify the resulting balances, debt, fees, indexes, rates, and events.

The documentation follows the same approach. Concept pages explain the
mathematics and data model, while flow pages trace operations such as deposit,
borrow, repay, liquidation, and flash loan from beginning to end.

## Differences From the Original Aave V1

The intention is to preserve the important Aave V1 mechanics while removing
historical complexity that is not necessary for learning. The main differences
are listed below.

| Area | Original Aave V1 | This project | Reason |
| --- | --- | --- | --- |
| Deployment | Upgradeable contracts initialized through a proxy | Contracts use constructors and are deployed directly | Direct deployment makes initialization and contract relationships easier to follow |
| Solidity | An older Solidity version | Solidity `0.8.30` | Uses current language features and compiler checks |
| Development tools | The original repository used the tooling of its time | Foundry is used for building and testing | Provides a fast, Solidity-native test workflow |
| Arithmetic safety | `SafeMath` was required | Native checked arithmetic is used | Solidity 0.8 reverts on integer overflow and underflow by default |
| Revert handling | Mostly `require` statements and revert strings | `if` statements with custom errors | Makes failure cases explicit and reduces revert-data gas costs |
| OpenZeppelin | OpenZeppelin Contracts `2.3.0` | OpenZeppelin Contracts `5.6.1` | Adapts the implementation to modern library APIs and security utilities |
| aToken interest redirection | A deposit's accrued interest could be redirected to another address | Interest redirection is omitted | It adds substantial accounting complexity and was later removed from Aave |
| Stable-rate borrowing | Present in Aave V1 | Retained | It is needed to study stable debt accounting and the borrow-rate swap flow |

## Suggested Reading

The original Aave V1 source remains a valuable companion reference:
[aave/aave-protocol](https://github.com/aave/aave-protocol).
