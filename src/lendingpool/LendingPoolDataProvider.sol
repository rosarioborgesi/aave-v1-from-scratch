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

import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolCore} from "./LendingPoolCore.sol";
import {IPriceOracleGetter} from "src/interfaces/IPriceOracleGetter.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";
import {AToken} from "src/tokenization/AToken.sol";
import {CoreLibrary} from "src/libraries/CoreLibrary.sol";
import {IFeeProvider} from "src/interfaces/IFeeProvider.sol";

/**
 * @title LendingPoolDataProvider contract
 * @notice Implements functions to fetch data from the core, and aggregate them in order to allow computation
 * on the compounded balances and the account balances in ETH
 *
 */
contract LendingPoolDataProvider {
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////
    error LendingPoolDataProvider__ZeroAddress();

    ///////////////////////////////////
    //            Libraries          //
    ///////////////////////////////////
    using WadRayMath for uint256;

    /////////////////////////////////
    //      Type Declarations      //
    /////////////////////////////////
    struct BalanceDecreaseAllowedLocalVars {
        uint256 decimals;
        uint256 collateralBalanceETH;
        uint256 borrowBalanceETH;
        uint256 totalFeesETH;
        uint256 currentLiquidationThreshold;
        uint256 reserveLiquidationThreshold;
        uint256 amountToDecreaseETH;
        uint256 collateralBalanceAfterDecrease;
        uint256 liquidationThresholdAfterDecrease;
        uint256 healthFactorAfterDecrease;
        bool reserveUsageAsCollateralEnabled;
    }

    /**
     * @dev struct to hold calculateUserGlobalData() local computations
     */
    struct UserGlobalDataLocalVars {
        uint256 reserveUnitPrice;
        uint256 tokenUnit;
        uint256 compoundedLiquidityBalance;
        uint256 compoundedBorrowBalance;
        uint256 reserveDecimals;
        uint256 baseLtv;
        uint256 liquidationThreshold;
        uint256 originationFee;
        bool usageAsCollateralEnabled;
        bool userUsesReserveAsCollateral;
        address currentReserve;
    }

    ///////////////////////////////
    //      State Variables      //
    ///////////////////////////////
    uint256 private constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18;

    LendingPoolAddressesProvider private immutable i_addressesProvider;
    LendingPoolCore private immutable i_core;

    ////////////////////////////////
    //           Events           //
    ////////////////////////////////

    ////////////////////////////////
    //          Modifiers         //
    ////////////////////////////////

    ////////////////////////////////
    //          Functions         //
    ////////////////////////////////
    constructor(address _addressesProvider) {
        if (_addressesProvider == address(0)) {
            revert LendingPoolDataProvider__ZeroAddress();
        }
        i_addressesProvider = LendingPoolAddressesProvider(_addressesProvider);

        address coreAddress = i_addressesProvider.getLendingPoolCore();
        if (coreAddress == address(0)) {
            revert LendingPoolDataProvider__ZeroAddress();
        }
        i_core = LendingPoolCore(payable(coreAddress));
    }

    ////////////////////////////////
    //     External Functions     //
    ////////////////////////////////

    ////////////////////////////////
    //       Public Functions     //
    ////////////////////////////////

    //////////////////////////////////
    //       Internal Functions     //
    //////////////////////////////////

    /**
     * @dev calculates the health factor from the corresponding balances
     * @param collateralBalanceETH the total collateral balance in ETH
     * @param borrowBalanceETH the total borrow balance in ETH
     * @param totalFeesETH the total fees in ETH
     * @param liquidationThreshold the avg liquidation threshold
     *
     */
    function _calculateHealthFactorFromBalances(
        uint256 collateralBalanceETH,
        uint256 borrowBalanceETH,
        uint256 totalFeesETH,
        uint256 liquidationThreshold
    ) internal pure returns (uint256) {
        // healthFactor = collateral x liquidation threshold / (borrow + fees)
        // healthFactor = collateral adjusted by liquidation threshold / (borrow + fees)

        // 1. No borrow = max health factor
        if (borrowBalanceETH == 0) {
            return type(uint256).max;
        }
        // 2. Adjust collateral by liquidation threshold:
        // (collateralBalanceETH * liquidationThreshold) / 100
        //
        // collateralBalanceETH = 2 ETH
        // liquidationThreshold = 80
        // 2 ETH * 80 / 100 = 1.6 ETH

        // 3. Divide by debt + fees
        // .wadDiv(borrowBalanceETH + totalFeesETH)
        //
        // adjusted collateral = 1.6 ETH
        // borrow + fees = 1 ETH
        // health factor = 1.6 = 1.6e18
        return ((collateralBalanceETH * liquidationThreshold) / 100).wadDiv(borrowBalanceETH + totalFeesETH);
    }

    /////////////////////////////////
    //       Private Functions     //
    /////////////////////////////////

    //////////////////////////////////////////////////////
    //     Private & Internal View & Pure Functions     //
    //////////////////////////////////////////////////////

    /**
     * @dev calculates the equivalent amount in ETH that an user can borrow, depending on the available collateral and the
     * average Loan To Value.
     * @param collateralBalanceETH the total collateral balance
     * @param borrowBalanceETH the total borrow balance
     * @param totalFeesETH the total fees
     * @param ltv the average loan to value
     * @return the amount available to borrow in ETH for the user
     *
     */

    function _calculateAvailableBorrowsETH(
        uint256 collateralBalanceETH,
        uint256 borrowBalanceETH,
        uint256 totalFeesETH,
        uint256 ltv
    ) internal view returns (uint256) {
        uint256 availableBorrowsETH = collateralBalanceETH * ltv / 100; //ltv is in percentage

        if (availableBorrowsETH < borrowBalanceETH) {
            return 0;
        }

        availableBorrowsETH = availableBorrowsETH + totalFeesETH - borrowBalanceETH;
        //calculate fee
        uint256 borrowFee = IFeeProvider(i_addressesProvider.getFeeProvider())
            .calculateLoanOriginationFee(msg.sender, availableBorrowsETH);
        return availableBorrowsETH - borrowFee;
    }

    //////////////////////////////////////////////////////
    //      External & Public View & Pure Functions     //
    //////////////////////////////////////////////////////

    /**
     * @dev check if a specific balance decrease is allowed (i.e. doesn't bring the user borrow position health factor under 1e18)
     * Can this user reduce/transfer/redeem this aToken balance without making their borrow position unsafe?
     * Simulates the user removing collateral and returns true only if the position stays healthy.
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     * @param _amount the amount to decrease
     * @return true if the decrease of the balance is allowed
     *
     */
    function balanceDecreaseAllowed(address _reserve, address _user, uint256 _amount) external view returns (bool) {
        // Usage of a memory struct of vars to avoid "Stack too deep" errors due to local variables
        BalanceDecreaseAllowedLocalVars memory vars;

        // read reserve configuration
        (vars.decimals,, vars.reserveLiquidationThreshold, vars.reserveUsageAsCollateralEnabled) =
            i_core.getReserveConfiguration(_reserve);

        // If this reserve is not collateral, allow decrease
        if (!vars.reserveUsageAsCollateralEnabled || !i_core.isUserUseReserveAsCollateralEnabled(_reserve, _user)) {
            return true;
        }

        // Read the user global position
        (, vars.collateralBalanceETH, vars.borrowBalanceETH, vars.totalFeesETH,, vars.currentLiquidationThreshold,,) =
            calculateUserGlobalData(_user);

        // If the user has no borrow, allow decrease
        // In other words: if the user has no debt, there is no liquidation risk
        if (vars.borrowBalanceETH == 0) {
            return true;
        }

        // get the oracle
        IPriceOracleGetter oracle = IPriceOracleGetter(i_addressesProvider.getPriceOracle());

        // Convert the decrease amount to ETH
        //
        // _amount = 100 DAI
        // DAI price = 0.0005 ETH
        // amountToDecreaseETH = 0.05 ETH
        vars.amountToDecreaseETH = oracle.getAssetPrice(_reserve) * _amount / (10 ** vars.decimals);

        // Calculate new collateral after decrease
        //
        // current collateral = 2 ETH
        // decrease amount = 0.5 ETH
        // collateral after decrease = 1.5 ETH
        vars.collateralBalanceAfterDecrease = vars.collateralBalanceETH - vars.amountToDecreaseETH;

        // If there is a borrow, there can't be 0 collateral
        if (vars.collateralBalanceAfterDecrease == 0) {
            return false;
        }

        // Recalculate liquidation threshold after removing collateral
        //
        // Example before decrease:
        // 1 ETH of DAI collateral, liquidation threshold = 80
        // 1 ETH of WETH collateral, liquidation threshold = 85
        //
        // current liquidation threshold = 82.5
        //
        // Now the user removes 0.5 ETH worth of DAI
        //
        // New collateral:
        // 0.5 ETH of DAI at 80
        // 1 ETH of WETH at 85
        //
        // New weighted liquidation threshold = (0.5 * 80 + 1 * 85) / 1.5 = 83.33
        vars.liquidationThresholdAfterDecrease =
            (vars.collateralBalanceETH
                    * vars.currentLiquidationThreshold
                    - vars.amountToDecreaseETH
                    * vars.reserveLiquidationThreshold) / vars.collateralBalanceAfterDecrease;

        // Calculate health factor after decrease
        uint256 healthFactorAfterDecrease = _calculateHealthFactorFromBalances(
            vars.collateralBalanceAfterDecrease,
            vars.borrowBalanceETH,
            vars.totalFeesETH,
            vars.liquidationThresholdAfterDecrease
        );

        // After removing this collateral, will the user still have health factor > 1?
        // Return true only if the user remains safe
        // or healthFactorAfterDecrease > 1e18
        return healthFactorAfterDecrease > HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    /**
     * @dev Calculates the user data across the reserves.
     * This includes the total liquidity/collateral/borrow balances in ETH,
     * the average Loan To Value, the average Liquidation Ratio, and the Health factor.
     * @param _user The address of the user.
     * @return totalLiquidityBalanceETH The total liquidity balance of the user in ETH.
     * @return totalCollateralBalanceETH The total collateral balance of the user in ETH.
     * @return totalBorrowBalanceETH The total borrow balance of the user in ETH.
     * @return totalFeesETH The total fees of the user in ETH.
     * @return currentLtv The weighted average LTV of the user.
     * @return currentLiquidationThreshold The weighted average liquidation threshold of the user.
     * @return healthFactor The health factor of the user.
     * @return healthFactorBelowThreshold True if the health factor is below the liquidation threshold.
     */
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
    {
        IPriceOracleGetter oracle = IPriceOracleGetter(i_addressesProvider.getPriceOracle());

        // Usage of a memory struct of vars to avoid "Stack too deep" errors due to local variables
        UserGlobalDataLocalVars memory vars;

        address[] memory reserves = i_core.getReserves();

        for (uint256 i = 0; i < reserves.length; i++) {
            vars.currentReserve = reserves[i];

            // For each reserve the function asks the core:
            // - How much has this user deposited in this reserve?
            // - How much has this user borrowed in this reserve?
            // - How much origination fee does this user owe?
            // - Is this reserve enabled as collateral by this user?
            (
                // User's current deposit balance, including accrued interest
                vars.compoundedLiquidityBalance,
                // User's current borrow balance, including accrued interest
                vars.compoundedBorrowBalance,
                // Fee owed by the user
                vars.originationFee,
                // Whether the user enabled this reserve as collateral
                vars.userUsesReserveAsCollateral
            ) = i_core.getUserBasicReserveData(vars.currentReserve, _user);

            // If the user has neither supplied nor borrowed this asset, skip the reserve
            if (vars.compoundedLiquidityBalance == 0 && vars.compoundedBorrowBalance == 0) {
                continue;
            }

            // Read reserve configuration
            (vars.reserveDecimals, vars.baseLtv, vars.liquidationThreshold, vars.usageAsCollateralEnabled) =
                i_core.getReserveConfiguration(vars.currentReserve);

            // Example 10 ** 18
            vars.tokenUnit = 10 ** vars.reserveDecimals;
            // reserveUnitPrice is the price of one full token in ETH.
            // Example 1 DAI = 0.0005 ETH
            vars.reserveUnitPrice = oracle.getAssetPrice(vars.currentReserve);

            if (vars.compoundedLiquidityBalance > 0) {
                // Calculate liquidity balance in ETH
                // liquidityBalanceETH = assetPriceInETH * userTokenBalance / tokenUnit
                //
                // Example:
                // User deposit = 1000 DAI
                // DAI price = 0.0005 ETH
                // tokenUnit = 1e18
                // liquidityBalanceETH = 1000 DAI * 0.0005 ETH = 0.5 ETH
                uint256 liquidityBalanceETH = vars.reserveUnitPrice * vars.compoundedLiquidityBalance / vars.tokenUnit;
                totalLiquidityBalanceETH += liquidityBalanceETH;

                // A deposited asset counts as collateral only if both conditions are true:
                // 1. The reserve allows collateral usage
                // 2. The user enabled this reserve as collateral
                if (vars.usageAsCollateralEnabled && vars.userUsesReserveAsCollateral) {
                    totalCollateralBalanceETH += liquidityBalanceETH;
                    // Weighted LTV accumulation
                    //
                    // Example user collateral:
                    // 1 ETH worth of DAI, LTV = 75
                    // 2 ETH worth of ETH, LTV 80
                    //
                    // currentLtv = 1 ETH * 75 + 2 ETH * 80 = 235
                    currentLtv += liquidityBalanceETH * vars.baseLtv;
                    // Weighted liquidation threshold accumulation
                    //
                    // Example
                    // 1 ETH worth of DAI, liquidation threshold = 80
                    // 2 ETH worth of WETH, liquidation threshold = 82.5
                    // currentLiquidationThreshold = 1 * 80 + 2 * 82.5 = 245
                    currentLiquidationThreshold += liquidityBalanceETH * vars.liquidationThreshold;
                }
            }

            // Calculate borrow balance in ETH
            if (vars.compoundedBorrowBalance > 0) {
                // borrowBalanceETH = assetPriceInETH * borrowBalance / tokenUnit
                //
                // Example
                // User borrowed = 500 DAI
                // DAI price = 0.0005 ETH
                // borrowBalanceETH = 500 * 0.0005 = 0.25 ETH
                totalBorrowBalanceETH += vars.reserveUnitPrice * vars.compoundedBorrowBalance / vars.tokenUnit;
                // feeETH = originationFee * assetPriceInETH / tokenUnit
                //
                // Example
                // origination fee = 10 DAI
                // DAI Price = 0.0005 ETH
                // feeETH = 10 * 0.0005 = 0.005 ETH
                totalFeesETH += vars.originationFee * vars.reserveUnitPrice / vars.tokenUnit;
            }
        }

        // Finalize average LTV
        // currentLtv = sum(collateralValueETH * reserveLtv) / totalCollateralBalanceETH
        //
        // Example collateral:
        // 1 ETH at 75 LTV
        // 2 ETH at 80 LTV
        //
        // currentLtv = (1 * 75 + 2 * 80) / 3 = 235 / 3 = 78.33
        currentLtv = totalCollateralBalanceETH > 0 ? currentLtv / totalCollateralBalanceETH : 0;
        // Finalize average liquidation threshold
        // currentLiquidationThreshold = sum(collateralvalueETH * liquidationThreshold) / totalCollateralBalanceETH
        currentLiquidationThreshold =
            totalCollateralBalanceETH > 0 ? currentLiquidationThreshold / totalCollateralBalanceETH : 0;

        // Calculate health factor
        // healthFactor = collateral adjusted by liquidation threshold / debt plus fees
        // healthFactor = TotalCollateralETH * LiquidationThreshold / (TotalBorrowsETH + TotalFeesETH)
        //
        // Example
        // total collateral = 2 ETH
        // liquidation threshold = 80%
        // total borrow + fees = 1 ETH
        //
        // health factor = 2 * 0.80 / 1 = 1.6
        healthFactor = _calculateHealthFactorFromBalances(
            totalCollateralBalanceETH, totalBorrowBalanceETH, totalFeesETH, currentLiquidationThreshold
        );

        // healthFactor < 1e18
        // -> user can be liquidated

        // healthfactor >= 1e18
        // -> user is not liquidatable
        healthFactorBelowThreshold = healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    /**
     * @notice calulcates the amount of collateral needed in ETH to cover a new borrow.
     * @param _reserve the reserve from which the user wants to borrow
     * @param _amount the amount the user wants to borrow
     * @param _fee the fee for the amount that the user needs to cover
     * @param _userCurrentBorrowBalanceETH the current borrow balance of the user (before the borrow)
     * @param _userCurrentLtv the average ltv of the user given his current collateral
     * @return the total amount of collateral in ETH to cover the current borrow balance + the new amount + fee
     */
    function calculateCollateralNeededInETH(
        address _reserve,
        uint256 _amount,
        uint256 _fee,
        uint256 _userCurrentBorrowBalanceETH,
        uint256 _userCurrentFeesETH,
        uint256 _userCurrentLtv
    ) external view returns (uint256) {
        uint256 reserveDecimals = i_core.getReserveDecimals(_reserve);

        IPriceOracleGetter oracle = IPriceOracleGetter(i_addressesProvider.getPriceOracle());

        // It converts the requested borrow amount plus its fee into their ETH-equivalent value
        uint256 requestedBorrowAmountETH = oracle.getAssetPrice(_reserve) * (_amount + _fee) / (10 ** reserveDecimals); // price in ether

        // Add the current already borrowed amount to the amount requested to calculate the total collateral needed.
        uint256 collateralNeededInETH =
            (_userCurrentBorrowBalanceETH + _userCurrentFeesETH + requestedBorrowAmountETH) * 100 / _userCurrentLtv; //LTV is calculated in percentage

        return collateralNeededInETH;
    }

    /**
     * @dev accessory functions to fetch data from the lendingPoolCore
     *
     */
    function getReserveConfigurationData(address _reserve)
        external
        view
        returns (
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            address rateStrategyAddress,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive
        )
    {
        (, ltv, liquidationThreshold, usageAsCollateralEnabled) = i_core.getReserveConfiguration(_reserve);
        stableBorrowRateEnabled = i_core.getReserveIsStableBorrowRateEnabled(_reserve);
        borrowingEnabled = i_core.isReserveBorrowingEnabled(_reserve);
        isActive = i_core.getReserveIsActive(_reserve);
        liquidationBonus = i_core.getReserveLiquidationBonus(_reserve);
        rateStrategyAddress = i_core.getReserveInterestRateStrategyAddress(_reserve);
    }

    function getReserveData(address _reserve)
        external
        view
        returns (
            uint256 totalLiquidity,
            uint256 availableLiquidity,
            uint256 totalBorrowsStable,
            uint256 totalBorrowsVariable,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 stableBorrowRate,
            uint256 averageStableBorrowRate,
            uint256 utilizationRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            address aTokenAddress,
            uint40 lastUpdateTimestamp
        )
    {
        totalLiquidity = i_core.getReserveTotalLiquidity(_reserve);
        availableLiquidity = i_core.getReserveAvailableLiquidity(_reserve);
        totalBorrowsStable = i_core.getReserveTotalBorrowsStable(_reserve);
        totalBorrowsVariable = i_core.getReserveTotalBorrowsVariable(_reserve);
        liquidityRate = i_core.getReserveCurrentLiquidityRate(_reserve);
        variableBorrowRate = i_core.getReserveCurrentVariableBorrowRate(_reserve);
        stableBorrowRate = i_core.getReserveCurrentStableBorrowRate(_reserve);
        averageStableBorrowRate = i_core.getReserveCurrentAverageStableBorrowRate(_reserve);
        utilizationRate = i_core.getReserveUtilizationRate(_reserve);
        liquidityIndex = i_core.getReserveLiquidityCumulativeIndex(_reserve);
        variableBorrowIndex = i_core.getReserveVariableBorrowsCumulativeIndex(_reserve);
        aTokenAddress = i_core.getReserveATokenAddress(_reserve);
        lastUpdateTimestamp = i_core.getReserveLastUpdate(_reserve);
    }

    function getUserAccountData(address _user)
        external
        view
        returns (
            uint256 totalLiquidityETH,
            uint256 totalCollateralETH,
            uint256 totalBorrowsETH,
            uint256 totalFeesETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        (
            totalLiquidityETH,
            totalCollateralETH,
            totalBorrowsETH,
            totalFeesETH,
            ltv,
            currentLiquidationThreshold,
            healthFactor,
        ) = calculateUserGlobalData(_user);

        availableBorrowsETH = _calculateAvailableBorrowsETH(totalCollateralETH, totalBorrowsETH, totalFeesETH, ltv);
    }

    function getUserReserveData(address _reserve, address _user)
        external
        view
        returns (
            uint256 currentATokenBalance,
            uint256 currentBorrowBalance,
            uint256 principalBorrowBalance,
            uint256 borrowRateMode,
            uint256 borrowRate,
            uint256 liquidityRate,
            uint256 originationFee,
            uint256 variableBorrowIndex,
            uint256 lastUpdateTimestamp,
            bool usageAsCollateralEnabled
        )
    {
        currentATokenBalance = AToken(i_core.getReserveATokenAddress(_reserve)).balanceOf(_user);
        CoreLibrary.InterestRateMode mode = i_core.getUserCurrentBorrowRateMode(_reserve, _user);
        (principalBorrowBalance, currentBorrowBalance,) = i_core.getUserBorrowBalances(_reserve, _user);

        //default is 0, if mode == CoreLibrary.InterestRateMode.NONE
        if (mode == CoreLibrary.InterestRateMode.STABLE) {
            borrowRate = i_core.getUserCurrentStableBorrowRate(_reserve, _user);
        } else if (mode == CoreLibrary.InterestRateMode.VARIABLE) {
            borrowRate = i_core.getReserveCurrentVariableBorrowRate(_reserve);
        }

        borrowRateMode = uint256(mode);
        liquidityRate = i_core.getReserveCurrentLiquidityRate(_reserve);
        originationFee = i_core.getUserOriginationFee(_reserve, _user);
        variableBorrowIndex = i_core.getUserVariableBorrowCumulativeIndex(_reserve, _user);
        lastUpdateTimestamp = i_core.getUserLastUpdate(_reserve, _user);
        usageAsCollateralEnabled = i_core.isUserUseReserveAsCollateralEnabled(_reserve, _user);
    }

    /**
     * @dev returns the health factor liquidation threshold
     *
     */
    function getHealthFactorLiquidationThreshold() external pure returns (uint256) {
        return HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }
}
