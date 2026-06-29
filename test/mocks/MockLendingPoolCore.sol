// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract MockLendingPoolCore {
    mapping(address reserve => uint256 normalizedIncome) private s_reserveNormalizedIncome;

    function setReserveNormalizedIncome(address reserve, uint256 normalizedIncome) external {
        s_reserveNormalizedIncome[reserve] = normalizedIncome;
    }

    function getReserveNormalizedIncome(address reserve) external view returns (uint256) {
        return s_reserveNormalizedIncome[reserve];
    }
}
