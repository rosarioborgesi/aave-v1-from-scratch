// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IPriceOracleGetter
 * @notice Interface for retrieving reserve asset prices.
 */
interface IPriceOracleGetter {
    /**
     * @notice Returns the price of an asset denominated in ETH.
     * @param _asset The address of the asset.
     * @return The asset price in ETH.
     */
    function getAssetPrice(address _asset) external view returns (uint256);
}
