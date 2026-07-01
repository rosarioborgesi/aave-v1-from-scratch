# Redeem

The `redeem` feature allows a depositor to exchange aTokens back for the underlying reserve asset.

For example:

```text
user burns 100 aDAI
user receives 100 DAI
```

Unlike `deposit()`, the user does not call `LendingPool.redeemUnderlying()` directly.

The redemption begins from the reserve's `AToken` contract.

The high-level flow is:

```text
User
  |
  | redeem aTokens
  v
AToken
  |
  | calls redeemUnderlying()
  v
LendingPool
  |
  | updates reserve state
  | transfers underlying asset
  v
LendingPoolCore
  |
  | sends underlying asset
  v
User
```

The aTokens represent the user's supplied liquidity.

When the user redeems:

```text
aToken balance decreases
underlying balance increases
reserve available liquidity decreases
```


# Full Redemption Example

Assume Alice has:

```text
aDAI balance = 100 aDAI
```

Alice redeems the full amount:

```text
100 DAI
```

After the aToken updates Alice's balance:

```text
aToken balance after redeem =
    100 - 100

aToken balance after redeem = 0
```

The aToken calls:

```solidity
lendingPool.redeemUnderlying(
    DAI,
    Alice,
    100 ether,
    0
);
```

The `LendingPool` calls:

```text
updateStateOnRedeem(
    DAI,
    Alice,
    100 DAI,
    true
)
```

The final argument is `true` because Alice has fully exited the reserve.

The core can then disable the reserve as collateral for Alice.

Finally:

```text
LendingPoolCore sends 100 DAI to Alice
```

Final balances:

```text
Alice aDAI = 0
Alice DAI increases by 100 DAI
LendingPoolCore DAI decreases by 100 DAI
```

# Redemption Order

```text
user starts redemption through AToken
        ↓
AToken updates the user's aToken balance
        ↓
AToken calls LendingPool.redeemUnderlying()
        ↓
LendingPool validates the request
        ↓
LendingPool checks available liquidity
        ↓
LendingPoolCore updates reserve and user state
        ↓
LendingPoolCore transfers the underlying asset
        ↓
LendingPool emits RedeemUnderlying
```

# Current Scope

For now, the redeem feature requires the following high-level components:

```text
AToken
LendingPool
LendingPoolCore
the reserve asset
```

The main responsibilities are:

```text
AToken
→ starts the redemption and updates the user's aToken balance

LendingPool
→ validates and coordinates the redemption

LendingPoolCore
→ updates reserve accounting and transfers the underlying asset

Reserve asset
→ is returned to the user
```

Once all redemption-related functions have been implemented, this document can be expanded with:

```text
all contracts involved
all required functions
permissions
libraries
reserve-state updates
aToken burn logic
collateral behavior
ERC20 and ETH transfer flows
integration tests
complete execution diagrams
```

# Implementation Order

So the correct implementation order should be:

1. Study and implement AToken.redeem()
2. Implement the internal AToken logic it needs
3. Implement LendingPool.redeemUnderlying()
4. Implement LendingPoolCore.updateStateOnRedeem()
5. Implement LendingPoolCore.transferToUser()
6. Add unit and integration tests
7. Expand the full redeem documentation