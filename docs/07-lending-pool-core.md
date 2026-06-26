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
transferToReserve()
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

The current implementation also stores `i_lendingPoolAddress`, although the access-control modifier uses the address provider dynamically instead.

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
