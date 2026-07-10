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

    function _setUpReserveScenario(address reserveAddress, ReserveScenario memory scenario) internal {
        _setUpReserve(
            reserveAddress,
            scenario.decimals,
            scenario.baseLtv,
            scenario.liquidationThreshold,
            scenario.reserveUsageAsCollateralEnabled,
            scenario.priceInETH
        );

        core.setUserBasicReserveData(
            user,
            reserveAddress,
            scenario.liquidityBalance,
            scenario.borrowBalance,
            scenario.originationFee,
            scenario.userUsesReserveAsCollateral
        );
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

        // Empty reserve, should not affect calculation.
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

        _setUpReserveScenario(reserve, firstReserveScenario);
        _setUpReserveScenario(secondReserve, secondReserveScenario);
        _setUpReserveScenario(emptyReserve, thirdReserveScenario);

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

        // First reserve uses 18 decimals, so tokenUnit = 10 ** 18 = 1e18.
        // liquidityBalanceETH = liquidityBalance * priceInETH / tokenUnit
        // liquidityBalanceETH = 100e18 * 0.01e18 / 1e18 = 1e18 = 1 ETH
        //
        // borrowBalanceETH = borrowBalance * priceInETH / tokenUnit
        // borrowBalanceETH = 20e18 * 0.01e18 / 1e18 = 0.2e18 = 0.2 ETH
        //
        // feesETH = originationFee * priceInETH / tokenUnit
        // feesETH = 1e18 * 0.01e18 / 1e18 = 0.01e18 = 0.01 ETH
        //
        // Second reserve uses 6 decimals, so tokenUnit = 10 ** 6 = 1_000_000.
        // liquidityBalanceETH = liquidityBalance * priceInETH / tokenUnit
        // liquidityBalanceETH = 4_000_000 * 0.5e18 / 1_000_000 = 2e18 = 2 ETH
        //
        // borrowBalanceETH = borrowBalance * priceInETH / tokenUnit
        // borrowBalanceETH = 1_000_000 * 0.5e18 / 1_000_000 = 0.5e18 = 0.5 ETH
        //
        // feesETH = originationFee * priceInETH / tokenUnit
        // feesETH = 100_000 * 0.5e18 / 1_000_000 = 0.05e18 = 0.05 ETH
        //
        // Empty reserve has no user liquidity or borrow, so its 90 LTV, 95 threshold,
        // and 99 ETH price must not affect any aggregate value.
        //
        // expectedTotalLiquidityBalanceETH = 1 ETH + 2 ETH = 3 ETH.
        uint256 expectedTotalLiquidityBalanceETH = 3 ether;

        // Both non-empty reserves are enabled as collateral by the reserve and by the user,
        // so all liquidity also counts as collateral.
        // expectedTotalCollateralBalanceETH = 1 ETH + 2 ETH = 3 ETH.
        uint256 expectedTotalCollateralBalanceETH = 3 ether;

        // expectedTotalBorrowBalanceETH = 0.2 ETH + 0.5 ETH = 0.7 ETH.
        uint256 expectedTotalBorrowBalanceETH = 0.7 ether;

        // expectedTotalFeesETH = 0.01 ETH + 0.05 ETH = 0.06 ETH.
        uint256 expectedTotalFeesETH = 0.06 ether;

        // currentLtv = ((1 ETH * 75) + (2 ETH * 50)) / 3 ETH
        // currentLtv = (75 + 100) / 3 = 58.
        uint256 expectedCurrentLtv = 58;

        // currentLiquidationThreshold = ((1 ETH * 80) + (2 ETH * 60)) / 3 ETH
        // currentLiquidationThreshold = (80 + 120) / 3 = 66.
        uint256 expectedCurrentLiquidationThreshold = 66;

        // healthFactor = adjusted collateral / total debt
        // adjustedCollateral = 3 ETH * 66 / 100 = 1.98 ETH
        // totalDebt = 0.7 ETH borrow + 0.06 ETH fees = 0.76 ETH
        // healthFactor = 1.98 ETH / 0.76 ETH = 2.605263157894736842e18
        uint256 expectedHealthFactor = ((expectedTotalCollateralBalanceETH * expectedCurrentLiquidationThreshold) / 100)
        .wadDiv(expectedTotalBorrowBalanceETH + expectedTotalFeesETH);

        assertEq(totalLiquidityBalanceETH, expectedTotalLiquidityBalanceETH);
        assertEq(totalCollateralBalanceETH, expectedTotalCollateralBalanceETH);
        assertEq(totalBorrowBalanceETH, expectedTotalBorrowBalanceETH);
        assertEq(totalFeesETH, expectedTotalFeesETH);
        assertEq(currentLtv, expectedCurrentLtv);
        assertEq(currentLiquidationThreshold, expectedCurrentLiquidationThreshold);
        assertEq(healthFactor, expectedHealthFactor);
        assertFalse(healthFactorBelowThreshold);
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

        _setUpReserveScenario(reserve, firstReserveScenario);
        _setUpReserveScenario(secondReserve, secondReserveScenario);

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
        ReserveScenario memory reserveScenario = ReserveScenario({
            decimals: 18,
            baseLtv: 75,
            liquidationThreshold: 80,
            priceInETH: 0.01 ether,
            liquidityBalance: 100 ether,
            borrowBalance: 200 ether,
            originationFee: 0,
            reserveUsageAsCollateralEnabled: true,
            userUsesReserveAsCollateral: true
        });

        _setUpReserveScenario(reserve, reserveScenario);

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
        uint256 expectedHealthFactor = 0.4 ether;

        assertEq(healthFactor, expectedHealthFactor);
        assertLt(expectedHealthFactor, HEALTH_FACTOR_LIQUIDATION_THRESHOLD);
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
