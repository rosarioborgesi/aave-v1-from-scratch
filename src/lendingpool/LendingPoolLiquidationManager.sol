// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {LendingPoolCore} from "src/lendingpool/LendingPoolCore.sol";
import {LendingPoolDataProvider} from "src/lendingpool/LendingPoolDataProvider.sol";
import {AToken} from "src/tokenization/AToken.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolParametersProvider} from "src/configuration/LendingPoolParametersProvider.sol";
import {IFeeProvider} from "src/interfaces/IFeeProvider.sol";
import {CoreLibrary} from "src/libraries/CoreLibrary.sol";
import {IPriceOracleGetter} from "src/interfaces/IPriceOracleGetter.sol";

/**
 * @title LendingPoolLiquidationManager contract
 * @notice Implements the liquidation function.
 *
 */
contract LendingPoolLiquidationManager is ReentrancyGuard {
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////

    ///////////////////////////////////
    //            Libraries          //
    ///////////////////////////////////

    //////////////////////////////////
    //      Type declarations       //
    //////////////////////////////////

    struct LiquidationCallLocalVars {
        uint256 userCollateralBalance;
        uint256 userCompoundedBorrowBalance;
        uint256 borrowBalanceIncrease;
        uint256 maxPrincipalAmountToLiquidate;
        uint256 actualAmountToLiquidate;
        uint256 liquidationRatio;
        uint256 collateralPrice;
        uint256 principalCurrencyPrice;
        uint256 maxAmountCollateralToLiquidate;
        uint256 originationFee;
        uint256 feeLiquidated;
        uint256 liquidatedCollateralForFee;
        CoreLibrary.InterestRateMode borrowRateMode;
        uint256 userStableRate;
        bool isCollateralEnabled;
        bool healthFactorBelowThreshold;
    }

    enum LiquidationErrors {
        NO_ERROR,
        NO_COLLATERAL_AVAILABLE,
        COLLATERAL_CANNOT_BE_LIQUIDATED,
        CURRENCY_NOT_BORROWED,
        HEALTH_FACTOR_ABOVE_THRESHOLD,
        NOT_ENOUGH_LIQUIDITY
    }

    struct AvailableCollateralToLiquidateLocalVars {
        uint256 userCompoundedBorrowBalance;
        uint256 liquidationBonus;
        uint256 collateralPrice;
        uint256 principalCurrencyPrice;
        uint256 maxAmountCollateralToLiquidate;
    }

    ////////////////////////////////
    //      State Variables       //
    ////////////////////////////////
    LendingPoolAddressesProvider private s_addressesProvider;
    LendingPoolCore private s_core;
    LendingPoolDataProvider private s_dataProvider;
    LendingPoolParametersProvider private s_parametersProvider;
    IFeeProvider private s_feeProvider;
    address private s_ethereumAddress;

    uint256 constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 50;

    ////////////////////////////////
    //           Events           //
    ////////////////////////////////

    /**
     * @dev emitted when a borrow fee is liquidated
     * @param _collateral the address of the collateral being liquidated
     * @param _reserve the address of the reserve
     * @param _user the address of the user being liquidated
     * @param _feeLiquidated the total fee liquidated
     * @param _liquidatedCollateralForFee the amount of collateral received by the protocol in exchange for the fee
     * @param _timestamp the timestamp of the action
     *
     */
    event OriginationFeeLiquidated(
        address indexed _collateral,
        address indexed _reserve,
        address indexed _user,
        uint256 _feeLiquidated,
        uint256 _liquidatedCollateralForFee,
        uint256 _timestamp
    );

    /**
     * @dev emitted when a borrower is liquidated
     * @param _collateral the address of the collateral being liquidated
     * @param _reserve the address of the reserve
     * @param _user the address of the user being liquidated
     * @param _purchaseAmount the total amount liquidated
     * @param _liquidatedCollateralAmount the amount of collateral being liquidated
     * @param _accruedBorrowInterest the amount of interest accrued by the borrower since the last action
     * @param _liquidator the address of the liquidator
     * @param _receiveAToken true if the liquidator wants to receive aTokens, false otherwise
     * @param _timestamp the timestamp of the action
     *
     */
    event LiquidationCall(
        address indexed _collateral,
        address indexed _reserve,
        address indexed _user,
        uint256 _purchaseAmount,
        uint256 _liquidatedCollateralAmount,
        uint256 _accruedBorrowInterest,
        address _liquidator,
        bool _receiveAToken,
        uint256 _timestamp
    );

    ////////////////////////////////
    //          Modifiers         //
    ////////////////////////////////

    ////////////////////////////////
    //          Functions         //
    ////////////////////////////////

    ////////////////////////////////
    //     External Functions     //
    ////////////////////////////////

    /**
     * @dev users can invoke this function to liquidate an undercollateralized position.
     * @param _reserve the address of the collateral to liquidated
     * @param _reserve the address of the principal reserve
     * @param _user the address of the borrower
     * @param _purchaseAmount the amount of principal that the liquidator wants to repay
     * @param _receiveAToken true if the liquidators wants to receive the aTokens, false if
     * he wants to receive the underlying asset directly
     *
     */
    function liquidationCall(
        address _collateral,
        address _reserve,
        address _user,
        uint256 _purchaseAmount,
        bool _receiveAToken
    ) external payable returns (uint256, string memory) {
        // Usage of a memory struct of vars to avoid "Stack too deep" errors due to local variables
        LiquidationCallLocalVars memory vars;

        // Query the user's global data
        (,,,,,,, vars.healthFactorBelowThreshold) = s_dataProvider.calculateUserGlobalData(_user);

        // Only proceed if the health factor is below the liquidation threshold.
        if (!vars.healthFactorBelowThreshold) {
            return (uint256(LiquidationErrors.HEALTH_FACTOR_ABOVE_THRESHOLD), "Health factor is not below threshold");
        }

        // Get the user's collateral balance
        vars.userCollateralBalance = s_core.getUserUnderlyingAssetBalance(_collateral, _user);

        // The borrower must have a balance of _collateral
        if (vars.userCollateralBalance == 0) {
            return (uint256(LiquidationErrors.NO_COLLATERAL_AVAILABLE), "Invalid collateral to liquidate");
        }

        // The borrower must:
        //   - have that reserve enabled as collateral
        //   - and have personally opted to use it as collateral
        vars.isCollateralEnabled = s_core.isReserveUsageAsCollateralEnabled(_collateral)
            && s_core.isUserUseReserveAsCollateralEnabled(_collateral, _user);

        if (!vars.isCollateralEnabled) {
            return
                (
                    uint256(LiquidationErrors.COLLATERAL_CANNOT_BE_LIQUIDATED),
                    "The collateral chosen cannot be lquidated"
                );
        }

        // Get the user's compounded borrow balance and borrow balance increase
        (, vars.userCompoundedBorrowBalance, vars.borrowBalanceIncrease) = s_core.getUserBorrowBalances(_reserve, _user);

        // If the user hasn't borrowed the specific currency defined by _reserve, it cannot be liquidated
        if (vars.userCompoundedBorrowBalance == 0) {
            return (uint256(LiquidationErrors.CURRENCY_NOT_BORROWED), "User did not borrow the specified currency");
        }

        // A user can repay max 50% of the debt not all of it
        vars.maxPrincipalAmountToLiquidate = vars.userCompoundedBorrowBalance * LIQUIDATION_CLOSE_FACTOR_PERCENT / 100;

        // The actual repayment is the smaller of _purchaseAmount and 50 % limit
        vars.actualAmountToLiquidate =
            _purchaseAmount > vars.maxPrincipalAmountToLiquidate ? vars.maxPrincipalAmountToLiquidate : _purchaseAmount;

        // Price the seized collateral
        (uint256 maxCollateralToLiquidate, uint256 principalAmountNeeded) = _calculateAvailableCollateralToLiquidate(
            _collateral, _reserve, vars.actualAmountToLiquidate, vars.userCollateralBalance
        );

        // Get the origination fee
        vars.originationFee = s_core.getUserOriginationFee(_reserve, _user);

        // If there is a fee to liquidate, calculate the maximum amount of fee that can be liquidated
        // If such fee exists, this attempst to cover it using collateral left after the liquidator's collateral has been reserved
        // - liquidatedCollateralForFee: collateral to take for the protocol’s fee.
        // - feeLiquidated: amount of fee this collateral can cover.
        if (vars.originationFee > 0) {
            (vars.liquidatedCollateralForFee, vars.feeLiquidated) = _calculateAvailableCollateralToLiquidate(
                _collateral, _reserve, vars.originationFee, vars.userCollateralBalance - maxCollateralToLiquidate
            );
        }

        // If the account had insufficient collateral for the desired repayment,
        // reduce the actual debt repayment (vars.actualAmountToLiquidate)
        // to the amount supported by the collateral that will be seized (principalAmountNeeded)
        if (principalAmountNeeded < vars.actualAmountToLiquidate) {
            vars.actualAmountToLiquidate = principalAmountNeeded;
        }

        // If liquidator reclaims the underlying asset (not aTokens), we make sure
        // there is enough available collateral in the reserve
        if (!_receiveAToken) {
            uint256 currentAvailableCollateral = s_core.getReserveAvailableLiquidity(_collateral);
            if (currentAvailableCollateral < maxCollateralToLiquidate) {
                return (
                    uint256(LiquidationErrors.NOT_ENOUGH_LIQUIDITY),
                    "There isn't neough liquidity available to liquidate"
                );
            }
        }

        // Update the protocol's accounting before asset transfers:
        // - principal reserve debt and interest state;
        // - borrower’s debt and origination-fee state;
        // - collateral reserve state;
        // - reserve interest rates and timestamps.
        s_core.updateStateOnLiquidation(
            _reserve,
            _collateral,
            _user,
            vars.actualAmountToLiquidate,
            maxCollateralToLiquidate,
            vars.feeLiquidated,
            vars.liquidatedCollateralForFee,
            vars.borrowBalanceIncrease,
            _receiveAToken
        );

        // Looks up the AToken contract corresponding to the collateral reserve
        // and casts its address to AToken
        AToken collateralAToken = AToken(s_core.getReserveATokenAddress(_collateral));

        // If liquidator reclaims the aToken, he receives the equivalent atoken amount
        if (_receiveAToken) {
            collateralAToken.transferOnLiquidation(_user, msg.sender, maxCollateralToLiquidate);
        } else {
            // Otherwise:
            // 1. Burn the borrower's aTokens representing the seized deposit
            // 2. Transfer the matching underlying collateral from the pool to the liquidator
            collateralAToken.burnOnLiquidation(_user, maxCollateralToLiquidate);
            s_core.transferToUser(_collateral, payable(msg.sender), maxCollateralToLiquidate);
        }

        // Collect the debt repayment from the liquidator.
        s_core.transferToReserve{value: msg.value}(_reserve, payable(msg.sender), vars.actualAmountToLiquidate);

        if (vars.feeLiquidated > 0) {
            // Burn the borrower's aTokens corresponding to collateral reserved for the protocol fee.
            collateralAToken.burnOnLiquidation(_user, vars.liquidatedCollateralForFee);

            // Liquidate the fee by transferring it to the fee collection address
            s_core.liquidateFee(
                _collateral, vars.liquidatedCollateralForFee, payable(s_addressesProvider.getTokenDistributor())
            );

            emit OriginationFeeLiquidated(
                _collateral, _reserve, _user, vars.feeLiquidated, vars.liquidatedCollateralForFee, block.timestamp
            );
        }

        emit LiquidationCall(
            _collateral,
            _reserve,
            _user,
            vars.actualAmountToLiquidate,
            maxCollateralToLiquidate,
            vars.borrowBalanceIncrease,
            msg.sender,
            _receiveAToken,
            //solium-disable-next-line
            block.timestamp
        );

        return (uint256(LiquidationErrors.NO_ERROR), "No errors");
    }

    //////////////////////////////////////////////////////
    //     Private & Internal View & Pure Functions     //
    //////////////////////////////////////////////////////
    /**
     * @dev Determines the collateral that can be seized for a given debt repayment and, when collateral is
     * insufficient, the debt amount that collateral can cover. The caller must have validated the reserve and
     * oracle configuration before calling this function.
     * @param _collateral The collateral asset to be liquidated.
     * @param _principal The debt asset being repaid.
     * @param _purchaseAmount The already-capped amount of principal to liquidate.
     * @param _userCollateralBalance The user's balance of the selected collateral asset.
     * @return collateralAmount The collateral amount that can be liquidated.
     * @return principalAmountNeeded The principal amount covered by `collateralAmount`.
     */
    function _calculateAvailableCollateralToLiquidate(
        address _collateral,
        address _principal,
        uint256 _purchaseAmount,
        uint256 _userCollateralBalance
    ) internal view returns (uint256 collateralAmount, uint256 principalAmountNeeded) {
        // Initialize the return values
        collateralAmount = 0;
        principalAmountNeeded = 0;
        // Fetch the price oracle
        IPriceOracleGetter oracle = IPriceOracleGetter(s_addressesProvider.getPriceOracle());

        // Usage of a memory struct of vars to avoid "Stack too deep" errors due to local variables
        AvailableCollateralToLiquidateLocalVars memory vars;

        // Read the oracle price of the asset being seized
        vars.collateralPrice = oracle.getAssetPrice(_collateral);

        // Read the oracle price of the debt asset being repaid
        vars.principalCurrencyPrice = oracle.getAssetPrice(_principal);

        // Get the liquidation bonus for the collateral reserve
        vars.liquidationBonus = s_core.getReserveLiquidationBonus(_collateral);

        // Compute the maximum collateral corresponding to the requested repayment
        //
        // Let's convert the debt being repaid into an equivalent amount of collateral, then add the liquidation incentive.
        // Let:
        // - repayment = amount of debt asset the liquidator repays
        // - principalPrice = value of 1 debt token in the oracle's base currency
        // - collateralPrice = value of 1 collateral token in that same base currency
        // - liquidationBonus = e.g 105, meaning the liquidator recieves 105% of the equivalent collateral value
        //
        //  repayment is denominated in the borrowed asset, while the liquidator is paid in collateral tokens.
        //
        // So:
        // 1. Convert the repaid debt into a common value (e.g. USD):
        //      debt value = principal Price x repayment
        // 2. Convert that value into an amount of collateral tokens:
        //      equivalent collateral = debt value / collateralPrice
        // 3. Apply the liquidation bonus
        //      collateral seized = equivalent collateral x liquidation Bonus / 100
        // 4. Final formula:
        //      maxCollateral = ( principal price x repayment / collateral price) x liquidation bonus / 100

        // Repaying 100 DAI at 0.0005 ETH/DAI is worth 0.05 ETH.
        // If WETH collateral is 1 ETH/WETH, the value-equivalent collateral is 0.05 WETH.
        // With a 105 liquidation bonus, the liquidator receives:
        // 0.05 WETH × 105 / 100 = 0.0525 WETH
        vars.maxAmountCollateralToLiquidate =
            vars.principalCurrencyPrice * _purchaseAmount / vars.collateralPrice * vars.liquidationBonus / 100;

        // Check if the calculated collateral seizure exceeds what the borrower owns
        if (vars.maxAmountCollateralToLiquidate > _userCollateralBalance) {
            // Seize only the borrower’s entire available balance
            collateralAmount = _userCollateralBalance;
            // supportedRepayment = collateral price × available collateral / principal price × 100 / liquidation bonus
            principalAmountNeeded =
                vars.collateralPrice * collateralAmount / vars.principalCurrencyPrice * 100 / vars.liquidationBonus;
        } else {
            // If sufficient collateral exists:
            // - seize the calculated collateral amount, and
            // - allow the requested repayment in full
            collateralAmount = vars.maxAmountCollateralToLiquidate;
            principalAmountNeeded = _purchaseAmount;
        }

        return (collateralAmount, principalAmountNeeded);
    }
}
