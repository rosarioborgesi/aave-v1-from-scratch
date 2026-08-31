# AToken

`AToken` is the interest-bearing ERC20 token used by Aave V1 to represent a user's deposit in a reserve.


# Main Responsibilities

The current implementation of `AToken` has eight main responsibilities:

```text
1. Mint aTokens when a user deposits.
2. Track each user's reserve-income checkpoint.
3. Calculate the user's current interest-bearing balance.
4. Materialize accrued interest during state-changing actions.
5. Redeem aTokens for the underlying reserve asset.
6. Prevent balance reductions that would make a borrowing position unsafe.
7. Clear user accounting data after a full redemption when possible.
8. Move or burn aTokens when collateral is liquidated.
```

## Underlying Asset

Each aToken represents one underlying reserve asset.

Examples:

```text
aDAI represents DAI
aUSDC represents USDC
```

The underlying asset itself is held by `LendingPoolCore`, not by `AToken`.

This implementation intentionally omits Aave V1's interest-redirection feature. Each account receives interest only on its own aToken balance.


# Stored State

## `i_underlyingAssetAddress`

```solidity
address private immutable i_underlyingAssetAddress;
```

Stores the underlying asset represented by the aToken.

For example:

```text
aDAI -> DAI address
```

The address is used when requesting the reserve normalized income from `LendingPoolCore`.

## `i_underlyingAssetDecimals`

```solidity
uint8 private immutable i_underlyingAssetDecimals;
```

Stores the decimals of the underlying asset.

The aToken overrides `decimals()` so that it uses the same decimal precision as the represented asset.

## `s_userIndexes`

```solidity
mapping(address user => uint256 lastNormalizedIncome)
    private s_userIndexes;
```

Stores the reserve normalized income last applied to each user.

The user index acts as a checkpoint.

For example:

```text
user index = 1.02 ray
current normalized income = 1.08 ray
```

Only the growth between `1.02` and `1.08` still needs to be applied to that user.

# Minting on Deposit

## `mintOnDeposit`

```solidity
function mintOnDeposit(
    address _account,
    uint256 _amount
) external onlyLendingPool
```

This function mints aTokens after a user deposits the underlying asset.

Only `LendingPool` can call it.

Before minting the new deposit, the function:

```text
materializes any interest already accrued
mints the new deposit amount
emits MintOnDeposit
```

## 1. Accumulate Existing Interest

```solidity
(
    ,
    ,
    uint256 balanceIncrease,
    uint256 index
) = _cumulateBalance(_account);
```

Before minting the new deposit, the function first converts the user's already accrued interest into stored aToken principal.

This prevents the new deposit from receiving interest for the period before it entered the protocol.

For example:

```text
stored principal = 100 aDAI
user index = 1.00 ray
current normalized income = 1.05 ray
```

The current balance is:

```text
current balance =
    100 × 1.05 / 1.00

current balance = 105 aDAI
```

Therefore:

```text
balance increase =
    105 - 100

balance increase = 5 aDAI
```

`_cumulateBalance()` mints the `5 aDAI` and updates the user's index to `1.05 ray`.

After cumulation:

```text
stored principal = 105 aDAI
user index = 1.05 ray
```

## 2. Mint the Deposit Amount

```solidity
_mint(_account, _amount);
```

The user receives one aToken unit for each unit deposited.

Example:

```text
deposit 20 DAI
mint 20 aDAI
```

The new deposit is minted only after the old interest has been accumulated and the user index has been updated.

## 3. Emit `MintOnDeposit`

```solidity
emit MintOnDeposit(
    _account,
    _amount,
    balanceIncrease,
    index
);
```

The event records:

```text
the user receiving the aTokens
the deposited amount
the interest materialized before the deposit
the user's new index
```

# Deposit Example

Assume Alice has:

```text
stored principal = 100 aDAI
user index = 1.00 ray
current normalized income = 1.05 ray
```

She deposits another:

```text
20 DAI
```

`LendingPool` calls:

```solidity
aToken.mintOnDeposit(
    Alice,
    20 ether
);
```

## Step 1: Materialize Existing Interest

Before the new deposit is minted, `_cumulateBalance(Alice)` calculates Alice's current balance:

```text
current balance =
    100 × 1.05 / 1.00

current balance = 105 aDAI
```

The accrued interest is:

```text
balance increase =
    105 - 100

balance increase = 5 aDAI
```

`_cumulateBalance()` then:

```text
mints 5 aDAI to Alice
updates Alice's index to 1.05 ray
```

Alice's stored principal becomes:

```text
100 + 5 = 105 aDAI
```

## Step 2: Mint the New Deposit

The function mints:

```text
20 aDAI
```

to Alice.

Alice's stored principal becomes:

```text
105 + 20 = 125 aDAI
```

## Step 3: Emit the Event

The event contains:

```text
_from = Alice
_value = 20 aDAI
_fromBalanceIncrease = 5 aDAI
_fromIndex = 1.05 ray
```

## Final State

```text
Alice stored principal = 125 aDAI
Alice user index = 1.05 ray
```

The sequence is:

```text
materialize 5 aDAI of existing interest
        ↓
update Alice's index to 1.05 ray
        ↓
mint 20 aDAI for the new deposit
```

The new `20 aDAI` does not receive interest for the period before Alice deposited it.

# Redeeming the Underlying Asset

## `redeem`

```solidity
function redeem(uint256 _amount) external
```

`redeem()` is the user-facing entry point for exchanging aTokens for the
underlying reserve asset.

For example:

```text
burn 40 aDAI
receive 40 DAI
```

The aToken does not hold the DAI itself. The complete call path is:

```text
user
  -> AToken.redeem()
  -> LendingPool.redeemUnderlying()
  -> LendingPoolCore transfers the underlying asset
  -> user receives the asset
```

The function performs the following sequence:

```text
validate the requested amount
materialize accrued interest
resolve the amount to redeem
check collateral safety
burn the aTokens
clear zero-balance data when needed
ask LendingPool to return the underlying asset
emit Redeem
```

## 1. Validate the Requested Amount

```solidity
if (_amount == 0) {
    revert AToken__AmountIsZero();
}
```

A redemption request must be greater than zero.

## 2. Materialize Accrued Interest

```solidity
(
    ,
    uint256 currentBalance,
    uint256 balanceIncrease,
    uint256 index
) = _cumulateBalance(msg.sender);
```

Before deciding how many aTokens to burn, the function converts the user's
accrued interest into stored principal.

Assume Alice has:

```text
stored principal = 100 aDAI
accrued interest = 5 aDAI
```

After `_cumulateBalance()`:

```text
current balance = 105 aDAI
balance increase = 5 aDAI
stored principal = 105 aDAI
```

The redemption can therefore include interest that accrued since Alice's last
state-changing interaction.

## 3. Resolve the Redemption Amount

```solidity
uint256 amountToRedeem = _amount;

if (_amount == MAX_UINT) {
    amountToRedeem = currentBalance;
}
```

An explicit amount redeems that number of aTokens. Passing
`type(uint256).max` means "redeem the entire current balance," including
accrued interest.

The resolved amount cannot exceed the current balance:

```solidity
if (amountToRedeem > currentBalance) {
    revert AToken__AmountToRedeemGreaterThanCurrentBalance();
}
```

## 4. Check Whether the Balance Can Be Reduced

```solidity
if (!isTransferAllowed(
    msg.sender,
    amountToRedeem
)) {
    revert AToken__TransferNotAllowed();
}
```

An aToken balance may be serving as collateral for a borrow. Before burning
the tokens, `redeem()` asks the data provider whether removing the requested
amount would leave the user's position above the liquidation threshold.

If the check returns `false`, the entire transaction reverts. The interest
minted by `_cumulateBalance()` is also rolled back because all steps occur in
one atomic transaction.

## 5. Burn the aTokens

```solidity
_burn(msg.sender, amountToRedeem);
```

The redeemed aTokens are destroyed before the pool transfers the underlying
asset.

The remaining balance is:

```text
balance after redeem =
    current balance - amount redeemed
```

## 6. Reset Empty User Data

```solidity
bool userIndexReset = false;

if (currentBalance - amountToRedeem == 0) {
    userIndexReset =
        _resetDataOnZeroBalance(msg.sender);
}
```

The cleanup runs only when the user redeems their complete current balance.
Its behavior is described in detail in the
[`_resetDataOnZeroBalance`](#_resetdataonzerobalance) section.

## 7. Request the Underlying Asset

```solidity
i_pool.redeemUnderlying(
    i_underlyingAssetAddress,
    payable(msg.sender),
    amountToRedeem,
    currentBalance - amountToRedeem
);
```

`AToken` cannot transfer the underlying asset because the reserve funds are
held by `LendingPoolCore`. It delegates that part of the operation to
`LendingPool`.

The remaining balance is passed to the pool so reserve user data can be updated
correctly for partial and full redemptions.

If the pool cannot complete the redemption, for example because the reserve
does not have enough available liquidity, the call reverts and the earlier
burn and accounting changes are rolled back.

## 8. Emit `Redeem`

```solidity
emit Redeem(
    msg.sender,
    amountToRedeem,
    balanceIncrease,
    userIndexReset ? 0 : index
);
```

The event records:

```text
the user redeeming the aTokens
the resolved redemption amount
the interest materialized before redemption
the user's remaining index, or zero if it was reset
```

## Complete Redemption Example

Assume Alice has:

```text
stored principal = 100 aDAI
current balance = 105 aDAI
no outstanding borrow
```

Alice calls:

```solidity
aDAI.redeem(type(uint256).max);
```

The operation:

```text
materializes 5 aDAI of accrued interest
resolves amountToRedeem to 105 aDAI
confirms the balance decrease is allowed
burns 105 aDAI
clears Alice's user index
transfers 105 DAI from LendingPoolCore to Alice
emits Redeem with an index of 0
```

Final state:

```text
Alice aDAI balance = 0
Alice user index = 0
Alice receives = 105 DAI
```

# Liquidating Collateral

During a liquidation, the borrower can repay debt using collateral from their
reserve position. The liquidator chooses whether to receive the collateral as
aTokens or as the underlying asset. `LendingPool` is the only contract allowed
to invoke either liquidation entry point.

## `transferOnLiquidation`

```solidity
function transferOnLiquidation(
    address _from,
    address _to,
    uint256 _value
) external onlyLendingPool
```

This is used when the liquidator elects to receive aTokens. It transfers
`_value` aTokens from the liquidated borrower (`_from`) to the liquidator
(`_to`):

```text
borrower collateral: 100 aDAI
liquidated amount:    40 aDAI

after transfer:
borrower:              60 aDAI
liquidator:            40 aDAI
```

The function delegates to `_executeTransfer()`, which first materializes
interest for both accounts and then performs the ERC-20 transfer. It does not
call `isTransferAllowed()`: liquidation has already been authorized and sized
by the lending-pool liquidation flow, so the ordinary user-transfer collateral
check must not prevent it.

## `burnOnLiquidation`

```solidity
function burnOnLiquidation(
    address _account,
    uint256 _value
) external onlyLendingPool
```

This is used when the liquidator elects to receive the underlying asset rather
than aTokens. `LendingPool` transfers the underlying asset to the liquidator;
this function removes the matching aTokens from the liquidated user's balance.

It first calls `_cumulateBalance(_account)` so interest accrued up to the
liquidation is included in the user's stored balance. It then burns `_value`
aTokens. If that leaves no aTokens, it resets the user's normalized-income
index to zero. Finally, it emits `BurnOnLiquidation` with the interest
materialized and the applicable user index.

```text
borrower collateral: 100 aDAI
liquidated amount:    40 aDAI
underlying paid out:   40 DAI

after burn:
borrower:              60 aDAI
```

## `_executeTransfer`

```solidity
function _executeTransfer(
    address _from,
    address _to,
    uint256 _value
) internal
```

This shared internal routine implements the accounting for both normal aToken
transfers and `transferOnLiquidation()`. The public ERC-20 update hook performs
the collateral-safety check for normal transfers before reaching this function.

`_executeTransfer()` performs these steps:

```text
1. Reject a zero-value transfer.
2. Materialize the sender's accrued interest and record its new index.
3. Materialize the recipient's accrued interest and record its new index.
4. Perform the ERC-20 transfer with super._update().
5. Reset the sender's index if its balance is now zero.
6. Emit BalanceTransfer with the transferred amount, both interest increases,
   and both indexes.
```

Materializing each balance before the transfer is essential: interest earned
before the transfer remains with the account that held the aTokens during that
period, while the transferred aTokens begin accruing future interest for the
recipient from the current normalized-income index.

## `_update`

The ERC20 `_update()` hook preserves ordinary parent behavior for mints and
burns. For a transfer between two nonzero addresses, it first calls
`isTransferAllowed(_from, _value)` and then delegates to `_executeTransfer()`.
Therefore both `transfer()` and `transferFrom()` enforce the same collateral
safety check as redemption.

# Validating a Balance Decrease

## `isTransferAllowed`

```solidity
function isTransferAllowed(
    address _user,
    uint256 _amount
) public view returns (bool)
```

This function delegates the collateral-safety decision to
`LendingPoolDataProvider`:

```solidity
return i_dataProvider.balanceDecreaseAllowed(
    i_underlyingAssetAddress,
    _user,
    _amount
);
```

The data provider returns `true` immediately when:

```text
the reserve cannot be used as collateral
the user has not enabled the reserve as collateral
the user has no outstanding borrow
```

Otherwise, it simulates the user's collateral and health factor after the
decrease. The operation is allowed only when the resulting health factor is
greater than `1e18`, or `1.0`.

Despite its transfer-oriented name, this function is used by `redeem()`,
`transfer()`, and `transferFrom()`. Liquidation transfers bypass it because
the lending-pool liquidation flow has already authorized and sized the balance
decrease.

# Resetting Data After a Full Redemption

## `_resetDataOnZeroBalance`

```solidity
function _resetDataOnZeroBalance(
    address _user
) internal returns (bool)
```

This function clears the user's normalized-income checkpoint after their
balance has been fully burned:

```solidity
s_userIndexes[_user] = 0;
return true;
```

The boolean return value lets `redeem()` and `burnOnLiquidation()` emit an
index of zero after a full balance decrease.


# Reading the User Balance

## `balanceOf`

```solidity
function balanceOf(address _user)
    public
    view
    override
    returns (uint256)
```

`super.balanceOf(_user)` returns the stored ERC20 principal, without interest
accrued since the user's latest checkpoint. The override returns zero when that
stored balance is zero; otherwise it calculates the current balance from the
stored principal, the reserve normalized income, and the user's index:

```text
current balance =
    stored principal × current normalized income ÷ user index
```

For example, a user with `100 aDAI`, a user index of `1.00 ray`, and current
normalized income of `1.10 ray` has a visible balance of `110 aDAI`. The
additional `10 aDAI` is virtual interest: it becomes stored ERC20 principal
only when `_cumulateBalance()` runs.

Returning zero before the calculation avoids division by the zero index of an
account that has never held a balance.

## `principalBalanceOf`

```solidity
function principalBalanceOf(address _user)
    external
    view
    returns (uint256)
```

Returns the stored ERC20 principal for `_user`, without virtual accrued
interest. This is useful when code needs the last materialized balance rather
than the interest-bearing value returned by `balanceOf()`.

# Accumulating Interest

## `_cumulateBalance`

```solidity
function _cumulateBalance(
    address _user
)
    internal
    returns (
        uint256,
        uint256,
        uint256,
        uint256
    )
```

`_cumulateBalance` converts the interest already included in the user's dynamic `balanceOf()` into stored ERC20 principal.

Before this function is called, the user's balance may be divided into:

```text
stored principal
+
virtual accrued interest
```

After the function runs, the accrued interest is minted and becomes part of the stored principal.

The user's economic balance does not increase during this operation. The function only materializes interest that had already accrued.

It returns:

```text
previous principal balance
new principal balance
balance increase
new user index
```

### 1. Read the Stored Principal

```solidity
uint256 previousPrincipalBalance =
    super.balanceOf(_user);
```

`super.balanceOf()` reads the balance stored directly in the inherited ERC20 contract.

It does not include interest accrued since the user's last index update.

Example:

```text
stored principal = 100 aDAI
```

### 2. Calculate the Current Balance

The function calls the overridden `balanceOf()`:

```solidity
balanceOf(_user)
```

This returns the user's current interest-bearing balance by applying the reserve normalized income to the user's balance.

For any user in this implementation:

```text
current balance =
    principal balance
    × current normalized income
    ÷ user index
```

Assume:

```text
previous principal balance = 100 aDAI
user index = 1.00 ray
current normalized income = 1.05 ray
```

Then:

```text
current balance =
    100 × 1.05 / 1.00

current balance = 105 aDAI
```

### 3. Calculate the Balance Increase

```solidity
uint256 balanceIncrease =
    balanceOf(_user)
        - previousPrincipalBalance;
```

The balance increase is the interest accrued since the user's previous index checkpoint.

Using the previous example:

```text
current balance = 105 aDAI
previous principal balance = 100 aDAI

balance increase =
    105 - 100

balance increase = 5 aDAI
```

The `5 aDAI` already belongs to the user economically, but it has not yet been minted into ERC20 storage.

### 4. Mint the Accrued Interest

```solidity
_mint(_user, balanceIncrease);
```

The function mints the accrued interest and adds it to the stored principal.

Before minting:

```text
stored principal = 100 aDAI
dynamic balance = 105 aDAI
```

After minting:

```text
stored principal = 105 aDAI
dynamic balance = 105 aDAI
```

The user's current balance remains unchanged.

Only its representation changes:

```text
before:
    100 stored principal
    + 5 virtual interest

after:
    105 stored principal
    + 0 unapplied interest
```

Minting also increases the stored ERC20 supply by the same `balanceIncrease`.

### 5. Update the User Index

```solidity
uint256 index =
    s_userIndexes[_user] =
        i_core.getReserveNormalizedIncome(
            i_underlyingAssetAddress
        );
```

After materializing the interest, the user's index is moved to the current reserve normalized income.

Using the example:

```text
old user index = 1.00 ray
current normalized income = 1.05 ray
new user index = 1.05 ray
```

This records that all reserve growth up to `1.05 ray` has already been applied to the user.

Future interest is calculated only from this new checkpoint onward.

Immediately after the update:

```text
current balance =
    105 × 1.05 / 1.05

current balance = 105 aDAI
```

The division by the new user index prevents the previously accrued `5 aDAI` from being counted again.

### 6. Return the Updated Values

```solidity
return (
    previousPrincipalBalance,
    previousPrincipalBalance
        + balanceIncrease,
    balanceIncrease,
    index
);
```

Using the complete example, the returned values are:

```text
previousPrincipalBalance = 100 aDAI
newPrincipalBalance = 105 aDAI
balanceIncrease = 5 aDAI
index = 1.05 ray
```

## Complete Example

Assume Alice has:

```text
stored principal = 100 aDAI
user index = 1.00 ray
current normalized income = 1.05 ray
```

The function first calculates:

```text
current balance =
    100 × 1.05 / 1.00

current balance = 105 aDAI
```

Then:

```text
balance increase =
    105 - 100

balance increase = 5 aDAI
```

It mints the accrued interest:

```text
new stored principal =
    100 + 5

new stored principal = 105 aDAI
```

Finally, it updates the user index:

```text
new user index = 1.05 ray
```

The final state is:

```text
stored principal = 105 aDAI
current balance = 105 aDAI
user index = 1.05 ray
```

The user's value was already `105 aDAI` before the function ran. `_cumulateBalance()` only converted the virtual `5 aDAI` of accrued interest into stored principal.

## First Interaction

For a user with no balance:

```text
stored principal = 0
user index = 0
```

`balanceOf()` returns zero before attempting to divide by the user index.

Therefore:

```text
previous principal balance = 0
current balance = 0
balance increase = 0
```

The function mints zero interest and sets the user's index to the current reserve normalized income.

This establishes the user's starting checkpoint before a new deposit is minted.


# Calculating the Cumulated Balance

## `_calculateCumulatedBalance`

```solidity
function _calculateCumulatedBalance(
    address _user,
    uint256 _balance
) internal view returns (uint256)
```

This function calculates a user's balance including the interest accrued since the user's index was last updated.

The formula is:

```text
cumulated balance =
    stored balance
    × current reserve normalized income
    ÷ user index
```

The implementation is:

```solidity
return _balance
    .wadToRay()
    .rayMul(
        i_core.getReserveNormalizedIncome(
            i_underlyingAssetAddress
        )
    )
    .rayDiv(s_userIndexes[_user])
    .rayToWad();
```

The ratio:

```text
current normalized income / user index
```

represents the reserve growth that occurred since the user's last balance update.

For example:

```text
user index = 1.02 ray
current normalized income = 1.071 ray

growth factor =
    1.071 / 1.02
    = 1.05
```

This means the reserve grew by 5% relative to the user's stored index.

For a stored balance of 100 tokens:

```text
cumulated balance =
    100 × 1.05
    = 105 tokens
```

### Example 1: the reserve has grown by 10%

```text
stored balance = 200 tokens
user index = 1.00 ray
current normalized income = 1.10 ray
```

First, calculate the growth factor:

```text
growth factor =
    1.10 / 1.00
    = 1.10
```

Then apply it to the stored balance:

```text
cumulated balance =
    200 × 1.10
    = 220 tokens
```

The user has earned:

```text
220 - 200 = 20 tokens
```

### Example 2: the reserve has grown, but the user entered later

```text
stored balance = 200 tokens
user index = 1.20 ray
current normalized income = 1.26 ray
```

The reserve normalized income has increased from `1.20` to `1.26`.

The relative growth is:

```text
growth factor =
    1.26 / 1.20
    = 1.05
```

Therefore:

```text
cumulated balance =
    200 × 1.05
    = 210 tokens
```

Even though the current normalized income is `1.26`, the user does not receive 26% interest.

The user only receives the 5% growth that occurred after their index was recorded at `1.20`.

### Example 3: two users with the same stored balance but different indexes

Assume both users have a stored balance of 100 tokens and the current normalized income is `1.20 ray`.

#### User A

```text
stored balance = 100 tokens
user index = 1.00 ray
current normalized income = 1.20 ray
```

```text
growth factor =
    1.20 / 1.00
    = 1.20
```

```text
cumulated balance =
    100 × 1.20
    = 120 tokens
```

User A has earned 20 tokens.

#### User B

```text
stored balance = 100 tokens
user index = 1.10 ray
current normalized income = 1.20 ray
```

```text
growth factor =
    1.20 / 1.10
    ≈ 1.090909
```

```text
cumulated balance =
    100 × 1.090909
    ≈ 109.0909 tokens
```

User B earns less because their index was updated later.

The current normalized income is the same for both users, but each user's balance depends on the normalized income stored in their own user index.

### Example 4: the user interacts multiple times

Assume the user initially has:

```text
stored balance = 100 tokens
user index = 1.00 ray
```

Later, the current normalized income becomes:

```text
current normalized income = 1.05 ray
```

Before updating the user's stored state, the balance is:

```text
cumulated balance =
    100 × 1.05 / 1.00
    = 105 tokens
```

When the user performs an action, the protocol may store:

```text
new stored balance = 105 tokens
new user index = 1.05 ray
```

Later, the normalized income increases again:

```text
current normalized income = 1.1025 ray
```

The new cumulated balance is:

```text
cumulated balance =
    105 × 1.1025 / 1.05
```

The relative growth factor is:

```text
1.1025 / 1.05 = 1.05
```

Therefore:

```text
cumulated balance =
    105 × 1.05
    = 110.25 tokens
```

The previously accrued interest becomes part of the stored balance, and the next calculation applies only the growth that happened after the latest index update.

### Example 5: normalized income contains cumulative reserve growth

Assume the reserve normalized income has grown as follows:

```text
reserve initialization: 1.00 ray
after first period:      1.10 ray
after second period:     1.21 ray
```

The value `1.21 ray` means the reserve has grown cumulatively by 21% since initialization.

However, assume the user index was recorded after the first period:

```text
stored balance = 100 tokens
user index = 1.10 ray
current normalized income = 1.21 ray
```

The user's growth factor is:

```text
growth factor =
    1.21 / 1.10
    = 1.10
```

Therefore:

```text
cumulated balance =
    100 × 1.10
    = 110 tokens
```

The user receives only the 10% growth from `1.10` to `1.21`, not the complete 21% growth since the reserve was initialized.

### Example 6: calculation using wad and ray units

Assume:

```text
stored balance = 100e18
user index = 1.02e27
current normalized income = 1.071e27
```

The stored balance starts in wad precision:

```text
100e18
```

It is converted to ray precision:

```text
100e18 × 1e9 = 100e27
```

The normalized income is then applied:

```text
100e27 × 1.071e27 / 1e27
= 107.1e27
```

The result is divided by the user index:

```text
107.1e27 × 1e27 / 1.02e27
= 105e27
```

Finally, the result is converted back to wad:

```text
105e27 / 1e9
= 105e18
```

Therefore, the returned balance is:

```text
105e18
```

which represents 105 tokens with 18 decimals.

The conversion from wad to ray is necessary because the reserve normalized income and the user index are stored using ray precision.

# Token Decimals

## `decimals`

```solidity
function decimals()
    public
    view
    override
    returns (uint8)
```

Returns the decimals of the underlying asset.

This preserves the same unit precision between the reserve asset and its aToken.

# Reading the Total Supply

## `totalSupply`

```solidity
function totalSupply()
    public
    view
    override
    returns (uint256)
```

This function returns the current interest-bearing total supply.

It first reads the stored principal supply:

```solidity
uint256 currentSupplyPrincipal =
    super.totalSupply();
```

`super.totalSupply()` is the total aToken balance that has been minted (less any burned tokens)—i.e., the stored “principal” supply before applying accrued interest.

If no aTokens exist:

```solidity
if (currentSupplyPrincipal == 0) {
    return 0;
}
```

Otherwise, it applies the current reserve normalized income:

```solidity
return currentSupplyPrincipal
    .wadToRay()
    .rayMul(
        i_core.getReserveNormalizedIncome(
            i_underlyingAssetAddress
        )
    )
    .rayToWad();
```

Example:

```text
stored principal supply = 1,000 aDAI
normalized income = 1.05 ray

current total supply =
    1,000 × 1.05
    = 1,050 aDAI
```

Unlike an individual balance, `totalSupply()` does not divide by a user index because it represents the global deposit supply.

> **Implementation caveat:** deposits are minted 1:1 while each account has
> its own index. Applying the current normalized income to all stored supply
> can overstate the reported supply after deposits made at a non-unit index.
> The formula above documents the current code; it is not necessarily equal to
> the sum of all users' `balanceOf()` values.

# Getter Functions

## `getPoolAddress`

```solidity
function getPoolAddress()
    external
    view
    returns (address)
```

Returns the configured `LendingPool` address.

## `getUnderlyingAssetAddress`

```solidity
function getUnderlyingAssetAddress()
    external
    view
    returns (address)
```

Returns the underlying asset represented by the aToken.

## `getUserIndex`

```solidity
function getUserIndex(
    address _user
) external view returns (uint256)
```

Returns the reserve normalized income last applied to the user.

A zero value usually means that the user has never held a balance or their data has been reset.

# First Deposit Example

Before the user's first deposit:

```text
stored principal = 0
user index = 0
```

`balanceOf()` returns zero before performing any division.

`_cumulateBalance()` then sets the user index to the current reserve normalized income.

Finally, `mintOnDeposit()` mints the deposited amount.

Example:

```text
deposit = 100 DAI
current normalized income = 1.08 ray

stored principal = 100 aDAI
user index = 1.08 ray
```

The user does not receive interest for the period before the deposit.

# Later Deposit Example

Assume the user already has:

```text
stored principal = 100 aDAI
user index = 1.00 ray
current normalized income = 1.05 ray
```

The user deposits another `20 DAI`.

Before minting the new deposit:

```text
current balance =
    100 × 1.05 / 1.00
    = 105

balance increase =
    105 - 100
    = 5
```

`_cumulateBalance()` mints the `5 aDAI` interest and updates the user index to `1.05 ray`.

`mintOnDeposit()` then mints `20 aDAI`.

The final state is:

```text
stored principal = 125 aDAI
user index = 1.05 ray
```

# Virtual and Materialized Interest

Interest exists in two forms.

## Virtual Interest

Virtual interest is calculated dynamically by `balanceOf()`.

```text
virtual interest =
    current balance
    - stored principal
```

It is not yet stored in ERC20 state.

## Materialized Interest

Materialized interest is minted by `_cumulateBalance()`:

```solidity
_mint(_user, balanceIncrease);
```

Before cumulation:

```text
stored principal = 100
current balance = 105
```

After cumulation:

```text
stored principal = 105
current balance = 105
```

The user's economic value does not change. The function only converts already accrued virtual interest into stored principal.
