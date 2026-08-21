// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IFeeProvider} from "src/interfaces/IFeeProvider.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";

contract FeeProvider is IFeeProvider {
    using WadRayMath for uint256;

    uint256 private constant LOAN_ORIGINATION_FEE_PERCENTAGE = 0.0025 ether;

    function calculateLoanOriginationFee(address, uint256 amount) external pure returns (uint256) {
        return amount.wadMul(LOAN_ORIGINATION_FEE_PERCENTAGE);
    }

    function getLoanOriginationFeePercentage() external pure returns (uint256) {
        return LOAN_ORIGINATION_FEE_PERCENTAGE;
    }
}
