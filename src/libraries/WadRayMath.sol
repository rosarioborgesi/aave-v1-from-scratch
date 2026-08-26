// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

library WadRayMath {
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////
    error WadRayMath__DivisionByZero();

    ////////////////////////////////
    //        State Variables     //
    ////////////////////////////////
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = WAD / 2;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = RAY / 2;

    uint256 internal constant WAD_RAY_RATIO = 1e9;

    ////////////////////////////////
    //      Internal Functions    //
    ////////////////////////////////

    /**
     * @dev Returns one ray, the unit for 27-decimal fixed-point numbers.
     * @return One ray (1e27).
     */
    function ray() internal pure returns (uint256) {
        return RAY;
    }

    /**
     * @dev Returns one wad, the unit for 18-decimal fixed-point numbers.
     * @return One wad (1e18).
     */
    function wad() internal pure returns (uint256) {
        return WAD;
    }

    /**
     * @dev Returns half a ray.
     * @return Half a ray (0.5e27).
     */
    function halfRay() internal pure returns (uint256) {
        return HALF_RAY;
    }

    /**
     * @dev Returns half a wad.
     * @return Half a wad (0.5e18).
     */
    function halfWad() internal pure returns (uint256) {
        return HALF_WAD;
    }

    /**
     * @dev Multiplies two wad values, rounding half up.
     * @param a The first wad value.
     * @param b The second wad value.
     * @return The product of a and b, expressed in wad.
     */
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        return (a * b + HALF_WAD) / WAD;
    }

    /**
     * @dev Divides two wad values, rounding half up.
     * @param a The dividend, expressed in wad.
     * @param b The divisor, expressed in wad.
     * @return The quotient of a and b, expressed in wad.
     */
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            revert WadRayMath__DivisionByZero();
        }

        return (a * WAD + b / 2) / b;
    }

    /**
     * @dev Multiplies two ray values, rounding half up.
     * @param a The first ray value.
     * @param b The second ray value.
     * @return The product of a and b, expressed in ray.
     */
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        return (a * b + HALF_RAY) / RAY;
    }

    /**
     * @dev Divides two ray values, rounding half up.
     * @param a The dividend, expressed in ray.
     * @param b The divisor, expressed in ray.
     * @return The quotient of a and b, expressed in ray.
     */
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            revert WadRayMath__DivisionByZero();
        }

        return (a * RAY + b / 2) / b;
    }

    /**
     * @dev Converts a ray value to wad, rounding half up.
     * @param a The value to convert, expressed in ray.
     * @return The converted value, expressed in wad.
     */
    function rayToWad(uint256 a) internal pure returns (uint256) {
        return (a + WAD_RAY_RATIO / 2) / WAD_RAY_RATIO;
    }

    /**
     * @dev Converts a wad value to ray.
     * @param a The value to convert, expressed in wad.
     * @return The converted value, expressed in ray.
     */
    function wadToRay(uint256 a) internal pure returns (uint256) {
        return a * WAD_RAY_RATIO;
    }

    /**
     * @dev Raises a ray value to an integer power using exponentiation by squaring.
     * @param x The base, expressed in ray.
     * @param n The exponent.
     * @return z The result of x raised to the power of n, expressed in ray.
     */
    function rayPow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? x : RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = rayMul(x, x);

            if (n % 2 != 0) {
                z = rayMul(z, x);
            }
        }
    }
}
