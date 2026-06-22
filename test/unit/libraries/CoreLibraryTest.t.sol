// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {CoreLibrary} from "src/libraries/CoreLibrary.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";

contract CoreLibraryHarness {
    using CoreLibrary for CoreLibrary.ReserveData;

    CoreLibrary.ReserveData internal reserve;

    function setReserveData(
        uint256 _currentLiquidityRate,
        uint40 _lastUpdateTimestamp,
        uint256 _lastLiquidityCumulativeIndex
    ) external {
        reserve.currentLiquidityRate = _currentLiquidityRate;
        reserve.lastUpdateTimestamp = _lastUpdateTimestamp;
        reserve.lastLiquidityCumulativeIndex = _lastLiquidityCumulativeIndex;
    }

    function calculateLinearInterest(uint256 _rate, uint40 _lastUpdateTimestamp) external view returns (uint256) {
        return CoreLibrary.calculateLinearInterest(_rate, _lastUpdateTimestamp);
    }

    function getNormalizedIncome() external view returns (uint256) {
        return reserve.getNormalizedIncome();
    }
}

contract CoreLibraryTest is Test {
    uint256 private constant RAY = 1e27;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    CoreLibraryHarness private harness;

    function setUp() external {
        harness = new CoreLibraryHarness();
    }

    ////////////////////////////////////
    //    calculateLinearInterest     //
    ////////////////////////////////////
    function testCalculateLinearInterestReturnsOneRayIfNoTimePassed() external {
        uint256 rate = 5e25; // 5% expressed in ray
        uint40 lastUpdateTimestamp = uint40(block.timestamp);

        uint256 linearInterest = harness.calculateLinearInterest(rate, lastUpdateTimestamp);

        assertEq(linearInterest, RAY);
    }

    function testCalculateLinearInterestAfterOneYearAtFivePercent() external {
        uint256 rate = 5e25; // 5% expressed in ray
        uint40 lastUpdateTimestamp = uint40(block.timestamp);

        vm.warp(block.timestamp + SECONDS_PER_YEAR);

        uint256 linearInterest = harness.calculateLinearInterest(rate, lastUpdateTimestamp);

        // 1 + 5% = 1.05 ray
        assertEq(linearInterest, 105e25);
    }

    function testCalculateLinearInterestAfterHalfYearAtFivePercent() external {
        uint256 rate = 5e25; // 5% expressed in ray
        uint40 lastUpdateTimestamp = uint40(block.timestamp);

        vm.warp(block.timestamp + SECONDS_PER_YEAR / 2);

        uint256 linearInterest = harness.calculateLinearInterest(rate, lastUpdateTimestamp);

        // 1 + 2.5% = 1.025 ray
        assertEq(linearInterest, 1025e24);
    }

    ////////////////////////////////
    //    getNormalizedIncome     //
    ////////////////////////////////
    function testGetNormalizedIncomeReturnsPreviousIndexIfNoTimePassed() external {
        uint256 rate = 5e25; // 5%
        uint40 lastUpdateTimestamp = uint40(block.timestamp);
        uint256 lastLiquidityCumulativeIndex = RAY;

        harness.setReserveData(rate, lastUpdateTimestamp, lastLiquidityCumulativeIndex);

        uint256 normalizedIncome = harness.getNormalizedIncome();

        assertEq(normalizedIncome, RAY);
    }

    function testGetNormalizedIncomeAfterOneYearAtFivePercent() external {
        uint256 rate = 5e25; // 5%
        uint40 lastUpdateTimestamp = uint40(block.timestamp);
        uint256 lastLiquidityCumulativeIndex = RAY;

        harness.setReserveData(rate, lastUpdateTimestamp, lastLiquidityCumulativeIndex);

        vm.warp(block.timestamp + SECONDS_PER_YEAR);

        uint256 normalizedIncome = harness.getNormalizedIncome();

        // normalizedIncome = 1.05 * 1.00 = 1.05 ray
        assertEq(normalizedIncome, 105e25);
    }

    function testGetNormalizedIncomeUsesPreviousLiquidityIndex() external {
        uint256 rate = 5e25; // 5%
        uint40 lastUpdateTimestamp = uint40(block.timestamp);

        // Previous index already grew to 1.10
        uint256 lastLiquidityCumulativeIndex = 11e26; // 1.10 ray

        harness.setReserveData(rate, lastUpdateTimestamp, lastLiquidityCumulativeIndex);

        vm.warp(block.timestamp + SECONDS_PER_YEAR);

        uint256 normalizedIncome = harness.getNormalizedIncome();

        // normalizedIncome = 1.05 * 1.10 = 1.155 ray
        assertEq(normalizedIncome, 1155e24);
    }


    
}
