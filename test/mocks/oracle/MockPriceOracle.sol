// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    mapping(address asset => uint256 price) private s_prices;
    uint256 private s_ethPriceUsd;

    event AssetPriceUpdated(address _asset, uint256 _price, uint256 timestamp);
    event EthPriceUpdated(uint256 _price, uint256 timestamp);

    function getAssetPrice(address _asset) external view returns (uint256) {
        return s_prices[_asset];
    }

    function setAssetPrice(address _asset, uint256 _price) external {
        s_prices[_asset] = _price;
        emit AssetPriceUpdated(_asset, _price, block.timestamp);
    }

    function getEthUsdPrice() external view returns (uint256) {
        return s_ethPriceUsd;
    }

    function setEthUsdPrice(uint256 _price) external {
        s_ethPriceUsd = _price;
        emit EthPriceUpdated(_price, block.timestamp);
    }
}
