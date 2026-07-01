# Deposit

The `deposit` feature is the user entry point for supplying liquidity to the
protocol.

In this implementation, a user deposits an underlying reserve asset and receives
the matching aToken. The underlying asset is stored in `LendingPoolCore`, while
`LendingPool` only coordinates the action.

This document is a rebuild map. It lists the contracts involved and the
functions that must exist for `LendingPool.deposit()` to work.

## Deposit Goal

```text
User deposits DAI
LendingPoolCore receives DAI
User receives aDAI
```

For the deposit itself, aTokens are minted 1:1 with the deposited amount:

```text
deposit amount = 100 DAI
new aTokens minted = 100 aDAI
```

If the user already has accrued aToken interest, `AToken.mintOnDeposit()` first
materializes that interest and then mints the new deposit amount.

## High-Level Flow

For an ERC20 reserve, the user must approve `LendingPoolCore` before calling
`LendingPool.deposit()`.

```text
User
  |
  | approve(LendingPoolCore, amount)
  v
Reserve ERC20

User
  |
  | deposit(reserve, amount, referralCode)
  v
LendingPool
  |
  | checks reserve state
  | updates reserve accounting
  | mints aTokens
  | transfers underlying into core
  v
LendingPoolCore
```

The important balance changes are:

```text
user underlying balance decreases by amount
core underlying balance increases by amount
user aToken balance increases by amount, plus any materialized interest
```

## Contracts Involved

### `LendingPool`

Main user-facing contract for the deposit call.

It validates the request, asks the core to update reserve accounting, mints the
corresponding aTokens, transfers the underlying asset into the core, and emits
the `Deposit` event.

Required functions and modifiers:

- `constructor(address _addressesProvider)`
- `deposit(address _reserve, uint256 _amount, uint16 _referralCode)`
- `onlyActiveReserve(address _reserve)`
- `onlyUnfreezedReserve(address _reserve)`
- `onlyAmountGreaterThanZero(uint256 _amount)`
- `getLendingPoolCoreAddress()`
- `getLendingPoolAddressesProvider()`

External functions called by `deposit()`:

- `LendingPoolCore.getReserveIsActive(_reserve)`
- `LendingPoolCore.getReserveIsFreezed(_reserve)`
- `LendingPoolCore.getReserveATokenAddress(_reserve)`
- `AToken.balanceOf(msg.sender)`
- `LendingPoolCore.updateStateOnDeposit(_reserve, msg.sender, _amount, isFirstDeposit)`
- `AToken.mintOnDeposit(msg.sender, _amount)`
- `LendingPoolCore.transferToReserve{value: msg.value}(_reserve, payable(msg.sender), _amount)`

### `LendingPoolCore`

Stores reserve state, user reserve data, and the deposited funds.

For deposit, it must know which aToken belongs to a reserve, whether the reserve
is active or frozen, how to update indexes and rates, and how to pull the
underlying asset from the user.

Required setup and deposit functions:

- `constructor(address _addressesProvider)`
- `initReserve(address _reserve, address _aTokenAddress, uint256 _decimals, address _interestRateStrategyAddress)`
- `updateStateOnDeposit(address _reserve, address _user, uint256 _amount, bool _isFirstDeposit)`
- `transferToReserve(address _reserve, address payable _user, uint256 _amount)`
- `setUserUseReserveAsCollateral(address _reserve, address _user, bool _useAsCollateral)`
- `_updateReserveInterestRatesAndTimestamp(address _reserve, uint256 _liquidityAdded, uint256 _liquidityTaken)`
- `_addReserveToList(address _reserve)`

Required view functions:

- `getReserveATokenAddress(address _reserve)`
- `getReserveAvailableLiquidity(address _reserve)`
- `getReserveNormalizedIncome(address _reserve)`
- `getReserveTotalBorrows(address _reserve)`
- `getUserBasicReserveData(address _reserve, address _user)`
- `getUserUnderlyingAssetBalance(address _reserve, address _user)`
- `getReserveIsActive(address _reserve)`
- `getReserveIsFreezed(address _reserve)`
- `getReserves()`

Important permissions:

- `onlyLendingPool()` protects deposit-time state updates and transfers.
- `onlyLendingPoolConfigurator()` protects reserve initialization.

For ERC20 deposits, `transferToReserve()` calls `safeTransferFrom(_user,
address(this), _amount)`, so the user approves `LendingPoolCore`, not
`LendingPool`.

### `AToken`

Represents the user's supplied liquidity.

During deposit, `LendingPool` mints aTokens to the depositor through
`mintOnDeposit()`. The aToken also tracks user indexes so interest can be
materialized before a later deposit.

Required functions:

- `constructor(address _addressesProvider, address _underlyingAsset, uint8 _underlyingAssetDecimals, string memory _name, string memory _symbol)`
- `mintOnDeposit(address _account, uint256 _amount)`
- `balanceOf(address _user)`
- `totalSupply()`
- `principalBalanceOf(address _user)`
- `decimals()`
- `getPoolAddress()`
- `getUnderlyingAssetAddress()`
- `getUserIndex(address _user)`
- `_cumulateBalance(address _user)`
- `_updateRedirectedBalanceOfRedirectionAddress(address _user, uint256 _balanceToAdd, uint256 _balanceToRemove)`
- `_calculateCumulatedBalance(address _user, uint256 _balance)`

Important permission:

- `onlyLendingPool()` protects `mintOnDeposit()`.

### `LendingPoolAddressesProvider`

Registry used by the pool, core, and aToken to find each other.

Deposit depends on this contract because authorization checks compare callers
against the registered `LendingPool`, and constructors resolve the registered
core and pool addresses.

Required functions:

- `constructor(address _owner)`
- `setLendingPool(address _pool)`
- `setLendingPoolCore(address _lendingPoolCore)`
- `setLendingPoolConfigurator(address _configurator)`
- `getLendingPool()`
- `getLendingPoolCore()`
- `getLendingPoolConfigurator()`

### `AddressStorage`

Small base contract used by `LendingPoolAddressesProvider`.

Required functions:

- `_setAddress(bytes32 _key, address _value)`
- `getAddress(bytes32 _key)`

### Reserve ERC20

The reserve token is the underlying asset being deposited, such as DAI.

In tests this is `MockERC20`, but any ERC20-compatible reserve needs the normal
ERC20 functions used by the flow.

Required functions:

- `approve(address spender, uint256 amount)`
- `transferFrom(address from, address to, uint256 amount)`
- `balanceOf(address account)`
- `decimals()`

Test-only helper:

- `MockERC20.mint(address to, uint256 amount)`

### Interest Rate Strategy

`LendingPoolCore` calls the reserve's interest rate strategy whenever a deposit
updates reserve state.

Required interface functions:

- `calculateInterestRates(address _reserve, uint256 _utilizationrate, uint256 _totalBorrowsStable, uint256 _totalBorrowsVariable, uint256 _averageStableBorrowRate)`
- `getBaseVariableBorrowRate()`

The current tests use `MockReserveInterestRateStrategy`.

## Libraries Involved

### `CoreLibrary`

Defines reserve and user accounting structs and the reserve math helpers used
by `LendingPoolCore`.

Required items:

- `ReserveData`
- `UserReserveData`
- `init(ReserveData storage _self, address _aTokenAddress, uint256 _decimals, address _interestRateStrategyAddress)`
- `updateCumulativeIndexes(ReserveData storage _self)`
- `getNormalizedIncome(ReserveData storage _reserve)`
- `getTotalBorrows(ReserveData storage _reserve)`
- `getCompoundedBorrowBalance(UserReserveData storage _self, ReserveData storage _reserve)`
- `calculateLinearInterest(uint256 _rate, uint40 _lastUpdateTimestamp)`
- `calculateCompoundedInterest(uint256 _rate, uint40 _lastUpdateTimestamp)`

### `WadRayMath`

Used by `CoreLibrary` and `AToken` for wad/ray conversions and interest math.

Required functions include:

- `ray()`
- `wadToRay(uint256)`
- `rayToWad(uint256)`
- `rayMul(uint256, uint256)`
- `rayDiv(uint256, uint256)`
- `rayPow(uint256, uint256)`

### `EthAddressLib`

Used by `LendingPoolCore.transferToReserve()` to distinguish native ETH
reserves from ERC20 reserves.

Required function:

- `ethAddress()`

### OpenZeppelin Dependencies

These are not project-specific contracts, but the deposit flow relies on them.

- `ReentrancyGuard.nonReentrant()` protects `LendingPool.deposit()`.
- `ERC20.balanceOf()`, `ERC20._mint()`, `ERC20.totalSupply()`, and
  `ERC20.decimals()` are used by `AToken` and test reserves.
- `SafeERC20.safeTransferFrom()` is used by `LendingPoolCore.transferToReserve()`.
- `Ownable.onlyOwner` protects address-provider setters.

## Required Setup Before Deposit

A reserve must be configured before users can deposit into it.

Minimum setup order:

1. Deploy `LendingPoolAddressesProvider`.
2. Deploy `LendingPoolCore` with the addresses provider.
3. Register the core with `setLendingPoolCore()`.
4. Deploy `LendingPool` with the addresses provider.
5. Register the pool with `setLendingPool()`.
6. Register the configurator with `setLendingPoolConfigurator()`.
7. Deploy the reserve token, such as DAI.
8. Deploy the matching aToken, such as aDAI.
9. Deploy or select an interest rate strategy.
10. From the registered configurator, call `core.initReserve()`.
11. Give the user reserve tokens.
12. User calls `reserve.approve(address(core), amount)`.
13. User calls `pool.deposit(reserve, amount, referralCode)`.

The important reserve initialization call is:

```solidity
core.initReserve(
    reserve,
    aToken,
    reserveDecimals,
    interestRateStrategy
);
```

This stores the aToken address, sets the initial liquidity and variable borrow
indexes to `1 ray`, stores the interest rate strategy, and marks the reserve as
active and not frozen.

## `LendingPool.deposit()` Execution

The implemented function follows this order.

### 1. Validate the Request

The modifiers check:

- reserve is active: `core.getReserveIsActive(_reserve)`
- reserve is not frozen: `core.getReserveIsFreezed(_reserve) == false`
- amount is greater than zero
- call is not reentrant

### 2. Resolve the aToken

```solidity
AToken aToken = AToken(i_core.getReserveATokenAddress(_reserve));
```

The pool asks the core which aToken represents the reserve.

### 3. Detect First Deposit

```solidity
bool isFirstDeposit = aToken.balanceOf(msg.sender) == 0;
```

The result is passed to the core. On a first deposit, the core enables the
reserve as collateral for that user.

### 4. Update Reserve State

```solidity
i_core.updateStateOnDeposit(
    _reserve,
    msg.sender,
    _amount,
    isFirstDeposit
);
```

Inside the core:

- `updateCumulativeIndexes()` updates reserve indexes if there are borrows.
- `_updateReserveInterestRatesAndTimestamp()` calls the interest rate strategy
  and stores the new rates and timestamp.
- `setUserUseReserveAsCollateral()` is called if this is the user's first
  deposit.

### 5. Mint aTokens

```solidity
aToken.mintOnDeposit(msg.sender, _amount);
```

Inside the aToken:

- `_cumulateBalance()` materializes any accrued interest for the user.
- the user index is updated from `core.getReserveNormalizedIncome()`.
- `_updateRedirectedBalanceOfRedirectionAddress()` handles interest redirection
  accounting if configured.
- `_mint(_account, _amount)` mints the new deposit amount.

### 6. Transfer the Underlying Asset

```solidity
i_core.transferToReserve{value: msg.value}(
    _reserve,
    payable(msg.sender),
    _amount
);
```

For ERC20 reserves:

- `msg.value` must be zero.
- the core calls `safeTransferFrom(user, core, amount)`.
- the user must have approved the core.

For the native ETH reserve:

- `_reserve` must equal `EthAddressLib.ethAddress()`.
- `msg.value` must be at least `_amount`.
- any extra ETH is refunded to the user.

### 7. Emit the Event

```solidity
emit Deposit(
    _reserve,
    msg.sender,
    _amount,
    _referralCode,
    block.timestamp
);
```

If any previous step reverts, the whole transaction reverts.

## Minimal ERC20 Deposit Example

Assume:

```text
reserve = DAI
aToken = aDAI
amount = 100 ether
referralCode = 0
```

The user prepares the deposit:

```solidity
dai.approve(address(core), 100 ether);
```

Then the user calls:

```solidity
pool.deposit(address(dai), 100 ether, 0);
```

Expected result:

```text
user DAI decreases by 100
core DAI increases by 100
user aDAI increases by 100, plus any materialized interest
first deposit enables DAI as collateral for the user
```
