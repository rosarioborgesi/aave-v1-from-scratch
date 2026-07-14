# LendingPool

The `LendingPool` contract is the main user-facing entry point of the lending protocol.

In the current implementation, it supports:

```text
deposits
redemptions of underlying assets
```

When a user deposits an underlying asset or redeems it through an aToken,
`LendingPool` coordinates the operation between:

```text
the user
LendingPoolCore
the reserve's AToken
```

The contract does not hold reserve assets directly.

For deposits, it:

```text
validates the deposit
updates the reserve state
mints aTokens to the user
transfers the underlying asset to LendingPoolCore
emits the Deposit event
```

For redemptions, it:

```text
accepts calls only from the reserve's aToken
validates the reserve and amount
checks available liquidity
updates the reserve state
transfers the underlying asset from LendingPoolCore to the user
emits the RedeemUnderlying event
```

# Contract Declaration

```solidity
contract LendingPool is ReentrancyGuard
```

The contract inherits from OpenZeppelin's `ReentrancyGuard`.

The `nonReentrant` modifier protects functions such as `deposit()` and `redeemUnderlying()` from being reentered before their execution has completed.

# Errors

## `LendingPool__AmountIsZero`

```solidity
error LendingPool__AmountIsZero();
```

This error is raised when an operation attempts to use an amount equal to zero.

Example:

```text
deposit amount = 0
redeem amount = 0
```

The transaction reverts because no meaningful reserve operation can be performed.

## `LendingPool__ReserveIsNotActive`

```solidity
error LendingPool__ReserveIsNotActive();
```

This error is raised when an operation targets a reserve that is not active.

Inactive reserves cannot accept deposits or redemptions.

## `LendingPool__ReserveIsFrozen`

```solidity
error LendingPool__ReserveIsFrozen();
```

This error is raised when the user attempts to deposit into a frozen reserve.

A frozen reserve may still support operations such as redemptions or repayments, but it cannot accept new deposits.

## `LendingPool__ZeroAddress`

```solidity
error LendingPool__ZeroAddress();
```

This error is used by the constructor when:

```text
the addresses provider is the zero address
or
the addresses provider returns the zero address for LendingPoolCore
```

## `LendingPool__ATokenOnly`

```solidity
error LendingPool__ATokenOnly();
```

This error is raised when an address other than the reserve's registered aToken
tries to call `redeemUnderlying()`.

Users do not call `redeemUnderlying()` directly. They call `redeem()` on the
aToken, and the aToken calls back into `LendingPool`.

## `LendingPool__InsufficientLiquidityToRedeem`

```solidity
error LendingPool__InsufficientLiquidityToRedeem();
```

This error is raised when the requested redemption amount is greater than the
reserve liquidity currently available in `LendingPoolCore`.

Example:

```text
available liquidity = 80 DAI
requested redeem    = 100 DAI
```

The transaction reverts because the core cannot send out more underlying
liquidity than it currently holds.

# State Variables

```solidity
LendingPoolCore private immutable i_core;

LendingPoolAddressesProvider
    private immutable i_addressesProvider;
```

Both variables are immutable.

They are assigned once during construction and cannot be changed afterward.

## `i_core`

```solidity
LendingPoolCore private immutable i_core;
```

This variable stores the `LendingPoolCore` contract reference.

`LendingPool` uses it to:

```text
read reserve configuration
resolve the reserve's AToken
update reserve state
transfer deposited assets into LendingPoolCore
transfer redeemed assets out to users
```

## `i_addressesProvider`

```solidity
LendingPoolAddressesProvider
    private immutable i_addressesProvider;
```

This variable stores the protocol's addresses provider.

The constructor uses it to discover the configured `LendingPoolCore` address.

# Deposit Event

```solidity
event Deposit(
    address indexed _reserve,
    address indexed _user,
    uint256 _amount,
    uint16 indexed _referral,
    uint256 _timestamp
);
```

The event is emitted after a successful deposit.

It records:

```text
the reserve address
the depositor
the deposited amount
the referral code
the timestamp
```

## `_reserve`

The address identifying the deposited reserve.

For ERC20 reserves, this is the token address.

For the native ETH reserve, Aave V1 uses a special reserve address.

## `_user`

The address of the user making the deposit.

## `_amount`

The amount of the underlying asset deposited.

## `_referral`

The referral code associated with the deposit.

Integrators can use referral codes to identify deposits originating from their applications.

## `_timestamp`

The block timestamp at which the deposit was completed.

# RedeemUnderlying Event

```solidity
event RedeemUnderlying(
    address indexed _reserve,
    address indexed _user,
    uint256 _amount,
    uint256 _timestamp
);
```

The event is emitted after a successful redemption of underlying assets.

It records:

```text
the reserve address
the redeeming user
the redeemed amount
the timestamp
```

## `_reserve`

The address identifying the reserve whose underlying asset was redeemed.

## `_user`

The address receiving the redeemed underlying asset.

## `_amount`

The amount of underlying asset sent back to the user.

## `_timestamp`

The block timestamp at which the redemption was completed.

# Modifiers

## `onlyAmountGreaterThanZero`

```solidity
modifier onlyAmountGreaterThanZero(
    uint256 _amount
) {
    if (_amount == 0) {
        revert LendingPool__AmountIsZero();
    }

    _;
}
```

This modifier ensures that the operation amount is greater than zero.

Example:

```text
amount = 0
```

The call reverts with:

```solidity
LendingPool__AmountIsZero()
```

Example:

```text
amount = 100 DAI
```

The function continues.

## `onlyActiveReserve`

```solidity
modifier onlyActiveReserve(
    address _reserve
) {
    if (
        !i_core.getReserveIsActive(_reserve)
    ) {
        revert LendingPool__ReserveIsNotActive();
    }

    _;
}
```

This modifier checks that the reserve is active.

It calls:

```solidity
i_core.getReserveIsActive(_reserve)
```

If the result is `false`, the operation reverts.

```text
active reserve   → operation allowed
inactive reserve → operation rejected
```

## `onlyUnfreezedReserve`

```solidity
modifier onlyUnfreezedReserve(
    address _reserve
) {
    if (
        i_core.getReserveIsFreezed(_reserve)
    ) {
        revert LendingPool__ReserveIsFrozen();
    }

    _;
}
```

This modifier prevents deposits into frozen reserves.

It calls:

```solidity
i_core.getReserveIsFreezed(_reserve)
```

If the result is `true`, the transaction reverts.

```text
unfrozen reserve → deposit allowed
frozen reserve   → deposit rejected
```

The name `onlyUnfreezedReserve` is preserved from the original Aave V1 terminology.

## `onlyOverlyingAToken`

```solidity
modifier onlyOverlyingAToken(
    address _reserve
) {
    if (
        msg.sender !=
        i_core.getReserveATokenAddress(_reserve)
    ) {
        revert LendingPool__ATokenOnly();
    }

    _;
}
```

This modifier restricts `redeemUnderlying()` to the aToken registered for the
reserve.

The call path is:

```text
User
  │ redeem()
  ▼
AToken
  │ redeemUnderlying()
  ▼
LendingPool
```

If a user or unrelated contract calls `redeemUnderlying()` directly, the call
reverts with:

```solidity
LendingPool__ATokenOnly()
```

# Constructor

```solidity
constructor(address _addressesProvider) {
    if (_addressesProvider == address(0)) {
        revert LendingPool__ZeroAddress();
    }

    i_addressesProvider =
        LendingPoolAddressesProvider(
            _addressesProvider
        );

    address coreAddress =
        i_addressesProvider
            .getLendingPoolCore();

    if (coreAddress == address(0)) {
        revert LendingPool__ZeroAddress();
    }

    i_core =
        LendingPoolCore(coreAddress);
}
```

The constructor receives the address of `LendingPoolAddressesProvider`.

It performs four operations.

## 1. Validate the Addresses Provider

```solidity
if (_addressesProvider == address(0)) {
    revert LendingPool__ZeroAddress();
}
```

The addresses provider cannot be the zero address.

Without a valid addresses provider, the contract would not be able to discover `LendingPoolCore`.

## 2. Store the Addresses Provider

```solidity
i_addressesProvider =
    LendingPoolAddressesProvider(
        _addressesProvider
    );
```

The supplied address is converted into a `LendingPoolAddressesProvider` contract reference.

Because the variable is immutable, it cannot be changed after construction.

## 3. Resolve LendingPoolCore

```solidity
address coreAddress =
    i_addressesProvider
        .getLendingPoolCore();
```

The constructor asks the addresses provider for the configured `LendingPoolCore` address.

The relationship is:

```text
LendingPool
    │
    ▼
LendingPoolAddressesProvider
    │
    ▼
LendingPoolCore address
```

## 4. Validate and Store LendingPoolCore

```solidity
if (coreAddress == address(0)) {
    revert LendingPool__ZeroAddress();
}

i_core =
    LendingPoolCore(coreAddress);
```

The core address must not be zero.

The validated address is then stored as an immutable `LendingPoolCore` contract reference.

# Proxy Difference

The original Aave V1 contract used an `initialize()` function because it was deployed behind a proxy.

The current implementation uses a constructor:

```solidity
constructor(address _addressesProvider)
```

This is appropriate for the current non-proxy version.

The contract includes a reminder:

```solidity
// TODO replace with initialize for proxy
```

If proxy support is added later, constructor-based state initialization will need to be replaced with an initializer.

# Depositing Assets

## `deposit`

```solidity
function deposit(
    address _reserve,
    uint256 _amount,
    uint16 _referralCode
)
    external
    payable
    nonReentrant
    onlyActiveReserve(_reserve)
    onlyUnfreezedReserve(_reserve)
    onlyAmountGreaterThanZero(_amount)
```

This function deposits an underlying asset into a reserve.

In exchange, the user receives the corresponding amount of aTokens.

Example:

```text
deposit 100 DAI
receive 100 aDAI
```

The function is payable because the original Aave V1 protocol supports both:

```text
ERC20 deposits
native ETH deposits
```

For an ERC20 deposit:

```text
msg.value = 0
```

For an ETH deposit:

```text
msg.value contains the ETH sent
```

Before executing the deposit, the modifiers verify that:

```text
the function is not being reentered
the reserve is active
the reserve is not frozen
the amount is greater than zero
```

The function then performs six operations.

# 1. Get the Reserve's AToken

```solidity
AToken aToken =
    AToken(
        i_core.getReserveATokenAddress(
            _reserve
        )
    );
```

Each reserve has a corresponding aToken.

Examples:

```text
DAI reserve  → aDAI
USDC reserve → aUSDC
ETH reserve  → aETH
```

`LendingPool` asks `LendingPoolCore` for the aToken associated with `_reserve`.

The returned address is converted into an `AToken` contract reference.

# 2. Check Whether This Is the First Deposit

```solidity
bool isFirstDeposit =
    aToken.balanceOf(msg.sender) == 0;
```

The function reads the user's current interest-bearing aToken balance.

If the balance is zero:

```text
isFirstDeposit = true
```

Otherwise:

```text
isFirstDeposit = false
```

This value is later passed to `LendingPoolCore`.

On the first deposit, the core can initialize user-specific reserve state, such as enabling the deposited reserve as collateral.

The function uses the overridden `aToken.balanceOf()`.

This means it checks the user's current economic balance, including accrued interest, rather than only the stored ERC20 principal.

# 3. Update the Reserve State

```solidity
i_core.updateStateOnDeposit(
    _reserve,
    msg.sender,
    _amount,
    isFirstDeposit
);
```

Before minting aTokens, the pool asks `LendingPoolCore` to update the reserve and user state.

This operation can include:

```text
updating the liquidity index
updating reserve interest rates
updating the reserve timestamp
initializing the user's collateral state
```

The state update occurs before `mintOnDeposit()`.

This order is important because the aToken uses the reserve's current normalized income when setting the user's index.

```text
update reserve accounting
        ↓
update user aToken accounting
```

# 4. Mint aTokens

```solidity
aToken.mintOnDeposit(
    msg.sender,
    _amount
);
```

The reserve's aToken mints the deposited amount to the user.

Before minting the new deposit, `mintOnDeposit()`:

```text
materializes already accrued interest
updates the user's index
updates interest-redirection accounting
mints the new deposit amount
```

Example:

```text
stored principal = 100 aDAI
accrued interest = 5 aDAI
new deposit = 20 DAI
```

After `mintOnDeposit()`:

```text
old interest materialized = 5 aDAI
new deposit minted = 20 aDAI
final stored principal = 125 aDAI
```

# 5. Transfer the Underlying Asset

```solidity
i_core.transferToReserve{
    value: msg.value
}(
    _reserve,
    payable(msg.sender),
    _amount
);
```

The deposited underlying asset is transferred to `LendingPoolCore`.

`LendingPoolCore` holds the reserve liquidity.

The behavior depends on the type of asset.

## ERC20 Deposit

For an ERC20 reserve:

```text
msg.value = 0
```

`LendingPoolCore` transfers the tokens from the user using `transferFrom()`.

```text
User
  │
  │ ERC20 transferFrom()
  ▼
LendingPoolCore
```

The user must approve `LendingPoolCore` before calling `deposit()`.

Example:

```text
Alice approves LendingPoolCore for 100 DAI
Alice deposits 100 DAI
LendingPoolCore transfers 100 DAI from Alice
```

## ETH Deposit

For the native ETH reserve, `msg.value` is forwarded to `LendingPoolCore`.

Example:

```text
_amount = 1 ETH
msg.value = 1 ETH
```

The core receives and stores the deposited ETH.

If more ETH than `_amount` is sent, `LendingPoolCore` can refund the excess according to the original Aave V1 behavior.

# 6. Emit `Deposit`

```solidity
emit Deposit(
    _reserve,
    msg.sender,
    _amount,
    _referralCode,
    block.timestamp
);
```

After all deposit operations complete, the contract emits the `Deposit` event.

If any previous step reverts, the entire transaction is reverted.

This includes:

```text
reserve state updates
aToken minting
underlying asset transfers
event emission
```

# Complete First Deposit Example

Assume Alice wants to deposit:

```text
100 DAI
```

The reserve configuration is:

```text
reserve = DAI
aToken = aDAI
reserve active = true
reserve frozen = false
```

Alice currently has:

```text
aDAI balance = 0
```

Before calling `deposit()`, Alice approves `LendingPoolCore` to spend `100 DAI`.

Alice calls:

```solidity
lendingPool.deposit(
    DAI,
    100 ether,
    0
);
```

## Step 1: Validate the Deposit

The modifiers check:

```text
reserve active = true
reserve frozen = false
amount = 100 DAI
```

The deposit is allowed to continue.

## Step 2: Resolve aDAI

```text
DAI reserve → aDAI
```

## Step 3: Detect the First Deposit

```text
Alice aDAI balance = 0

isFirstDeposit = true
```

## Step 4: Update the Reserve State

```solidity
i_core.updateStateOnDeposit(
    DAI,
    Alice,
    100 ether,
    true
);
```

The core updates the reserve indexes, rates, timestamp, and Alice's reserve state.

## Step 5: Mint aDAI

```solidity
aDAI.mintOnDeposit(
    Alice,
    100 ether
);
```

Alice receives:

```text
100 aDAI
```

Her user index is initialized to the reserve's current normalized income.

## Step 6: Transfer DAI

`LendingPoolCore` performs the equivalent of:

```text
transferFrom(
    Alice,
    LendingPoolCore,
    100 DAI
)
```

The final balances are:

```text
Alice DAI decreases by 100
LendingPoolCore DAI increases by 100
Alice aDAI increases by 100
```

## Step 7: Emit the Event

```text
reserve = DAI
user = Alice
amount = 100 DAI
referral = 0
timestamp = current block timestamp
```

# Deposit With Existing Interest

Assume Alice already has:

```text
stored principal = 100 aDAI
user index = 1.00 ray
current normalized income = 1.05 ray
```

Her current balance is:

```text
100 × 1.05 / 1.00 = 105 aDAI
```

Alice deposits another:

```text
20 DAI
```

The flow is:

```text
1. LendingPoolCore updates the reserve state

2. mintOnDeposit materializes:
   5 aDAI of accrued interest

3. Alice's stored principal becomes:
   100 + 5 = 105 aDAI

4. mintOnDeposit mints:
   20 new aDAI

5. Alice's stored principal becomes:
   105 + 20 = 125 aDAI

6. LendingPoolCore receives:
   20 DAI
```

The final state is:

```text
Alice stored principal = 125 aDAI
Alice current balance = 125 aDAI
Alice user index = current normalized income
LendingPoolCore received 20 DAI
```

The new `20 DAI` deposit does not receive interest for the period before it entered the protocol.

# Deposit Order

```text
validate reserve and amount
        ↓
resolve the reserve's aToken
        ↓
check whether this is the user's first deposit
        ↓
update reserve and user state in LendingPoolCore
        ↓
materialize old interest and mint new aTokens
        ↓
transfer the underlying asset to LendingPoolCore
        ↓
emit Deposit
```

This order ensures that:

```text
inactive reserves reject deposits
frozen reserves reject deposits
zero-value deposits reject early
reserve accounting is updated before aToken accounting
new deposits do not receive past interest
existing interest is materialized correctly
the underlying asset reaches LendingPoolCore
the whole transaction reverts if the transfer fails
```

# Redeeming Underlying Assets

## `redeemUnderlying`

```solidity
function redeemUnderlying(
    address _reserve,
    address payable _user,
    uint256 _amount,
    uint256 _aTokenBalanceAfterRedeem
)
    external
    nonReentrant
    onlyOverlyingAToken(_reserve)
    onlyActiveReserve(_reserve)
    onlyAmountGreaterThanZero(_amount)
```

This function redeems an underlying asset from a reserve.

Users do not call it directly.

Instead, the user calls `redeem()` on the aToken. The aToken validates and burns
the user's aToken balance, then calls `LendingPool.redeemUnderlying()` to update
protocol state and release the underlying asset.

The relationship is:

```text
User burns aTokens
        ↓
AToken calls LendingPool.redeemUnderlying()
        ↓
LendingPool updates reserve state through LendingPoolCore
        ↓
LendingPoolCore sends underlying asset to the user
```

Example:

```text
redeem 100 aDAI
receive 100 DAI
```

Before executing the redemption, the modifiers verify that:

```text
the function is not being reentered
the caller is the reserve's registered aToken
the reserve is active
the amount is greater than zero
```

A frozen reserve is not rejected here.

Freezing blocks new deposits, but users must still be able to exit an active
reserve by redeeming their aTokens.

The function then performs four operations.

# 1. Check Available Liquidity

```solidity
uint256 currentAvailableLiquidity =
    i_core.getReserveAvailableLiquidity(
        _reserve
    );

if (currentAvailableLiquidity < _amount) {
    revert LendingPool__InsufficientLiquidityToRedeem();
}
```

The pool checks how much underlying liquidity is currently available in
`LendingPoolCore`.

If the requested amount is greater than the available liquidity, the redemption
reverts.

Example:

```text
available liquidity = 80 DAI
redeem amount       = 100 DAI
```

The call reverts because the core cannot return `100 DAI` when only `80 DAI` is
available.

# 2. Update the Reserve State

```solidity
i_core.updateStateOnRedeem(
    _reserve,
    _user,
    _amount,
    _aTokenBalanceAfterRedeem == 0
);
```

Before transferring the underlying asset, the pool asks `LendingPoolCore` to
update reserve and user state.

This operation can include:

```text
updating cumulative indexes
updating reserve interest rates
updating the reserve timestamp
disabling the user's collateral flag after a full redemption
```

The last argument tells the core whether the user redeemed their entire aToken
balance.

It is derived from the user's balance after the aToken burn:

```text
_aTokenBalanceAfterRedeem == 0
```

If the user redeemed everything, the core disables that reserve as collateral
for the user.

# 3. Transfer the Underlying Asset to the User

```solidity
i_core.transferToUser(
    _reserve,
    _user,
    _amount
);
```

`LendingPoolCore` sends the redeemed underlying asset to the user.

For an ERC20 reserve, the core transfers tokens to the user.

```text
LendingPoolCore
  │ ERC20 transfer()
  ▼
User
```

For the native ETH reserve, the core sends ETH to the user.

# 4. Emit `RedeemUnderlying`

```solidity
emit RedeemUnderlying(
    _reserve,
    _user,
    _amount,
    block.timestamp
);
```

After the reserve state has been updated and the underlying asset has been sent,
the contract emits the `RedeemUnderlying` event.

If any previous step reverts, the entire transaction is reverted.

# Complete Redeem Example

Assume Alice wants to redeem:

```text
100 DAI
```

The reserve configuration is:

```text
reserve = DAI
aToken = aDAI
reserve active = true
available liquidity = 1,000 DAI
```

Alice calls:

```solidity
aDAI.redeem(100 ether);
```

The aToken:

```text
calculates Alice's current aDAI balance
checks whether the balance decrease is allowed
burns 100 aDAI
calls LendingPool.redeemUnderlying()
```

Then `LendingPool.redeemUnderlying()`:

```text
verifies the caller is aDAI
verifies the DAI reserve is active
verifies the amount is greater than zero
checks that at least 100 DAI is available
updates reserve accounting in LendingPoolCore
asks LendingPoolCore to send 100 DAI to Alice
emits RedeemUnderlying
```

The final balances are:

```text
Alice aDAI decreases by 100
LendingPoolCore DAI decreases by 100
Alice DAI increases by 100
```

# Redeem Order

```text
user calls redeem() on the aToken
        ↓
aToken validates and burns the user's aTokens
        ↓
aToken calls LendingPool.redeemUnderlying()
        ↓
LendingPool verifies the caller, reserve, and amount
        ↓
LendingPool checks available liquidity
        ↓
LendingPoolCore updates reserve and user state
        ↓
LendingPoolCore transfers underlying asset to the user
        ↓
LendingPool emits RedeemUnderlying
```

This order ensures that:

```text
users cannot bypass aToken accounting
inactive reserves reject redemptions
zero-value redemptions reject early
redemptions cannot exceed available liquidity
reserve accounting is updated before liquidity leaves
full redemptions disable the user's collateral flag
the whole transaction reverts if the transfer fails
```

For the full redemption flow, including the aToken and data-provider checks, see
[`docs/11-redeem.md`](./11-redeem.md).

# View Functions

## `getLendingPoolCoreAddress`

```solidity
function getLendingPoolCoreAddress()
    external
    view
    returns (address)
{
    return address(i_core);
}
```

This function returns the configured `LendingPoolCore` address.

## `getLendingPoolAddressesProvider`

```solidity
function getLendingPoolAddressesProvider()
    external
    view
    returns (address)
{
    return address(i_addressesProvider);
}
```

This function returns the configured `LendingPoolAddressesProvider` address.

# Current Scope

The current `LendingPool` implementation includes:

```text
deposit validation
redeem validation
active-reserve validation
frozen-reserve validation
zero-amount validation
aToken-only redeem access control
available-liquidity checks for redemptions
reentrancy protection
reserve-state updates
aToken minting
ERC20 and ETH deposit transfers
ERC20 and ETH redeem transfers through LendingPoolCore
deposit event emission
redeem event emission
protocol address getters
```

The current contract does not yet include the other operations present in the original Aave V1 `LendingPool`, such as:

```text
borrowing
repaying
interest-rate switching
collateral configuration
liquidations
flash loans
```
