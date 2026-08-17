// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract MockLendingPoolDataProvider {
    bool private s_balanceDecreaseAllowed;

    function setBalanceDecreaseAllowed(bool allowed) external {
        s_balanceDecreaseAllowed = allowed;
    }

    function balanceDecreaseAllowed(address, address, uint256) external view returns (bool) {
        return s_balanceDecreaseAllowed;
    }
}
