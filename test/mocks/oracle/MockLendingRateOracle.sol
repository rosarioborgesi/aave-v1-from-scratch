// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ILendingRateOracle} from "src/interfaces/ILendingRateOracle.sol";

contract MockLendingRateOracle is ILendingRateOracle {
    mapping(address => uint256) s_borrowRates;
    mapping(address => uint256) s_liquidityRates;

    function getMarketBorrowRate(address _asset) external view returns (uint256) {
        return s_borrowRates[_asset];
    }

    function setMarketBorrowRate(address _asset, uint256 _rate) external {
        s_borrowRates[_asset] = _rate;
    }

    function getMarketLiquidityRate(address _asset) external view returns (uint256) {
        return s_liquidityRates[_asset];
    }

    function setMarketLiquidityRate(address _asset, uint256 _rate) external {
        s_liquidityRates[_asset] = _rate;
    }
}
