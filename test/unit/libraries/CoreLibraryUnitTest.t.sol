// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {CoreLibrary} from "src/libraries/CoreLibrary.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";

contract CoreLibraryHarness {
    using CoreLibrary for CoreLibrary.ReserveData;
    using CoreLibrary for CoreLibrary.UserReserveData;

    CoreLibrary.ReserveData internal reserve;
    CoreLibrary.UserReserveData internal userReserve;

    function setReserveData(CoreLibrary.ReserveData memory _reserveData) external {
        reserve = _reserveData;
    }

    function setUserReserveData(CoreLibrary.UserReserveData memory _userReserveData) external {
        userReserve = _userReserveData;
    }

    function initReserve(address _aTokenAddress, uint256 _decimals, address _interestRateStrategyAddress) external {
        reserve.init(_aTokenAddress, _decimals, _interestRateStrategyAddress);
    }

    function updateCumulativeIndexes() external {
        reserve.updateCumulativeIndexes();
    }

    function calculateLinearInterest(uint256 _rate, uint40 _lastUpdateTimestamp) external view returns (uint256) {
        return CoreLibrary.calculateLinearInterest(_rate, _lastUpdateTimestamp);
    }

    function calculateCompoundedInterest(uint256 _rate, uint40 _lastUpdateTimestamp) external view returns (uint256) {
        return CoreLibrary.calculateCompoundedInterest(_rate, _lastUpdateTimestamp);
    }

    function getNormalizedIncome() external view returns (uint256) {
        return reserve.getNormalizedIncome();
    }

    function getTotalBorrows() external view returns (uint256) {
        return reserve.getTotalBorrows();
    }

    function increaseTotalBorrowsStableAndUpdateAverageRate(uint256 _amount, uint256 _rate) external {
        reserve.increaseTotalBorrowsStableAndUpdateAverageRate(_amount, _rate);
    }

    function decreaseTotalBorrowsStableAndUpdateAverageRate(uint256 _amount, uint256 _rate) external {
        reserve.decreaseTotalBorrowsStableAndUpdateAverageRate(_amount, _rate);
    }

    function increaseTotalBorrowsVariable(uint256 _amount) external {
        reserve.increaseTotalBorrowsVariable(_amount);
    }

    function decreaseTotalBorrowsVariable(uint256 _amount) external {
        reserve.decreaseTotalBorrowsVariable(_amount);
    }

    function enableBorrowing(bool _stableBorrowRateEnabled) external {
        reserve.enableBorrowing(_stableBorrowRateEnabled);
    }

    function disableBorrowing() external {
        reserve.disableBorrowing();
    }

    function enableAsCollateral(uint256 _baseLTVasCollateral, uint256 _liquidationThreshold, uint256 _liquidationBonus)
        external
    {
        reserve.enableAsCollateral(_baseLTVasCollateral, _liquidationThreshold, _liquidationBonus);
    }

    function disableAsCollateral() external {
        reserve.disableAsCollateral();
    }

    function getBorrowTotals()
        external
        view
        returns (uint256 totalBorrowsStable, uint256 totalBorrowsVariable, uint256 currentAverageStableBorrowRate)
    {
        return (reserve.totalBorrowsStable, reserve.totalBorrowsVariable, reserve.currentAverageStableBorrowRate);
    }

    function getBorrowingConfiguration() external view returns (bool borrowingEnabled, bool isStableBorrowRateEnabled) {
        return (reserve.borrowingEnabled, reserve.isStableBorrowRateEnabled);
    }

    function getCollateralConfiguration()
        external
        view
        returns (
            bool usageAsCollateralEnabled,
            uint256 baseLTVasCollateral,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 lastLiquidityCumulativeIndex
        )
    {
        return (
            reserve.usageAsCollateralEnabled,
            reserve.baseLTVasCollateral,
            reserve.liquidationThreshold,
            reserve.liquidationBonus,
            reserve.lastLiquidityCumulativeIndex
        );
    }

    function getCompoundedBorrowBalance() external view returns (uint256) {
        return userReserve.getCompoundedBorrowBalance(reserve);
    }

    function getReserveConfiguration()
        external
        view
        returns (
            address aTokenAddress,
            uint256 decimals,
            address interestRateStrategyAddress,
            uint256 lastLiquidityCumulativeIndex,
            uint256 lastVariableBorrowCumulativeIndex,
            bool isActive,
            bool isFreezed
        )
    {
        return (
            reserve.aTokenAddress,
            reserve.decimals,
            reserve.interestRateStrategyAddress,
            reserve.lastLiquidityCumulativeIndex,
            reserve.lastVariableBorrowCumulativeIndex,
            reserve.isActive,
            reserve.isFreezed
        );
    }

    function getReserveIndexes()
        external
        view
        returns (uint256 lastLiquidityCumulativeIndex, uint256 lastVariableBorrowCumulativeIndex)
    {
        return (reserve.lastLiquidityCumulativeIndex, reserve.lastVariableBorrowCumulativeIndex);
    }
}

contract CoreLibraryUnitTest is Test {
    using WadRayMath for uint256;

    uint256 private constant RAY = 1e27;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    CoreLibraryHarness private harness;

    function setUp() external {
        harness = new CoreLibraryHarness();
    }

    function _defaultReserveData() private view returns (CoreLibrary.ReserveData memory reserveData) {
        reserveData.lastLiquidityCumulativeIndex = RAY;
        reserveData.lastVariableBorrowCumulativeIndex = RAY;
        reserveData.lastUpdateTimestamp = uint40(block.timestamp);
    }

    function _defaultUserReserveData() private view returns (CoreLibrary.UserReserveData memory userReserveData) {
        userReserveData.lastVariableBorrowCumulativeIndex = RAY;
        userReserveData.lastUpdateTimestamp = uint40(block.timestamp);
    }

    /////////////////////
    //       init      //
    /////////////////////
    function testInitReserveSetsCoreConfigurationAndStartingIndexes() external {
        address aToken = makeAddr("aToken");
        address strategy = makeAddr("strategy");

        // Initializing a reserve wires the aToken and strategy addresses, stores the asset decimals,
        // activates the reserve, and starts both indexes at 1 ray so future interest math has a base.
        harness.initReserve(aToken, 18, strategy);

        (
            address aTokenAddress,
            uint256 decimals,
            address interestRateStrategyAddress,
            uint256 lastLiquidityCumulativeIndex,
            uint256 lastVariableBorrowCumulativeIndex,
            bool isActive,
            bool isFreezed
        ) = harness.getReserveConfiguration();

        assertEq(aTokenAddress, aToken);
        assertEq(decimals, 18);
        assertEq(interestRateStrategyAddress, strategy);
        assertEq(lastLiquidityCumulativeIndex, RAY);
        assertEq(lastVariableBorrowCumulativeIndex, RAY);
        assertTrue(isActive);
        assertFalse(isFreezed);
    }

    function testInitReserveRevertsIfReserveWasAlreadyInitialized() external {
        // A reserve is considered initialized once it has an aToken address. Calling init again
        // should fail so the reserve configuration cannot be accidentally overwritten.
        harness.initReserve(makeAddr("aToken"), 18, makeAddr("strategy"));

        vm.expectRevert(CoreLibrary.CoreLibrary__ReserveAlreadyInitialized.selector);
        harness.initReserve(makeAddr("anotherAToken"), 6, makeAddr("anotherStrategy"));
    }

    ////////////////////////////////////
    //    calculateLinearInterest     //
    ////////////////////////////////////

    // Linear Interest
    // elapsedTime = block.timestamp - lastUpdateTimestamp;
    // linearInterest = 1 ray + rate * elapsedTime / secondsPerYear

    // 1. No Time Passed
    function testCalculateLinearInterestReturnsOneRayIfNoTimePassed() external {
        uint256 rate = 5e25; // 5% expressed in ray
        uint40 lastUpdateTimestamp = uint40(block.timestamp);

        // No time has passed:
        //
        // elapsedSeconds = block.timestamp - lastUpdateTimestamp
        // elapsedSeconds = 0
        //
        // linearInterest = 1 + annualRate * elapsedSeconds / secondsPerYear
        // linearInterest = RAY + rate * 0 / SECONDS_PER_YEAR
        // linearInterest = 1e27 + 0
        //
        // linearInterest = 1 ray
        // linearInterest = 1e27
        uint256 linearInterest = harness.calculateLinearInterest(rate, lastUpdateTimestamp);

        assertEq(linearInterest, RAY);
    }

    // 2. One Year at 5%
    function testCalculateLinearInterestAfterOneYearAtFivePercent() external {
        uint256 rate = 5e25; // 5% expressed in ray
        uint40 lastUpdateTimestamp = uint40(block.timestamp);

        vm.warp(block.timestamp + SECONDS_PER_YEAR);

        // One full year has passed:
        //
        // elapsedSeconds = SECONDS_PER_YEAR
        //
        // linearInterest = 1 + annualRate * elapsedSeconds / secondsPerYear
        // linearInterest = RAY + rate * SECONDS_PER_YEAR / SECONDS_PER_YEAR
        // linearInterest = RAY + rate
        // linearInterest = 1e27 + 5e25
        //
        // 1e27 = 1.00 ray
        // 5e25 = 0.05 ray
        //
        // linearInterest = 1.05 ray
        // linearInterest = 105e25
        uint256 linearInterest = harness.calculateLinearInterest(rate, lastUpdateTimestamp);

        assertEq(linearInterest, 105e25);
    }

    // 3. Half Year at 5%
    function testCalculateLinearInterestAfterHalfYearAtFivePercent() external {
        uint256 rate = 5e25; // 5% expressed in ray
        uint40 lastUpdateTimestamp = uint40(block.timestamp);

        vm.warp(block.timestamp + SECONDS_PER_YEAR / 2);

        // Half a year has passed:
        //
        // elapsedSeconds = SECONDS_PER_YEAR / 2
        //
        // linearInterest = 1 + annualRate * elapsedSeconds / secondsPerYear
        // linearInterest = RAY + rate * (SECONDS_PER_YEAR / 2) / SECONDS_PER_YEAR
        // linearInterest = RAY + rate / 2
        // linearInterest = 1e27 + 5e25 / 2
        // linearInterest = 1e27 + 2.5e25
        //
        // 1e27 = 1.00 ray
        // 2.5e25 = 0.025 ray
        //
        // linearInterest = 1.025 ray
        // linearInterest = 1025e24
        uint256 linearInterest = harness.calculateLinearInterest(rate, lastUpdateTimestamp);

        assertEq(linearInterest, 1025e24);
    }

    ///////////////////////////////////////
    //    calculateCompoundedInterest    //
    ///////////////////////////////////////

    // Compounded interest
    // elapsedTime = block.timestamp - lastUpdateTimestamp;
    // compoundedInterest = (1 ray + rate / SECONDS_PER_YEAR) ^ elapsedTime

    // 1. No time passed
    function testCalculateCompoundedInterestReturnsOneRayIfNoTimePassed() external {
        uint256 rate = 5e25; // 5% expressed in ray
        uint40 lastUpdateTimestamp = uint40(block.timestamp);

        // No time has passed:
        //
        // elapsedSeconds = block.timestamp - lastUpdateTimestamp
        // elapsedSeconds = 0
        //
        // compoundedInterest = (1 + annualRate / secondsPerYear) ^ elapsedSeconds
        // compoundedInterest = (RAY + rate / SECONDS_PER_YEAR) ^ 0
        //
        // Any non-zero value raised to the power of zero is 1:
        //
        // compoundedInterest = 1 ray
        // compoundedInterest = 1e27
        uint256 compoundedInterest = harness.calculateCompoundedInterest(rate, lastUpdateTimestamp);

        assertEq(compoundedInterest, RAY);
    }

    // 2. One month at 5%
    function testCalculateCompoundedInterestAfterOneMonthAtFivePercent() external {
        uint256 rate = 5e25; // 5% expressed in ray
        uint40 lastUpdateTimestamp = uint40(block.timestamp);

        uint256 oneMonth = SECONDS_PER_YEAR / 12;
        uint256 ratePerSecond = rate / SECONDS_PER_YEAR;
        uint256 oneSecondInterestFactor = RAY + ratePerSecond;

        vm.warp(block.timestamp + oneMonth);

        // Compounded interest applies the per-second interest factor once for every elapsed second.
        //
        // compoundedInterest = (1 + annualRate / secondsPerYear) ^ elapsedSeconds
        // compoundedInterest = (RAY + rate / SECONDS_PER_YEAR) ^ (SECONDS_PER_YEAR / 12)
        // compoundedInterest = (1e27 + 5e25 / 31_536_000) ^ 2_628_000
        //
        // In decimal form:
        // compoundedInterest = (1 + 0.05 / 31_536_000) ^ 2_628_000
        // compoundedInterest ≈ 1.004175 ray
        //
        // Therefore, after one month, 1,000 DAI of debt would become approximately:
        // 1,000 * 1.004175 = 1,004.175 DAI
        uint256 compoundedInterest = harness.calculateCompoundedInterest(rate, lastUpdateTimestamp);

        uint256 expectedCompoundedInterest = oneSecondInterestFactor.rayPow(oneMonth);

        assertEq(compoundedInterest, expectedCompoundedInterest);
    }

    // 3. Two months at 5%
    function testCalculateCompoundedInterestAfterTwoMonthsAtFivePercent() external {
        uint256 rate = 5e25; // 5% expressed in ray
        uint40 lastUpdateTimestamp = uint40(block.timestamp);

        uint256 twoMonths = SECONDS_PER_YEAR / 6;
        uint256 ratePerSecond = rate / SECONDS_PER_YEAR;
        uint256 oneSecondInterestFactor = RAY + ratePerSecond;

        vm.warp(block.timestamp + twoMonths);

        // Two months represent one sixth of a year:
        //
        // elapsedSeconds = SECONDS_PER_YEAR / 6
        // elapsedSeconds = 31_536_000 / 6
        // elapsedSeconds = 5_256_000
        //
        // compoundedInterest = (1 + annualRate / secondsPerYear) ^ elapsedSeconds
        // compoundedInterest = (RAY + rate / SECONDS_PER_YEAR) ^ (SECONDS_PER_YEAR / 6)
        // compoundedInterest = (1e27 + 5e25 / 31_536_000) ^ 5_256_000
        //
        // In decimal form:
        // compoundedInterest = (1 + 0.05 / 31_536_000) ^ 5_256_000
        // compoundedInterest ≈ 1.008368 ray
        //
        // Therefore, after two months, 1,000 DAI of debt would become approximately:
        // 1,000 * 1.008368 = 1,008.368 DAI
        uint256 compoundedInterest = harness.calculateCompoundedInterest(rate, lastUpdateTimestamp);

        uint256 expectedCompoundedInterest = oneSecondInterestFactor.rayPow(twoMonths);

        assertEq(compoundedInterest, expectedCompoundedInterest);
    }

    ////////////////////////////////
    //    getNormalizedIncome     //
    ////////////////////////////////

    // 1. No Time Passed
    function testGetNormalizedIncomeReturnsPreviousIndexIfNoTimePassed() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.currentLiquidityRate = 5e25; // 5%

        harness.setReserveData(reserveData);

        // No time has passed:
        //
        // elapsedSeconds = 0
        //
        // linearInterest = RAY + rate * 0 / SECONDS_PER_YEAR
        // linearInterest = RAY
        // linearInterest = 1.00 ray
        //
        // normalizedIncome = linearInterest * lastLiquidityCumulativeIndex
        // normalizedIncome = 1.00 * 1.00
        // normalizedIncome = 1.00 ray
        //
        // Since no interest has accrued, the previous liquidity index
        // is returned unchanged.
        uint256 normalizedIncome = harness.getNormalizedIncome();

        assertEq(normalizedIncome, RAY);
    }

    // 2. One Year at 5%
    function testGetNormalizedIncomeAfterOneYearAtFivePercent() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.currentLiquidityRate = 5e25; // 5%

        harness.setReserveData(reserveData);

        vm.warp(block.timestamp + SECONDS_PER_YEAR);

        // One full year has passed:
        //
        // linearInterest = RAY + rate * SECONDS_PER_YEAR / SECONDS_PER_YEAR
        // linearInterest = RAY + rate
        // linearInterest = 1e27 + 5e25
        // linearInterest = 1.05 ray
        //
        // normalizedIncome = linearInterest * lastLiquidityCumulativeIndex
        // normalizedIncome = 1.05 * 1.00
        // normalizedIncome = 1.05 ray
        // normalizedIncome = 105e25
        uint256 normalizedIncome = harness.getNormalizedIncome();

        assertEq(normalizedIncome, 105e25);
    }

    function testGetNormalizedIncomeUsesPreviousLiquidityIndex() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.currentLiquidityRate = 5e25; // 5%
        reserveData.lastLiquidityCumulativeIndex = 11e26; // 1.10 ray

        harness.setReserveData(reserveData);

        vm.warp(block.timestamp + SECONDS_PER_YEAR);

        // linearInterest = 1.05 ray
        // previousLiquidityIndex = 1.10 ray
        //
        // normalizedIncome = 1.05 * 1.10
        // normalizedIncome = 1.155 ray
        //
        // 1.155 ray = 1.155 * 1e27
        // 1.155 ray = 1155e24
        uint256 normalizedIncome = harness.getNormalizedIncome();

        assertEq(normalizedIncome, 1155e24);
    }

    /////////////////////////////////
    //    updateCumulativeIndexes  //
    /////////////////////////////////
    function testUpdateCumulativeIndexesDoesNothingWhenThereAreNoBorrows() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.currentLiquidityRate = 5e25;
        reserveData.currentVariableBorrowRate = 10e25;
        reserveData.lastLiquidityCumulativeIndex = 11e26;
        reserveData.lastVariableBorrowCumulativeIndex = 12e26;

        harness.setReserveData(reserveData);

        vm.warp(block.timestamp + SECONDS_PER_YEAR);
        // If the reserve has no stable or variable borrows (reserveData.totalBorrowsStable = 0 and reserveData.totalBorrowsVariable = 0),
        // no income is being produced.
        // updateCumulativeIndexes should therefore leave both indexes unchanged.
        harness.updateCumulativeIndexes();

        (uint256 liquidityIndex, uint256 variableBorrowIndex) = harness.getReserveIndexes();

        assertEq(liquidityIndex, 11e26); // liquidityIndex == reserveData.lastLiquidityCumulativeIndex
        assertEq(variableBorrowIndex, 12e26); // variableBorrowIndex == reserveData.lastVariableBorrowCumulativeIndex
    }

    function testUpdateCumulativeIndexesAccruesLiquidityAndVariableBorrowIndexes() external {
        uint256 liquidityRate = 5e25; // 5%
        uint256 variableBorrowRate = 10e25; // 10%

        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsStable = 100 ether;
        reserveData.totalBorrowsVariable = 50 ether;
        reserveData.currentLiquidityRate = liquidityRate;
        reserveData.currentVariableBorrowRate = variableBorrowRate;

        harness.setReserveData(reserveData);

        vm.warp(block.timestamp + SECONDS_PER_YEAR);

        // The previous liquidity index is 1 ray and one full year has passed.
        //
        // linearInterest = RAY + liquidityRate * elapsedSeconds / SECONDS_PER_YEAR
        // linearInterest = RAY + liquidityRate * SECONDS_PER_YEAR / SECONDS_PER_YEAR
        // linearInterest = RAY + liquidityRate
        // linearInterest = 1e27 + 5e25
        // linearInterest = 1.05 ray
        //
        // newLiquidityIndex = linearInterest * previousLiquidityIndex
        // newLiquidityIndex = 1.05 * 1.00
        // newLiquidityIndex = 1.05 ray
        // newLiquidityIndex = 105e25
        uint256 expectedLiquidityIndex = 105e25;

        // The variable borrow index uses per-second compounded interest:
        //
        // ratePerSecond = annualVariableRate / SECONDS_PER_YEAR
        // ratePerSecond = 10e25 / 31_536_000
        //
        // oneSecondInterestFactor = RAY + ratePerSecond
        //
        // compoundedInterest =
        //     oneSecondInterestFactor ^ elapsedSeconds
        //
        // compoundedInterest =
        //     (RAY + variableBorrowRate / SECONDS_PER_YEAR) ^ SECONDS_PER_YEAR
        uint256 ratePerSecond = variableBorrowRate / SECONDS_PER_YEAR;
        uint256 oneSecondInterestFactor = RAY + ratePerSecond;
        uint256 compoundedVariableInterest = oneSecondInterestFactor.rayPow(SECONDS_PER_YEAR);

        // The previous variable borrow index is 1 ray:
        //
        // newVariableBorrowIndex =
        //     compoundedVariableInterest * previousVariableBorrowIndex
        //
        // newVariableBorrowIndex =
        //     compoundedVariableInterest * 1.00
        uint256 expectedVariableBorrowIndex =
            compoundedVariableInterest.rayMul(reserveData.lastVariableBorrowCumulativeIndex);

        harness.updateCumulativeIndexes();

        (uint256 liquidityIndex, uint256 variableBorrowIndex) = harness.getReserveIndexes();

        assertEq(liquidityIndex, expectedLiquidityIndex);
        assertEq(variableBorrowIndex, expectedVariableBorrowIndex);
    }

    //////////////////////////
    //    getTotalBorrows   //
    //////////////////////////
    function testGetTotalBorrowsAddsStableAndVariableBorrows() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsStable = 100 ether;
        reserveData.totalBorrowsVariable = 250 ether;

        harness.setReserveData(reserveData);

        // Total borrows is just the sum of stable debt and variable debt for the reserve.
        uint256 totalBorrows = harness.getTotalBorrows();

        assertEq(totalBorrows, 350 ether);
    }

    //////////////////////////////////////
    //    getCompoundedBorrowBalance    //
    //////////////////////////////////////
    function testGetCompoundedBorrowBalanceReturnsZeroWhenUserHasNoDebt() external {
        CoreLibrary.UserReserveData memory userReserveData = _defaultUserReserveData();
        userReserveData.stableBorrowRate = 5e25;

        harness.setUserReserveData(userReserveData);

        // A user with no principal debt has no compounded debt, even if a borrow rate exists.
        uint256 compoundedBalance = harness.getCompoundedBorrowBalance();

        assertEq(compoundedBalance, 0);
    }

    function testGetCompoundedBorrowBalanceUsesStableBorrowRateWhenPresent() external {
        uint256 principalBorrowBalance = 1_000 ether;
        uint256 stableBorrowRate = 5e25; // 5%
        uint40 lastUpdateTimestamp = uint40(block.timestamp);

        CoreLibrary.UserReserveData memory userReserveData = _defaultUserReserveData();

        userReserveData.principalBorrowBalance = principalBorrowBalance;
        userReserveData.stableBorrowRate = stableBorrowRate;
        userReserveData.lastUpdateTimestamp = lastUpdateTimestamp;

        harness.setUserReserveData(userReserveData);

        vm.warp(block.timestamp + SECONDS_PER_YEAR);

        // Stable debt uses the user's stable rate and the time elapsed
        // since the user's borrow position was last updated.
        //
        // ratePerSecond = stableBorrowRate / SECONDS_PER_YEAR
        // ratePerSecond = 5e25 / 31_536_000
        //
        // compoundedStableInterest =
        //     (RAY + ratePerSecond) ^ elapsedSeconds
        //
        // compoundedStableInterest =
        //     (RAY + stableBorrowRate / SECONDS_PER_YEAR)
        //     ^ SECONDS_PER_YEAR
        uint256 ratePerSecond = stableBorrowRate / SECONDS_PER_YEAR;

        uint256 compoundedStableInterest = (RAY + ratePerSecond).rayPow(SECONDS_PER_YEAR);

        // expectedBalance =
        //     principalBorrowBalance * compoundedStableInterest
        //
        // The principal is converted from wad to ray before multiplication,
        // then converted back to wad.
        uint256 expectedBalance = principalBorrowBalance.wadToRay().rayMul(compoundedStableInterest).rayToWad();

        uint256 compoundedBalance = harness.getCompoundedBorrowBalance();

        assertEq(compoundedBalance, expectedBalance);
    }

    function testGetCompoundedBorrowBalanceUsesReserveVariableIndexWhenStableRateIsZero() external {
        uint256 principalBorrowBalance = 100 ether;
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsVariable = 100 ether;
        reserveData.lastVariableBorrowCumulativeIndex = 11e26;
        CoreLibrary.UserReserveData memory userReserveData = _defaultUserReserveData();
        userReserveData.principalBorrowBalance = principalBorrowBalance;

        harness.setReserveData(reserveData);
        harness.setUserReserveData(userReserveData);

        // With stableBorrowRate == 0, the user is treated as variable debt. The balance scales by
        // reserveVariableIndex / userLastVariableIndex: 100 ether * 1.10 / 1.00 = 110 ether.
        uint256 compoundedBalance = harness.getCompoundedBorrowBalance();

        assertEq(compoundedBalance, 110 ether);
    }

    function testGetCompoundedBorrowBalanceAccruesCurrentVariableRate() external {
        uint256 principalBorrowBalance = 100 ether;
        uint256 variableBorrowRate = 10e25; // 10%
        uint40 lastUpdateTimestamp = uint40(block.timestamp);

        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsVariable = principalBorrowBalance;
        reserveData.currentVariableBorrowRate = variableBorrowRate;
        reserveData.lastVariableBorrowCumulativeIndex = RAY;
        reserveData.lastUpdateTimestamp = lastUpdateTimestamp;

        CoreLibrary.UserReserveData memory userReserveData = _defaultUserReserveData();

        userReserveData.principalBorrowBalance = principalBorrowBalance;

        userReserveData.lastVariableBorrowCumulativeIndex = RAY;

        harness.setReserveData(reserveData);
        harness.setUserReserveData(userReserveData);

        vm.warp(block.timestamp + SECONDS_PER_YEAR);

        // Variable debt calculation:
        //
        // currentReserveVariableIndex =
        //     compoundedVariableInterest
        //     * storedReserveVariableIndex
        //
        // compoundedVariableInterest =
        //     (RAY + variableBorrowRate / SECONDS_PER_YEAR)
        //     ^ SECONDS_PER_YEAR
        uint256 ratePerSecond = variableBorrowRate / SECONDS_PER_YEAR;

        uint256 compoundedVariableInterest = (RAY + ratePerSecond).rayPow(SECONDS_PER_YEAR);

        // Both the stored reserve index and the user checkpoint are 1 ray:
        //
        // cumulatedInterest =
        //     compoundedVariableInterest
        //     * 1.00
        //     / 1.00
        //
        // cumulatedInterest = compoundedVariableInterest
        uint256 expectedBalance = principalBorrowBalance.wadToRay().rayMul(compoundedVariableInterest).rayToWad();

        uint256 compoundedBalance = harness.getCompoundedBorrowBalance();

        assertEq(compoundedBalance, expectedBalance);
    }

    function testGetCompoundedBorrowBalanceAddsOneWeiWhenInterestRoundsToZero() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsVariable = 1;

        // A positive rate exists, but it is too small to produce a
        // representable per-second rate after integer division.
        reserveData.currentVariableBorrowRate = 1;

        CoreLibrary.UserReserveData memory userReserveData = _defaultUserReserveData();

        userReserveData.principalBorrowBalance = 1;

        harness.setReserveData(reserveData);
        harness.setUserReserveData(userReserveData);

        vm.warp(block.timestamp + 1);

        // ratePerSecond = currentVariableBorrowRate / SECONDS_PER_YEAR
        // ratePerSecond = 1 / 31_536_000
        // ratePerSecond = 0 because Solidity uses integer division
        //
        // compoundedInterest = (RAY + 0) ^ 1
        // compoundedInterest = RAY
        //
        // compoundedBalance = 1 wei * 1.00
        // compoundedBalance = 1 wei
        //
        // Time passed, but the positive interest rate produced no visible
        // increase because of rounding. The function therefore adds 1 wei.
        uint256 compoundedBalance = harness.getCompoundedBorrowBalance();

        assertEq(compoundedBalance, 2);
    }

    ////////////////////////////////////////////////////////////////
    //    increaseTotalBorrowsStableAndUpdateAverageRate         //
    ////////////////////////////////////////////////////////////////
    function testIncreaseTotalBorrowsStableSetsTotalAndRateForFirstStableBorrow() external {
        uint256 amount = 1_000 ether;
        uint256 rate = 5e25; // 5% in ray

        harness.increaseTotalBorrowsStableAndUpdateAverageRate(amount, rate);

        (uint256 totalBorrowsStable,, uint256 currentAverageStableBorrowRate) = harness.getBorrowTotals();

        // With one stable borrower, the weighted average is that borrower's rate.
        assertEq(totalBorrowsStable, amount);
        assertEq(currentAverageStableBorrowRate, rate);
    }

    function testIncreaseTotalBorrowsStableCalculatesWeightedAverageRate() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsStable = 1_000 ether; // 1,000 DAI
        reserveData.currentAverageStableBorrowRate = 5e25; // Existing 1,000 DAI at 5%
        harness.setReserveData(reserveData);

        // A new 500 DAI stable borrow at 8% makes the reserve average:
        uint256 newDebt = 500 ether;
        uint256 newRate = 8e25;

        harness.increaseTotalBorrowsStableAndUpdateAverageRate(newDebt, newRate);

        (uint256 totalBorrowsStable,, uint256 currentAverageStableBorrowRate) = harness.getBorrowTotals();

        // totalBorrowsStable = previous debt + new debt = 1,000 + 500 = 1,500 DAI
        assertEq(totalBorrowsStable, 1_500 ether);

        // newAverageRate = (previousStableDebt * previousAverageRate + newDebt * newDebtRate) / (previousStableDebt + newDebt)
        // (1,000 * 5% + 500 * 8%) / 1,500 = 6%.
        assertEq(currentAverageStableBorrowRate, 6e25);
    }

    ////////////////////////////////////////////////////////////////
    //    decreaseTotalBorrowsStableAndUpdateAverageRate         //
    ////////////////////////////////////////////////////////////////
    function testDecreaseTotalBorrowsStableRemovesDebtAndRecalculatesAverageRate() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsStable = 1_500 ether; // previous debt 1,500 DAI
        reserveData.currentAverageStableBorrowRate = 6e25; // previous average rate 6%
        harness.setReserveData(reserveData);

        // Removing the 500 DAI position at 8% leaves 1,000 DAI at 5%.
        uint256 removedDebt = 500 ether;
        uint256 removedDebtRate = 8e25;
        harness.decreaseTotalBorrowsStableAndUpdateAverageRate(removedDebt, removedDebtRate);

        (uint256 totalBorrowsStable,, uint256 currentAverageStableBorrowRate) = harness.getBorrowTotals();

        // totalBorrowStable = previous debt - removed debt = 1,500 - 500 = 1,000
        assertEq(totalBorrowsStable, 1_000 ether);
        // newAverageRate = ( previousTotalDebt * previousAverageRate - removedDebt * removedDebtRate) / remainingDebt;
        // (1,500 * 6% - 500 * 8%) / 1,000 = 5%
        assertEq(currentAverageStableBorrowRate, 5e25);
    }

    function testDecreaseTotalBorrowsStableResetsAverageRateWhenAllDebtIsRemoved() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsStable = 500 ether; // previous debt 500 DAI
        reserveData.currentAverageStableBorrowRate = 8e25; // previous average rate 8%
        harness.setReserveData(reserveData);

        uint256 removedDebt = 500 ether;
        uint256 removedDebtRate = 8e25;
        harness.decreaseTotalBorrowsStableAndUpdateAverageRate(removedDebt, removedDebtRate);

        (uint256 totalBorrowsStable,, uint256 currentAverageStableBorrowRate) = harness.getBorrowTotals();

        // totalBorrowsStable = previous debt - removed debt = 500 - 500 = 0
        assertEq(totalBorrowsStable, 0);
        assertEq(currentAverageStableBorrowRate, 0);
    }

    function testDecreaseTotalBorrowsStableRevertsWhenAmountExceedsStableDebt() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsStable = 100 ether; // previous debt 100 DAI
        harness.setReserveData(reserveData);

        vm.expectRevert(CoreLibrary.CoreLibrary__InvalidAmountToDecrease.selector);
        // We are removing 101 DAI so previous debt - removed debt < 0
        harness.decreaseTotalBorrowsStableAndUpdateAverageRate(101 ether, 5e25);
    }

    function testDecreaseTotalBorrowsStableRevertsWhenRemovedRateDoesNotMatchReserveDebt() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsStable = 1_500 ether;
        reserveData.currentAverageStableBorrowRate = 6e25;
        harness.setReserveData(reserveData);

        // The reserve's total weighted rate is 1,500 * 6% = 90.
        // Removing 500 DAI at 20% would remove a weight of 100, which is impossible.
        vm.expectRevert(CoreLibrary.CoreLibrary__AmountsToSubtractDontMatch.selector);
        harness.decreaseTotalBorrowsStableAndUpdateAverageRate(500 ether, 20e25);
    }

    ///////////////////////////////////////
    //    increaseTotalBorrowsVariable   //
    ///////////////////////////////////////
    function testIncreaseTotalBorrowsVariableAddsToVariableDebtOnly() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsStable = 100 ether;
        reserveData.currentAverageStableBorrowRate = 5e25;
        reserveData.totalBorrowsVariable = 200 ether; // previous variable debt 200 DAI
        harness.setReserveData(reserveData);

        // Adding a new variable debt of 50 DAI
        harness.increaseTotalBorrowsVariable(50 ether);

        (uint256 totalBorrowsStable, uint256 totalBorrowsVariable, uint256 currentAverageStableBorrowRate) =
            harness.getBorrowTotals();

        assertEq(totalBorrowsStable, 100 ether);
        // total borrows variable = previous variable debt + new variable debt = 200 + 50 = 250
        assertEq(totalBorrowsVariable, 250 ether);
        assertEq(currentAverageStableBorrowRate, 5e25);
    }

    ///////////////////////////////////////
    //    decreaseTotalBorrowsVariable   //
    ///////////////////////////////////////

    function testDecreaseTotalBorrowsVariableSubtractsVariableDebtOnly() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsStable = 100 ether;
        reserveData.currentAverageStableBorrowRate = 5e25;
        reserveData.totalBorrowsVariable = 250 ether; // prevous variable debt 250 DAI
        harness.setReserveData(reserveData);

        // removed variable debt 50 DAI
        harness.decreaseTotalBorrowsVariable(50 ether);

        (uint256 totalBorrowsStable, uint256 totalBorrowsVariable, uint256 currentAverageStableBorrowRate) =
            harness.getBorrowTotals();

        assertEq(totalBorrowsStable, 100 ether);
        // new variable debt = previsious variable debt - removed variable debt = 250 - 50 = 200
        assertEq(totalBorrowsVariable, 200 ether);
        //
        assertEq(currentAverageStableBorrowRate, 5e25);
    }

    function testDecreaseTotalBorrowsVariableRevertsWhenAmountExceedsVariableDebt() external {
        CoreLibrary.ReserveData memory reserveData = _defaultReserveData();
        reserveData.totalBorrowsVariable = 100 ether; // previous variable debt 100 DAI
        harness.setReserveData(reserveData);

        vm.expectRevert(CoreLibrary.CoreLibrary__InvalidVariableBorrowDecrease.selector);
        // Trying to remove 101 DAI but previous debt is 100 DAi so 101 - 100 = -1 --> reverts
        harness.decreaseTotalBorrowsVariable(101 ether);
    }

    //////////////////////////
    //    enableBorrowing   //
    //////////////////////////
    function testEnableBorrowingEnablesBorrowingAndConfiguresStableRateMode() external {
        harness.enableBorrowing(true);

        (bool borrowingEnabled, bool isStableBorrowRateEnabled) = harness.getBorrowingConfiguration();

        assertTrue(borrowingEnabled);
        assertTrue(isStableBorrowRateEnabled);
    }

    function testEnableBorrowingRevertsWhenBorrowingIsAlreadyEnabled() external {
        harness.enableBorrowing(false);

        vm.expectRevert(CoreLibrary.CoreLibrary__ReserveAlreadyEnabled.selector);
        harness.enableBorrowing(true);
    }

    ///////////////////////////
    //    disableBorrowing   //
    ///////////////////////////
    function testDisableBorrowingDisablesNewBorrowsWithoutChangingStableRateConfiguration() external {
        harness.enableBorrowing(true);

        harness.disableBorrowing();

        (bool borrowingEnabled, bool isStableBorrowRateEnabled) = harness.getBorrowingConfiguration();

        assertFalse(borrowingEnabled);
        assertTrue(isStableBorrowRateEnabled);
    }

    /////////////////////////////
    //    enableAsCollateral   //
    /////////////////////////////
    function testEnableAsCollateralStoresRiskParametersAndInitializesLiquidityIndex() external {
        // Start from an all-zero reserve to exercise the defensive index initialization path.
        uint256 baseLTVasCollateral = 75;
        uint256 liquidationThreshold = 80;
        uint256 liquidationBonus = 105;
        harness.enableAsCollateral(baseLTVasCollateral, liquidationThreshold, liquidationBonus);

        (
            bool usageAsCollateralEnabled,
            uint256 actualBaseLTVasCollateral,
            uint256 actualLiquidationThreshold,
            uint256 actualLiquidationBonus,
            uint256 lastLiquidityCumulativeIndex
        ) = harness.getCollateralConfiguration();

        assertTrue(usageAsCollateralEnabled);
        assertEq(actualBaseLTVasCollateral, baseLTVasCollateral);
        assertEq(actualLiquidationThreshold, liquidationThreshold);
        assertEq(actualLiquidationBonus, liquidationBonus);
        assertEq(lastLiquidityCumulativeIndex, RAY);
    }

    function testEnableAsCollateralRevertsWhenCollateralIsAlreadyEnabled() external {
        harness.enableAsCollateral(75, 80, 105);

        vm.expectRevert(CoreLibrary.CoreLibrary__ReserveAlreadyNeabledAsCollateral.selector);
        harness.enableAsCollateral(60, 70, 110);
    }

    function testDisableAsCollateralDisablesCollateralWithoutErasingRiskParameters() external {
        harness.enableAsCollateral(75, 80, 105);

        harness.disableAsCollateral();

        (
            bool usageAsCollateralEnabled,
            uint256 baseLTVasCollateral,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
        ) = harness.getCollateralConfiguration();

        assertFalse(usageAsCollateralEnabled);
        assertEq(baseLTVasCollateral, 75);
        assertEq(liquidationThreshold, 80);
        assertEq(liquidationBonus, 105);
    }
}
