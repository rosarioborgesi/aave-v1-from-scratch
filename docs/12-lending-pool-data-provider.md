# LendingPoolDataProvider

`LendingPoolDataProvider` is the protocol's high-level data aggregation contract.

It does not hold funds and it does not mutate protocol state.

Instead, it reads from:

```text
LendingPoolCore
PriceOracle
LendingPoolAddressesProvider
```

and combines that information into values that are useful for protocol decisions.

The most important examples are:

```text
user collateral balance in ETH
user borrow balance in ETH
user fees in ETH
weighted average LTV
weighted average liquidation threshold
health factor
whether a user can safely reduce an aToken balance
collateral required for a new borrow
```

A useful mental model is:

```text
LendingPoolCore
    = stores reserve and user state

LendingPoolDataProvider
    = reads that state and calculates higher-level risk data

AToken / LendingPool
    = use that data to decide whether user actions are allowed
```

# Why This Contract Exists

Without `LendingPoolDataProvider`, the core protocol contracts would need to repeat the same cross-reserve calculations in multiple places.

That would mix two different responsibilities:

```text
storing protocol state
calculating high-level user risk data
```

The data provider keeps those concerns separate.

The split is:

```text
LendingPoolCore
    stores reserve and user data

LendingPoolDataProvider
    aggregates reserve and user data into risk metrics

AToken / LendingPool
    use those risk metrics to validate user actions
```

This makes the protocol easier to reason about as borrowing, collateral management, and liquidation logic are added.

# Main Responsibilities

The current implementation of `LendingPoolDataProvider` has four main responsibilities:

```text
1. Calculate a user's global position across all reserves.
2. Calculate a user's health factor.
3. Check whether decreasing a user's aToken balance keeps the position healthy.
4. Calculate the collateral required to cover a new borrow.
```

This contract becomes especially important once the protocol supports borrowing, collateral checks, redemptions, transfers, and liquidations.


# Stored State

## `HEALTH_FACTOR_LIQUIDATION_THRESHOLD`

```solidity
uint256 private constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18;
```

This constant represents the minimum safe health factor.

The health factor uses wad precision:

```text
1e18 = 1.0
```

If a user's health factor is below `1e18`, the position is considered below the liquidation threshold.

In plain terms:

```text
health factor >= 1.0 -> position is safe
health factor < 1.0  -> position can be liquidated
```


# Local Variable Structs

The contract defines local variable structs to avoid Solidity's "stack too deep" error.

These structs are not protocol storage. They are temporary memory containers used during calculations.

## `BalanceDecreaseAllowedLocalVars`

```solidity
struct BalanceDecreaseAllowedLocalVars
```

This struct stores intermediate values used by `balanceDecreaseAllowed()`.

It contains values such as:

```text
reserve decimals
current collateral balance in ETH
current borrow balance in ETH
current liquidation threshold
amount being removed in ETH
new collateral balance after the decrease
new liquidation threshold after the decrease
```

## `UserGlobalDataLocalVars`

```solidity
struct UserGlobalDataLocalVars
```

This struct stores intermediate values used by `calculateUserGlobalData()`.

It contains values such as:

```text
reserve price
token unit
user liquidity balance
user borrow balance
reserve decimals
reserve LTV
reserve liquidation threshold
origination fee
collateral flags
current reserve address
```


# Health Factor Calculation

## `_calculateHealthFactorFromBalances`

```solidity
function _calculateHealthFactorFromBalances(
    uint256 collateralBalanceETH,
    uint256 borrowBalanceETH,
    uint256 totalFeesETH,
    uint256 liquidationThreshold
) internal pure returns (uint256)
```

This internal function calculates a user's health factor from already-aggregated balances.

The formula is:

```text
health factor =
    collateral value adjusted by liquidation threshold
    /
    debt plus fees
```

In code:

```solidity
return ((collateralBalanceETH * liquidationThreshold) / 100)
    .wadDiv(borrowBalanceETH + totalFeesETH);
```

## No Borrow Case

If the user has no borrow balance, the function returns the maximum `uint256` value:

```solidity
if (borrowBalanceETH == 0) {
    return type(uint256).max;
}
```

This makes sense because a user with no debt cannot be liquidated.

Example:

```text
collateral = 10 ETH
borrow = 0 ETH

health factor = max uint256
```

## Borrow Case

Example:

```text
collateral = 2 ETH
liquidation threshold = 80
borrow = 1 ETH
fees = 0 ETH
```

First, collateral is adjusted by the liquidation threshold:

```text
2 ETH * 80 / 100 = 1.6 ETH
```

Then the adjusted collateral is divided by debt:

```text
1.6 ETH / 1 ETH = 1.6
```

Because the result uses wad precision:

```text
health factor = 1.6e18
```

# Balance Decrease Check

## `balanceDecreaseAllowed`

```solidity
function balanceDecreaseAllowed(
    address _reserve,
    address _user,
    uint256 _amount
) external view returns (bool)
```

This function answers one question:

```text
Can this user reduce this reserve balance by this amount
without making their borrow position unsafe?
```

This is used before a user transfers or redeems aTokens.

Reducing an aToken balance can reduce the user's collateral. If the user has active debt, that reduction can lower the health factor.

## Step 1: Read Reserve Configuration

The function first reads:

```text
reserve decimals
reserve liquidation threshold
whether the reserve can be used as collateral
```

```solidity
(vars.decimals,, vars.reserveLiquidationThreshold, vars.reserveUsageAsCollateralEnabled) =
    i_core.getReserveConfiguration(_reserve);
```

## Step 2: Allow If The Reserve Is Not Collateral

If the reserve is not enabled as collateral, or the user is not using it as collateral, reducing the balance cannot harm the user's collateral position.

In that case, the function returns:

```text
true
```

## Step 3: Read The User Global Position

The function calls:

```solidity
calculateUserGlobalData(_user)
```

and uses the result to get:

```text
total collateral balance in ETH
total borrow balance in ETH
total fees in ETH
current weighted liquidation threshold
```

## Step 4: Allow If The User Has No Debt

If the user has no borrow balance, there is no liquidation risk.

The function returns:

```text
true
```

## Step 5: Convert The Decrease Amount To ETH

The function gets the reserve price from the oracle:

```solidity
oracle.getAssetPrice(_reserve)
```

Then it converts `_amount` into ETH:

```solidity
vars.amountToDecreaseETH =
    oracle.getAssetPrice(_reserve) * _amount / (10 ** vars.decimals);
```

Example:

```text
amount = 100 DAI
DAI price = 0.0005 ETH

amount to decrease = 0.05 ETH
```

## Step 6: Simulate The New Collateral Balance

The function subtracts the decrease amount from the user's collateral:

```solidity
vars.collateralBalanceAfterDecrease =
    vars.collateralBalanceETH - vars.amountToDecreaseETH;
```

If the result is zero while the user still has debt, the function returns:

```text
false
```

Debt with no collateral is unsafe.

## Step 7: Recalculate The Weighted Liquidation Threshold

When collateral is removed, the user's average liquidation threshold can change.

Example before decrease:

```text
1 ETH of DAI collateral, liquidation threshold = 80
1 ETH of WETH collateral, liquidation threshold = 85

weighted liquidation threshold = 82.5
```

If the user removes `0.5 ETH` worth of DAI, the remaining collateral is:

```text
0.5 ETH of DAI at 80
1 ETH of WETH at 85
```

The new weighted threshold is different because the collateral mix changed.

The function calculates this by removing the decreased collateral's contribution:

```solidity
vars.liquidationThresholdAfterDecrease =
    (
        vars.collateralBalanceETH
            * vars.currentLiquidationThreshold
            - vars.amountToDecreaseETH
            * vars.reserveLiquidationThreshold
    ) / vars.collateralBalanceAfterDecrease;
```

## Step 8: Recalculate Health Factor

The function calculates what the user's health factor would be after the decrease:

```solidity
uint256 healthFactorAfterDecrease =
    _calculateHealthFactorFromBalances(
        vars.collateralBalanceAfterDecrease,
        vars.borrowBalanceETH,
        vars.totalFeesETH,
        vars.liquidationThresholdAfterDecrease
    );
```

Then it returns:

```solidity
return healthFactorAfterDecrease > HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
```

So the decrease is allowed only if the user remains above a health factor of `1`.

# User Global Data

## `calculateUserGlobalData`

```solidity
function calculateUserGlobalData(address _user)
    public
    view
    returns (
        uint256 totalLiquidityBalanceETH,
        uint256 totalCollateralBalanceETH,
        uint256 totalBorrowBalanceETH,
        uint256 totalFeesETH,
        uint256 currentLtv,
        uint256 currentLiquidationThreshold,
        uint256 healthFactor,
        bool healthFactorBelowThreshold
    )
```

This function calculates the user's full protocol position across all reserves.

It loops through every initialized reserve in `LendingPoolCore` and aggregates the user's data in ETH.

It returns:

```text
total liquidity balance in ETH
total collateral balance in ETH
total borrow balance in ETH
total fees in ETH
weighted average LTV
weighted average liquidation threshold
health factor
whether health factor is below 1
```

## Step 1: Load Oracle And Reserves

The function resolves the price oracle:

```solidity
IPriceOracleGetter oracle =
    IPriceOracleGetter(i_addressesProvider.getPriceOracle());
```

Then it gets the reserve list:

```solidity
address[] memory reserves = i_core.getReserves();
```

## Step 2: Read User Data For Each Reserve

For each reserve, the function asks `LendingPoolCore` for:

```text
user deposited balance, including accrued interest
user compounded borrow balance
user origination fee
whether the user enabled the reserve as collateral
```

```solidity
(
    vars.compoundedLiquidityBalance,
    vars.compoundedBorrowBalance,
    vars.originationFee,
    vars.userUsesReserveAsCollateral
) = i_core.getUserBasicReserveData(vars.currentReserve, _user);
```

If the user has neither supplied nor borrowed that reserve, the function skips it.

## Step 3: Read Reserve Configuration

For each reserve the user uses, the function reads:

```text
reserve decimals
reserve base LTV
reserve liquidation threshold
whether the reserve can be used as collateral
```

```solidity
(vars.reserveDecimals, vars.baseLtv, vars.liquidationThreshold, vars.usageAsCollateralEnabled) =
    i_core.getReserveConfiguration(vars.currentReserve);
```

It also gets the reserve price from the oracle:

```solidity
vars.reserveUnitPrice = oracle.getAssetPrice(vars.currentReserve);
```

## Step 4: Convert Deposits To ETH

If the user supplied the reserve, the function converts that balance into ETH:

```solidity
uint256 liquidityBalanceETH =
    vars.reserveUnitPrice
        * vars.compoundedLiquidityBalance
        / vars.tokenUnit;
```

Example:

```text
user deposit = 1000 DAI
DAI price = 0.0005 ETH
token unit = 1e18

liquidity balance = 0.5 ETH
```

This value is added to:

```text
totalLiquidityBalanceETH
```

## Step 5: Count Collateral Only When It Is Enabled

A deposit counts as collateral only when both conditions are true:

```text
the reserve allows collateral usage
the user enabled this reserve as collateral
```

If both are true, the function adds the ETH value to:

```text
totalCollateralBalanceETH
```

It also accumulates weighted values for:

```text
currentLtv
currentLiquidationThreshold
```

Example:

```text
1 ETH of DAI collateral, LTV = 75
2 ETH of WETH collateral, LTV = 80

weighted LTV sum = 1 * 75 + 2 * 80 = 235
```

The final weighted average is calculated after the loop.

## Step 6: Convert Borrows And Fees To ETH

If the user borrowed from the reserve, the function converts the borrow balance into ETH:

```solidity
totalBorrowBalanceETH +=
    vars.reserveUnitPrice
        * vars.compoundedBorrowBalance
        / vars.tokenUnit;
```

It also converts the origination fee into ETH:

```solidity
totalFeesETH +=
    vars.originationFee
        * vars.reserveUnitPrice
        / vars.tokenUnit;
```

Example:

```text
borrow = 500 DAI
fee = 10 DAI
DAI price = 0.0005 ETH

borrow balance = 0.25 ETH
fee balance = 0.005 ETH
```

## Step 7: Finalize Weighted Averages

After all reserves are processed, the function converts weighted sums into weighted averages:

```solidity
currentLtv =
    totalCollateralBalanceETH > 0
        ? currentLtv / totalCollateralBalanceETH
        : 0;
```

```solidity
currentLiquidationThreshold =
    totalCollateralBalanceETH > 0
        ? currentLiquidationThreshold / totalCollateralBalanceETH
        : 0;
```

Example:

```text
1 ETH collateral at 75 LTV
2 ETH collateral at 80 LTV

weighted LTV = (1 * 75 + 2 * 80) / 3
weighted LTV = 78.33
```

## Step 8: Calculate Health Factor

Finally, the function calculates the health factor:

```solidity
healthFactor = _calculateHealthFactorFromBalances(
    totalCollateralBalanceETH,
    totalBorrowBalanceETH,
    totalFeesETH,
    currentLiquidationThreshold
);
```

Then it checks whether the result is below the liquidation threshold:

```solidity
healthFactorBelowThreshold =
    healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
```

# Example Full Position

Assume Alice has:

```text
Deposits:
1 ETH worth of DAI, LTV = 75, liquidation threshold = 80
2 ETH worth of WETH, LTV = 80, liquidation threshold = 85

Borrow:
1 ETH worth of USDC

Fees:
0.05 ETH
```

The data provider calculates:

```text
totalLiquidityBalanceETH = 3 ETH
totalCollateralBalanceETH = 3 ETH
totalBorrowBalanceETH = 1 ETH
totalFeesETH = 0.05 ETH
```

Weighted LTV:

```text
(1 * 75 + 2 * 80) / 3 = 78.33
```

Weighted liquidation threshold:

```text
(1 * 80 + 2 * 85) / 3 = 83.33
```

Health factor:

```text
(3 ETH * 83.33%) / (1 ETH + 0.05 ETH)
= 2.38
```

In wad precision:

```text
healthFactor = 2.38e18
```

Alice is safely above the liquidation threshold.


# Collateral Needed for a New Borrow

## `calculateCollateralNeededInETH`

```solidity
function calculateCollateralNeededInETH(
    address _reserve,
    uint256 _amount,
    uint256 _fee,
    uint256 _userCurrentBorrowBalanceETH,
    uint256 _userCurrentFeesETH,
    uint256 _userCurrentLtv
) external view returns (uint256)
```

This function calculates the minimum total collateral, denominated in ETH, that a user must have after taking a new borrow.

`LendingPool.borrow()` uses it to determine whether the user's collateral is sufficient to cover their existing debt, fees, and the new borrow.

The calculation includes all debt the user would owe after the borrow:

```text
existing borrow balance in ETH
+ existing origination fees in ETH
+ requested borrow amount in ETH
+ fee for the requested borrow in ETH
```

The requested amount and its new fee are expressed in units of the asset being borrowed (whose address is `_reserve`). The function first converts them to ETH using the reserve’s decimals and the price oracle:

```text
requestedBorrowAmountETH =
    asset price in ETH * (_amount + _fee) / 10^reserveDecimals
```

It then divides the resulting total debt by the user's weighted average LTV:

```text
collateralNeededInETH =
    (existing debt + existing fees + requested borrow and fee in ETH)
    * 100
    / current LTV
```

LTV is stored as a percentage, so an LTV of `75` means the user may borrow up to `75%` of their collateral value. Dividing by `75` and multiplying by `100` reverses that relationship to find the collateral required for a given debt.

### Example

Assume the user has a weighted average LTV of `75%` and already owes:

```text
existing borrow balance = 0.5 ETH
existing fees           = 0.05 ETH
```

They want to borrow `1,000 DAI`. DAI has `18` decimals, its oracle price is `0.0005 ETH`, and the new origination fee is `10 DAI`.

First, convert the new borrow plus fee to ETH:

```text
(1,000 DAI + 10 DAI) * 0.0005 ETH per DAI
= 0.505 ETH
```

Then calculate the total debt after the borrow:

```text
0.5 ETH + 0.05 ETH + 0.505 ETH = 1.055 ETH
```

Finally, calculate the collateral required at a `75%` LTV:

```text
1.055 ETH * 100 / 75 = 1.406666666666666666 ETH
```

Therefore, the user needs at least `1.406666666666666666 ETH` of eligible collateral. A user with `1.4 ETH` of collateral cannot complete the borrow, while a user with `1.5 ETH` can, assuming the earlier health-factor checks pass.
