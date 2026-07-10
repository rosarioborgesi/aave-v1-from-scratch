// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract MockPriceOracle {
    mapping(address asset => uint256 price) private s_prices;

    function setAssetPrice(address asset, uint256 price) external {
        s_prices[asset] = price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return s_prices[asset];
    }
}
