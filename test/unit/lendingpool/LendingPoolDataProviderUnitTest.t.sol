// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";

import {MockLendingPoolCore} from "../../mocks/MockLendingPoolCore.sol";
import {MockPriceOracle} from "../../mocks/oracle/MockPriceOracle.sol";
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

    // Input values for _setUpReserveScenario
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

    function _setUpReserveScenario(address reserveAddress, ReserveScenario memory scenario) internal {
        _setUpReserve(
            reserveAddress,
            scenario.decimals,
            scenario.baseLtv,
            scenario.liquidationThreshold,
            scenario.reserveUsageAsCollateralEnabled,
            scenario.priceInETH
        );

        core.setTestUserReserveData(
            user,
            reserveAddress,
            scenario.liquidityBalance,
            scenario.borrowBalance,
            scenario.originationFee,
            scenario.userUsesReserveAsCollateral
        );
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

    ////////////////////////////////////////////////
    //     _calculateHealthFactorFromBalances     //
    ////////////////////////////////////////////////

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

    // This test registers a reserve and configures it but it deliberately gives user no deposit, borrow or fee balance
    // The provider skips this reserve because both the user’s supplied and borrowed balances are zero
    // if (vars.compoundedLiquidityBalance == 0 && vars.compoundedBorrowBalance == 0) {
    //            continue;
    //     }
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

    // Checks that calculateUserGlobalData combines a user's position across multiple reserves

    // The third reserve is intentionally empty for this user. It proves the continue logic
    // if (vars.compoundedLiquidityBalance == 0 && vars.compoundedBorrowBalance == 0) {
    //            continue;
    //     }
    // In fact it has liquidityBalance: 0, and borrowBalance: 0,
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

    // It tests that for a deposit to count as collateral, both flags must be true:
    // reserveUsageAsCollateralEnabled && userUsesReserveAsCollateral
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

    // Tests that an undercollateralized borrower is identified as liquidatable.
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

    function _defaultBalanceDecreaseScenario() internal pure returns (ReserveScenario memory) {
        return ReserveScenario({
            decimals: 18,
            baseLtv: 75,
            liquidationThreshold: 80,
            priceInETH: 0.01 ether,
            liquidityBalance: 100 ether,
            borrowBalance: 50 ether,
            originationFee: 0,
            reserveUsageAsCollateralEnabled: true,
            userUsesReserveAsCollateral: true
        });
    }

    function testBalanceDecreaseAllowedReturnsTrueWhenReserveCollateralIsDisabled() external {
        ReserveScenario memory disabledCollateralReserve = _defaultBalanceDecreaseScenario();
        disabledCollateralReserve.borrowBalance = 200 ether;
        disabledCollateralReserve.reserveUsageAsCollateralEnabled = false;
        _setUpReserveScenario(reserve, disabledCollateralReserve);

        uint256 amountToDecrease = 100 ether;
        bool allowed = dataProvider.balanceDecreaseAllowed(reserve, user, amountToDecrease);

        assertTrue(allowed);
    }

    function testBalanceDecreaseAllowedReturnsTrueWhenUserDoesNotUseReserveAsCollateral() external {
        ReserveScenario memory userDisabledCollateralReserve = _defaultBalanceDecreaseScenario();
        userDisabledCollateralReserve.borrowBalance = 200 ether;
        userDisabledCollateralReserve.userUsesReserveAsCollateral = false;
        _setUpReserveScenario(reserve, userDisabledCollateralReserve);

        uint256 amountToDecrease = 100 ether;
        bool allowed = dataProvider.balanceDecreaseAllowed(reserve, user, amountToDecrease);

        assertTrue(allowed);
    }

    function testBalanceDecreaseAllowedReturnsTrueWhenUserHasNoBorrow() external {
        ReserveScenario memory noBorrowReserve = _defaultBalanceDecreaseScenario();
        noBorrowReserve.borrowBalance = 0;
        _setUpReserveScenario(reserve, noBorrowReserve);

        uint256 amountToDecrease = 100 ether;
        bool allowed = dataProvider.balanceDecreaseAllowed(reserve, user, amountToDecrease);

        assertTrue(allowed);
    }

    function testBalanceDecreaseAllowedReturnsFalseWhenCollateralWouldBecomeZeroWithBorrow() external {
        ReserveScenario memory borrowedAgainstCollateralReserve = _defaultBalanceDecreaseScenario();
        _setUpReserveScenario(reserve, borrowedAgainstCollateralReserve);

        uint256 amountToDecrease = 100 ether;
        bool allowed = dataProvider.balanceDecreaseAllowed(reserve, user, amountToDecrease);

        assertFalse(allowed);
    }

    function testBalanceDecreaseAllowedReturnsTrueWhenHealthFactorStaysAboveThreshold() external {
        ReserveScenario memory healthyBorrowingReserve = _defaultBalanceDecreaseScenario();
        _setUpReserveScenario(reserve, healthyBorrowingReserve);

        uint256 amountToDecrease = 10 ether;
        bool allowed = dataProvider.balanceDecreaseAllowed(reserve, user, amountToDecrease);

        // Initial collateral = 100 tokens * 0.01 ETH = 1 ETH.
        // Borrow balance = 50 tokens * 0.01 ETH = 0.5 ETH.
        // Decrease amount = 10 tokens * 0.01 ETH = 0.1 ETH.
        //
        // collateralAfterDecrease = 1 ETH - 0.1 ETH = 0.9 ETH
        // liquidationThresholdAfterDecrease = (1 ETH * 80 - 0.1 ETH * 80) / 0.9 ETH = 80
        // healthFactorAfterDecrease = (0.9 ETH * 80 / 100) / 0.5 ETH = 1.44e18
        //
        // Since 1.44e18 is above the liquidation threshold of 1e18,
        // the balance decrease should be allowed.
        assertTrue(allowed);
    }

    function testBalanceDecreaseAllowedReturnsFalseWhenHealthFactorFallsBelowThreshold() external {
        ReserveScenario memory riskyBorrowingReserve = _defaultBalanceDecreaseScenario();
        _setUpReserveScenario(reserve, riskyBorrowingReserve);

        uint256 amountToDecrease = 40 ether;
        bool allowed = dataProvider.balanceDecreaseAllowed(reserve, user, amountToDecrease);

        // Initial collateral = 100 tokens * 0.01 ETH = 1 ETH.
        // Borrow balance = 50 tokens * 0.01 ETH = 0.5 ETH.
        // Decrease amount = 40 tokens * 0.01 ETH = 0.4 ETH.
        //
        // collateralAfterDecrease = 1 ETH - 0.4 ETH = 0.6 ETH
        // liquidationThresholdAfterDecrease = (1 ETH * 80 - 0.4 ETH * 80) / 0.6 ETH = 80
        // healthFactorAfterDecrease = (0.6 ETH * 80 / 100) / 0.5 ETH = 0.96e18
        //
        // Since 0.96e18 is below the liquidation threshold of 1e18,
        // the balance decrease should not be allowed.
        assertFalse(allowed);
    }

    //////////////////////////////////////////
    //    calculateCollateralNeededInETH     //
    //////////////////////////////////////////

    // Just tests that the calculateCollateralNeededInETH works correctly
    function testCalculateCollateralNeededInETHIncludesNewBorrowFeeAndExistingDebt() external {
        // 1 DAI = 0.0005 ETH and DAI has 18 decimals.
        _setUpReserve(reserve, 18, 75, 80, true, 0.0005 ether);

        uint256 amountToBorrow = 1_000 ether;
        uint256 newBorrowFee = 10 ether;
        uint256 currentBorrowBalanceETH = 0.5 ether;
        uint256 currentFeesETH = 0.05 ether;
        uint256 currentLtv = 75;

        uint256 collateralNeededInETH = dataProvider.calculateCollateralNeededInETH(
            reserve, amountToBorrow, newBorrowFee, currentBorrowBalanceETH, currentFeesETH, currentLtv
        );

        // New debt in ETH = (amountToBorrow + newBorrowFee) * DAI price in ETH
        // New debt in ETH = (1,000 DAI + 10 DAI) * 0.0005 ETH = 0.505 ETH.

        // Total debt in ETH = currentBorrowBalanceETH + currentFeesETH + newDebtInETH
        // Total debt in ETH = 0.5 ETH + 0.05 ETH + 0.505 ETH = 1.055 ETH.

        // Required collateral = Total debt in ETH * 100 / currentLtv
        // Required collateral = 1.055 ETH * 100 / 75 = 1.406666666666666666 ETH.
        assertEq(collateralNeededInETH, 1_406_666_666_666_666_666);
    }

    // Verifies that assets with decimals other than 18 are converted from raw token units to ETH correctly.
    // For example, 2_000_000 units of a 6-decimal asset represent 2 tokens, not 2,000,000 tokens.
    function testCalculateCollateralNeededInETHUsesReserveDecimalsWhenConvertingBorrowToETH() external {
        // A 6-decimal reserve priced at 0.5 ETH per token.
        _setUpReserve(reserve, 6, 80, 85, true, 0.5 ether);

        uint256 currentBorrowBalanceETH = 0;
        uint256 currentFeesETH = 0;

        uint256 amountToBorrow = 2_000_000; // 2 tokens
        uint256 newBorrowFee = 100_000; // 0.1 token

        // This test represents a user with no existing debt (currentBorrowBalanceETH = 0) or fees (currentFeesETH = 0), using collateral with an 80% LTV
        uint256 collateralNeededInETH = dataProvider.calculateCollateralNeededInETH(
            reserve, amountToBorrow, newBorrowFee, currentBorrowBalanceETH, currentFeesETH, 80
        );

        // new debt in ETH = (amountToBorrow + newBorrowFee) * token price in ETH
        // new debt in ETH = 2.1 tokens * 0.5 ETH = 1.05 ETH.

        // Total debt in ETH equals new debt in ETH because  currentBorrowBalanceETH = 0 and currentFeesETH = 0

        // Required collateral = new debt in ETH * 100 / currentLtv
        // Required collateral = 1.05 ETH * 100 / 80 = 1.3125 ETH.
        assertEq(collateralNeededInETH, 1.3125 ether);
    }
}
