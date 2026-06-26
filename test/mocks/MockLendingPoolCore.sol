// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract MockLendingPoolCore {
    uint256 private s_normalizedIncome;

    function setNormalizedIncome(uint256 normalizedIncome) external {
        s_normalizedIncome = normalizedIncome;
    }

    function getReserveNormalizedIncome(address) external view returns (uint256) {
        return s_normalizedIncome;
    }
}
