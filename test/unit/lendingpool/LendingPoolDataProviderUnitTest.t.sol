// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

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
        core.addReserve(reserve);
        core.setReserveConfiguration(reserve, 18, 75, 80, true);

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

    function testCalculateUserGlobalDataAggregatesBalancesAcrossReserves() external {
        _setUpReserve(reserve, 18, 75, 80, true, 0.01 ether);
        _setUpReserve(secondReserve, 6, 50, 60, true, 0.5 ether);
        _setUpReserve(emptyReserve, 18, 90, 95, true, 99 ether);

        core.setUserBasicReserveData(user, reserve, 100 ether, 20 ether, 1 ether, true);
        core.setUserBasicReserveData(user, secondReserve, 4_000_000, 1_000_000, 100_000, true);

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

        uint256 expectedTotalLiquidityBalanceETH = 3 ether;
        uint256 expectedTotalCollateralBalanceETH = 3 ether;
        uint256 expectedTotalBorrowBalanceETH = 0.7 ether;
        uint256 expectedTotalFeesETH = 0.06 ether;
        uint256 expectedCurrentLtv = 58;
        uint256 expectedCurrentLiquidationThreshold = 66;
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
        _setUpReserve(reserve, 18, 75, 80, false, 0.01 ether);
        _setUpReserve(secondReserve, 18, 50, 60, true, 0.5 ether);

        core.setUserBasicReserveData(user, reserve, 100 ether, 0, 0, true);
        core.setUserBasicReserveData(user, secondReserve, 2 ether, 0, 0, false);

        (
            uint256 totalLiquidityBalanceETH,
            uint256 totalCollateralBalanceETH,,,
            uint256 currentLtv,
            uint256 currentLiquidationThreshold,,
        ) = dataProvider.calculateUserGlobalData(user);

        assertEq(totalLiquidityBalanceETH, 2 ether);
        assertEq(totalCollateralBalanceETH, 0);
        assertEq(currentLtv, 0);
        assertEq(currentLiquidationThreshold, 0);
    }

    function testCalculateUserGlobalDataMarksHealthFactorBelowThreshold() external {
        _setUpReserve(reserve, 18, 75, 80, true, 0.01 ether);
        core.setUserBasicReserveData(user, reserve, 100 ether, 200 ether, 0, true);

        (,,,,,, uint256 healthFactor, bool healthFactorBelowThreshold) = dataProvider.calculateUserGlobalData(user);

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
