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
    ///////////////////////////////////
    //            Libraries          //
    ///////////////////////////////////
    using WadRayMath for uint256;

    ////////////////////////////////
    //      State Variables       //
    ////////////////////////////////
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    ///////////////////////////////////////////
    //            Type Declarations          //
    ///////////////////////////////////////////
    struct UserReserveData {
        //principal amount borrowed by the user.
        uint256 principalBorrowBalance;
        //cumulated variable borrow index for the user. Expressed in ray
        uint256 lastVariableBorrowCumulativeIndex;
        //origination fee cumulated by the user
        uint256 originationFee;
        // stable borrow rate at which the user has borrowed. Expressed in ray
        uint256 stableBorrowRate;
        uint40 lastUpdateTimestamp;
        //defines if a specific deposit should or not be used as a collateral in borrows
        bool useAsCollateral;
    }

    struct ReserveData {
        /**
         * @dev refer to the whitepaper, section 1.1 basic concepts for a formal description of these properties.
         *
         */
        //the liquidity index. Expressed in ray
        uint256 lastLiquidityCumulativeIndex;
        //the current supply rate. Expressed in ray
        uint256 currentLiquidityRate;
        //the total borrows of the reserve at a stable rate. Expressed in the currency decimals
        uint256 totalBorrowsStable;
        //the total borrows of the reserve at a variable rate. Expressed in the currency decimals
        uint256 totalBorrowsVariable;
        //the current variable borrow rate. Expressed in ray
        uint256 currentVariableBorrowRate;
        //the current stable borrow rate. Expressed in ray
        uint256 currentStableBorrowRate;
        //the current average stable borrow rate (weighted average of all the different stable rate loans). Expressed in ray
        uint256 currentAverageStableBorrowRate;
        //variable borrow index. Expressed in ray
        uint256 lastVariableBorrowCumulativeIndex;
        //the ltv of the reserve. Expressed in percentage (0-100)
        uint256 baseLTVasCollateral;
        //the liquidation threshold of the reserve. Expressed in percentage (0-100)
        uint256 liquidationThreshold;
        //the liquidation bonus of the reserve. Expressed in percentage
        uint256 liquidationBonus;
        //the decimals of the reserve asset
        uint256 decimals;
        /**
         * @dev address of the aToken representing the asset
         *
         */
        address aTokenAddress;
        /**
         * @dev address of the interest rate strategy contract
         *
         */
        address interestRateStrategyAddress;
        uint40 lastUpdateTimestamp;
        // borrowingEnabled = true means users can borrow from this reserve
        bool borrowingEnabled;
        // usageAsCollateralEnabled = true means users can use this reserve as collateral
        bool usageAsCollateralEnabled;
        // isStableBorrowRateEnabled = true means users can borrow at a stable rate
        bool isStableBorrowRateEnabled;
        // isActive = true means the reserve has been activated and properly configured
        bool isActive;
        // isFreezed = true means the reserve only allows repays and redeems, but not deposits, new borrowings or rate swap
        bool isFreezed;
    }

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

    //////////////////////////////////
    //       Internal Functions     //
    //////////////////////////////////
    /**
     * @dev Updates the liquidity cumulative index Ci and variable borrow cumulative index Bvc. Refer to the whitepaper for
     * a formal specification.
     * @param _self the reserve object
     *
     */
    function updateCumulativeIndexes(ReserveData storage _self) internal {
        uint256 totalBorrows = getTotalBorrows(_self);

        if (totalBorrows > 0) {
            // Only cumulating of there is any income being produced
            uint256 cumulatedLiquidityInterest =
                calculateLinearInterest(_self.currentLiquidityRate, _self.lastUpdateTimestamp);

            _self.lastLiquidityCumulativeIndex = cumulatedLiquidityInterest.rayMul(_self.lastLiquidityCumulativeIndex);

            uint256 cumulatedVariableBorrowInterest =
                calculateCompoundedInterest(_self.currentVariableBorrowRate, _self.lastUpdateTimestamp);

            _self.lastVariableBorrowCumulativeIndex =
                cumulatedVariableBorrowInterest.rayMul(_self.lastVariableBorrowCumulativeIndex);
        }
    }

    //////////////////////////////////////////////////////
    //     Private & Internal View & Pure Functions     //
    //////////////////////////////////////////////////////

    /**
     * @dev returns the ongoing normalized income for the reserve.
     * a value of 1e27 means there is no income. As time passes, the income is accrued.
     * A value of 2*1e27 means that the income of the reserve is double the initial amount.
     * @param _reserve the reserve object
     * @return the normalized income. expressed in ray
     *
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

        // Linear interest factor: 1 + annualRate * elapsedYearFraction.
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
     * @param _self the userReserve object
     * @param _reserve the reserve object
     * @return the user compounded borrow balance
     *
     */
    function getCompoundedBorrowBalance(
        CoreLibrary.UserReserveData storage _self,
        CoreLibrary.ReserveData storage _reserve
    ) internal view returns (uint256) {
        if (_self.principalBorrowBalance == 0) {
            return 0;
        }

        uint256 principalBorrowBalanceRay = _self.principalBorrowBalance.wadToRay();
        uint256 compoundedBalance = 0;
        uint256 cumulatedInterest = 0;

        if (_self.stableBorrowRate > 0) {
            cumulatedInterest = calculateCompoundedInterest(_self.stableBorrowRate, _self.lastUpdateTimestamp);
        } else {
            // variable interest
            cumulatedInterest = calculateCompoundedInterest(
                    _reserve.currentVariableBorrowRate, _reserve.lastUpdateTimestamp
                ).rayMul(_reserve.lastVariableBorrowCumulativeIndex).rayDiv(_self.lastVariableBorrowCumulativeIndex);
        }

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
