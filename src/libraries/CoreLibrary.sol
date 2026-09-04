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

import {WadRayMath} from "./WadRayMath.sol";

/**
 * @title CoreLibrary library
 * @notice Defines the data structures of the reserves and the user data
 */
library CoreLibrary {
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////
    error CoreLibrary__ReserveAlreadyInitialized();
    error CoreLibrary__InvalidAmountToDecrease();
    error CoreLibrary__AmountsToSubtractDontMatch();
    error CoreLibrary__InvalidVariableBorrowDecrease();
    error CoreLibrary__ReserveAlreadyEnabled();
    error CoreLibrary__ReserveAlreadyNeabledAsCollateral();

    ///////////////////////////////////
    //            Libraries          //
    ///////////////////////////////////
    using WadRayMath for uint256;

    ///////////////////////////////////////////
    //            Type Declarations          //
    ///////////////////////////////////////////
    // Stores a user's borrowing and collateral settings for a specific reserve.
    struct UserReserveData {
        // Principal amount currently borrowed by the user, in the reserve asset's decimals.
        uint256 principalBorrowBalance;
        // Variable-borrow index recorded when the user's debt was last updated, expressed in ray.
        uint256 lastVariableBorrowCumulativeIndex;
        // Cumulative origination fee owed by the user, in the reserve asset's decimals.
        uint256 originationFee;
        // Stable annual borrow rate for the user's debt, expressed in ray.
        uint256 stableBorrowRate;
        // Unix timestamp of the user's most recent reserve-data update.
        uint40 lastUpdateTimestamp;
        // Whether the user's deposit in this reserve is enabled as collateral.
        bool useAsCollateral;
    }

    // Stores the global accounting, configuration, and interest-rate state for a reserve.
    struct ReserveData {
        /// @dev See whitepaper section 1.1, “Basic concepts,” for a formal description of these properties.
        // Cumulative liquidity index used to account for supplier income, expressed in ray.
        uint256 lastLiquidityCumulativeIndex;
        // Current annual liquidity rate paid to suppliers, expressed in ray.
        uint256 currentLiquidityRate;
        // Total outstanding stable-rate debt, in the reserve asset's decimals.
        uint256 totalBorrowsStable;
        // Total outstanding variable-rate debt, in the reserve asset's decimals.
        uint256 totalBorrowsVariable;
        // Current annual variable borrow rate, expressed in ray.
        uint256 currentVariableBorrowRate;
        // Current annual stable borrow rate, expressed in ray.
        uint256 currentStableBorrowRate;
        // Weighted-average annual stable borrow rate across all stable-rate debt, expressed in ray.
        uint256 currentAverageStableBorrowRate;
        // Cumulative variable-borrow index used to account for variable-rate debt, expressed in ray.
        uint256 lastVariableBorrowCumulativeIndex;
        // Maximum loan-to-value when the reserve asset is collateral, expressed as a percentage from 0 to 100.
        uint256 baseLTVasCollateral;
        // Collateral value threshold below which a position becomes liquidatable, expressed as a percentage from 0 to 100.
        uint256 liquidationThreshold;
        // Bonus awarded to liquidators, expressed as a percentage.
        uint256 liquidationBonus;
        // Number of decimals used by the reserve asset.
        uint256 decimals;
        // Address of the aToken representing deposits of the reserve asset.
        address aTokenAddress;
        // Address of the interest-rate strategy contract for this reserve.
        address interestRateStrategyAddress;
        // Unix timestamp of the reserve's most recent update.
        uint40 lastUpdateTimestamp;
        // Whether users can borrow this reserve asset.
        bool borrowingEnabled;
        // Whether this reserve asset can be used as collateral.
        bool usageAsCollateralEnabled;
        // Whether stable-rate borrowing is enabled for this reserve.
        bool isStableBorrowRateEnabled;
        // Whether this reserve has been activated and configured.
        bool isActive;
        // Whether the reserve is frozen, allowing only repayments and redemptions.
        bool isFreezed;
    }

    ////////////////////////////////
    //      State Variables       //
    ////////////////////////////////
    enum InterestRateMode {
        NONE,
        STABLE,
        VARIABLE
    }

    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    //////////////////////////////////
    //       External Functions     //
    //////////////////////////////////
    /**
     * @dev initializes a reserve
     * @param _self the reserve object
     * @param _aTokenAddress the address of the overlying atoken contract
     * @param _decimals the number of decimals of the underlying asset
     * @param _interestRateStrategyAddress the address of the interest rate strategy contract
     *
     */
    function init(
        ReserveData storage _self,
        address _aTokenAddress,
        uint256 _decimals,
        address _interestRateStrategyAddress
    ) external {
        if (_self.aTokenAddress != address(0)) {
            revert CoreLibrary__ReserveAlreadyInitialized();
        }

        if (_self.lastLiquidityCumulativeIndex == 0) {
            // If the reserve has not been initialized yet
            _self.lastLiquidityCumulativeIndex = WadRayMath.ray();
        }

        if (_self.lastVariableBorrowCumulativeIndex == 0) {
            _self.lastVariableBorrowCumulativeIndex = WadRayMath.ray();
        }

        _self.aTokenAddress = _aTokenAddress;
        _self.decimals = _decimals;

        _self.interestRateStrategyAddress = _interestRateStrategyAddress;
        _self.isActive = true;
        _self.isFreezed = false;
    }

    /**
     * @dev enables borrowing on a reserve
     * @param _self the reserve object
     * @param _stableBorrowRateEnabled true if the stable borrow rate must be enabled by default, false otherwise
     *
     */
    function enableBorrowing(ReserveData storage _self, bool _stableBorrowRateEnabled) external {
        if (_self.borrowingEnabled) {
            revert CoreLibrary__ReserveAlreadyEnabled();
        }

        _self.borrowingEnabled = true;
        _self.isStableBorrowRateEnabled = _stableBorrowRateEnabled;
    }

    /**
     * @dev disables borrowing on a reserve
     * @param _self the reserve object
     *
     */
    function disableBorrowing(ReserveData storage _self) external {
        _self.borrowingEnabled = false;
    }

    /**
     * @dev enables a reserve to be used as collateral
     * @param _self the reserve object
     * @param _baseLTVasCollateral the loan to value of the asset when used as collateral
     * @param _liquidationThreshold the threshold at which loans using this asset as collateral will be considered undercollateralized
     * @param _liquidationBonus the bonus liquidators receive to liquidate this asset
     *
     */
    function enableAsCollateral(
        ReserveData storage _self,
        uint256 _baseLTVasCollateral,
        uint256 _liquidationThreshold,
        uint256 _liquidationBonus
    ) external {
        if (_self.usageAsCollateralEnabled) {
            revert CoreLibrary__ReserveAlreadyNeabledAsCollateral();
        }

        _self.usageAsCollateralEnabled = true;
        _self.baseLTVasCollateral = _baseLTVasCollateral;
        _self.liquidationThreshold = _liquidationThreshold;
        _self.liquidationBonus = _liquidationBonus;

        // This is a defensive fallback because lastLiquidityCumulativeIndex is set in the init function
        if (_self.lastLiquidityCumulativeIndex == 0) {
            _self.lastLiquidityCumulativeIndex = WadRayMath.ray();
        }
    }

    /**
     * @dev disables a reserve as collateral
     * @param _self the reserve object
     *
     */
    function disableAsCollateral(ReserveData storage _self) external {
        _self.usageAsCollateralEnabled = false;
    }

    //////////////////////////////////
    //       Internal Functions     //
    //////////////////////////////////
    /**
     * @dev Updates the liquidity cumulative index Ci and variable borrow cumulative index Bvc. Refer to the whitepaper for
     * a formal specification.
     * @param _self the reserve object
     */
    function updateCumulativeIndexes(ReserveData storage _self) internal {
        uint256 totalBorrows = getTotalBorrows(_self);

        // With no debt outstanding (totalBorrowsStable + totalBorrowsVariable),
        // the reserve earns no borrower-paid interest, so both indexes remain unchanged
        if (totalBorrows > 0) {
            // The liquidity index tracks depositor's accumulated income.
            // It applies the current liquidity rate with linear interest:
            // newLiquidityIndex = oldLiquidityIndex x (1 + liquidityRate x elapsedYears)
            uint256 cumulatedLiquidityInterest =
                calculateLinearInterest(_self.currentLiquidityRate, _self.lastUpdateTimestamp);
            _self.lastLiquidityCumulativeIndex = cumulatedLiquidityInterest.rayMul(_self.lastLiquidityCumulativeIndex);

            // The variable-borrow index tracks the growth of variable-rate debt.
            // It applies per-second compound interest
            // newVariableBorrowIndex = oldVariableBorrowIndex x ((1 + variablerate / secondsPerYear) ^ elapsedSeconds)
            uint256 cumulatedVariableBorrowInterest =
                calculateCompoundedInterest(_self.currentVariableBorrowRate, _self.lastUpdateTimestamp);
            _self.lastVariableBorrowCumulativeIndex =
                cumulatedVariableBorrowInterest.rayMul(_self.lastVariableBorrowCumulativeIndex);
        }
    }

    /**
     * @dev decreases the total borrows at a stable rate on a specific reserve and updates the
     * average stable rate consequently
     * @param _reserve the reserve object
     * @param _amount the amount to substract to the total borrows stable
     * @param _rate the rate at which the amount has been repaid
     */
    function decreaseTotalBorrowsStableAndUpdateAverageRate(
        ReserveData storage _reserve,
        uint256 _amount,
        uint256 _rate
    ) internal {
        // This function removes stable-rate debt from a reserve
        // and recalculates the reserve's average stable borrow rate

        // The function cannot remove more stable debt than the reserve currently contains
        if (_reserve.totalBorrowsStable < _amount) {
            revert CoreLibrary__InvalidAmountToDecrease();
        }

        // The previous total is needed to reconstruct the total weighted interest before removing the position
        uint256 previousTotalBorrowsStable = _reserve.totalBorrowsStable;

        // Decrease stable debt
        // The removed amount is subtracted from the reserve's stable debt
        _reserve.totalBorrowsStable = _reserve.totalBorrowsStable - _amount;


        // Calculate the new average rate

        // Handle an empty stable-debt pool
        // If no stable debt remains, there is no average stable rate.
        // Returning also prevents division by zero later
        if (_reserve.totalBorrowsStable == 0) {
            _reserve.currentAverageStableBorrowRate = 0;
            return;
        }

        // Formula when stable debt is removed:
        // newAverageRate = (previousTotalDebt * previousAverageRate - removedDebt * removedDebtRate) / remainingDebt;

        // Calculate the interest weight associated with the debt being removed
        // Removed amount x its stable rate
        uint256 weightedLastBorrow = _amount.wadToRay().rayMul(_rate);

        // Calculate the previous total weighted interest
        // Reconstruct the combined interest weight of all stable debt before the removal:
        // Previous total stable debt x previous average rate
        uint256 weightedPreviousTotalBorrows =
            previousTotalBorrowsStable.wadToRay().rayMul(_reserve.currentAverageStableBorrowRate);

        // The removed position's weighted interest cannot be greater
        // than the weighted interest of the complete reserve
        if (weightedPreviousTotalBorrows < weightedLastBorrow) {
            revert CoreLibrary__AmountsToSubtractDontMatch();
        }

        // Calculate the new average rate
        // New average rate = remaining weighted interest / remaining stable debt
        _reserve.currentAverageStableBorrowRate =
            (weightedPreviousTotalBorrows - weightedLastBorrow).rayDiv(_reserve.totalBorrowsStable.wadToRay());
    }

    /**
     * @dev decreases the total borrows at a variable rate
     * @param _reserve the reserve object
     * @param _amount the amount to substract to the total borrows variable
     *
     */
    function decreaseTotalBorrowsVariable(ReserveData storage _reserve, uint256 _amount) internal {
        // Prevent removing more variable debt than the reserve currently contains
        if (_reserve.totalBorrowsVariable < _amount) {
            revert CoreLibrary__InvalidVariableBorrowDecrease();
        }
        _reserve.totalBorrowsVariable -= _amount;
    }

    /**
     * @dev increases the total borrows at a stable rate on a specific reserve and updates the
     * average stable rate consequently
     * @param _reserve the reserve object
     * @param _amount the amount to add to the total borrows stable
     * @param _rate the rate at which the amount has been borrowed
     *
     */
    function increaseTotalBorrowsStableAndUpdateAverageRate(
        ReserveData storage _reserve,
        uint256 _amount,
        uint256 _rate
    ) internal {
        uint256 previousTotalBorrowStable = _reserve.totalBorrowsStable;

        // The new debt is added to the previous total
        _reserve.totalBorrowsStable += _amount;

        // Update the average stable rate
        // The weighted contribution of the new borrow is calculated
        uint256 weightedLastBorrow = _amount.wadToRay().rayMul(_rate);
        // The previous weighted contribution is reconstructed:
        uint256 weightedPreviousTotalBorrows =
            previousTotalBorrowStable.wadToRay().rayMul(_reserve.currentAverageStableBorrowRate);

        // Average rate = total weighted rate contribution / total stable debt
        _reserve.currentAverageStableBorrowRate =
            (weightedLastBorrow + weightedPreviousTotalBorrows).rayDiv(_reserve.totalBorrowsStable.wadToRay());
    }

    /**
     * @dev increases the total borrows at a variable rate
     * @param _reserve the reserve object
     * @param _amount the amount to add to the total borrows variable
     *
     */
    function increaseTotalBorrowsVariable(ReserveData storage _reserve, uint256 _amount) internal {
        _reserve.totalBorrowsVariable += _amount;
    }

    /**
     * @dev distributes a one-off amount of income across every liquidity provider
     * by increasing the reserve's liquidity index.
     * Used for example to accumulate the flashloan fee to the reserve, and spread it through the depositors.
     * @param _self the reserve object
     * @param _totalLiquidity the total liquidity available in the reserve
     * @param _amount the amount to accomulate
     *
     */
    function cumulateToLiquidityIndex(ReserveData storage _self, uint256 _totalLiquidity, uint256 _amount) internal {
        // Mathematically it applies:
        // newIndex = oldIndex x (1 + amount / totalLiquidity)

        // Example: if the reserve has 1,000 tokens of total liquidity and earns a one-time fee of 10 tokens:
        //    - fee ratio: 10 / 1000 = 1%
        //    - multiplier = 1 + 1% = 1.01
        //    - A liquidity index of 1.0 ray becomes 1.01 ray
        // Therefore every depositor's aToken balance gains 1% proportionally

        // amountToLiquidityRatio = amount / totalLiquidity
        uint256 amountToLiquidityRatio = _amount.wadToRay().rayDiv(_totalLiquidity.wadToRay());

        // cumulatedLiquidity = 1 + amountToLiquidityRatio = 1 + amount / totalLiquidity
        uint256 cumulatedLiquidity = amountToLiquidityRatio + WadRayMath.ray();

        // newIndex = oldIndex x cumulatedLiquidity = oldIndex x (1 + amount / totalLiquidity)
        _self.lastLiquidityCumulativeIndex = cumulatedLiquidity.rayMul(_self.lastLiquidityCumulativeIndex);
    }

    //////////////////////////////////////////////////////
    //     Private & Internal View & Pure Functions     //
    //////////////////////////////////////////////////////

    /**
     * @dev returns the ongoing normalized income for the reserve.
     * @param _reserve the reserve object
     * @return the normalized income. expressed in ray
     */
    function getNormalizedIncome(CoreLibrary.ReserveData storage _reserve) internal view returns (uint256) {
        // Current normalized income: linearInterest * lastLiquidityCumulativeIndex.
        uint256 cumulated = calculateLinearInterest(_reserve.currentLiquidityRate, _reserve.lastUpdateTimestamp)
            .rayMul(_reserve.lastLiquidityCumulativeIndex);

        return cumulated;
    }

    /**
     * @dev Calculates the linear interest factor accumulated from the last reserve update until now.
     * @param _rate The annual liquidity rate of the reserve, expressed in ray.
     * @param _lastUpdateTimestamp The timestamp of the last reserve update.
     * @return The linear interest factor accumulated during the elapsed time, expressed in ray.
     *
     * Example:
     * If `_rate` is 5% annualized and one year has passed, the return value is 1.05 ray.
     */
    function calculateLinearInterest(uint256 _rate, uint40 _lastUpdateTimestamp) internal view returns (uint256) {
        // Elapsed time since the reserve was last updated.
        uint256 timeDifference = block.timestamp - uint256(_lastUpdateTimestamp);

        // Fraction of a year elapsed, expressed in ray.
        uint256 timeDelta = timeDifference.wadToRay().rayDiv(SECONDS_PER_YEAR.wadToRay());

        // Linear interest: 1 + annualRate * elapsedYearFraction.
        return _rate.rayMul(timeDelta) + WadRayMath.ray();
    }

    /**
     * @dev Calculates the compounded interest factor accumulated from the last reserve update until now.
     * @param _rate The annual interest rate of the reserve, expressed in ray.
     * @param _lastUpdateTimestamp The timestamp of the last reserve update.
     * @return The compounded interest factor accumulated during the elapsed time, expressed in ray.
     *
     * Example:
     * If `_rate` is 5% annualized and one year has passed, the return value is approximately 1.05127 ray.
     */
    function calculateCompoundedInterest(uint256 _rate, uint40 _lastUpdateTimestamp) internal view returns (uint256) {
        // Elapsed time since the reserve was last updated.
        uint256 timeDifference = block.timestamp - uint256(_lastUpdateTimestamp);

        // ratePerSecond = annualRate / secondsPerYear
        uint256 ratePerSecond = _rate / SECONDS_PER_YEAR;

        // compoundedInterest = (1 + ratePerSecond) ^ timeDifference
        return (ratePerSecond + WadRayMath.ray()).rayPow(timeDifference);
    }

    /**
     * @dev returns the total borrows on the reserve
     * @param _reserve the reserve object
     * @return the total borrows (stable + variable)
     *
     */
    function getTotalBorrows(CoreLibrary.ReserveData storage _reserve) internal view returns (uint256) {
        return _reserve.totalBorrowsStable + _reserve.totalBorrowsVariable;
    }

    /**
     * @dev calculates the compounded borrow balance of a user
     * It returns the user’s current debt including accrued interest.
     * @param _self the userReserve object
     * @param _reserve the reserve object
     * @return the user compounded borrow balance
     *
     */
    function getCompoundedBorrowBalance(
        CoreLibrary.UserReserveData storage _self,
        CoreLibrary.ReserveData storage _reserve
    ) internal view returns (uint256) {
        // _self.principalBorrowBalance is only the debt recorded at the user’s last update.
        // The function calculates how much that debt has grown since then.

        if (_self.principalBorrowBalance == 0) {
            // return 0 if the user has no debt
            return 0;
        }

        uint256 principalBorrowBalanceRay = _self.principalBorrowBalance.wadToRay();
        uint256 compoundedBalance = 0;
        uint256 cumulatedInterest = 0;

        if (_self.stableBorrowRate > 0) {
            // stableBorrowRate > 0 → stable-rate debt

            // cumulatedInterest = (1 + stableRatePerSecond) ^ elapsedSeconds
            cumulatedInterest = calculateCompoundedInterest(_self.stableBorrowRate, _self.lastUpdateTimestamp);
        } else {
            // stableBorrowRate == 0 → variable-rate debt

            // 1. interestSinceReserveUpdate = (1 + currentVariableRatePerSecond) ^ elapsedSeconds
            // 2. currentReserveVariableIndex = storedReserveVariableIndex * interestSinceReserveUpdate
            // 3. userGrowthFactor = currentReserveVariableIndex / userLastVariableBorrowIndex
            cumulatedInterest = calculateCompoundedInterest(
                    _reserve.currentVariableBorrowRate, _reserve.lastUpdateTimestamp
                ).rayMul(_reserve.lastVariableBorrowCumulativeIndex).rayDiv(_self.lastVariableBorrowCumulativeIndex);
        }

        // currentDebt = principal * cumulatedInterest
        compoundedBalance = principalBorrowBalanceRay.rayMul(cumulatedInterest).rayToWad();

        if (compoundedBalance == _self.principalBorrowBalance) {
            if (_self.lastUpdateTimestamp != block.timestamp) {
                // No interest cumulation because of the rounding - we add 1 wei
                // as symbolic cumulated interest to avoid interest free loans

                return _self.principalBorrowBalance + 1;
            }
        }

        return compoundedBalance;
    }
}
