# Deposit

The first feature we will implement is `deposit`.

In Aave V1, deposit is the entry point for supplying liquidity to the protocol. A user sends an underlying asset, such as DAI, to the protocol and receives an interest-bearing aToken, such as aDAI, in return.

For this project, we will start with a simplified version of that idea. The first implementation will not include borrowing, interest accrual, liquidations, rate strategies, or reserve configuration. It will only focus on the core deposit flow.

## Goal

The goal of this step is to implement the following flow:

```text
User deposits DAI
User receives aDAI
```

In the first version, aTokens are minted 1:1 with the deposited amount:

```math
aTokenAmount = depositAmount
```

For example:

```text
User deposits 100 DAI
User receives 100 aDAI
```

## Original Aave V1 Idea

Aave V1 has a modular architecture. The original protocol separates responsibilities across several contracts, including:

- `LendingPool`
- `LendingPoolCore`
- `LendingPoolDataProvider`
- `LendingPoolConfigurator`
- `InterestRateStrategy`
- `AToken`

The `LendingPool` is the main user-facing contract. Users call it to deposit, redeem, borrow, repay, swap rates, liquidate positions, and use flash loans.

The `LendingPoolCore` stores reserve data and holds the deposited assets.

The `LendingPoolConfigurator` initializes and configures reserves.

The `AToken` represents the user's supplied liquidity.

## Simplified Design

To keep the first implementation small, we will use only three contracts:

```text
LendingPool
AToken
MockERC20
```

This means our first version will merge some responsibilities that Aave V1 keeps separate.

In the original protocol, `LendingPoolCore` holds the deposited assets. In our first version, the `LendingPool` itself will hold the deposited assets.

In the original protocol, reserve setup is handled by `LendingPoolConfigurator`. In our first version, we will initialize the relationship between an underlying asset and its aToken directly in the `LendingPool`.

## Contracts

### LendingPool

The `LendingPool` coordinates the deposit flow.

In this version, it will:

- store the relationship between an underlying asset and its aToken
- receive underlying tokens from users
- mint aTokens to users

The reserve-to-aToken relationship can be stored with a mapping:

```solidity
mapping(address reserve => address aToken) private s_reserveToAToken;
```

Example reserve pairs:

```text
DAI  -> aDAI
USDC -> aUSDC
WETH -> aWETH
```

### AToken

The `AToken` is an ERC20 token minted when a user deposits into the pool.

In the real Aave protocol, aTokens accrue interest over time. In this first version, we will ignore interest and mint aTokens 1:1 with the deposited amount.

### MockERC20

`MockERC20` is only used for testing.

It represents the underlying asset deposited into the pool. For example, we can deploy a mock DAI token and use it as the reserve asset in our tests.

## Deposit Flow

The first deposit flow looks like this:

```text
User
 |
 | approve LendingPool
 v
MockERC20
 |
 | deposit(reserve, amount)
 v
LendingPool
 |
 | transferFrom(user, LendingPool, amount)
 v
Underlying reserve stored in LendingPool
 |
 | mint aTokens
 v
User receives aTokens
```

The implementation should satisfy these balance changes:

```math
poolBalanceAfter = poolBalanceBefore + depositAmount
```

```math
userATokenBalanceAfter = userATokenBalanceBefore + depositAmount
```

## Implementation Strategy

We will implement the deposit feature in small steps:

1. Deploy a `MockERC20` token to represent the underlying asset.
2. Deploy an `AToken` to represent the user's deposit position.
3. Deploy the `LendingPool`.
4. Initialize the reserve by connecting the underlying asset to its aToken.
5. Mint mock underlying tokens to the user in the test.
6. Have the user approve the `LendingPool`.
7. Call `deposit(reserve, amount)`.
8. Assert that the `LendingPool` received the underlying tokens.
9. Assert that the user received the correct amount of aTokens.

This gives us a working base before introducing more complex Aave concepts such as interest accrual, collateral, borrowing, and liquidations.
