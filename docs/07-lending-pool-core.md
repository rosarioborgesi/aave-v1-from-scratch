# LendingPoolCore

`LendingPoolCore` is the accounting and custody layer of Aave V1.

The original Aave V1 whitepaper describes it as the center of the protocol because it:

- stores the state of every reserve;
- holds the assets deposited into the protocol;
- handles core accounting logic such as index accumulation and interest-rate updates.

Users normally interact with `LendingPool`, not directly with `LendingPoolCore`.

A useful mental model is:

```text
LendingPool
    = validates and coordinates user actions

LendingPoolCore
    = stores protocol state, updates accounting, and holds funds
```

`LendingPool` is responsible for checking whether an action is allowed. `LendingPoolCore` assumes that those checks have already happened and applies the corresponding state changes.

# Main Responsibilities

The current implementation of `LendingPoolCore` has four main responsibilities:

```text
1. Store global data for every reserve.
2. Store user-specific data for every reserve.
3. Hold deposited ERC20 tokens and ETH.
4. Update reserve indexes and interest rates when liquidity changes.
```

It also manages reserve initialization and exposes read functions used by other protocol components.

# Stored State

## `s_reserves`

```solidity
mapping(address asset => CoreLibrary.ReserveData reserveData)
    internal s_reserves;
```

This mapping stores the global accounting state of every reserve.

For example:

```text
s_reserves[DAI]
```

contains the DAI reserve's:

```text
liquidity index
variable borrow index
current interest rates
stable and variable borrows
collateral parameters
aToken address
interest-rate strategy
status flags
```

Each supported asset has one shared `ReserveData` object.

## `s_usersReserveData`

```solidity
mapping(
    address user =>
        mapping(
            address reserve =>
                CoreLibrary.UserReserveData userReserveData
        )
) internal s_usersReserveData;
```

This mapping stores each user's state for each reserve.

For example:

```text
s_usersReserveData[Alice][DAI]
```

contains Alice's DAI-specific:

```text
principal borrow balance
variable borrow checkpoint
origination fee
stable borrow rate
last update timestamp
use-as-collateral preference
```

A user therefore has separate state for every reserve they use.

## `s_reservesList`

```solidity
address[] private s_reservesList;
```

This array stores initialized reserve addresses so the protocol can enumerate them.

## `s_isReserveAdded`

```solidity
mapping(address reserve => bool isAdded)
    private s_isReserveAdded;
```

This mapping provides a constant-time membership check and prevents duplicate entries in `s_reservesList`.


# Deposit State Update

## `updateStateOnDeposit`

```solidity
function updateStateOnDeposit(
    address _reserve,
    address _user,
    uint256 _amount,
    bool _isFirstDeposit
) external onlyLendingPool
```

This function updates reserve and user state as part of a deposit.

It does not transfer the deposited tokens. Fund movement is handled separately by `transferToReserve()`.

The function performs three operations.

## 1. Accumulate Existing Interest

```solidity
s_reserves[_reserve].updateCumulativeIndexes();
```

Before adding new liquidity, the protocol updates the reserve's cumulative indexes.

This ensures that interest accumulated before the deposit is recorded using the old reserve state.

The new depositor must not receive interest that accrued before their deposit.

## 2. Recalculate Reserve Rates

```solidity
_updateReserveInterestRatesAndTimestamp(
    _reserve,
    _amount,
    0
);
```

A deposit adds liquidity, so the function passes:

```text
liquidityAdded = deposit amount
liquidityTaken = 0
```

The interest-rate strategy recalculates the reserve rates using the projected liquidity after the deposit.

## 3. Enable Collateral on the First Deposit

```solidity
if (_isFirstDeposit) {
    setUserUseReserveAsCollateral(
        _reserve,
        _user,
        true
    );
}
```

If this is the user's first deposit in the reserve, the deposit is automatically enabled as collateral.

This sets:

```text
s_usersReserveData[user][reserve].useAsCollateral = true
```

# Moving Deposited Funds

## `transferToReserve`

```solidity
function transferToReserve(
    address _reserve,
    address payable _user,
    uint256 _amount
) external payable onlyLendingPool
```

This function transfers the deposited asset into `LendingPoolCore`.

It supports both ERC20 reserves and the native ETH reserve.

# ERC20 Path

When the reserve is not ETH:

```solidity
if (_reserve != EthAddressLib.ethAddress()) {
```

the function first rejects any attached ETH:

```solidity
if (msg.value != 0) {
    revert LendingPoolCore__CantSendEthAndTransferErc20();
}
```

It then transfers the tokens:

```solidity
IERC20(_reserve).safeTransferFrom(
    _user,
    address(this),
    _amount
);
```

The user must approve `LendingPoolCore`, because the core is the contract executing `transferFrom`.

After the operation:

```text
user token balance decreases
core token balance increases
```

# ETH Path

For the ETH reserve, `msg.value` must be at least `_amount`:

```solidity
if (msg.value < _amount) {
    revert LendingPoolCore__MsgValueLessThanAmount();
}
```

If too much ETH is sent, the excess is refunded:

```solidity
uint256 excessAmount = msg.value - _amount;

(bool result,) =
    _user.call{value: excessAmount}("");
```

If the refund fails, the transaction reverts.

Example:

```text
deposit amount = 1 ETH
msg.value = 1.2 ETH

core keeps = 1 ETH
user receives refund = 0.2 ETH
```

# Redeem State Update

## `updateStateOnRedeem`

```solidity
function updateStateOnRedeem(
    address _reserve,
    address _user,
    uint256 _amountRedeemed,
    bool _userRedeemedEverything
) external onlyLendingPool
```

This function updates reserve and user state as part of a redeem.

It does not burn aTokens and it does not transfer the redeemed asset to the user. Those actions are coordinated by `LendingPool`; `LendingPoolCore` only updates accounting state and collateral preference.

The function performs three operations.

## 1. Accumulate Existing Interest

```solidity
s_reserves[_reserve].updateCumulativeIndexes();
```

Before liquidity leaves the reserve, the protocol updates the reserve's cumulative indexes.

This records supplier and variable-borrow interest that accrued before the redeem, using the reserve state that existed before liquidity was removed.

## 2. Recalculate Reserve Rates

```solidity
_updateReserveInterestRatesAndTimestamp(
    _reserve,
    0,
    _amountRedeemed
);
```

A redeem removes liquidity, so the function passes:

```text
liquidityAdded = 0
liquidityTaken = redeemed amount
```

The interest-rate strategy recalculates reserve rates using the projected liquidity after the redemption.

## 3. Disable Collateral After Full Redeem

```solidity
if (_userRedeemedEverything) {
    setUserUseReserveAsCollateral(
        _reserve,
        _user,
        false
    );
}
```

If the user redeemed their entire balance in that reserve, the reserve is no longer marked as collateral for that user.

This clears:

```text
s_usersReserveData[user][reserve].useAsCollateral
```

Partial redemptions leave the user's collateral preference unchanged.

# Moving Redeemed Funds

## `transferToUser`

```solidity
function transferToUser(
    address _reserve,
    address payable _user,
    uint256 _amount
) external onlyLendingPool
```

This function transfers reserve liquidity from `LendingPoolCore` to the user during operations such as redeem.

It supports both ERC20 reserves and the native ETH reserve.

# ERC20 Path

When the reserve is not ETH:

```solidity
if (_reserve != EthAddressLib.ethAddress()) {
```

the core sends tokens directly to the user:

```solidity
IERC20(_reserve).safeTransfer(_user, _amount);
```

After the operation:

```text
core token balance decreases
user token balance increases
```

# ETH Path

For the ETH reserve, the core sends native ETH:

```solidity
(bool result,) =
    _user.call{value: _amount, gas: 50000}("");
```

If the transfer fails, the transaction reverts with:

```solidity
LendingPoolCore__EthTransferFailed(_user, _amount)
```

The fixed gas stipend keeps the ETH transfer bounded while still allowing the receiver more than Solidity's old `transfer()` stipend.

# Borrow State Update

## `updateStateOnBorrow`

```solidity
function updateStateOnBorrow(
    address _reserve,
    address _user,
    uint256 _amountBorrowed,
    uint256 _borrowFee,
    CoreLibrary.InterestRateMode _rateMode
) external onlyLendingPool returns (uint256, uint256)
```

This is the core accounting entry point for an accepted borrow. It updates debt accounting before `LendingPool` transfers the underlying asset to the borrower with `transferToUser()`.

It assumes `LendingPool` has already validated the action. In particular, it does not itself verify reserve status, user collateral capacity, available liquidity, or whether stable borrowing is permitted.

The operation is performed in this order:

```text
1. Calculate the user's stored principal and interest accrued since their last debt update.
2. Update reserve indexes and global stable/variable debt totals.
3. Update the user's debt position, selected rate data, fee, and timestamp.
4. Recalculate reserve interest rates for the liquidity removed by the borrow.
```

The return values are:

```text
1. the borrower's current rate after the update
2. interest accrued on their previous debt before this borrow (`balanceIncrease`)
```

For a stable loan, the returned rate is the stable rate recorded on the user. For a variable loan, it is the reserve's current variable borrow rate.

## Worked Example: a First Stable Borrow After Time Has Passed

This example covers a user with **no existing debt** taking a stable-rate loan. It also deliberately lets one year pass since the reserve's previous update. That elapsed time affects the reserve-wide indexes because the reserve already has debt, but it does not create any historical debt or interest for the new borrower.

Amounts are shown in DAI and rates are simplified annual rates; the contract stores rates and indexes in ray precision. Assume Bob already has `5,000 DAI` of stable debt at the reserve's `7%` weighted average stable rate. Alice has never borrowed DAI. The reserve was last updated one year ago, and Alice now borrows `500 DAI` in stable mode with a `5 DAI` origination fee.

```text
Call:
updateStateOnBorrow(DAI, Alice, 500 DAI, 5 DAI, STABLE)

Before:
Alice principalBorrowBalance             = 0 DAI
Alice stableBorrowRate                   = 0
Alice lastUpdateTimestamp                = 0
Alice lastVariableBorrowCumulativeIndex  = 0

reserve liquidity index                  = 1.00
reserve variable borrow index            = 1.00
reserve lastUpdateTimestamp              = one year ago
reserve currentLiquidityRate             = 5%
reserve currentStableBorrowRate          = 9%
reserve currentVariableBorrowRate        = 10%
reserve totalBorrowsStable               = 5,000 DAI
reserve totalBorrowsVariable             = 0 DAI
reserve currentAverageStableBorrowRate   = 7%
core's DAI balance                       = 10,000 DAI
```

### 1. `getUserBorrowBalances()` finds no prior Alice debt

`updateStateOnBorrow()` starts with `getUserBorrowBalances(DAI, Alice)`. This is a view call: it calculates values but does not change storage.

Alice's stored `principalBorrowBalance` is zero, so the function returns immediately:

```text
principalBorrowBalance = 0 DAI
compoundedBalance      = 0 DAI
balanceIncrease        = 0 DAI
```

The one-year interval does not make Alice owe interest. Interest belongs to a debt position, and Alice has no previous principal, stable rate, or debt timestamp to compound. Her stable rate will only be set later in this transaction.

### 2. `_updateReserveStateOnBorrow()` checkpoints the old reserve state

`_updateReserveStateOnBorrow()` first calls `updateCumulativeIndexes()`. The reserve has `5,000 DAI` of total borrow debt, so it checkpoints the elapsed year using the **old** reserve rates:

```text
liquidity index       = 1.00 × (1 + 5%)    = 1.05
variable borrow index = 1.00 × 1.105170918 ≈ 1.105170918
```

The liquidity index records the year's supplier interest. The variable-borrow index also advances because `updateCumulativeIndexes()` checks whether *total* reserve borrowing is nonzero, not whether variable debt is nonzero. In this scenario there is only stable debt, so that variable-index update does not change any user's stable balance.

Checkpointing happens before the new `500 DAI` loan changes debt totals and before the reserve is repriced. Therefore the elapsed year is accounted for at the old `5%` liquidity and `10%` variable rates.

Next, `_updateReserveTotalBorrowsByRateMode()` reads Alice's previous mode. Since her stored principal is zero, `getUserCurrentBorrowRateMode()` returns `NONE`:

```text
previous rate mode = NONE
previous principal = 0 DAI
balanceIncrease    = 0 DAI
new borrow         = 500 DAI
updated principal  = 0 + 0 + 500 = 500 DAI
```

There is no old Alice debt to remove from either aggregate. Since the selected new mode is `STABLE`, the helper adds the complete `500 DAI` position to `totalBorrowsStable` at the reserve's current `9%` stable rate. It recomputes the weighted average stable rate:

```text
totalBorrowsStable = 5,000 + 500
                   = 5,500 DAI

new average stable rate =
    (5,000 × 7% + 500 × 9%) / 5,500
    ≈ 7.181818%

totalBorrowsVariable = 0 DAI
```

The reserve's stable aggregate rises by exactly `500 DAI`. Unlike an additional borrow, there is no Alice interest to materialize and no old Alice principal to remove first.

### 3. `_updateUserStateOnBorrow()` creates Alice's stable position

Because Alice chose `STABLE`, `_updateUserStateOnBorrow()` takes the reserve's currently stored stable rate (`9%`) and records it on Alice's new position. It clears the variable-index checkpoint, adds the borrowed amount and accrued interest to her principal, adds the origination fee, and writes the current timestamp:

```text
Alice stableBorrowRate                   = 9%
Alice lastVariableBorrowCumulativeIndex  = 0
Alice principalBorrowBalance             = 0 + 500 + 0 = 500 DAI
Alice originationFee                     = 0 + 5 = 5 DAI
Alice lastUpdateTimestamp                = block.timestamp
```

From this block onward, Alice's `500 DAI` stable principal accrues at her stored `9%` rate. The earlier one-year interval is not included in her position: her `lastUpdateTimestamp` begins now.

### 4. `_updateReserveInterestRatesAndTimestamp()` prices the new loan for future actions

`LendingPool` has not transferred the DAI to Alice yet, so `getReserveAvailableLiquidity()` still reads the core's actual `10,000 DAI` balance. `_updateReserveInterestRatesAndTimestamp()` accounts for the pending transfer by passing `_liquidityTaken = 500 DAI` to the strategy:

```text
liquidity supplied to strategy = 10,000 + 0 - 500 = 9,500 DAI
strategy inputs                = 9,500 DAI liquidity,
                                 5,500 DAI stable debt,
                                 0 DAI variable debt,
                                 7.181818% average stable rate
```

The concrete output depends on the configured strategy. For a `MockReserveInterestRateStrategy` example, suppose it is preset to return:

```text
new liquidity rate       = 4%  = 4e25 ray
new stable borrow rate   = 10% = 10e25 ray
new variable borrow rate = 11% = 11e25 ray
```

The core stores those three future reserve rates and sets `reserve.lastUpdateTimestamp` to `block.timestamp`. Alice's rate is already fixed at the `9%` rate that existed when her position was created. `_getUserCurrentBorrowRate()` therefore returns her stored rate, so this call returns:

```text
user borrow rate = 9% = 9e25 ray
balanceIncrease  = 0 DAI
```

The newly stored `10%` stable rate is the rate offered to later stable borrowers; it does not retroactively change Alice's loan. After this accounting call returns, `LendingPool` transfers the `500 DAI` to Alice. The core's actual DAI balance then becomes `9,500 DAI`, matching the liquidity used to calculate the new reserve rates.

## Worked Example: a First Variable Borrow After Time Has Passed

This is the equivalent first-borrow case for a variable-rate loan. Alice has **no existing DAI debt**, while Bob already has variable debt in the same reserve. One year has passed since the reserve was last updated. The elapsed time checkpoints Bob's and suppliers' reserve-wide indexes, but Alice has no prior position from which to accrue interest.

Amounts are shown in DAI and rates are simplified annual rates; the contract stores rates and indexes in ray precision. Assume Bob's and other users' stored variable principal totals `5,000 DAI`. Alice now borrows `500 DAI` in variable mode with a `5 DAI` origination fee.

```text
Call:
updateStateOnBorrow(DAI, Alice, 500 DAI, 5 DAI, VARIABLE)

Before:
Alice principalBorrowBalance             = 0 DAI
Alice stableBorrowRate                   = 0
Alice lastUpdateTimestamp                = 0
Alice lastVariableBorrowCumulativeIndex  = 0

reserve liquidity index                  = 1.00
reserve variable borrow index            = 1.00
reserve lastUpdateTimestamp              = one year ago
reserve currentLiquidityRate             = 5%
reserve currentStableBorrowRate          = 9%
reserve currentVariableBorrowRate        = 10%
reserve totalBorrowsStable               = 0 DAI
reserve totalBorrowsVariable             = 5,000 DAI
reserve currentAverageStableBorrowRate   = 0
core's DAI balance                       = 10,000 DAI
```

### 1. `getUserBorrowBalances()` finds no prior Alice debt

`updateStateOnBorrow()` calls `getUserBorrowBalances(DAI, Alice)` first. This is a view calculation and does not write storage. Since Alice's stored principal is zero, the function returns without using either her unset variable-index checkpoint or the reserve's current variable index:

```text
principalBorrowBalance = 0 DAI
compoundedBalance      = 0 DAI
balanceIncrease        = 0 DAI
```

Alice does not pay for the preceding year. Variable interest is calculated by scaling an existing principal from that user's last variable-index checkpoint; Alice has neither an existing principal nor a checkpointed position yet.

### 2. `_updateReserveStateOnBorrow()` checkpoints existing variable debt and adds Alice's debt

`_updateReserveStateOnBorrow()` first calls `updateCumulativeIndexes()`. Because the reserve's total borrows are nonzero, it writes the interest accrued during the year using the **old** reserve rates:

```text
liquidity index       = 1.00 × (1 + 5%)    = 1.05
variable borrow index = 1.00 × 1.105170918 ≈ 1.105170918
```

The liquidity index captures the year's supplier income. The variable-borrow index captures the year's variable-debt growth for Bob and any other existing variable borrowers. It is written before Alice's new borrow changes utilization and therefore before the strategy produces future rates.

Next, `_updateReserveTotalBorrowsByRateMode()` reads Alice's previous mode. `getUserCurrentBorrowRateMode()` returns `NONE`, because her stored principal is still zero:

```text
previous rate mode = NONE
previous principal = 0 DAI
balanceIncrease    = 0 DAI
new borrow         = 500 DAI
updated principal  = 0 + 0 + 500 = 500 DAI
```

There is no old Alice principal to remove from either debt aggregate. The selected mode is `VARIABLE`, so the complete updated position is added to the variable aggregate:

```text
totalBorrowsStable   = 0 DAI
totalBorrowsVariable = 5,000 + 500
                     = 5,500 DAI
```

The stored variable total increases by exactly the new `500 DAI` loan. It does not maintain a weighted average rate because all variable positions use the common reserve variable-borrow index.

### 3. `_updateUserStateOnBorrow()` creates Alice's variable position

Because Alice selected `VARIABLE`, `_updateUserStateOnBorrow()` clears her stable rate and stores the reserve's **newly checkpointed** variable-borrow index as her starting point. It then records the principal, fee, and timestamp:

```text
Alice stableBorrowRate                   = 0
Alice lastVariableBorrowCumulativeIndex  ≈ 1.105170918
Alice principalBorrowBalance             = 0 + 500 + 0 = 500 DAI
Alice originationFee                     = 0 + 5 = 5 DAI
Alice lastUpdateTimestamp                = block.timestamp
```

Saving `1.105170918` is essential: it means Alice's future variable debt starts at the index after the past year was checkpointed. A later balance calculation scales her `500 DAI` only by index growth **after this borrow**, so Bob's earlier year of interest is not charged to Alice.

### 4. `_updateReserveInterestRatesAndTimestamp()` prices the post-borrow reserve

The underlying transfer has not happened yet. `getReserveAvailableLiquidity()` still sees `10,000 DAI` in the core, so `_updateReserveInterestRatesAndTimestamp()` passes the pending `500 DAI` transfer as `_liquidityTaken` to price the post-borrow state:

```text
liquidity supplied to strategy = 10,000 + 0 - 500 = 9,500 DAI
strategy inputs                = 9,500 DAI liquidity,
                                 0 DAI stable debt,
                                 5,500 DAI variable debt,
                                 0 average stable rate
```

The actual rates come from the reserve's configured strategy. For a `MockReserveInterestRateStrategy` example, suppose it is preset to return:

```text
new liquidity rate       = 3% = 3e25 ray
new stable borrow rate   = 6% = 6e25 ray
new variable borrow rate = 7% = 7e25 ray
```

The core stores these values and sets `reserve.lastUpdateTimestamp` to `block.timestamp`. Finally, `_getUserCurrentBorrowRate()` sees Alice's `VARIABLE` mode and returns the reserve's newly stored variable rate:

```text
user borrow rate = 7% = 7e25 ray
balanceIncrease  = 0 DAI
```

The old `10%` variable rate was used only to checkpoint the year before Alice borrowed. The new `7%` rate applies to variable borrowing from this point onward, including Alice's position. `LendingPool` then transfers `500 DAI` to Alice, leaving the core with `9,500 DAI`, the same liquidity amount used to calculate the new rates.

## Worked Example: an Additional Stable Borrow

This example follows the same entry point when Alice already has stable debt and takes an additional stable loan. Amounts are shown in DAI and rates are simplified annual rates; the contract stores rates and indexes in ray precision.

Alice has `1,000 DAI` of stable debt at her personal `8%` stable rate. Her position and the reserve were last updated one year ago. The reserve has `5,000 DAI` of stored stable debt, including Alice's `1,000 DAI`, and its weighted average stable borrow rate is `7%`. The current stable rate offered by the reserve is `9%`. Alice borrows another `500 DAI` in stable mode and pays a `5 DAI` origination fee.

```text
Call:
updateStateOnBorrow(DAI, Alice, 500 DAI, 5 DAI, STABLE)

Before:
Alice principalBorrowBalance             = 1,000 DAI
Alice stableBorrowRate                   = 8%
Alice lastUpdateTimestamp                = one year ago
Alice lastVariableBorrowCumulativeIndex  = 0

reserve liquidity index                  = 1.00
reserve variable borrow index            = 1.00
reserve lastUpdateTimestamp              = one year ago
reserve currentLiquidityRate             = 5%
reserve currentStableBorrowRate          = 9%
reserve currentVariableBorrowRate        = 10%
reserve totalBorrowsStable               = 5,000 DAI
reserve totalBorrowsVariable             = 0 DAI
reserve currentAverageStableBorrowRate   = 7%
core's DAI balance                       = 10,000 DAI
```

### 1. `getUserBorrowBalances()` accrues Alice's personal stable rate

`getUserBorrowBalances(DAI, Alice)` is a view call, so it does not write storage. A stable borrower does **not** use the reserve variable-borrow index. Instead, `CoreLibrary.getCompoundedBorrowBalance()` compounds Alice's stored principal using her own stored `stableBorrowRate` and her own `lastUpdateTimestamp`:

```text
stable interest factor  = (1 + 8% per year) ^ 1 year
                        ≈ 1.083287068

compounded balance      = 1,000 × 1.083287068
                        ≈ 1,083.287068 DAI
balanceIncrease         ≈ 1,083.287068 - 1,000
                        ≈    83.287068 DAI
```

Thus `updateStateOnBorrow()` receives a stored principal of `1,000 DAI` and a `balanceIncrease` of approximately `83.287068 DAI`. The reserve's current `9%` stable rate does not retroactively change this result: Alice's old debt accrued at the `8%` rate locked into her position.

### 2. `_updateReserveStateOnBorrow()` checkpoints the reserve and updates stable debt

`_updateReserveStateOnBorrow()` first calls `updateCumulativeIndexes()`. Because the reserve has outstanding debt, this checkpoints its shared indexes using the old reserve-wide rates:

```text
liquidity index       = 1.00 × (1 + 5%)    = 1.05
variable borrow index = 1.00 × 1.105170918 ≈ 1.105170918
```

The variable index advances even though Alice is stable because `updateCumulativeIndexes()` is reserve-wide and the reserve has total borrows. It does not affect Alice's stable balance; stable debt is accrued from each user's stored rate and timestamp. These indexes must be checkpointed before the new borrow changes liquidity and the strategy sets future rates.

Next, `_updateReserveTotalBorrowsByRateMode()` identifies Alice's previous mode as `STABLE`. It removes her old `1,000 DAI` principal from the stable aggregate and recalculates the average rate of the remaining stable debt:

```text
remaining stable debt = 5,000 - 1,000 = 4,000 DAI

remaining average rate = (5,000 × 7% - 1,000 × 8%) / 4,000
                       = 6.75%
```

The helper then calculates Alice's complete updated debt and adds it to the stable aggregate at the reserve's current `9%` stable rate:

```text
updated principal = 1,000 + 83.287068 + 500
                  ≈ 1,583.287068 DAI

totalBorrowsStable = 4,000 + 1,583.287068
                   ≈ 5,583.287068 DAI

new average stable rate =
    (4,000 × 6.75% + 1,583.287068 × 9%) / 5,583.287068
    ≈ 7.388046%
```

The total stable debt increases by approximately `583.287068 DAI`: Alice's materialized interest plus her new `500 DAI` loan. Removing her old principal first prevents it from being counted twice.

### 3. `_updateUserStateOnBorrow()` records Alice's new stable position

Because Alice selected `STABLE`, the helper replaces her old `8%` rate with the reserve's current `9%` stable rate. It clears her variable-index checkpoint, materializes the accrued interest into principal, adds the fee, and writes the timestamp:

```text
Alice stableBorrowRate                   = 9%
Alice lastVariableBorrowCumulativeIndex  = 0
Alice principalBorrowBalance             ≈ 1,583.287068 DAI
Alice originationFee                     += 5 DAI
Alice lastUpdateTimestamp                = block.timestamp
```

The `9%` rate applies to Alice's complete updated stable balance from this point onward. Her prior year remains accounted for at `8%`.

### 4. `_updateReserveInterestRatesAndTimestamp()` sets rates for future actions

The underlying tokens have not yet been transferred. The strategy receives the post-borrow projected liquidity and the new debt totals:

```text
liquidity supplied to strategy = 10,000 - 500 = 9,500 DAI
strategy inputs                = 9,500 DAI liquidity,
                                 5,583.287068 DAI stable debt,
                                 0 DAI variable debt,
                                 7.388046% average stable rate
```

The concrete rates depend on the configured strategy. For a `MockReserveInterestRateStrategy` example, suppose it is preset to return:

```text
new liquidity rate       = 4%  = 4e25 ray
new stable borrow rate   = 10% = 10e25 ray
new variable borrow rate = 11% = 11e25 ray
```

The core stores those three values and sets `reserve.lastUpdateTimestamp` to `block.timestamp`. They apply to the reserve from now on.

Finally, `_getUserCurrentBorrowRate()` sees Alice's `STABLE` mode and returns **her stored stable rate**, not the reserve's newly returned `10%` stable rate. Therefore this `updateStateOnBorrow()` call returns:

```text
user borrow rate = 9% = 9e25 ray
balanceIncrease  ≈ 83.287068 DAI
```

The `10%` rate is offered to later stable borrows; Alice's updated position remains at `9%` unless another operation changes it. `LendingPool` then transfers her `500 DAI`.

## Worked Example: an Additional Variable Borrow

The following example follows every call made by `updateStateOnBorrow()` for one transaction. Amounts are shown in DAI and rates are simplified annual rates; the contract stores rates and indexes in ray precision.

Alice already has `1,000 DAI` of variable debt. Her debt was last materialized a year ago, when the variable-borrow index was `1.00`. The reserve has not been updated since then. During that year, its old liquidity rate is `5%` and its old variable-borrow rate is `10%`. Alice now borrows another `500 DAI` in variable mode with a `5 DAI` origination fee. The core currently holds `10,000 DAI` of liquid DAI; the reserve has no stable debt and its stored variable debt total is `5,000 DAI`, including Alice's stored `1,000 DAI` principal.

```text
Call:
updateStateOnBorrow(DAI, Alice, 500 DAI, 5 DAI, VARIABLE)

Before:
Alice principalBorrowBalance             = 1,000 DAI
Alice lastVariableBorrowCumulativeIndex  = 1.00
reserve liquidity index                  = 1.00
reserve variable borrow index            = 1.00
reserve lastUpdateTimestamp              = one year ago
reserve currentLiquidityRate             = 5%
reserve currentVariableBorrowRate        = 10%
reserve totalBorrowsVariable             = 5,000 DAI
core's DAI balance                       = 10,000 DAI
```

### 1. `getUserBorrowBalances()` reads Alice's debt including accrued interest

`getUserBorrowBalances(DAI, Alice)` is a view call, so it does not change storage. Because Alice is a variable borrower, `CoreLibrary.getCompoundedBorrowBalance()` first calculates the index's growth from `lastUpdateTimestamp` to the current block using the old `10%` variable rate. It then scales Alice's stored principal by that current, not-yet-stored index:

```text
current variable index = 1.00 × 1.105170918 = 1.105170918

compounded balance = 1,000 × 1.105170918 / 1.00
                   ≈ 1,105.170918 DAI
balanceIncrease    ≈ 1,105.170918 - 1,000
                   ≈   105.170918 DAI
```

So `updateStateOnBorrow()` receives `principalBorrowBalance = 1,000 DAI` and `balanceIncrease ≈ 105.170918 DAI`. That accrued interest is still only calculated at this point; the later helpers write it into reserve and user state.

### 2. `_updateReserveStateOnBorrow()` updates indexes and reserve debt totals

This helper first calls `updateCumulativeIndexes()`. Unlike the preceding view calculation, this call writes the year of interest into the reserve's stored indexes, still using the old rates:

```text
liquidity index       = 1.00 × (1 + 5%)    = 1.05
variable borrow index = 1.00 × 1.105170918 ≈ 1.105170918
```

The variable index now equals the effective current index used to calculate Alice's `balanceIncrease` in step 1. This is why `_updateUserStateOnBorrow()` can safely store `1.105170918` as Alice's next variable-debt checkpoint. Checkpointing happens before the new borrow changes debt totals, removes liquidity, and causes new rates to be calculated for future time.

It then calls `_updateReserveTotalBorrowsByRateMode()`. Alice's previous mode is `VARIABLE`, so the helper removes her old stored principal from the variable total, calculates her complete updated principal, and adds it back to the selected variable bucket:

```text
updated principal = 1,000 + 105.170918 + 500
                  ≈ 1,605.170918 DAI

totalBorrowsVariable = 5,000 - 1,000 + 1,605.170918
                     ≈ 5,605.170918 DAI
```

The increase is approximately `605.170918 DAI`: the materialized interest plus the `500 DAI` of new debt. Separating the removal and addition avoids counting Alice's old `1,000 DAI` twice.

### 3. `_updateUserStateOnBorrow()` checkpoints Alice's new position

Because the selected mode is `VARIABLE`, this helper clears Alice's stable rate and records the reserve's current variable-borrow index as her new checkpoint. It also materializes the interest into principal, accumulates the fee, and writes the timestamp:

```text
Alice stableBorrowRate                   = 0
Alice lastVariableBorrowCumulativeIndex  ≈ 1.105170918
Alice principalBorrowBalance             ≈ 1,605.170918 DAI
Alice originationFee                     += 5 DAI
Alice lastUpdateTimestamp                = block.timestamp
```

From now on, interest on approximately `1,605.170918 DAI` is measured relative to index `1.105170918`.

### 4. `_updateReserveInterestRatesAndTimestamp()` prices the liquidity removal

The tokens have not yet been transferred: `LendingPool` calls `transferToUser()` only after this function returns. `getReserveAvailableLiquidity()` therefore still reads the core's `10,000 DAI` balance. The helper compensates by passing `_liquidityTaken = 500 DAI` to the interest-rate strategy:

```text
liquidity supplied to strategy = 10,000 + 0 - 500 = 9,500 DAI
strategy inputs                = 9,500 DAI liquidity, 0 DAI stable debt,
                                 5,605.170918 DAI variable debt, current average stable rate
```

`calculateInterestRates()` returns the new liquidity, stable-borrow, and variable-borrow rates for that post-borrow state. The core stores all three rates, sets `reserve.lastUpdateTimestamp`, and emits `ReserveUpdated`.

### Example strategy response and returned user rate

The concrete rates depend on the reserve's configured strategy. The test strategy in this repository, `MockReserveInterestRateStrategy`, is configurable: it returns preset values and does not derive them from the inputs above. For example, suppose it is configured to return:

```text
new liquidity rate       = 3% = 3e25 ray
new stable borrow rate   = 6% = 6e25 ray
new variable borrow rate = 7% = 7e25 ray
```

For the post-borrow inputs above, its return value is therefore:

```solidity
(3e25, 6e25, 7e25)
```

`_updateReserveInterestRatesAndTimestamp()` stores those values:

```text
reserve.currentLiquidityRate       = 3%
reserve.currentStableBorrowRate    = 6%
reserve.currentVariableBorrowRate  = 7%
reserve.lastUpdateTimestamp        = block.timestamp
```

Finally, `_getUserCurrentBorrowRate()` sees that Alice's position is in `VARIABLE` mode and returns `reserve.currentVariableBorrowRate`. In this example, `updateStateOnBorrow()` therefore returns a user borrow rate of `7%` (`7e25 ray`) and the earlier approximately `105.170918 DAI` `balanceIncrease`.

The old `10%` variable rate is used only to accrue the year before Alice's borrow. The new `7%` rate applies from this borrow onward. `LendingPool` then transfers the `500 DAI` to Alice, making the core's actual DAI balance match the `9,500 DAI` liquidity used for repricing.

## Worked Example: Switch From Stable Debt to Variable Debt After Time Has Passed

This example follows a borrower who already has stable debt and takes a new variable-rate borrow. In this implementation, the new borrow rate mode applies to the user's **complete updated debt position**. Therefore Alice's old stable principal, its accrued stable interest, and the new amount all leave the stable aggregate and enter the variable aggregate.

Amounts are shown in DAI and rates are simplified annual rates; the contract stores rates and indexes in ray precision. Alice has `1,000 DAI` of stable debt at her personal `8%` stable rate. Her position and the reserve were last updated one year ago. The reserve's `5,000 DAI` stable-debt total includes Alice's stored `1,000 DAI`; its average stable rate is `7%`. Other borrowers have `2,000 DAI` of variable debt. Alice now borrows another `500 DAI` in variable mode and pays a `5 DAI` origination fee.

```text
Call:
updateStateOnBorrow(DAI, Alice, 500 DAI, 5 DAI, VARIABLE)

Before:
Alice principalBorrowBalance             = 1,000 DAI
Alice stableBorrowRate                   = 8%
Alice lastUpdateTimestamp                = one year ago
Alice lastVariableBorrowCumulativeIndex  = 0

reserve liquidity index                  = 1.00
reserve variable borrow index            = 1.00
reserve lastUpdateTimestamp              = one year ago
reserve currentLiquidityRate             = 5%
reserve currentStableBorrowRate          = 9%
reserve currentVariableBorrowRate        = 10%
reserve totalBorrowsStable               = 5,000 DAI
reserve totalBorrowsVariable             = 2,000 DAI
reserve currentAverageStableBorrowRate   = 7%
core's DAI balance                       = 10,000 DAI
```

### 1. `getUserBorrowBalances()` accrues Alice's old stable position

`getUserBorrowBalances(DAI, Alice)` is a view call, so it writes nothing. Alice's current mode is `STABLE`, because her stored principal is nonzero and `stableBorrowRate` is `8%`. Her old debt compounds using her personal stable rate and her own debt timestamp, rather than the reserve variable-borrow index:

```text
stable interest factor  = (1 + 8% per year) ^ 1 year
                        ≈ 1.083287068

compounded balance      = 1,000 × 1.083287068
                        ≈ 1,083.287068 DAI
balanceIncrease         ≈ 1,083.287068 - 1,000
                        ≈    83.287068 DAI
```

Thus the outer function receives `principalBorrowBalance = 1,000 DAI` and `balanceIncrease ≈ 83.287068 DAI`. The reserve's old `10%` variable rate does not affect Alice's past year: until this transaction, her entire position was stable at `8%`.

### 2. `_updateReserveStateOnBorrow()` checkpoints indexes and moves the complete position

First, `_updateReserveStateOnBorrow()` calls `updateCumulativeIndexes()`. The reserve has outstanding stable and variable debt, so its shared indexes record the elapsed year using the old reserve-wide rates:

```text
liquidity index       = 1.00 × (1 + 5%)    = 1.05
variable borrow index = 1.00 × 1.105170918 ≈ 1.105170918
```

The liquidity index accounts for supplier income. The variable index accounts for the pre-existing variable borrowers' debt growth. Alice is still a stable borrower during this checkpoint, so the variable index does not calculate her prior `83.287068 DAI` of interest; that amount came from her own `8%` stable rate in step 1.

The helper then calls `_updateReserveTotalBorrowsByRateMode()`. Alice's previous mode is `STABLE`, so it first removes her **stored** `1,000 DAI` principal from the stable aggregate and removes its `8%` weight from the stable average:

```text
remaining stable debt = 5,000 - 1,000 = 4,000 DAI

remaining average stable rate =
    (5,000 × 7% - 1,000 × 8%) / 4,000
    = 6.75%
```

It then builds Alice's complete updated position and, because the selected new mode is `VARIABLE`, adds that position to the variable aggregate:

```text
updated principal = 1,000 + 83.287068 + 500
                  ≈ 1,583.287068 DAI

totalBorrowsStable   = 4,000 DAI
totalBorrowsVariable = 2,000 + 1,583.287068
                     ≈ 3,583.287068 DAI
```

The two aggregate totals together increase by only `583.287068 DAI`: Alice's materialized stable interest plus the new `500 DAI`. Her original `1,000 DAI` is moved, not duplicated. `currentAverageStableBorrowRate` remains `6.75%`, because Alice's complete updated position now belongs to the variable bucket.

### 3. `_updateUserStateOnBorrow()` converts Alice's position to variable mode

Because the selected mode is `VARIABLE`, `_updateUserStateOnBorrow()` clears the old stable rate and saves the reserve's newly checkpointed variable index as Alice's starting index. It also materializes her prior stable interest into principal, adds the new loan and fee, and updates her timestamp:

```text
Alice stableBorrowRate                   = 0
Alice lastVariableBorrowCumulativeIndex  ≈ 1.105170918
Alice principalBorrowBalance             ≈ 1,583.287068 DAI
Alice originationFee                     += 5 DAI
Alice lastUpdateTimestamp                = block.timestamp
```

This is the mode-switch boundary. Alice's preceding year has already been charged at `8%` and included in her principal. From this block onward, her complete `1,583.287068 DAI` position grows relative to index `1.105170918`, using the reserve's variable rate from future time.

### 4. `_updateReserveInterestRatesAndTimestamp()` prices the post-switch borrow

`LendingPool` has not transferred the `500 DAI` yet. The core still holds `10,000 DAI`, so `_updateReserveInterestRatesAndTimestamp()` subtracts the pending transfer through `_liquidityTaken` when it calls the strategy:

```text
liquidity supplied to strategy = 10,000 + 0 - 500 = 9,500 DAI
strategy inputs                = 9,500 DAI liquidity,
                                 4,000 DAI stable debt,
                                 3,583.287068 DAI variable debt,
                                 6.75% average stable rate
```

For a `MockReserveInterestRateStrategy` example, suppose the strategy is preset to return:

```text
new liquidity rate       = 3% = 3e25 ray
new stable borrow rate   = 6% = 6e25 ray
new variable borrow rate = 7% = 7e25 ray
```

The core stores these future reserve rates and sets `reserve.lastUpdateTimestamp` to `block.timestamp`. `_getUserCurrentBorrowRate()` now sees that Alice is in `VARIABLE` mode, so it returns the newly stored reserve variable rate:

```text
user borrow rate = 7% = 7e25 ray
balanceIncrease  ≈ 83.287068 DAI
```

The old `10%` variable rate was used only to checkpoint existing variable borrowers through the past year. The new `7%` variable rate applies to Alice after her switch; it does not alter the prior year of `8%` stable accrual. `LendingPool` then transfers Alice's newly borrowed `500 DAI`, leaving `9,500 DAI` in core liquidity.

## Worked Example: Switch From Variable Debt to Stable Debt After Time Has Passed

This is the reciprocal mode switch. Alice already has variable debt and takes a new stable-rate borrow after one year. The variable index first materializes the interest on her old variable position. Then the helper moves Alice's complete updated debt from the variable aggregate into the stable aggregate, where it receives the reserve's currently offered stable rate.

Amounts are shown in DAI and rates are simplified annual rates; the contract stores rates and indexes in ray precision. Alice has `1,000 DAI` of variable debt, recorded when the variable-borrow index was `1.00`. Her position and the reserve were last updated one year ago. The reserve's `5,000 DAI` variable-debt total includes Alice's stored `1,000 DAI`; other borrowers have `2,000 DAI` of stable debt at a `7%` average stable rate. Alice now borrows another `500 DAI` in stable mode and pays a `5 DAI` origination fee.

```text
Call:
updateStateOnBorrow(DAI, Alice, 500 DAI, 5 DAI, STABLE)

Before:
Alice principalBorrowBalance             = 1,000 DAI
Alice stableBorrowRate                   = 0
Alice lastUpdateTimestamp                = one year ago
Alice lastVariableBorrowCumulativeIndex  = 1.00

reserve liquidity index                  = 1.00
reserve variable borrow index            = 1.00
reserve lastUpdateTimestamp              = one year ago
reserve currentLiquidityRate             = 5%
reserve currentStableBorrowRate          = 9%
reserve currentVariableBorrowRate        = 10%
reserve totalBorrowsStable               = 2,000 DAI
reserve totalBorrowsVariable             = 5,000 DAI
reserve currentAverageStableBorrowRate   = 7%
core's DAI balance                       = 10,000 DAI
```

### 1. `getUserBorrowBalances()` materializes Alice's old variable interest in memory

`getUserBorrowBalances(DAI, Alice)` is a view call. Alice's principal is nonzero and her `stableBorrowRate` is zero, so `getUserCurrentBorrowRateMode()` identifies her as a `VARIABLE` borrower. `CoreLibrary.getCompoundedBorrowBalance()` calculates the current variable index in memory using the old `10%` variable rate, then scales Alice's principal from her saved `1.00` checkpoint:

```text
current variable index = 1.00 × 1.105170918
                       = 1.105170918

compounded balance = 1,000 × 1.105170918 / 1.00
                   ≈ 1,105.170918 DAI
balanceIncrease    ≈ 1,105.170918 - 1,000
                   ≈   105.170918 DAI
```

At this stage nothing has been written. The outer function receives Alice's stored `1,000 DAI` principal and the approximately `105.170918 DAI` of variable interest that must be materialized as part of the switch.

### 2. `_updateReserveStateOnBorrow()` checkpoints the reserve and moves Alice's debt

`_updateReserveStateOnBorrow()` first calls `updateCumulativeIndexes()`. Since the reserve has outstanding debt, it writes the elapsed year's growth using the old rates:

```text
liquidity index       = 1.00 × (1 + 5%)    = 1.05
variable borrow index = 1.00 × 1.105170918 ≈ 1.105170918
```

The stored variable index now matches the in-memory index from step 1. This locks in the past year for Alice and the other variable borrowers before Alice's switch changes the debt mix and before the strategy sets new rates.

Next, `_updateReserveTotalBorrowsByRateMode()` sees Alice's previous `VARIABLE` mode. It removes only her old stored `1,000 DAI` principal from `totalBorrowsVariable`; variable debt does not require an average-rate adjustment:

```text
remaining variable debt = 5,000 - 1,000 = 4,000 DAI
```

The helper then calculates Alice's complete updated debt and adds it to the selected `STABLE` bucket at the reserve's current `9%` stable rate:

```text
updated principal = 1,000 + 105.170918 + 500
                  ≈ 1,605.170918 DAI

totalBorrowsVariable = 4,000 DAI
totalBorrowsStable   = 2,000 + 1,605.170918
                     ≈ 3,605.170918 DAI

new average stable rate =
    (2,000 × 7% + 1,605.170918 × 9%) / 3,605.170918
    ≈ 7.8905%
```

The reserve's total debt increases by approximately `605.170918 DAI`: Alice's materialized variable interest plus her new `500 DAI` loan. Her old `1,000 DAI` is transferred from the variable bucket to the stable bucket rather than counted twice.

### 3. `_updateUserStateOnBorrow()` converts Alice's position to stable mode

The selected mode is `STABLE`, so `_updateUserStateOnBorrow()` stores the reserve's current `9%` stable rate and clears Alice's variable-index checkpoint. It adds the previously calculated interest and new amount into principal, adds the fee, and writes the new timestamp:

```text
Alice stableBorrowRate                   = 9%
Alice lastVariableBorrowCumulativeIndex  = 0
Alice principalBorrowBalance             ≈ 1,605.170918 DAI
Alice originationFee                     += 5 DAI
Alice lastUpdateTimestamp                = block.timestamp
```

The mode switch is now complete. Alice's past year is included in her principal at the old variable rate, while her entire updated principal will accrue from this timestamp at her newly stored `9%` stable rate. The reserve variable index no longer applies to Alice's debt.

### 4. `_updateReserveInterestRatesAndTimestamp()` prices the post-switch state

The underlying transfer still has not occurred. `getReserveAvailableLiquidity()` returns the core's actual `10,000 DAI` balance, so the helper subtracts the pending `500 DAI` through `_liquidityTaken` when calling the interest-rate strategy:

```text
liquidity supplied to strategy = 10,000 + 0 - 500 = 9,500 DAI
strategy inputs                = 9,500 DAI liquidity,
                                 3,605.170918 DAI stable debt,
                                 4,000 DAI variable debt,
                                 7.8905% average stable rate
```

For a `MockReserveInterestRateStrategy` example, suppose the strategy is preset to return:

```text
new liquidity rate       = 3% = 3e25 ray
new stable borrow rate   = 6% = 6e25 ray
new variable borrow rate = 7% = 7e25 ray
```

The core stores these rates and sets `reserve.lastUpdateTimestamp` to `block.timestamp`. Finally, `_getUserCurrentBorrowRate()` sees Alice's `STABLE` mode and returns her stored stable rate, not the strategy's new stable rate:

```text
user borrow rate = 9% = 9e25 ray
balanceIncrease  ≈ 105.170918 DAI
```

The old `10%` variable rate was used only to accrue the year before the switch. The new `6%` stable rate is offered to later stable borrows; it does not change Alice's newly recorded `9%` rate. `LendingPool` then transfers `500 DAI` to Alice, leaving the core with `9,500 DAI` of liquid DAI.

## `_updateReserveStateOnBorrow`

```solidity
function _updateReserveStateOnBorrow(...) internal
```

This helper applies the reserve-side effects of a borrow.

First, `updateCumulativeIndexes()` materializes interest accrued since the reserve's previous update into the liquidity and variable-borrow indexes. It then delegates to `_updateReserveTotalBorrowsByRateMode()` to reflect the borrower's complete updated debt in the reserve totals.

It deliberately operates before rates are recalculated: previously accrued interest must use the rates and indexes that existed before the new liquidity is removed.

### Example 1: first stable borrow

Assume a user has no debt and borrows `100 DAI` at a stable rate. No time has passed since the reserve was last updated.

```text
Before:
liquidity index        = 1.00 ray
variable borrow index  = 1.00 ray
total stable borrows   = 0 DAI
total variable borrows = 0 DAI

After _updateReserveStateOnBorrow(..., 0, 0, 100 DAI, STABLE):
liquidity index        = 1.00 ray  (no elapsed time, so no interest to materialize)
variable borrow index  = 1.00 ray
total stable borrows   = 100 DAI
total variable borrows = 0 DAI
```

The helper only updates reserve-level state. The separate `_updateUserStateOnBorrow()` call records the `100 DAI` principal, stable rate, fee, and timestamp on the user's position.

### Example 2: switch variable debt to stable debt after interest accrues

Assume the reserve has a `5%` liquidity rate and a `10%` variable borrow rate. A user is the only variable borrower with `100 DAI` of principal. One year passes, then the user borrows another `10 DAI` at stable rate. The caller has already calculated `5 DAI` of accrued interest on the user's previous debt.

```text
Before the borrow:
liquidity index        = 1.00 ray
variable borrow index  = 1.00 ray
total stable borrows   = 0 DAI
total variable borrows = 100 DAI

Updated user principal = 100 + 5 + 10 = 115 DAI
```

`_updateReserveStateOnBorrow()` first materializes the year of interest using the old rates:

```text
liquidity index        = 1.00 × 1.05 = 1.05 ray
variable borrow index  ≈ 1.00 × 1.105170918 = 1.105170918 ray
```

It then moves the user's debt between the reserve aggregates:

```text
total variable borrows = 100 - 100 = 0 DAI
total stable borrows   = 0 + 115 = 115 DAI
```

The key ordering is: accrue old interest first, then move/add the updated debt. Later in `updateStateOnBorrow()`, the core updates the user's position and recalculates the reserve's rates for the newly removed liquidity.

## `_updateReserveTotalBorrowsByRateMode`

```solidity
function _updateReserveTotalBorrowsByRateMode(...) internal
```

Reserves track stable and variable debt separately. This helper preserves those totals when a user takes an additional loan or changes rate mode.

It derives the user's previous mode from their stored position, removes their old principal from that mode's aggregate, and computes:

```text
updated user principal = previous principal + accrued interest + newly borrowed amount
```

It then adds the entire updated principal to the newly selected mode:

```text
stable mode:   updates total stable borrows and the weighted average stable rate
variable mode: updates total variable borrows
```

This remove-then-add approach handles both an additional borrow at the same rate mode and a stable/variable mode switch. The net increase in total reserve debt is always the accrued interest plus the newly borrowed amount. `NONE` is invalid for a new borrow and reverts with `LendingPoolCore__InvalidBorrowRateMode`.

### Why remove the old principal first?

Before this call, the user's stored `principalBorrowBalance` is already included in exactly one reserve total. Adding the updated debt without first removing that old principal would count the same debt twice.

The function therefore follows this invariant:

```text
old aggregate debt
- user's old principal in the old mode
+ user's complete updated principal in the selected new mode
```

Only the interest that accrued since the user's previous update and the newly borrowed amount increase the sum of the two reserve debt totals.

### Example 1: First borrow (`NONE` → `VARIABLE`)

Assume the reserve starts with 10,000 DAI of stable debt and 5,000 DAI of variable debt. Alice has no existing DAI debt, so her previous mode is `NONE`.

```text
Alice's previous principal =     0 DAI
accrued interest           =     0 DAI
new borrow                 =   500 DAI
updated principal          =   500 DAI
```

There is no previous principal to remove. Since Alice chooses variable mode, the function adds her full 500 DAI position to `totalBorrowsVariable`:

```text
totalBorrowsStable:   10,000 DAI  -> 10,000 DAI
totalBorrowsVariable:  5,000 DAI  ->  5,500 DAI
```

### Example 2: Additional variable borrow (`VARIABLE` → `VARIABLE`)

Assume Alice already has 1,000 DAI of variable debt. Since her last debt update, 20 DAI of interest accrued; she now borrows another 500 DAI at variable rate. The reserve has 5,000 DAI of variable debt before the operation, including Alice's stored 1,000 DAI principal.

```text
previous principal = 1,000 DAI
accrued interest   =    20 DAI
new borrow         =   500 DAI
updated principal  = 1,520 DAI
```

The function removes the 1,000 DAI old principal, then adds the 1,520 DAI updated position back to the variable aggregate:

```text
totalBorrowsVariable = 5,000 - 1,000 + 1,520
                     = 5,520 DAI
```

The aggregate increases by 520 DAI, exactly equal to `20 DAI` accrued interest plus `500 DAI` newly borrowed.

### Example 3: Switch from variable to stable (`VARIABLE` → `STABLE`)

Using the same user debt values, assume the reserve begins with 10,000 DAI of stable debt and 5,000 DAI of variable debt.

The old 1,000 DAI principal belongs to the variable aggregate, so it is removed there. The complete updated 1,520 DAI position is then added to the stable aggregate:

```text
totalBorrowsVariable: 5,000 - 1,000 =  4,000 DAI
totalBorrowsStable:  10,000 + 1,520 = 11,520 DAI
```

The user's debt has changed buckets, but total reserve debt still rises by only 520 DAI. Adding stable debt also recalculates the reserve's weighted average stable borrow rate, using the reserve's current stable rate for this updated position.

### Example 4: Switch from stable to variable (`STABLE` → `VARIABLE`)

Assume Alice has 1,000 DAI of stable debt, 20 DAI has accrued, and she borrows another 500 DAI in variable mode. The reserve starts with 10,000 DAI of stable debt and 5,000 DAI of variable debt.

```text
totalBorrowsStable:   10,000 - 1,000 =  9,000 DAI
totalBorrowsVariable:  5,000 + 1,520 =  6,520 DAI
```

Removing stable debt recalculates the weighted average stable borrow rate because Alice's old stable rate is leaving that pool. The variable total needs no average-rate update: variable debt is valued through the common variable borrow index.

### Rate-mode summary

```text
previous mode   selected mode   old principal removed from   updated principal added to
NONE            STABLE          none                         totalBorrowsStable
NONE            VARIABLE        none                         totalBorrowsVariable
STABLE          STABLE          totalBorrowsStable           totalBorrowsStable
STABLE          VARIABLE        totalBorrowsStable           totalBorrowsVariable
VARIABLE        STABLE          totalBorrowsVariable         totalBorrowsStable
VARIABLE        VARIABLE        totalBorrowsVariable         totalBorrowsVariable
```

## `_updateUserStateOnBorrow`

```solidity
function _updateUserStateOnBorrow(...) internal
```

This helper writes the borrower's reserve-specific debt state.

For a stable loan, it stores the reserve's current stable rate and clears the variable-borrow-index checkpoint. For a variable loan, it clears the user's stable rate and stores the reserve's current variable-borrow index as the new checkpoint.

In both cases it:

```text
increments principalBorrowBalance by newly borrowed amount + accrued interest
increments originationFee by the supplied borrow fee
sets lastUpdateTimestamp to the current block timestamp
```

The accrued interest is added to principal because it is being materialized at this borrow action; it is no longer merely a view-time calculation.

## `_getUserCurrentBorrowRate`

```solidity
function _getUserCurrentBorrowRate(
    address _reserve,
    address _user
) internal view returns (uint256)
```

This helper returns zero when the user has no debt. Otherwise it returns the rate relevant to the user's current mode:

```text
stable debt:   user's stored stableBorrowRate
variable debt: reserve.currentVariableBorrowRate
```

Variable borrowers do not store an individual variable rate because their debt follows the reserve-wide variable rate and borrow index.

# Reserve Initialization

## `initReserve`

```solidity
function initReserve(
    address _reserve,
    address _aTokenAddress,
    uint256 _decimals,
    address _interestRateStrategyAddress
) external onlyLendingPoolConfigurator
```

This function initializes a new reserve.

It first delegates to `CoreLibrary.init()`:

```solidity
s_reserves[_reserve].init(
    _aTokenAddress,
    _decimals,
    _interestRateStrategyAddress
);
```

That initialization sets:

```text
aToken address
asset decimals
interest-rate strategy address
liquidity index = 1 ray
variable borrow index = 1 ray
isActive = true
isFreezed = false
```

The reserve is then added to the reserve list:

```solidity
_addReserveToList(_reserve);
```

Finally, the function emits `ReserveInitialized`.

# Adding a Reserve to the List

## `_addReserveToList`

```solidity
function _addReserveToList(address _reserve) internal {
    if (s_isReserveAdded[_reserve]) {
        return;
    }

    s_reservesList.push(_reserve);
    s_isReserveAdded[_reserve] = true;
}
```

The membership mapping prevents duplicate reserve addresses.

The operations are constant-time:

```text
membership check = O(1)
array append = O(1)
```

# Removing the Last Reserve

## `removeLastAddedReserve`

```solidity
function removeLastAddedReserve(
    address _reserveToRemove
) external onlyLendingPoolConfigurator
```

This function removes only the most recently added reserve.

The last-only restriction allows the contract to use `pop()` without shifting array entries.

## 1. Require a Non-Empty List

```solidity
if (reservesListLength == 0) {
    revert LendingPoolCore__ReserveListIsEmpty();
}
```

## 2. Require the Requested Reserve to Be Last

```solidity
address lastReserve =
    s_reservesList[reservesListLength - 1];

if (lastReserve != _reserveToRemove) {
    revert LendingPoolCore__ReserveToRemoveIsNotLastReserve();
}
```

## 3. Require Zero Borrows

```solidity
if (getReserveTotalBorrows(lastReserve) != 0) {
    revert LendingPoolCore__ReserveHasBorrows();
}
```

A reserve with outstanding debt cannot be removed.

## 4. Reset Reserve Configuration

The function clears the main reserve fields, including:

```text
active status
aToken address
decimals
liquidity and borrow indexes
borrowing configuration
collateral configuration
risk parameters
interest-rate strategy
```

## 5. Remove the Reserve From the List

The intended final operations are:

```solidity
s_isReserveAdded[lastReserve] = false;
s_reservesList.pop();
```

and then `ReserveRemoved` is emitted.

# User Collateral Preference

## `setUserUseReserveAsCollateral`

```solidity
function setUserUseReserveAsCollateral(
    address _reserve,
    address _user,
    bool _useAsCollateral
) public onlyLendingPool
```

This function controls whether the user's deposit in the reserve is used as collateral.

It updates:

```solidity
s_usersReserveData[_user][_reserve]
    .useAsCollateral = _useAsCollateral;
```

When `true`, the asset may contribute to the user's borrowing capacity.

When `false`, the user still owns the deposit, but it is excluded from collateral calculations.

# Updating Interest Rates

## `_updateReserveInterestRatesAndTimestamp`

```solidity
function _updateReserveInterestRatesAndTimestamp(
    address _reserve,
    uint256 _liquidityAdded,
    uint256 _liquidityTaken
) internal
```

This function recalculates a reserve's rates after an operation changes liquidity.

Typical values are:

```text
deposit or repay:
    liquidityAdded > 0

borrow or redeem:
    liquidityTaken > 0
```

The projected available liquidity is:

```text
current available liquidity
+ liquidity added
- liquidity taken
```

The strategy is called with:

```solidity
calculateInterestRates(
    _reserve,
    getReserveAvailableLiquidity(_reserve)
        + _liquidityAdded
        - _liquidityTaken,
    reserve.totalBorrowsStable,
    reserve.totalBorrowsVariable,
    reserve.currentAverageStableBorrowRate
);
```

It returns:

```text
new liquidity rate
new stable borrow rate
new variable borrow rate
```

The core stores these values and emits `ReserveUpdated`.

The exact rate formulas belong to the reserve's configured interest-rate strategy, not to `LendingPoolCore`.

# Reading Reserve Data

## `getReserveATokenAddress`

```solidity
function getReserveATokenAddress(
    address _reserve
) public view returns (address)
```

Returns the aToken associated with the reserve.

Example:

```text
DAI reserve -> aDAI address
```

`LendingPool` uses this address when it needs to mint or interact with aTokens.

## `getReserveAvailableLiquidity`

```solidity
function getReserveAvailableLiquidity(
    address _reserve
) public view returns (uint256)
```

Returns the assets currently held by the core.

For ETH:

```solidity
address(this).balance
```

For ERC20 reserves:

```solidity
IERC20(_reserve).balanceOf(address(this))
```

Available liquidity is an actual asset balance, not an index.

It can increase through:

```text
deposits
repayments
```

and decrease through:

```text
borrows
redemptions
```

## `getReserveNormalizedIncome`

```solidity
function getReserveNormalizedIncome(
    address _reserve
) external view returns (uint256)
```

Returns the reserve's current supplier growth factor.

It tells: “How much has one deposited unit grown since the reserve started?”

It combines:

```text
the previously stored liquidity index
+
the linear interest accumulated since the last reserve update
```

Examples:

```text
1.00 ray = no cumulative supplier growth
1.05 ray = 5% cumulative supplier growth
```

ATokens use this value to derive users' current interest-bearing balances.

## `getReserveTotalBorrows`

```solidity
function getReserveTotalBorrows(
    address _reserve
) public view returns (uint256)
```

Returns:

```text
total stable borrows
+
total variable borrows
```

## `getReserveConfiguration`

```solidity
function getReserveConfiguration(
    address _reserve
)
    external
    view
    returns (
        uint256,
        uint256,
        uint256,
        bool
    )
```

This function returns several reserve configuration fields in a single external call:

```text
1. reserve decimals
2. base LTV as collateral
3. liquidation threshold
4. whether usage as collateral is enabled for the reserve
```

`LendingPoolDataProvider` uses this aggregated getter to avoid making multiple external calls to `LendingPoolCore` for fields that are usually needed together.

The final boolean is reserve-level configuration:

```text
reserve.usageAsCollateralEnabled
```

It answers whether the asset type can be used as collateral at all. It does not answer whether a specific user has enabled their own balance as collateral.

## `getUserUnderlyingAssetBalance`

```solidity
function getUserUnderlyingAssetBalance(
    address _reserve,
    address _user
) public view returns (uint256)
```

The function obtains the reserve's aToken and calls:

```solidity
aToken.balanceOf(_user)
```

Because `AToken.balanceOf()` includes accrued supplier interest, the result represents the user's current underlying deposit value rather than only the principal initially minted.

# Reading Basic User Reserve Data

## `getUserBasicReserveData`

```solidity
function getUserBasicReserveData(
    address _reserve,
    address _user
)
    external
    view
    returns (
        uint256,
        uint256,
        uint256,
        bool
    )
```

This function returns the basic user data needed by higher-level account calculations:

```text
1. current underlying deposit balance
2. current compounded borrow balance
3. origination fee
4. whether the reserve is enabled as collateral
```

It first reads the user's current deposit value through the aToken:

```solidity
uint256 underlyingBalance =
    getUserUnderlyingAssetBalance(
        _reserve,
        _user
    );
```

If the user has no debt:

```solidity
if (user.principalBorrowBalance == 0) {
```

the function returns zero borrow balance and zero fee without performing unnecessary compounded-debt calculations.

If the user has debt, it returns:

```solidity
user.getCompoundedBorrowBalance(reserve)
```

This is necessary because `principalBorrowBalance` is only the debt stored at the last user update. The compounded balance includes interest accrued up to the current block.

## `isUserUseReserveAsCollateralEnabled`

```solidity
function isUserUseReserveAsCollateralEnabled(
    address _reserve,
    address _user
) external view returns (bool)
```

Returns the user's collateral preference for a specific reserve:

```solidity
s_usersReserveData[_user][_reserve].useAsCollateral
```

This is user-level state.

It answers whether that user's balance in the reserve is currently marked as collateral. For the balance to actually count as collateral in account calculations, the reserve itself must also have collateral usage enabled.

## `isReserveBorrowingEnabled`

```solidity
function isReserveBorrowingEnabled(
    address _reserve
) external view returns (bool)
```

Returns the reserve-level `borrowingEnabled` configuration flag. `LendingPool.borrow()` uses this getter to reject borrowing from reserves whose borrowing feature is disabled.

This flag is distinct from whether the reserve is active or frozen, and it does not prove that a particular user can borrow: the user-facing flow performs those additional checks separately.

## `getReserveDecimals`

```solidity
function getReserveDecimals(
    address _reserve
) external view returns (uint256)
```

Returns the number of decimal places configured when the reserve was initialized. Consumers use it to normalize the reserve's raw token amounts for calculations and presentation.

# Reading User Borrow Data

## `getUserBorrowBalances`

```solidity
function getUserBorrowBalances(
    address _reserve,
    address _user
) public view returns (
    uint256 principalBorrowBalance,
    uint256 compoundedBorrowBalance,
    uint256 balanceIncrease
)
```

Returns a three-part view of the user's debt:

```text
principalBorrowBalance:  debt recorded at the user's last debt update
compoundedBorrowBalance: current debt after interest accrued until now
balanceIncrease:         interest accrued since that update
```

For a user without debt, all three values are zero. Otherwise, the function uses `CoreLibrary.getCompoundedBorrowBalance()` and calculates:

```text
balanceIncrease = compoundedBorrowBalance - principalBorrowBalance
```

For example, if the user's last stored debt update recorded `1,000 DAI` of principal and interest
has grown that debt to `1,020 DAI`, the getter returns:

```text
principalBorrowBalance  = 1,000 DAI
compoundedBorrowBalance = 1,020 DAI
balanceIncrease         =    20 DAI
```

This getter does not write state. `updateStateOnBorrow()` uses it to materialize the returned `balanceIncrease` into both the reserve totals and the user's stored principal before adding a new loan.

## `getUserCurrentBorrowRateMode`

```solidity
function getUserCurrentBorrowRateMode(
    address _reserve,
    address _user
) public view returns (CoreLibrary.InterestRateMode)
```

Returns the mode inferred from the user's stored debt data:

```text
principalBorrowBalance == 0  -> NONE
stableBorrowRate > 0         -> STABLE
otherwise                    -> VARIABLE
```

The function does not store a separate rate-mode field. A nonzero stable rate identifies stable debt; an outstanding debt with a zero stable rate is variable debt.

## `isUserAllowedToBorrowAtStable`

```solidity
function isUserAllowedToBorrowAtStable(
    address _reserve,
    address _user,
    uint256 _amount
) external view returns (bool)
```

Returns whether the core's stable-rate eligibility rule passes for this reserve, user, and amount.

First, stable borrowing must be enabled for the reserve:

```solidity
reserve.isStableBorrowRateEnabled
```

If it is enabled, the same-asset stable-borrow restriction passes when at least one condition is true:

1. The user is not using this reserve as collateral.
2. This reserve is not enabled for collateral use.
3. The requested stable borrow exceeds the user's underlying balance of this asset.

When the user is using this collateral-enabled reserve, a same-asset stable borrow is allowed only when its amount exceeds that user's current underlying deposit balance. The balance is read through the aToken, so accrued deposit interest is included.

### Example: stable borrowing against the same asset

Alice deposits `1,000 DAI` and enables DAI as collateral. If she then requests a `500 DAI` stable-rate borrow, this condition holds:

```text
500 DAI <= 1,000 DAI
```

The function returns `false`: Alice is attempting a stable borrow of the same asset she is using as collateral, and the requested amount does not exceed her DAI balance. If Alice instead borrows another asset, such as USDC, her DAI deposit is not used by this specific same-asset check.

This is not the complete stable-borrow validation. `LendingPool` also checks the stable borrowing cap relative to available liquidity, alongside the general borrow validations such as collateral capacity and available liquidity.

## `getReserveUtilizationRate`

```solidity
function getReserveUtilizationRate(
    address _reserve
) external view returns (uint256)
```

Returns the share of the reserve's supplied assets that is currently borrowed, expressed in ray (`1e27`):

```text
utilization = total borrows / (available liquidity + total borrows)
```

`available liquidity` is the asset balance held by `LendingPoolCore`, while `total borrows` includes both stable and variable debt. `rayDiv()` performs the division using ray precision, so a result of `0.80 ray` represents 80% utilization.

The explicit zero-borrow check returns `0` before dividing. Besides accurately describing an unused reserve, it avoids a zero-denominator when the reserve has neither borrows nor liquidity.

For example, a reserve with `800 DAI` borrowed and `200 DAI` available has:

```text
800 / (200 + 800) = 0.80
```

so the function returns `0.80 ray`. This getter only reports the current ratio; it does not update reserve state or interest rates.

# Repayment State Update

## `updateStateOnRepay`

```solidity
function updateStateOnRepay(
    address _reserve,
    address _user,
    uint256 _paybackAmountMinusFees,
    uint256 _originationFeeRepaid,
    uint256 _balanceIncrease,
    bool _repaidWholeLoan
) external onlyLendingPool
```

Updates the state of the core as a consequence of a repay action.

This is the accounting entry point for a repayment accepted by `LendingPool`. It does not pull tokens from the repayer; `LendingPool` performs that separately through `transferToFeeCollectionAddress()` and `transferToReserve()`.

The core trusts its caller: it does not verify that the amount is valid for the user. `LendingPool` supplies the current `balanceIncrease` obtained from `getUserBorrowBalances()` and splits the payment into principal/interest repayment and origination-fee repayment.

The operations occur in this order:

```text
1. Checkpoint reserve indexes and update the reserve's stable or variable debt total.
2. Update the user's principal, fee, rate/index checkpoint, and timestamp.
3. Reprice the reserve as though `_paybackAmountMinusFees` has been added to liquidity.
```

The fee is deliberately not counted as new reserve liquidity: it is sent to the protocol fee collector rather than remaining available to suppliers.

For a fee-only repayment, `_paybackAmountMinusFees` is zero. The user's accumulated borrowing interest is still materialized into debt totals and their principal, while only the outstanding origination fee is reduced.

## `_updateReserveStateOnRepay`

```solidity
function _updateReserveStateOnRepay(
    address _reserve,
    address _user,
    uint256 _paybackAmountMinusFees,
    uint256 _balanceIncrease
) internal
```

Updates the state of the reserve as a consequence of a repay action.

This function keeps the reserve-wide debt totals aligned with the borrower's repayment.

First it determines the user's current mode, then calls `updateCumulativeIndexes()`. That checkpoints supplier and variable-borrow index growth using the rates that applied before the repayment changes liquidity or debt totals.

It then applies the same accounting formula to the appropriate reserve aggregate:

```text
new total debt = old recorded total + user's accrued interest - repayment excluding fees
```

For a stable borrower, it uses `totalBorrowsStable` and calls the weighted-average stable-rate helpers when adding `balanceIncrease` and subtracting the repayment. The user's `stableBorrowRate` is supplied to both helpers because that is the rate associated with the affected stable debt.

For a variable borrower, it performs the corresponding additions and subtractions on `totalBorrowsVariable`. There is no average variable rate to maintain; variable positions are represented by the shared variable-borrow index.

## `_updateUserStateOnRepay`

```solidity
function _updateUserStateOnRepay(
    address _reserve,
    address _user,
    uint256 _paybackAmountMinusFees,
    uint256 _originationFeeRepaid,
    uint256 _balanceIncrease,
    bool _repaidWholeLoan
) internal
```

Updates the state of the user as a consequence of a repay action.

This function writes the borrower's individual position after the reserve totals have been updated.

It first materializes the interest accrued since the user's prior update, then removes the non-fee portion of the payment:

```text
new principalBorrowBalance =
    old principalBorrowBalance
    + balanceIncrease
    - paybackAmountMinusFees
```

It saves the reserve's current variable-borrow index as the user's new checkpoint. This makes a remaining variable debt position accrue only from the repayment block forward.

If `_repaidWholeLoan` is true, the function clears both rate-mode markers:

```text
stableBorrowRate = 0
lastVariableBorrowCumulativeIndex = 0
```

With a zero principal balance, this makes `getUserCurrentBorrowRateMode()` return `NONE`. Finally, the function subtracts `_originationFeeRepaid` from the user's outstanding fee and records `block.timestamp` as the user's latest debt update.

# Collecting Origination Fees

## `transferToFeeCollectionAddress`

```solidity
function transferToFeeCollectionAddress(
    address _token,
    address _user,
    uint256 _amount,
    address _destination
) external payable onlyLendingPool
```

This function moves the origination-fee portion of a repayment to the protocol's fee collector. It does not alter debt accounting; that is completed first by `updateStateOnRepay()`.

For an ERC20 reserve, no ETH may accompany the call. The core uses `safeTransferFrom(_user, _destination, _amount)`, so `_user` must have approved `LendingPoolCore` for the fee amount.

For the ETH reserve, `msg.value` must be at least `_amount`, and the core sends exactly `_amount` ETH to `_destination`. Any value above `_amount` remains in the core, so callers should pass the exact fee amount. `LendingPool.repay()` does so in its normal fee-transfer path.

# Liquidation State Update

## `updateStateOnLiquidation`

```solidity
function updateStateOnLiquidation(
    address _principalReserve,
    address _collateralReserve,
    address _user,
    uint256 _amountToLiquidate,
    uint256 _collateralToLiquidate,
    uint256 _feeLiquidated,
    uint256 _liquidatedCollateralForFee,
    uint256 _balanceIncrease,
    bool _liquidatorReceivesAToken
) external onlyLendingPool
```

This is the core accounting entry point after `LendingPool` has validated a liquidation and calculated its amounts. `_principalReserve` is the debt asset being repaid, while `_collateralReserve` is the asset seized from the borrower.

It performs accounting only: the liquidation manager subsequently collects the liquidator's repayment, moves or burns the borrower's collateral aTokens, and transfers any protocol fee. As with other core state-update functions, `onlyLendingPool` protects the entry point, but the core trusts the amounts supplied by that caller.

The updates occur in this order:

```text
1. Checkpoint the debt reserve and update its aggregate borrow total.
2. Checkpoint the collateral reserve's indexes.
3. Update the borrower's debt, fee, variable-rate checkpoint, and timestamp.
4. Reprice the debt reserve for the repayment entering its liquidity.
5. If underlying collateral leaves the pool, reprice the collateral reserve for that outflow.
```

`_amountToLiquidate` repays debt and therefore becomes liquidity added to the principal reserve. `_feeLiquidated` is the portion of the borrower's origination fee settled by the liquidation, denominated in the principal asset. `_liquidatedCollateralForFee` is the separately calculated amount of collateral taken to pay that fee, including its liquidation bonus.

When `_liquidatorReceivesAToken` is true, collateral aTokens move from the borrower to the liquidator and the underlying collateral stays in the core. The collateral reserve's available underlying liquidity does not change, so its interest rates are not recomputed. When it is false, the liquidator receives underlying collateral; both `_collateralToLiquidate` and `_liquidatedCollateralForFee` leave the pool and are passed as `liquidityTaken` to the rate update.

## `_updatePrincipalReserveStateOnLiquidation`

```solidity
function _updatePrincipalReserveStateOnLiquidation(
    address _principalReserve,
    address _user,
    uint256 _amountToLiquidate,
    uint256 _balanceIncrease
) internal
```

This helper keeps reserve-wide debt totals consistent with the liquidated borrower's position. It first calls `updateCumulativeIndexes()` so that supplier and variable-borrow index growth is recorded using the rates that applied before liquidation changes the reserve.

It then identifies the borrower's rate mode and materializes their accrued interest in the corresponding aggregate before subtracting the debt repayment:

```text
new aggregate debt = old aggregate debt + balanceIncrease - amountToLiquidate
```

For stable debt, the helper changes `totalBorrowsStable` through the weighted-average stable-rate helpers, using the borrower's `stableBorrowRate`. For variable debt, it changes `totalBorrowsVariable`; variable debt uses the reserve-wide cumulative index rather than a weighted average rate.

## `_updateCollateralReserveStateOnLiquidation`

```solidity
function _updateCollateralReserveStateOnLiquidation(
    address _collateralReserve
) internal
```

This helper checkpoints the collateral reserve's cumulative indexes immediately before the liquidation changes who owns the collateral or removes it from the pool:

```solidity
s_reserves[_collateralReserve].updateCumulativeIndexes();
```

The checkpoint records deposit interest, and any variable-borrow interest in the collateral reserve, using the rates in effect before the liquidation. It does not directly change the reserve's debt totals or liquidity. Those changes are handled separately: transferring aTokens changes ownership without moving underlying liquidity, while an underlying-collateral liquidation triggers the later interest-rate update with the collateral outflow.

## `_updateUserStateOnLiquidation`

```solidity
function _updateUserStateOnLiquidation(
    address _reserve,
    address _user,
    uint256 _amountToLiquidate,
    uint256 _feeLiquidated,
    uint256 _balanceIncrease
) internal
```

This helper writes the liquidated borrower's per-reserve debt state. It materializes the interest accrued since the last update and subtracts the debt repayment:

```text
new principalBorrowBalance =
    old principalBorrowBalance
    + balanceIncrease
    - amountToLiquidate
```

For a variable-rate loan, it saves the reserve's current `lastVariableBorrowCumulativeIndex` as the new user checkpoint. Any debt remaining after liquidation will therefore accrue from this index onward. For a stable-rate loan, the user's stable rate remains the rate attached to the remaining stable debt.

If `_feeLiquidated` is nonzero, the helper also reduces `user.originationFee` by that amount. It finally sets `lastUpdateTimestamp` to `block.timestamp` so future interest calculations begin from the liquidation update.

## `liquidateFee`

```solidity
function liquidateFee(
    address _token,
    uint256 _amount,
    address payable _destination
) external onlyLendingPool
```

This function sends collateral reserved for a liquidated origination fee from `LendingPoolCore` to the protocol fee collector. Before it is called, the liquidation manager burns the borrower's aTokens for the same collateral amount, keeping the aToken supply aligned with the underlying assets that leave the pool.

For ERC20 collateral, the core uses `safeTransfer(_destination, _amount)`. For ETH collateral, it sends `_amount` with a low-level call and reverts with `LendingPoolCore__EthTransferFailed` if the transfer fails. The function transfers funds only; the borrower’s outstanding fee was already reduced by `_updateUserStateOnLiquidation()`.

# Swap Borrow Rate State Update

Borrowers can switch an existing loan between the stable and variable rate modes without borrowing or repaying underlying funds. A rate swap first realizes the interest already accrued by that borrower, then moves the resulting debt between the reserve's stable and variable debt aggregates.

## `updateStateOnSwapRate`

```solidity
function updateStateOnSwapRate(
    address _reserve,
    address _user,
    uint256 _principalBorrowBalance,
    uint256 _compoundedBorrowBalance,
    uint256 _balanceIncrease,
    CoreLibrary.InterestRateMode _currentRateMode
) external onlyLendingPool returns (CoreLibrary.InterestRateMode, uint256)
```

This is the core accounting entry point for a rate swap validated by `LendingPool`. No underlying tokens move, so the reserve's available liquidity is unchanged. The function trusts the caller's supplied balances and current mode.

Its sequence is:

```text
1. Checkpoint reserve indexes and move the borrower's debt to the opposite aggregate.
2. Materialize the borrower's accrued interest and replace their rate-mode state.
3. Recalculate reserve rates with zero liquidity added and zero liquidity taken.
4. Return the new rate mode and the borrower's current rate in that mode.
```

`_principalBorrowBalance` is the debt recorded at the borrower's previous checkpoint. `_compoundedBorrowBalance` is that debt plus accrued interest, and `_balanceIncrease` is the difference between them. Passing both values lets reserve totals move the full current debt while the user's principal is updated by only the accrued increment.

## `_updateReserveStateOnSwapRate`

```solidity
function _updateReserveStateOnSwapRate(
    address _reserve,
    address _user,
    uint256 _principalBorrowBalance,
    uint256 _compoundedBorrowBalance,
    CoreLibrary.InterestRateMode _currentRateMode
) internal
```

This helper updates reserve-wide accounting. It first calls `updateCumulativeIndexes()`, recording liquidity-index and variable-borrow-index growth under the rates that existed before the swap.

It then removes the user's old checkpointed principal from their current aggregate and adds their interest-inclusive debt to the destination aggregate:

```text
source aggregate      -= principalBorrowBalance
destination aggregate += compoundedBorrowBalance
```

For a stable-to-variable swap, it removes principal from `totalBorrowsStable` using the user's existing `stableBorrowRate`, which also updates the reserve's weighted average stable rate. It adds `compoundedBorrowBalance` to `totalBorrowsVariable`.

For a variable-to-stable swap, it removes principal from `totalBorrowsVariable` and adds `compoundedBorrowBalance` to `totalBorrowsStable` at `reserve.currentStableBorrowRate`, updating the weighted average stable rate. `NONE` or any unsupported mode reverts with `LendingPoolCore__InvalidBorrowRateMode`.

The difference between the removed and added amounts is the borrower's accrued interest, which is materialized into the destination debt total rather than lost during the mode change.

## `_updateUserStateOnSwapRate`

```solidity
function _updateUserStateOnSwapRate(
    address _reserve,
    address _user,
    uint256 _balanceIncrease,
    CoreLibrary.InterestRateMode _currentRateMode
) internal returns (CoreLibrary.InterestRateMode)
```

This helper writes the borrower's new rate-specific state and returns the resulting mode.

For a variable-to-stable swap, it sets `stableBorrowRate` to the reserve's current stable borrow rate and clears `lastVariableBorrowCumulativeIndex`. For a stable-to-variable swap, it clears `stableBorrowRate` and snapshots the reserve's current `lastVariableBorrowCumulativeIndex`; remaining variable debt will accrue from that checkpoint forward.

In both cases, it realizes accrued interest in the user record:

```text
new principalBorrowBalance = old principalBorrowBalance + balanceIncrease
```

Finally, it sets `lastUpdateTimestamp` to `block.timestamp`. As in the reserve helper, an invalid current mode reverts.

# Flash-Loan State Update

When a flash loan completes, `LendingPool` first verifies that `LendingPoolCore` received back the principal plus exactly the total flash-loan fee. It then calls the functions below to split that fee between the protocol and the reserve's suppliers.

## `updateStateOnFlashLoan`

```solidity
function updateStateOnFlashLoan(
    address _reserve,
    uint256 _avaliableLiquidityBefore,
    uint256 _income,
    uint256 _protocolFee
) external onlyLendingPool
```

This is the flash-loan settlement accounting entry point. Only `LendingPool` can call it, and it relies on that caller to have validated the repayment and calculated the fee split.

`_avaliableLiquidityBefore` is the core's underlying-token balance immediately before the loan was sent. `_protocolFee` is the portion of the fee that belongs to the protocol, while `_income` is the remaining portion for aToken holders.

The function performs these updates in order:

```text
1. Transfer _protocolFee from the core to TokenDistributor.
2. Checkpoint time-based liquidity and variable-borrow index growth.
3. Distribute _income to suppliers by increasing the liquidity index.
4. Recalculate the reserve's interest rates and record the new timestamp.
```

For the one-off supplier distribution, it uses the reserve value before the flash-loan income was added:

```text
totalLiquidityBefore = _avaliableLiquidityBefore + total outstanding borrows
```

Calling `cumulateToLiquidityIndex(totalLiquidityBefore, _income)` raises the shared liquidity index, so each aToken holder receives a proportional claim on the supplier share without an individual balance update. The final rate update calls `_updateReserveInterestRatesAndTimestamp(_reserve, _income, 0)`.

## `_transferFlashLoanProtocolFee`

```solidity
function _transferFlashLoanProtocolFee(address _token, uint256 _amount) internal
```

This internal helper moves the protocol's portion of a flash-loan fee from `LendingPoolCore` to the current `TokenDistributor` address returned by `LendingPoolAddressesProvider`.

For an ERC20 reserve, it uses `IERC20(_token).safeTransfer(receiver, _amount)`. For the ETH reserve, it sends `_amount` with a low-level call. If that ETH transfer fails, the whole flash-loan settlement reverts with `LendingPoolCore__EthTransferFailed(receiver, _amount)`.

The helper only transfers the protocol share. The separate `_income` amount remains associated with the reserve and is distributed to suppliers by `updateStateOnFlashLoan`.
