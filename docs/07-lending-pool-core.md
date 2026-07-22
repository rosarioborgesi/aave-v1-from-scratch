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

# Protocol Relationships

## LendingPool

`LendingPool` is the user-facing entry point.

For a deposit, it:

```text
1. validates the request;
2. calls LendingPoolCore.updateStateOnDeposit();
3. mints aTokens;
4. calls LendingPoolCore.transferToReserve().
```

For a redeem, it:

```text
1. validates that the user can withdraw the requested liquidity;
2. burns the user's aTokens;
3. calls LendingPoolCore.updateStateOnRedeem();
4. calls LendingPoolCore.transferToUser().
```

## LendingPoolConfigurator

`LendingPoolConfigurator` performs administrative reserve operations such as:

```text
initializing a reserve
removing the most recently added reserve
```

## CoreLibrary

`LendingPoolCore` stores `ReserveData` and `UserReserveData`, while `CoreLibrary` performs the interest and index calculations on those structs.

## InterestRateStrategy

Every reserve has an interest-rate strategy contract.

`LendingPoolCore` supplies the reserve state to that strategy and stores the returned:

```text
liquidity rate
stable borrow rate
variable borrow rate
```

## AToken

Each reserve has an associated aToken.

The aToken represents a user's supplied position and uses the reserve normalized income exposed by `LendingPoolCore` to calculate the current interest-bearing balance.

# Access Control

## `onlyLendingPool`

```solidity
modifier onlyLendingPool() {
    if (msg.sender != i_addressesProvider.getLendingPool()) {
        revert LendingPoolCore__OnlyLendingPool();
    }
    _;
}
```

Only the current `LendingPool` registered in the addresses provider can call operational functions such as:

```text
updateStateOnDeposit()
updateStateOnRedeem()
updateStateOnBorrow()
transferToReserve()
transferToUser()
setUserUseReserveAsCollateral()
```

This prevents users and unrelated contracts from directly changing accounting state or transferring funds through the core.

## `onlyLendingPoolConfigurator`

```solidity
modifier onlyLendingPoolConfigurator() {
    if (msg.sender != i_addressesProvider.getLendingPoolConfigurator()) {
        revert LendingPoolCore__OnlyLendingPoolConfigurator();
    }
    _;
}
```

Only `LendingPoolConfigurator` can perform reserve-management actions such as:

```text
initReserve()
removeLastAddedReserve()
```

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

# Constructor

```solidity
constructor(address _addressesProvider) {
    i_addressesProvider =
        LendingPoolAddressesProvider(_addressesProvider);

    i_lendingPoolAddress =
        i_addressesProvider.getLendingPool();
}
```

The constructor stores the `LendingPoolAddressesProvider`.

The active LendingPool and LendingPoolConfigurator addresses are later resolved through this provider.

The access-control modifiers resolve the current addresses dynamically through the provider. This lets the configured LendingPool and configurator be updated without redeploying the core.

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

## `_updateReserveStateOnBorrow`

```solidity
function _updateReserveStateOnBorrow(...) internal
```

This helper applies the reserve-side effects of a borrow.

First, `updateCumulativeIndexes()` materializes interest accrued since the reserve's previous update into the liquidity and variable-borrow indexes. It then delegates to `_updateReserveTotalBorrowsByRateMode()` to reflect the borrower's complete updated debt in the reserve totals.

It deliberately operates before rates are recalculated: previously accrued interest must use the rates and indexes that existed before the new liquidity is removed.

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

If it is enabled, the function rejects only the following combination:

```text
the user has this reserve enabled as collateral
AND the reserve type supports collateral
AND the requested stable borrow is less than or equal to the user's current deposit of that same asset
```

Equivalently, a same-asset stable borrow is allowed only when its amount exceeds that user's current underlying deposit balance. The balance is read through the aToken, so accrued deposit interest is included.

This is not the complete stable-borrow validation. `LendingPool` also checks the stable borrowing cap relative to available liquidity, alongside the general borrow validations such as collateral capacity and available liquidity.
