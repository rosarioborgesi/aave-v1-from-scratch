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

    function ray() internal pure returns (uint256) {
        return RAY;
    }

    function wad() internal pure returns (uint256) {
        return WAD;
    }

    function halfRay() internal pure returns (uint256) {
        return HALF_RAY;
    }

    function halfWad() internal pure returns (uint256) {
        return HALF_WAD;
    }

    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        return (a * b + HALF_WAD) / WAD;
    }

    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            revert WadRayMath__DivisionByZero();
        }

        return (a * WAD + b / 2) / b;
    }

    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }

        return (a * b + HALF_RAY) / RAY;
    }

    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            revert WadRayMath__DivisionByZero();
        }

        return (a * RAY + b / 2) / b;
    }

    function rayToWad(uint256 a) internal pure returns (uint256) {
        return (a + WAD_RAY_RATIO / 2) / WAD_RAY_RATIO;
    }

    function wadToRay(uint256 a) internal pure returns (uint256) {
        return a * WAD_RAY_RATIO;
    }

    /**
     * @dev calculates base^exp. The code uses the ModExp precompile
     * @return z Returns base^exp, in ray
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
