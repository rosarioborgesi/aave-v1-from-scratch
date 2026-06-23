// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IReserveInterestRateStrategy} from "src/interfaces/IReserveInterestRateStrategy.sol";

contract MockReserveInterestRateStrategy is IReserveInterestRateStrategy {
    uint256 private s_liquidityRate;
    uint256 private s_stableBorrowRate;
    uint256 private s_variableBorrowRate;

    function setRates(uint256 _liquidityRate, uint256 _stableBorrowRate, uint256 _variableBorrowRate) external {
        s_liquidityRate = _liquidityRate;
        s_stableBorrowRate = _stableBorrowRate;
        s_variableBorrowRate = _variableBorrowRate;
    }

    function getBaseVariableBorrowRate() external view override returns (uint256) {
        return 0;
    }

    function calculateInterestRates(address, uint256, uint256, uint256, uint256)
        external
        view
        returns (uint256 liquidityRate, uint256 stableBorrowRate, uint256 variableBorrowRate)
    {
        return (s_liquidityRate, s_stableBorrowRate, s_variableBorrowRate);
    }
}
