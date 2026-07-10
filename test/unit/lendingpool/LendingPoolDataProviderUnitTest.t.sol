// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";

import {MockLendingPoolCore} from "../../mocks/MockLendingPoolCore.sol";
import {MockPriceOracle} from "../../mocks/MockPriceOracle.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolDataProvider} from "src/lendingpool/LendingPoolDataProvider.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";

contract LendingPoolDataProviderHarness is LendingPoolDataProvider {
    constructor(address addressesProvider) LendingPoolDataProvider(addressesProvider) {}

    function exposedCalculateHealthFactorFromBalances(
        uint256 collateralBalanceETH,
        uint256 borrowBalanceETH,
        uint256 totalFeesETH,
        uint256 liquidationThreshold
    ) external pure returns (uint256) {
        return _calculateHealthFactorFromBalances(
            collateralBalanceETH, borrowBalanceETH, totalFeesETH, liquidationThreshold
        );
    }
}

contract LendingPoolDataProviderUnitTest is Test {
    using WadRayMath for uint256;

    uint256 private constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18;

    address private user = makeAddr("user");
    address private reserve = makeAddr("reserve");
    address private secondReserve = makeAddr("secondReserve");
    address private emptyReserve = makeAddr("emptyReserve");

    LendingPoolAddressesProvider private addressesProvider;
    MockLendingPoolCore private core;
    MockPriceOracle private oracle;
    LendingPoolDataProviderHarness private dataProvider;

    function setUp() external {
        addressesProvider = new LendingPoolAddressesProvider(address(this));
        core = new MockLendingPoolCore();
        oracle = new MockPriceOracle();

        addressesProvider.setLendingPoolCore(address(core));
        addressesProvider.setPriceOracle(address(oracle));

        dataProvider = new LendingPoolDataProviderHarness(address(addressesProvider));
    }

    function _setUpReserve(
        address reserveAddress,
        uint256 decimals,
        uint256 baseLtv,
        uint256 liquidationThreshold,
        bool usageAsCollateralEnabled,
        uint256 priceInETH
    ) internal {
        core.addReserve(reserveAddress);
        core.setReserveConfiguration(reserveAddress, decimals, baseLtv, liquidationThreshold, usageAsCollateralEnabled);
        oracle.setAssetPrice(reserveAddress, priceInETH);
    }

    ////////////////////////////////
    //         constructor        //
    ////////////////////////////////

    function testConstructorRevertsWhenAddressesProviderIsZero() external {
        vm.expectRevert(LendingPoolDataProvider.LendingPoolDataProvider__ZeroAddress.selector);

        new LendingPoolDataProvider(address(0));
    }

    function testConstructorRevertsWhenCoreIsZero() external {
        LendingPoolAddressesProvider providerWithoutCore = new LendingPoolAddressesProvider(address(this));

        vm.expectRevert(LendingPoolDataProvider.LendingPoolDataProvider__ZeroAddress.selector);

        new LendingPoolDataProvider(address(providerWithoutCore));
    }

    ////////////////////////////////
    //     calculateHealthFactor  //
    ////////////////////////////////

    function testCalculateHealthFactorReturnsMaxWhenUserHasNoBorrow() external view {
        uint256 healthFactor = dataProvider.exposedCalculateHealthFactorFromBalances(1 ether, 0, 0, 80);

        assertEq(healthFactor, type(uint256).max);
    }

    function testCalculateHealthFactorUsesLiquidationThresholdBorrowAndFees() external view {
        // Health factor formula:
        // healthFactor = collateral adjusted by liquidation threshold / borrow balance + fees
        //
        // In Aave V1 terms:
        // Hf = TotalCollateralETH * LiquidationThreshold / (TotalBorrowsETH + TotalFeesETH)
        uint256 collateralBalanceETH = 2 ether;
        uint256 borrowBalanceETH = 1 ether;
        uint256 totalFeesETH = 0.2 ether;
        uint256 liquidationThreshold = 80;

        uint256 healthFactor = dataProvider.exposedCalculateHealthFactorFromBalances(
            collateralBalanceETH, borrowBalanceETH, totalFeesETH, liquidationThreshold
        );

        // Step 1: adjust collateral by liquidation threshold.
        //
        // adjustedCollateral = 2 ETH * 80 / 100
        // adjustedCollateral = 1.6 ETH
        uint256 adjustedCollateral = (collateralBalanceETH * liquidationThreshold) / 100;

        // Step 2: divide adjusted collateral by total debt.
        //
        // total debt = borrow + fees
        // total debt = 1 ETH + 0.2 ETH = 1.2 ETH
        //
        // expectedHealthFactor = 1.6 ETH / 1.2 ETH
        // expectedHealthFactor = 1.333333333333333333
        //
        // wadDiv returns the result in wad precision:
        // 1.333333333333333333e18
        uint256 expectedHealthFactor = adjustedCollateral.wadDiv(borrowBalanceETH + totalFeesETH);

        assertEq(healthFactor, expectedHealthFactor);
    }

    ////////////////////////////////
    //    calculateUserGlobalData //
    ////////////////////////////////

    function testCalculateUserGlobalDataReturnsEmptyPositionForUserWithoutBalances() external {
        uint256 decimals = 18;
        uint256 baseLtv = 75;
        uint256 liquidationThreshold = 80;
        bool usageAsCollateralEnabled = true;

        core.addReserve(reserve);
        core.setReserveConfiguration(reserve, decimals, baseLtv, liquidationThreshold, usageAsCollateralEnabled);

        (
            uint256 totalLiquidityBalanceETH,
            uint256 totalCollateralBalanceETH,
            uint256 totalBorrowBalanceETH,
            uint256 totalFeesETH,
            uint256 currentLtv,
            uint256 currentLiquidationThreshold,
            uint256 healthFactor,
            bool healthFactorBelowThreshold
        ) = dataProvider.calculateUserGlobalData(user);

        assertEq(totalLiquidityBalanceETH, 0);
        assertEq(totalCollateralBalanceETH, 0);
        assertEq(totalBorrowBalanceETH, 0);
        assertEq(totalFeesETH, 0);
        assertEq(currentLtv, 0);
        assertEq(currentLiquidationThreshold, 0);
        assertEq(healthFactor, type(uint256).max);
        assertFalse(healthFactorBelowThreshold);
    }

    // Reserve values for the test testCalculateUserGlobalDataAggregatesBalancesAcrossReserves()
    struct ReserveScenario {
        uint256 decimals;
        uint256 baseLtv;
        uint256 liquidationThreshold;
        uint256 priceInETH;
        uint256 liquidityBalance;
        uint256 borrowBalance;
        uint256 originationFee;
        bool reserveUsageAsCollateralEnabled;
        bool userUsesReserveAsCollateral;
    }

    // Values returned by the test function _calculateReserveValuesETH
    struct ReserveValuesETH {
        uint256 liquidityBalanceETH;
        uint256 borrowBalanceETH;
        uint256 feesETH;
    }

    // Expected values for the test testCalculateUserGlobalDataAggregatesBalancesAcrossReserves()
    // It maps the output of the function calculateUserGlobalData()
    struct ExpectedUserGlobalData {
        uint256 totalLiquidityBalanceETH;
        uint256 totalCollateralBalanceETH;
        uint256 totalBorrowBalanceETH;
        uint256 totalFeesETH;
        uint256 currentLtv;
        uint256 currentLiquidationThreshold;
        uint256 healthFactor;
        bool healthFactorBelowThreshold;
    }

    // Util function for _calculateExpectedGlobalData
    // Calculates: liquidityBalanceETH, borrowBalanceETH and feesETH for a single reserve
    function _calculateReserveValuesETH(ReserveScenario memory scenario)
        internal
        pure
        returns (ReserveValuesETH memory values)
    {
        // Example first reserve scenario:
        //
        // decimals = 18
        // liquidityBalance = 100e18
        // priceInETH = 0.01e18
        // originationFee = 1e18
        // borrowBalance = 20e18

        // tokenUnit = 10 ** 18
        uint256 tokenUnit = 10 ** scenario.decimals;

        // liquidityBalanceETH = liquidityBalance * priceInETH / tokenUnit
        // liquidityBalanceETH = 100e18 * 0.01e18 / 1e18 = 1e18
        values.liquidityBalanceETH = scenario.liquidityBalance * scenario.priceInETH / tokenUnit;

        // borrowBalanceETH = borrowBalance * priceInETH / tokenUnit
        // borrowBalanceETH = 20e18 * 0.01e18 / 1e18 = 0.2e18
        values.borrowBalanceETH = scenario.borrowBalance * scenario.priceInETH / tokenUnit;

        // feeETH = originationFee * priceInETH / tokenUnit
        // feesETH = 1e18 * 0.01e18 / 1e18 = 0.01e18
        values.feesETH = scenario.originationFee * scenario.priceInETH / tokenUnit;
    }

    // Util function for testCalculateUserGlobalDataAggregatesBalancesAcrossReserves
    // Calculates the field of ExpectedUserGlobalData, used to test the results of calculateUserGlobalData()
    function _calculateExpectedGlobalData(
        ReserveScenario memory firstReserveScenario,
        ReserveScenario memory secondReserveScenario
    ) internal pure returns (ExpectedUserGlobalData memory expected) {
        ReserveValuesETH memory firstReserveValuesETH = _calculateReserveValuesETH(firstReserveScenario);
        ReserveValuesETH memory secondReserveValuesETH = _calculateReserveValuesETH(secondReserveScenario);

        // First reserve values:
        // decimals: 18,
        // baseLtv: 75,
        // liquidationThreshold: 80,
        // priceInETH: 0.01e18,
        // liquidityBalance: 100e18,
        // borrowBalance: 20e18,
        // originationFee: 1e18
        //
        // Second reserve values:
        // decimals: 6,
        // baseLtv: 50,
        // liquidationThreshold: 60,
        // priceInETH: 0.5e18,
        // liquidityBalance: 4_000_000,
        // borrowBalance: 1_000_000,
        // originationFee: 100_000

        // First reserve ETH values:
        // tokenUnit = 10 ** 18 = 1e18
        // liquidityBalanceETH = 100e18 * 0.01e18 / 1e18 = 1e18 = 1 ETH
        // borrowBalanceETH = 20e18 * 0.01e18 / 1e18 = 0.2e18 = 0.2 ETH
        // feesETH = 1e18 * 0.01e18 / 1e18 = 0.01e18 = 0.01 ETH
        //
        // Second reserve ETH values:
        // tokenUnit = 10 ** 6 = 1_000_000
        // liquidityBalanceETH = 4_000_000 * 0.5e18 / 1_000_000 = 2e18 = 2 ETH
        // borrowBalanceETH = 1_000_000 * 0.5e18 / 1_000_000 = 0.5e18 = 0.5 ETH
        // feesETH = 100_000 * 0.5e18 / 1_000_000 = 0.05e18 = 0.05 ETH

        // Total liquidity/collateral = first reserve liquidity + second reserve liquidity
        // Total liquidity/collateral = 1 ETH + 2 ETH = 3 ETH.
        expected.totalLiquidityBalanceETH =
            firstReserveValuesETH.liquidityBalanceETH + secondReserveValuesETH.liquidityBalanceETH;
        expected.totalCollateralBalanceETH = expected.totalLiquidityBalanceETH;

        // Total borrow = first reserve borrow + second reserve borrow
        // Total borrow = 0.2 ETH + 0.5 ETH = 0.7 ETH.
        expected.totalBorrowBalanceETH =
            firstReserveValuesETH.borrowBalanceETH + secondReserveValuesETH.borrowBalanceETH;

        // Total fees = first reserve fees + second reserve fees
        // Total fees = 0.01 ETH + 0.05 ETH = 0.06 ETH.
        expected.totalFeesETH = firstReserveValuesETH.feesETH + secondReserveValuesETH.feesETH;

        // currentLtv = sum(collateralValueETH * reserveLtv) / totalCollateralBalanceETH
        // currentLtv = ((1 ETH * 75) + (2 ETH * 50)) / 3 ETH
        // currentLtv = (75 + 100) / 3 = 58.
        expected.currentLtv =
            ((firstReserveValuesETH.liquidityBalanceETH * firstReserveScenario.baseLtv)
                    + (secondReserveValuesETH.liquidityBalanceETH * secondReserveScenario.baseLtv))
                / expected.totalCollateralBalanceETH;

        // currentLiquidationThreshold = sum(collateralvalueETH * liquidationThreshold) / totalCollateralBalanceETH
        // currentLiquidationThreshold = ((1 ETH * 80) + (2 ETH * 60)) / 3 ETH
        // currentLiquidationThreshold = (80 + 120) / 3 = 66.
        expected.currentLiquidationThreshold =
            ((firstReserveValuesETH.liquidityBalanceETH * firstReserveScenario.liquidationThreshold)
                    + (secondReserveValuesETH.liquidityBalanceETH * secondReserveScenario.liquidationThreshold))
                / expected.totalCollateralBalanceETH;

        // healthFactor = TotalCollateralETH * LiquidationThreshold / (TotalBorrowsETH + TotalFeesETH)
        // adjustedCollateral = 3 ETH * 66 / 100 = 1.98 ETH
        // totalDebt = 0.7 ETH borrow + 0.06 ETH fees = 0.76 ETH
        // healthFactor = 1.98 ETH / 0.76 ETH = 2.605263157894736842e18
        expected.healthFactor = ((expected.totalCollateralBalanceETH * expected.currentLiquidationThreshold) / 100)
        .wadDiv(expected.totalBorrowBalanceETH + expected.totalFeesETH);

        expected.healthFactorBelowThreshold = expected.healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    function testCalculateUserGlobalDataAggregatesBalancesAcrossReserves() external {
        ReserveScenario memory firstReserveScenario = ReserveScenario({
            decimals: 18,
            baseLtv: 75,
            liquidationThreshold: 80,
            priceInETH: 0.01 ether,
            liquidityBalance: 100 ether,
            borrowBalance: 20 ether,
            originationFee: 1 ether,
            reserveUsageAsCollateralEnabled: true,
            userUsesReserveAsCollateral: true
        });
        ReserveScenario memory secondReserveScenario = ReserveScenario({
            decimals: 6,
            baseLtv: 50,
            liquidationThreshold: 60,
            priceInETH: 0.5 ether,
            liquidityBalance: 4_000_000,
            borrowBalance: 1_000_000,
            originationFee: 100_000,
            reserveUsageAsCollateralEnabled: true,
            userUsesReserveAsCollateral: true
        });

        // Empty reserve, should not effect calculation
        ReserveScenario memory thirdReserveScenario = ReserveScenario({
            decimals: 18,
            baseLtv: 90,
            liquidationThreshold: 95,
            priceInETH: 99 ether,
            liquidityBalance: 0,
            borrowBalance: 0,
            originationFee: 0,
            reserveUsageAsCollateralEnabled: true,
            userUsesReserveAsCollateral: false
        });

        _setUpReserve(
            reserve,
            firstReserveScenario.decimals,
            firstReserveScenario.baseLtv,
            firstReserveScenario.liquidationThreshold,
            firstReserveScenario.reserveUsageAsCollateralEnabled,
            firstReserveScenario.priceInETH
        );
        _setUpReserve(
            secondReserve,
            secondReserveScenario.decimals,
            secondReserveScenario.baseLtv,
            secondReserveScenario.liquidationThreshold,
            secondReserveScenario.reserveUsageAsCollateralEnabled,
            secondReserveScenario.priceInETH
        );
        _setUpReserve(
            emptyReserve,
            thirdReserveScenario.decimals,
            thirdReserveScenario.baseLtv,
            thirdReserveScenario.liquidationThreshold,
            thirdReserveScenario.reserveUsageAsCollateralEnabled,
            thirdReserveScenario.priceInETH
        );

        core.setUserBasicReserveData(
            user,
            reserve,
            firstReserveScenario.liquidityBalance,
            firstReserveScenario.borrowBalance,
            firstReserveScenario.originationFee,
            firstReserveScenario.userUsesReserveAsCollateral
        );
        core.setUserBasicReserveData(
            user,
            secondReserve,
            secondReserveScenario.liquidityBalance,
            secondReserveScenario.borrowBalance,
            secondReserveScenario.originationFee,
            secondReserveScenario.userUsesReserveAsCollateral
        );

        (
            uint256 totalLiquidityBalanceETH,
            uint256 totalCollateralBalanceETH,
            uint256 totalBorrowBalanceETH,
            uint256 totalFeesETH,
            uint256 currentLtv,
            uint256 currentLiquidationThreshold,
            uint256 healthFactor,
            bool healthFactorBelowThreshold
        ) = dataProvider.calculateUserGlobalData(user);

        ExpectedUserGlobalData memory expected =
            _calculateExpectedGlobalData(firstReserveScenario, secondReserveScenario);

        assertEq(totalLiquidityBalanceETH, expected.totalLiquidityBalanceETH);
        assertEq(totalCollateralBalanceETH, expected.totalCollateralBalanceETH);
        assertEq(totalBorrowBalanceETH, expected.totalBorrowBalanceETH);
        assertEq(totalFeesETH, expected.totalFeesETH);
        assertEq(currentLtv, expected.currentLtv);
        assertEq(currentLiquidationThreshold, expected.currentLiquidationThreshold);
        assertEq(healthFactor, expected.healthFactor);
        assertEq(healthFactorBelowThreshold, expected.healthFactorBelowThreshold);
    }

    function testCalculateUserGlobalDataExcludesCollateralWhenReserveOrUserDoesNotEnableIt() external {
        ReserveScenario memory firstReserveScenario = ReserveScenario({
            decimals: 18,
            baseLtv: 75,
            liquidationThreshold: 80,
            priceInETH: 0.01 ether,
            liquidityBalance: 100 ether,
            borrowBalance: 0,
            originationFee: 0,
            reserveUsageAsCollateralEnabled: false,
            userUsesReserveAsCollateral: true
        });
        ReserveScenario memory secondReserveScenario = ReserveScenario({
            decimals: 18,
            baseLtv: 50,
            liquidationThreshold: 60,
            priceInETH: 0.5 ether,
            liquidityBalance: 2 ether,
            borrowBalance: 0,
            originationFee: 0,
            reserveUsageAsCollateralEnabled: true,
            userUsesReserveAsCollateral: false
        });

        _setUpReserve(
            reserve,
            firstReserveScenario.decimals,
            firstReserveScenario.baseLtv,
            firstReserveScenario.liquidationThreshold,
            firstReserveScenario.reserveUsageAsCollateralEnabled,
            firstReserveScenario.priceInETH
        );
        _setUpReserve(
            secondReserve,
            secondReserveScenario.decimals,
            secondReserveScenario.baseLtv,
            secondReserveScenario.liquidationThreshold,
            secondReserveScenario.reserveUsageAsCollateralEnabled,
            secondReserveScenario.priceInETH
        );

        core.setUserBasicReserveData(
            user,
            reserve,
            firstReserveScenario.liquidityBalance,
            firstReserveScenario.borrowBalance,
            firstReserveScenario.originationFee,
            firstReserveScenario.userUsesReserveAsCollateral
        );
        core.setUserBasicReserveData(
            user,
            secondReserve,
            secondReserveScenario.liquidityBalance,
            secondReserveScenario.borrowBalance,
            secondReserveScenario.originationFee,
            secondReserveScenario.userUsesReserveAsCollateral
        );

        (
            uint256 totalLiquidityBalanceETH,
            uint256 totalCollateralBalanceETH,,,
            uint256 currentLtv,
            uint256 currentLiquidationThreshold,,
        ) = dataProvider.calculateUserGlobalData(user);

        // Both supplied balances still count as liquidity, even when they do not count as collateral:
        // first reserve liquidity = 100 tokens * 0.01 ETH = 1 ETH
        // second reserve liquidity = 2 tokens * 0.5 ETH = 1 ETH
        // totalLiquidityBalanceETH = 1 ETH + 1 ETH = 2 ETH
        assertEq(totalLiquidityBalanceETH, 2 ether);

        // Neither reserve counts as collateral:
        // first reserve: reserveUsageAsCollateralEnabled = false, so it is excluded
        // second reserve: userUsesReserveAsCollateral = false, so it is excluded
        // totalCollateralBalanceETH = 0 ETH + 0 ETH = 0 ETH
        assertEq(totalCollateralBalanceETH, 0);

        // LTV and liquidation threshold are weighted averages over collateral only.
        // Since total collateral is 0, both weighted values are 0.
        assertEq(currentLtv, 0);
        assertEq(currentLiquidationThreshold, 0);
    }

    function testCalculateUserGlobalDataMarksHealthFactorBelowThreshold() external {
        uint256 decimals = 18;
        uint256 baseLtv = 75;
        uint256 liquidationThreshold = 80;
        bool usageAsCollateralEnabled = true;
        uint256 priceInETH = 0.01 ether;

        _setUpReserve(reserve, decimals, baseLtv, liquidationThreshold, usageAsCollateralEnabled, priceInETH);

        uint256 liquidityBalance = 100 ether;
        uint256 borrowBalance = 200 ether;
        uint256 originationFee = 0;
        bool useAsCollateral = true;

        core.setUserBasicReserveData(user, reserve, liquidityBalance, borrowBalance, originationFee, useAsCollateral);

        (,,,,,, uint256 healthFactor, bool healthFactorBelowThreshold) = dataProvider.calculateUserGlobalData(user);

        // User position in ETH:
        // tokenUnit = 10 ** 18 = 1e18
        // collateral/liquidity = 100e18 tokens * 0.01e18 ETH / 1e18 = 1e18 = 1 ETH
        // borrow = 200e18 tokens * 0.01e18 ETH / 1e18 = 2e18 = 2 ETH
        // fees = 0
        //
        // Health factor formula:
        // healthFactor = collateral adjusted by liquidation threshold / (borrow + fees)
        // adjustedCollateral = 1 ETH * 80 / 100 = 0.8 ETH
        // totalDebt = 2 ETH + 0 ETH = 2 ETH
        // healthFactor = 0.8 ETH / 2 ETH = 0.4e18
        //
        // Since 0.4e18 is less than the liquidation threshold of 1e18,
        // healthFactorBelowThreshold should be true.
        assertLt(healthFactor, HEALTH_FACTOR_LIQUIDATION_THRESHOLD);
        assertTrue(healthFactorBelowThreshold);
    }

    ////////////////////////////////
    //    balanceDecreaseAllowed  //
    ////////////////////////////////

    function testBalanceDecreaseAllowedReturnsTrueWhenReserveCollateralIsDisabled() external {
        _setUpReserve(reserve, 18, 75, 80, false, 0.01 ether);
        core.setUserBasicReserveData(user, reserve, 100 ether, 200 ether, 0, true);

        bool allowed = dataProvider.balanceDecreaseAllowed(reserve, user, 100 ether);

        assertTrue(allowed);
    }

    function testBalanceDecreaseAllowedReturnsTrueWhenUserDoesNotUseReserveAsCollateral() external {
        _setUpReserve(reserve, 18, 75, 80, true, 0.01 ether);
        core.setUserBasicReserveData(user, reserve, 100 ether, 200 ether, 0, false);

        bool allowed = dataProvider.balanceDecreaseAllowed(reserve, user, 100 ether);

        assertTrue(allowed);
    }

    function testBalanceDecreaseAllowedReturnsTrueWhenUserHasNoBorrow() external {
        _setUpReserve(reserve, 18, 75, 80, true, 0.01 ether);
        core.setUserBasicReserveData(user, reserve, 100 ether, 0, 0, true);

        bool allowed = dataProvider.balanceDecreaseAllowed(reserve, user, 100 ether);

        assertTrue(allowed);
    }

    function testBalanceDecreaseAllowedReturnsFalseWhenCollateralWouldBecomeZeroWithBorrow() external {
        _setUpReserve(reserve, 18, 75, 80, true, 0.01 ether);
        core.setUserBasicReserveData(user, reserve, 100 ether, 50 ether, 0, true);

        bool allowed = dataProvider.balanceDecreaseAllowed(reserve, user, 100 ether);

        assertFalse(allowed);
    }

    function testBalanceDecreaseAllowedReturnsTrueWhenHealthFactorStaysAboveThreshold() external {
        _setUpReserve(reserve, 18, 75, 80, true, 0.01 ether);
        core.setUserBasicReserveData(user, reserve, 100 ether, 50 ether, 0, true);

        bool allowed = dataProvider.balanceDecreaseAllowed(reserve, user, 10 ether);

        assertTrue(allowed);
    }

    function testBalanceDecreaseAllowedReturnsFalseWhenHealthFactorFallsBelowThreshold() external {
        _setUpReserve(reserve, 18, 75, 80, true, 0.01 ether);
        core.setUserBasicReserveData(user, reserve, 100 ether, 50 ether, 0, true);

        bool allowed = dataProvider.balanceDecreaseAllowed(reserve, user, 40 ether);

        assertFalse(allowed);
    }
}
