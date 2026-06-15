// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {WadRayMath} from "../../src/libraries/WadRayMath.sol";

contract WadRayMathHarness {
    function ray() external pure returns (uint256) {
        return WadRayMath.ray();
    }

    function wad() external pure returns (uint256) {
        return WadRayMath.wad();
    }

    function halfRay() external pure returns (uint256) {
        return WadRayMath.halfRay();
    }

    function halfWad() external pure returns (uint256) {
        return WadRayMath.halfWad();
    }

    function wadMul(uint256 a, uint256 b) external pure returns (uint256) {
        return WadRayMath.wadMul(a, b);
    }

    function wadDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return WadRayMath.wadDiv(a, b);
    }

    function rayMul(uint256 a, uint256 b) external pure returns (uint256) {
        return WadRayMath.rayMul(a, b);
    }

    function rayDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return WadRayMath.rayDiv(a, b);
    }

    function rayToWad(uint256 a) external pure returns (uint256) {
        return WadRayMath.rayToWad(a);
    }

    function wadToRay(uint256 a) external pure returns (uint256) {
        return WadRayMath.wadToRay(a);
    }

    function rayPow(uint256 x, uint256 n) external pure returns (uint256) {
        return WadRayMath.rayPow(x, n);
    }
}

contract WadRayMathTest is Test {
    WadRayMathHarness internal math;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = WAD / 2;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = RAY / 2;

    uint256 internal constant WAD_RAY_RATIO = 1e9;

    function setUp() public {
        math = new WadRayMathHarness();
    }

    function testConstants() public view {
        assertEq(math.wad(), WAD);
        assertEq(math.ray(), RAY);
        assertEq(math.halfWad(), HALF_WAD);
        assertEq(math.halfRay(), HALF_RAY);
    }

    function testWadMul() public view {
        // 2 * 3 = 6
        // (2e18 * 3e18 + 0.5e18) / 1e18 = 6e18
        assertEq(math.wadMul(2e18, 3e18), 6e18);

        // 1.5 * 2 = 3
        // (1.5e18 * 2e18 + 0.5e18) / 1e18 = 3e18
        assertEq(math.wadMul(15e17, 2e18), 3e18);
    }

    function testWadMulReturnsZeroIfAnyInputIsZero() public view {
        // 0 * max = 0
        assertEq(math.wadMul(0, type(uint256).max), 0);

        // max * 0 = 0
        assertEq(math.wadMul(type(uint256).max, 0), 0);
    }

    function testWadMulRoundsHalfUp() public view {
        // (1 * (0.5e18 - 1) + 0.5e18) / 1e18 = 0
        assertEq(math.wadMul(1, HALF_WAD - 1), 0);

        // (1 * 0.5e18 + 0.5e18) / 1e18 = 1
        assertEq(math.wadMul(1, HALF_WAD), 1);
    }

    function testWadDiv() public view {
        // 3 / 2 = 1.5
        // (3e18 * 1e18 + 1e18) / 2e18 = 1.5e18
        assertEq(math.wadDiv(3e18, 2e18), 15e17);
    }

    function testWadDivRevertsIfDivisionByZero() public {
        // Division by zero must revert
        vm.expectRevert(WadRayMath.WadRayMath__DivisionByZero.selector);
        math.wadDiv(WAD, 0);
    }

    function testRayMul() public view {
        // 2 * 3 = 6
        // (2e27 * 3e27 + 0.5e27) / 1e27 = 6e27
        assertEq(math.rayMul(2e27, 3e27), 6e27);
    }

    function testRayMulReturnsZeroIfAnyInputIsZero() public view {
        // 0 * max = 0
        assertEq(math.rayMul(0, type(uint256).max), 0);

        // max * 0 = 0
        assertEq(math.rayMul(type(uint256).max, 0), 0);
    }

    function testRayMulRoundsHalfUp() public view {
        // (1 * (0.5e27 - 1) + 0.5e27) / 1e27 = 0
        assertEq(math.rayMul(1, HALF_RAY - 1), 0);

        // (1 * 0.5e27 + 0.5e27) / 1e27 = 1
        assertEq(math.rayMul(1, HALF_RAY), 1);
    }

    function testRayDiv() public view {
        // 3 / 2 = 1.5
        // (3e27 * 1e27 + 1e27) / 2e27 = 1.5e27
        assertEq(math.rayDiv(3e27, 2e27), 15e26);
    }

    function testRayDivRevertsIfDivisionByZero() public {
        // Division by zero must revert
        vm.expectRevert(WadRayMath.WadRayMath__DivisionByZero.selector);
        math.rayDiv(RAY, 0);
    }

    function testWadToRay() public view {
        // 1 wad = 1 ray
        // 1e18 * 1e9 = 1e27
        assertEq(math.wadToRay(1e18), 1e27);

        // 5 wad = 5 ray
        // 5e18 * 1e9 = 5e27
        assertEq(math.wadToRay(5e18), 5e27);
    }

    function testRayToWad() public view {
        // 1 ray = 1 wad
        // (1e27 + 0.5e9) / 1e9 = 1e18
        assertEq(math.rayToWad(1e27), 1e18);

        // 5 ray = 5 wad
        // (5e27 + 0.5e9) / 1e9 = 5e18
        assertEq(math.rayToWad(5e27), 5e18);
    }

    function testRayPowWithZeroExponentReturnsRay() public view {
        // 5^0 = 1
        // In ray math, 1 = 1e27
        assertEq(math.rayPow(5 * RAY, 0), RAY);
    }

    function testRayPowWithRayBaseReturnsRay() public view {
        // 1^100 = 1
        // In ray math, 1 = 1e27
        assertEq(math.rayPow(RAY, 100), RAY);
    }

    function testRayPow() public view {
        // 2^3 = 8
        // In ray math: (2e27)^3 = 8e27
        assertEq(math.rayPow(2 * RAY, 3), 8 * RAY);
    }
}
