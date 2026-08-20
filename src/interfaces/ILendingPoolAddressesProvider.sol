// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ILendingPoolAddressesProvider
 * @notice Interface for the protocol's central address registry.
 */
interface ILendingPoolAddressesProvider {
    ////////////////////////////////
    //     External Functions     //
    ////////////////////////////////
    function setLendingPoolImpl(address _pool) external;

    function setLendingPoolCoreImpl(address _lendingPoolCore) external;

    function setLendingPoolConfiguratorImpl(address _configurator) external;

    function setLendingPoolDataProviderImpl(address _provider) external;

    function setLendingPoolParametersProviderImpl(address _parametersProvider) external;

    function setTokenDistributor(address _tokenDistributor) external;

    function setFeeProviderImpl(address _feeProvider) external;

    function setLendingPoolLiquidationManager(address _manager) external;

    function setLendingPoolManager(address _lendingPoolManager) external;

    function setPriceOracle(address _priceOracle) external;

    function setLendingRateOracle(address _lendingRateOracle) external;

    //////////////////////////////////////////////////////
    //      External & external View & Pure Functions     //
    //////////////////////////////////////////////////////
    function getLendingPool() external view returns (address);

    function getLendingPoolCore() external view returns (address payable);

    function getLendingPoolConfigurator() external view returns (address);

    function getLendingPoolDataProvider() external view returns (address);

    function getLendingPoolParametersProvider() external view returns (address);

    function getTokenDistributor() external view returns (address);

    function getFeeProvider() external view returns (address);

    function getLendingPoolLiquidationManager() external view returns (address);

    function getLendingPoolManager() external view returns (address);

    function getPriceOracle() external view returns (address);

    function getLendingRateOracle() external view returns (address);
}
