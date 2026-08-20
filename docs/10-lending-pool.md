# LendingPool

The `LendingPool` contract is the main user-facing entry point of the lending protocol.


# Contract Declaration

```solidity
contract LendingPool is ReentrancyGuard
```

The contract inherits from OpenZeppelin's `ReentrancyGuard`.

The `nonReentrant` modifier protects functions such as `deposit()` and `redeemUnderlying()` from being reentered before their execution has completed.


# Proxy Difference

The original Aave V1 contract used an `initialize()` function because it was deployed behind a proxy.

The current implementation uses a constructor:

```solidity
constructor(address _addressesProvider)
```

This is appropriate for the current non-proxy version.

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

# Borrowing Assets

## `borrow`

```solidity
function borrow(
    address _reserve,
    uint256 _amount,
    uint256 _interestRateMode,
    uint16 _referralCode
)
    external
    nonReentrant
    onlyActiveReserve(_reserve)
    onlyUnfreezedReserve(_reserve)
    onlyAmountGreaterThanZero(_amount)
```

`borrow()` lets a user take underlying liquidity from a reserve against the
value of collateral they have supplied. The borrowed asset is sent directly to
`msg.sender`; no debt token is minted in this implementation. Instead,
`LendingPoolCore` records the user's debt and the reserve's borrow accounting.

The caller chooses one of the two supported interest-rate modes:

```text
1 = stable
2 = variable
```

Before a loan can be created, the function checks that the reserve can lend,
that sufficient liquidity exists, and that the caller's collateral can cover
their existing debt, existing fees, and the requested borrow plus its new fee.

The `nonReentrant`, active-reserve, unfrozen-reserve, and non-zero-amount
modifiers run first. Unlike redemption, borrowing from a frozen reserve is not
allowed because it would create new risk.

The function then performs the following operations.

# 1. Validate Borrowing Is Enabled and the Rate Mode

```solidity
if (!i_core.isReserveBorrowingEnabled(_reserve)) {
    revert LendingPool__ReserveNotEnabledForBorrowing();
}
```

Each reserve can independently enable or disable borrowing. An active reserve
is therefore not necessarily borrowable.

The requested mode must be `STABLE` or `VARIABLE`:

```solidity
if (
    _interestRateMode != uint256(CoreLibrary.InterestRateMode.VARIABLE)
        && _interestRateMode != uint256(CoreLibrary.InterestRateMode.STABLE)
) {
    revert LendingPool__InvalidInterestRateMode();
}
```

After validation, the numeric input is converted to the
`CoreLibrary.InterestRateMode` enum used by the core.

# 2. Check Reserve Liquidity

```solidity
vars.availableLiquidity =
    i_core.getReserveAvailableLiquidity(_reserve);

if (vars.availableLiquidity < _amount) {
    revert LendingPool__NotEnoughLiquidityInTheReserve();
}
```

The pool cannot lend tokens it does not currently hold. For example, a reserve
with `80 DAI` available rejects a request to borrow `100 DAI`, even if the
caller has enough collateral.

# 3. Read and Validate the User's Position

```solidity
(
    ,
    vars.userCollateralBalanceETH,
    vars.userBorrowBalanceETH,
    vars.userTotalFeesETH,
    vars.currentLtv,
    vars.currentLiquidationThreshold,,
    vars.healthFactorBelowThreshold
) = i_dataProvider.calculateUserGlobalData(msg.sender);
```

`LendingPoolDataProvider` aggregates the user's position across every reserve
and expresses collateral, debt, and fees in ETH using the price oracle. The
function uses the user's collateral value, current borrow value, outstanding
fees, weighted loan-to-value (LTV), and health status.

```solidity
if (vars.userCollateralBalanceETH == 0) {
    revert LendingPool__CollateralBalanceIsZero();
}

if (vars.healthFactorBelowThreshold) {
    revert LendingPool__HealthFactorBelowThreshold();
}
```

A user must have collateral and cannot increase a position that is already
below the liquidation health-factor threshold.

# 4. Calculate the Origination Fee and Required Collateral

```solidity
vars.borrowFee =
    i_feeProvider.calculateLoanOriginationFee(msg.sender, _amount);

if (vars.borrowFee == 0) {
    revert LendingPool__TooSmallAmountToBorrow();
}
```

The fee provider calculates a loan-origination fee in units of the borrowed
asset. A zero fee means the requested amount is too small after integer
rounding, so the transaction reverts rather than creating a fee-free dust loan.

The data provider then converts the new debt and fee to ETH and calculates the
collateral required at the user's current weighted LTV:

```solidity
vars.amountOfCollateralNeededETH =
    i_dataProvider.calculateCollateralNeededInETH(
        _reserve,
        _amount,
        vars.borrowFee,
        vars.userBorrowBalanceETH,
        vars.userTotalFeesETH,
        vars.currentLtv
    );
```

Conceptually, the check is:

```text
required collateral =
    (existing debt + existing fees + new borrow + new fee) / LTV
```

All values in the calculation are converted to ETH first. The borrow is only
accepted when the user's current collateral covers that requirement.

```solidity
if (vars.amountOfCollateralNeededETH > vars.userCollateralBalanceETH) {
    revert LendingPool__InsufficientCollateralToCoverNewBorrow();
}
```

# 5. Apply Stable-Rate Restrictions

Stable-rate borrowing has additional constraints:

```solidity
if (vars.rateMode == CoreLibrary.InterestRateMode.STABLE) {
    if (!i_core.isUserAllowedToBorrowAtStable(
        _reserve,
        msg.sender,
        _amount
    )) {
        revert LendingPool__UserCannotBorrowAmountAtStableRate();
    }

    uint256 maxLoanPercent =
        i_parametersProvider.getMaxStableRateBorrowSizePercent();
    uint256 maxLoanSizeStable =
        vars.availableLiquidity * maxLoanPercent / 100;

    if (_amount > maxLoanSizeStable) {
        revert LendingPool__UserIsBorrowingTooMuchLiquidityAtStableRate();
    }
}
```

The core verifies that stable borrowing is enabled for the reserve and prevents
the user from taking a stable-rate loan against a mostly same-asset collateral
position. It also limits one stable-rate loan to a configurable percentage of
currently available reserve liquidity.

For example, with `1,000 DAI` available and a maximum stable-borrow size of
`25%`, a stable-rate request above `250 DAI` reverts. Variable-rate borrowing
does not run these extra stable-rate checks.

# 6. Record the Borrow in `LendingPoolCore`

```solidity
(vars.finalUserBorrowRate, vars.borrowBalanceIncrease) =
    i_core.updateStateOnBorrow(
        _reserve,
        msg.sender,
        _amount,
        vars.borrowFee,
        vars.rateMode
    );
```

After every validation succeeds, `LendingPoolCore` updates the reserve and
borrower state. This includes materializing interest accrued since the user's
previous debt update, recording the new principal and origination fee, updating
the reserve's borrow accounting, and recalculating reserve interest rates after
the liquidity leaves.

The call returns the user's final borrow rate and `borrowBalanceIncrease`, the
interest that accrued on prior debt before this borrow. For a first borrow, the
balance increase is `0`.

# 7. Transfer the Borrowed Asset and Emit `Borrow`

```solidity
i_core.transferToUser(
    _reserve,
    payable(msg.sender),
    _amount
);
```

`LendingPoolCore` transfers the requested underlying ERC20 token or native ETH
to the borrower. Finally, the pool emits the `Borrow` event with the selected
rate mode, final rate, origination fee, prior-interest increase, referral code,
and timestamp.

# Borrow Order

```text
validate reserve, rate mode, liquidity, and collateral
        ↓
apply stable-rate-only restrictions when requested
        ↓
LendingPoolCore records debt and updates reserve rates
        ↓
LendingPoolCore transfers the borrowed underlying asset
        ↓
emit Borrow
```

If any validation, accounting update, or transfer fails, the complete borrow
transaction reverts, including the core state changes.

# Complete Borrow Example

Assume Alice has already supplied ETH as collateral. She wants to take a
variable-rate DAI loan:

```text
Alice collateral                 = 1 ETH
weighted LTV                     = 75%
DAI price                        = 0.0005 ETH
DAI available in LendingPoolCore = 5,000 DAI
origination fee                  = 0.25%
requested borrow                 = 1,000 DAI
rate mode                        = VARIABLE
```

Alice calls:

```solidity
lendingPool.borrow(
    DAI,
    1_000 ether,
    uint256(CoreLibrary.InterestRateMode.VARIABLE),
    0
);
```

The pool first confirms that DAI is active, unfrozen, borrow-enabled, and has
enough liquidity. It then reads Alice's position. Assume she has no existing
debt or fees and her health factor is above the liquidation threshold.

The fee provider calculates a `2.5 DAI` origination fee. The collateral check
includes both the requested loan and this fee:

```text
new borrow value = 1,000 DAI × 0.0005 ETH/DAI = 0.5 ETH
new fee value    =   2.5 DAI × 0.0005 ETH/DAI = 0.00125 ETH
total new debt   = 0.50125 ETH

collateral required = 0.50125 ETH / 75% = 0.66833 ETH
Alice's collateral  = 1 ETH
```

Because `1 ETH` covers the required `0.66833 ETH`, the borrow passes. The
variable-rate mode skips the stable-rate-only checks.

`LendingPoolCore.updateStateOnBorrow()` then records Alice's first DAI debt.
There is no earlier debt, so `borrowBalanceIncrease` is `0`. The core records
the `1,000 DAI` principal and the separate `2.5 DAI` origination fee, updates
the reserve's variable-borrow totals and interest rates, and sends the
requested DAI to Alice.

The final state is:

```text
Alice receives                    1,000 DAI
LendingPoolCore DAI liquidity      5,000 → 4,000 DAI
Alice DAI principal debt           1,000 DAI
Alice DAI origination fee            2.5 DAI
Alice prior-interest increase          0 DAI
```

Alice receives the full `1,000 DAI`; the fee is not deducted from the amount
sent to her. She owes that fee separately, alongside the principal and any
interest that accrues later.

# Repaying Assets

## `repay`

```solidity
function repay(
    address _reserve,
    uint256 _amount,
    address payable _onBehalfOf
)
    external
    payable
    nonReentrant
    onlyActiveReserve(_reserve)
    onlyAmountGreaterThanZero(_amount)
```

`repay()` pays down a borrow for `_onBehalfOf`. Usually the caller repays their
own loan, so `_onBehalfOf` and `msg.sender` are the same address. A different
caller can also make a repayment on a borrower's behalf.

Repayment has two components:

```text
total amount owed = compounded debt + outstanding origination fee
```

The compounded debt includes interest accrued since the borrower's previous
borrow-related update. The origination fee is paid first; only the amount left
after the fee reduces the loan principal.

For an ERC20 reserve, the core pulls tokens with `transferFrom()`. For the ETH
reserve, the caller provides ETH as `msg.value`. The function deliberately
does not require the reserve to be unfrozen: freezing stops new deposits and
borrows, but must not prevent borrowers from reducing risk.

The `nonReentrant`, active-reserve, and non-zero-amount modifiers run first.
The function then performs the following operations.

# 1. Read the Current Debt and Outstanding Fee

```solidity
(vars.principalBorrowBalance, vars.compoundedBorrowBalance, vars.borrowBalanceIncrease) =
    i_core.getUserBorrowBalances(_reserve, _onBehalfOf);

vars.originationFee =
    i_core.getUserOriginationFee(_reserve, _onBehalfOf);
```

`principalBorrowBalance` is the borrower's stored debt from the last state
update. `compoundedBorrowBalance` is the debt now, after adding accrued
interest. Their difference is `borrowBalanceIncrease`:

```text
borrowBalanceIncrease = compounded debt - stored principal
```

Example:

```text
stored principal     = 100 DAI
accrued interest     =   3 DAI
compounded debt      = 103 DAI
outstanding fee      =   1 DAI
total amount owed    = 104 DAI
```

The debt calculation is initially a view calculation. It becomes stored state
only when `updateStateOnRepay()` is called later.

If the borrower has no compounded debt, repayment is rejected:

```solidity
if (vars.compoundedBorrowBalance == 0) {
    revert LendingPool__NoBorrowPending();
}
```

# 2. Resolve the Asset Type and Repayment Amount

```solidity
vars.isETH = EthAddressLib.ethAddress() == _reserve;
```

This selects the transfer path later:

```text
ERC20 reserve → transferFrom()
ETH reserve   → msg.value
```

The special value `type(uint256).max` means “repay everything.” It is available
only when borrowers repay their own debt:

```solidity
if (_amount == type(uint256).max && msg.sender != _onBehalfOf) {
    revert LendingPool__ExplicitAmountRequiredForRepayOnBehalf();
}
```

This prevents a third party from using an unbounded instruction against another
user's position. A third-party repayer must state an exact amount.

The function starts by selecting the entire amount owed, then caps it for an
explicit partial repayment:

```solidity
vars.paybackAmount =
    vars.compoundedBorrowBalance + vars.originationFee;

if (_amount != type(uint256).max && _amount < vars.paybackAmount) {
    vars.paybackAmount = _amount;
}
```

Therefore, specifying more than the total owed does not overpay:

```text
total owed = 104 DAI
_amount    = 200 DAI
paid       = 104 DAI
```

For ETH, `msg.value` must cover the selected payment:

```solidity
if (vars.isETH && msg.value < vars.paybackAmount) {
    revert LendingPool__InvalidETHRepaymentAmount();
}
```

Any excess ETH is later refunded by `LendingPoolCore.transferToReserve()`.

# 3. Pay the Origination Fee First

```solidity
if (vars.paybackAmount <= vars.originationFee) {
    i_core.updateStateOnRepay(
        _reserve,
        _onBehalfOf,
        0,
        vars.paybackAmount,
        vars.borrowBalanceIncrease,
        false
    );
    // transfer the fee and emit Repay, then return
}
```

When the selected repayment is no greater than the outstanding fee, it pays
only the fee. The loan balance does not decrease. The core still materializes
the accrued interest supplied in `borrowBalanceIncrease`, reduces the stored
fee, updates reserve accounting, and recalculates interest rates.

Using the earlier example, if Alice pays `0.50 DAI`:

```text
compounded debt       = 103 DAI
outstanding fee       =   1 DAI
payment               = 0.5 DAI

fee remaining         = 0.5 DAI
debt remaining        = 103 DAI
debt repaid           = 0 DAI
```

The paid fee goes to the token distributor, the protocol's fee-collection
address. In this fee-only ERC20 branch, the implementation calls
`transferFrom(_onBehalfOf, ...)`, so the borrower must provide the ERC20 funds
and allowance even if another account initiated the call. This differs from
the normal repayment branch below, which pulls ERC20 funds from `msg.sender`.

# 4. Update Debt and Reserve Accounting

If the payment exceeds the fee, the fee is fully paid and the remainder reduces
the debt:

```solidity
vars.paybackAmountMinusFees =
    vars.paybackAmount - vars.originationFee;

i_core.updateStateOnRepay(
    _reserve,
    _onBehalfOf,
    vars.paybackAmountMinusFees,
    vars.originationFee,
    vars.borrowBalanceIncrease,
    vars.compoundedBorrowBalance == vars.paybackAmountMinusFees
);
```

The final boolean is true only when every unit of compounded debt is repaid.
In that case, the core clears the borrower's borrow data. A partial repayment
leaves the remaining debt open.

`updateStateOnRepay()` updates both levels of accounting:

```text
reserve level: reduce total borrows, include accrued interest, update rates
user level:    reduce debt, reduce/clear fee, materialize accrued interest
```

Because repayment adds liquidity back to the reserve, the core recalculates
the reserve's rates using the new liquidity level before the token transfer is
made. If a later transfer fails, the transaction reverts, including this state
update.

# 5. Send the Fee and Debt Payment

First, if a fee was owed, it is sent to the token distributor:

```solidity
i_core.transferToFeeCollectionAddress(
    _reserve,
    msg.sender,
    vars.originationFee,
    i_addressesProvider.getTokenDistributor()
);
```

Then the debt portion returns to reserve liquidity:

```solidity
i_core.transferToReserve(
    _reserve,
    payable(msg.sender),
    vars.paybackAmountMinusFees
);
```

For an ERC20 repayment in this normal branch, both transfers pull from
`msg.sender`. Therefore, the payer must approve `LendingPoolCore` for the fee
plus the debt portion. This also makes ordinary repay-on-behalf possible:

```text
Bob approves LendingPoolCore for 104 DAI
Bob calls repay(DAI, 104 DAI, Alice)
Alice's debt and fee are paid down
```

For ETH, the pool forwards the fee part to the token distributor and forwards
the remaining `msg.value` to the core as reserve liquidity. If more ETH was
sent than needed, `transferToReserve()` refunds the excess to `msg.sender`.

# 6. Emit `Repay`

```solidity
emit Repay(
    _reserve,
    _onBehalfOf,
    msg.sender,
    vars.paybackAmountMinusFees,
    vars.originationFee,
    vars.borrowBalanceIncrease,
    block.timestamp
);
```

The event distinguishes the borrower (`_onBehalfOf`) from the account that
provided the repayment (`msg.sender`). Its amount field excludes fees, so an
indexer can separately identify the debt reduction and protocol fee.

# Complete Repayment Example

Assume Alice borrowed DAI and now has the following position:

```text
stored principal = 100 DAI
accrued interest =   3 DAI
compounded debt  = 103 DAI
origination fee  =   1 DAI
```

Alice approves `LendingPoolCore` for `104 DAI` and calls:

```solidity
lendingPool.repay(
    DAI,
    type(uint256).max,
    payable(Alice)
);
```

The flow is:

```text
1. Read Alice's debt: 100 DAI principal + 3 DAI accrued interest = 103 DAI.
2. Read Alice's outstanding fee: 1 DAI.
3. Resolve “repay everything” to 104 DAI.
4. Allocate 1 DAI to the fee and 103 DAI to the debt.
5. Clear Alice's DAI borrow state and reduce the reserve's total borrows by 103 DAI.
6. Transfer 1 DAI from Alice to the token distributor.
7. Transfer 103 DAI from Alice back to LendingPoolCore.
8. Emit Repay with amountMinusFees = 103 DAI and fees = 1 DAI.
```

The final result is:

```text
Alice pays                 104 DAI
token distributor receives   1 DAI
LendingPoolCore receives   103 DAI
Alice's DAI debt             0 DAI
Alice's DAI fee              0 DAI
```

# Partial Repayment Example

With the same `103 DAI` debt and `1 DAI` fee, Alice repays `40 DAI`:

```solidity
lendingPool.repay(
    DAI,
    40 ether,
    payable(Alice)
);
```

The fee is paid first:

```text
payment                    = 40 DAI
fee paid                   =  1 DAI
debt repaid                = 39 DAI
remaining compounded debt  = 64 DAI
remaining fee              =  0 DAI
```

The `Repay` event records `39 DAI` as `_amountMinusFees`, `1 DAI` as `_fees`,
and `3 DAI` as the interest accrued since Alice's prior debt update.

# Repay Order

```text
validate reserve and amount
        ↓
read compounded debt, accrued interest, and outstanding fee
        ↓
resolve full or partial payment and validate ETH value
        ↓
apply payment to fee first
        ↓
LendingPoolCore updates borrower debt, reserve totals, and rates
        ↓
send fee to token distributor and debt portion to reserve liquidity
        ↓
emit Repay
```

If any validation, accounting update, fee transfer, or reserve transfer fails,
the entire repayment transaction reverts.

# Liquidating an Undercollateralized Position

## `liquidationCall`

```solidity
function liquidationCall(
    address _collateral,
    address _reserve,
    address _user,
    uint256 _purchaseAmount,
    bool _receiveAToken
) external payable nonReentrant onlyActiveReserve(_reserve) onlyActiveReserve(_collateral)
```

`liquidationCall()` lets any account repay part of an unhealthy borrower's debt
in exchange for that borrower's enabled collateral, plus the collateral
reserve's liquidation bonus. It is callable only when the borrower's global
health factor is below the liquidation threshold.

The parameters identify two different assets:

```text
_collateral      asset to seize from the borrower
_reserve         debt asset the liquidator will repay
_user            borrower being liquidated
_purchaseAmount  requested repayment, in units of _reserve
_receiveAToken   receive seized collateral as aTokens (true) or underlying (false)
```

Both selected reserves must be active. A reserve may be frozen: liquidation is
still allowed because it reduces protocol risk. The manager further requires
that the borrower has a balance of `_collateral`, that the reserve and borrower
have it enabled as collateral, and that the borrower has debt in `_reserve`.

## Delegated Liquidation Logic

`LendingPool` is the external entry point, but deliberately keeps liquidation
logic in the address-provider configured `LendingPoolLiquidationManager`:

```solidity
address liquidationManager =
    s_addressesProvider.getLendingPoolLiquidationManager();

(bool success, bytes memory result) = liquidationManager.delegatecall(
    abi.encodeCall(
        ILiquidationManager.liquidationCall,
        (_collateral, _reserve, _user, _purchaseAmount, _receiveAToken)
    )
);
```

`delegatecall` executes the manager's code in the `LendingPool`'s context:
the manager reads and updates the pool's storage and sees the original caller
as `msg.sender`. Thus the liquidator is the account that called
`LendingPool.liquidationCall()`, rather than the pool itself. The manager
returns `(errorCode, errorMessage)` instead of reverting for its expected
validation failures. The pool converts a non-zero code into
`LendingPool__LiquidationFailed(errorMessage)`; a failed delegate call becomes
`LendingPool__LiquidationCallFailed()`.

## Repayment and Collateral Amounts

The requested amount is not necessarily what the liquidator pays. The manager
first applies the fixed 50% close factor:

```text
maximum principal repayment = borrower's compounded debt × 50 / 100
actual repayment = min(_purchaseAmount, maximum principal repayment)
```

It then calculates the corresponding collateral using oracle prices and the
collateral reserve's liquidation bonus:

```text
collateral seized =
    debt-asset price × actual repayment
    / collateral-asset price
    × liquidation bonus / 100
```

For a `105` bonus, repaying debt worth `100` units of value entitles the
liquidator to collateral worth `105` units. If the borrower does not have
enough selected collateral, the manager seizes all of it and reduces the
repayment to the amount that collateral can support. The liquidator therefore
never pays the requested amount merely because it was supplied as
`_purchaseAmount`.

Any outstanding origination fee is handled separately. To the extent remaining
collateral can cover it, the manager seizes additional collateral (including
the same liquidation bonus), burns the matching borrower aTokens, and sends
that underlying collateral to the token distributor. This fee collateral is
not paid to the liquidator.

## Settlement Choices

After updating the debt, borrower, reserve, interest-rate, and timestamp
accounting, the manager settles the collateral according to `_receiveAToken`:

```text
true   transfer the borrower's collateral aTokens to the liquidator
false  burn the borrower's collateral aTokens and send underlying collateral
```

Receiving aTokens leaves the underlying in the reserve and gives the
liquidator the interest-bearing position. Receiving underlying requires the
reserve to have enough available liquidity for the liquidator's collateral
amount; otherwise the call reverts. This liquidity check does not apply to the
aToken path.

Finally, the liquidator pays `actual repayment` of `_reserve` into
`LendingPoolCore`. For an ERC20 debt asset, the liquidator must approve the
core to transfer that amount. For the native-ETH reserve, `msg.value` is
forwarded to the core and must cover the actual repayment.

## Example

Assume a borrower has `100 DAI` enabled as collateral and owes `0.02 WETH`.
DAI falls to `0.00025 ETH`, DAI's liquidation bonus is `105%`, and the
liquidator requests to repay all `0.02 WETH`:

```text
close-factor repayment = 0.02 WETH × 50% = 0.01 WETH
seized DAI = 0.01 ETH / 0.00025 ETH per DAI × 105% = 42 DAI
```

The liquidator pays `0.01 WETH`, not `0.02 WETH`. With
`_receiveAToken = false`, they receive `42 DAI` underlying; with
`_receiveAToken = true`, they receive `42 aDAI`. Any liquidatable origination
fee uses additional collateral left after those `42 DAI` and is sent to the
protocol's token distributor.


# Swapping Borrow Rate Modes

## `swapBorrowRateMode`

```solidity
function swapBorrowRateMode(address _reserve)
    external
    nonReentrant
    onlyActiveReserve(_reserve)
    onlyUnfreezedReserve(_reserve)
```

`swapBorrowRateMode()` lets a borrower move an existing loan from variable to
stable interest, or from stable to variable interest. It changes debt
accounting and the rate applied going forward; it neither transfers underlying
assets nor changes the borrowed amount apart from materializing interest that
has already accrued.

The call is protected against reentrancy and requires the reserve to be active
and not frozen. Unlike repayment and liquidation, a frozen reserve cannot have
its borrowers open a new rate position through a swap.

The pool first reads the caller's debt from the core:

```solidity
(
    uint256 principalBorrowBalance,
    uint256 compoundedBorrowBalance,
    uint256 borrowBalanceIncrease
) = s_core.getUserBorrowBalances(_reserve, msg.sender);
```

These values distinguish the debt at the previous user checkpoint from the
current interest-inclusive debt:

```text
principalBorrowBalance  debt recorded at the last debt update
compoundedBorrowBalance principal plus interest accrued since that update
borrowBalanceIncrease   compoundedBorrowBalance - principalBorrowBalance
```

If `compoundedBorrowBalance` is zero, the caller has no loan to swap and the
function reverts with `LendingPool__NoBorrowInProgress`.

## Variable-to-Stable Validation

The current mode comes from:

```solidity
s_core.getUserCurrentBorrowRateMode(_reserve, msg.sender)
```

When it is `VARIABLE`, the requested destination is stable, so the pool calls:

```solidity
s_core.isUserAllowedToBorrowAtStable(
    _reserve,
    msg.sender,
    compoundedBorrowBalance
)
```

This verifies that stable borrowing is enabled for the reserve and applies the
same-asset collateral restriction. In particular, it prevents a user from
using a large deposit of the borrowed asset as collateral to influence reserve
conditions, borrow at variable rate, and then lock in a stable rate. A failed
check reverts with `LendingPool__UserCannotBorrowAtStable`.

No equivalent stable-rate eligibility check is required for a stable-to-variable
swap. The special validation exists only because the destination rate is
stable.

## Core Accounting and Event

After validation, the pool delegates the accounting work to the core:

```solidity
(CoreLibrary.InterestRateMode newRateMode, uint256 newBorrowRate) =
    s_core.updateStateOnSwapRate(
        _reserve,
        msg.sender,
        principalBorrowBalance,
        compoundedBorrowBalance,
        borrowBalanceIncrease,
        currentRateMode
    );
```

`LendingPoolCore` checkpoints indexes, moves the interest-inclusive debt from
the old reserve-wide debt aggregate to the new one, updates the user's mode and
rate checkpoint, and recalculates reserve rates. See the LendingPoolCore swap
rate documentation for the detailed accounting flow.

Finally, the pool emits:

```solidity
Swap(
    _reserve,
    msg.sender,
    uint256(newRateMode),
    newBorrowRate,
    borrowBalanceIncrease,
    block.timestamp
);
```

The event exposes the selected new mode and rate, plus the interest that was
realized at the swap. This lets indexers reconstruct the rate transition
without treating the operation as a transfer of borrowed funds.

# Flash Loans

## `flashLoan`

```solidity
function flashLoan(address _receiver, address _reserve, uint256 _amount, bytes memory _params) external
```

`flashLoan()` lends reserve liquidity to a receiver contract for the remainder
of the current transaction. The receiver implements `IFlashLoanReceiver` and
uses its callback to perform its operation. Before that callback returns, it
must restore the borrowed principal and pay the flash-loan fee; otherwise the
whole transaction reverts.

The function is `nonReentrant`, requires an active reserve, and rejects a zero
loan amount. It reads the Core's actual ETH or ERC-20 balance before the loan
instead of its accounting-level available-liquidity value. This is both cheaper
and supplies the balance baseline used to prove repayment. If that balance is
smaller than `_amount`, the call reverts.

The parameters provider supplies the total and protocol fee rates in basis
points. The pool calculates them as:

```solidity
amountFee = _amount * totalFeeBips / 10_000;
protocolFee = amountFee * protocolFeeBips / 10_000;
```

Both calculated values must be nonzero. This prevents very small loans from
rounding their total fee or protocol share down to zero.

After transferring `_amount` from `LendingPoolCore` to `_receiver`, the pool
calls:

```solidity
receiver.executeOperation(_reserve, _amount, amountFee, _params);
```

`_params` is arbitrary data forwarded to the receiver, allowing a receiver to
configure its own transaction-specific operation. The receiver is responsible
for transferring the principal plus `amountFee` back to the Core during this
callback.

On return, the pool enforces an exact balance invariant:

```text
coreBalanceAfter == coreBalanceBefore + amountFee
```

Thus the principal must have been returned and the Core must have earned
exactly the quoted fee. A short repayment, an overpayment, or any other
unexpected Core balance change reverts with
`LendingPool__InconsistentProtocolBalance`.

Finally, `updateStateOnFlashLoan()` sends `protocolFee` to the token
distributor, credits the remaining fee to the reserve liquidity index for
aToken holders, and refreshes reserve rates and timestamps. The pool then
emits `FlashLoan`, recording the receiver, reserve, amount, total fee,
protocol fee, and timestamp.
