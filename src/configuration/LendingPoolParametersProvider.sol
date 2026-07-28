// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title LendingPoolParametersProvider
 * @notice stores the configuration parameters of the Lending Pool contract
 */
contract LendingPoolParametersProvider {
    uint256 private constant MAX_STABLE_RATE_BORROW_SIZE_PERCENT = 25;
    uint256 private constant REBALANCE_DOWN_RATE_DELTA = 1e27 / 5;
    uint256 private constant FLASHLOAN_FEE_TOTAL = 35;
    uint256 private constant FLASHLOAN_FEE_PROTOCOL = 3000;

    function getMaxStableRateBorrowSizePercent() external pure returns (uint256) {
        return MAX_STABLE_RATE_BORROW_SIZE_PERCENT;
    }

    function getRebalanceDownRateDelta() external pure returns (uint256) {
        return REBALANCE_DOWN_RATE_DELTA;
    }

    function getFlashLoanFeesInBips() external pure returns (uint256 totalFee, uint256 protocolFee) {
        return (FLASHLOAN_FEE_TOTAL, FLASHLOAN_FEE_PROTOCOL);
    }
}
