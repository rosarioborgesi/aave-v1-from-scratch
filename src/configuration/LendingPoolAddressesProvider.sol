// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {AddressStorage} from "./AddressStorage.sol";

/**
 * @title LendingPoolAddressesProvider contract
 * @notice Is the main registry of the protocol. All the different components of the protocol are accessible
 * through the addresses provider.
 */
contract LendingPoolAddressesProvider is Ownable, AddressStorage {
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////
    ///////////////////////////////////
    //            Libraries          //
    ///////////////////////////////////
    ////////////////////////////////
    //      State Variables       //
    ////////////////////////////////
    bytes32 private constant LENDING_POOL = "LENDING_POOL";
    bytes32 private constant LENDING_POOL_CORE = "LENDING_POOL_CORE";
    bytes32 private constant LENDING_POOL_CONFIGURATOR = "LENDING_POOL_CONFIGURATOR";
    bytes32 private constant DATA_PROVIDER = "DATA_PROVIDER";
    bytes32 private constant PRICE_ORACLE = "PRICE_ORACLE";
    bytes32 private constant FEE_PROVIDER = "FEE_PROVIDER";
    bytes32 private constant LENDING_POOL_PARAMETERS_PROVIDER = "PARAMETERS_PROVIDER";
    bytes32 private constant TOKEN_DISTRIBUTOR = "TOKEN_DISTRIBUTOR";
    bytes32 private constant LENDING_POOL_LIQUIDATION_MANAGER = "LIQUIDATION_MANAGER";

    ////////////////////////////////
    //           Events           //
    ////////////////////////////////
    event LendingPoolUpdated(address indexed newAddress);
    event LendingPoolCoreUpdated(address indexed newAddress);
    event LendingPoolConfiguratorUpdated(address indexed newAddress);
    event LendingPoolDataProviderUpdated(address indexed newAddress);
    event PriceOracleUpdated(address indexed newAddress);
    event FeeProviderUpdated(address indexed newAddress);
    event LendingPoolParametersProviderUpdated(address indexed newAddress);
    event TokenDistributorUpdated(address indexed newAddress);
    event LendingPoolLiquidationManagerUpdated(address indexed newAddress);

    ////////////////////////////////
    //          Modifiers         //
    ////////////////////////////////
    ////////////////////////////////
    //          Functions         //
    ////////////////////////////////
    constructor(address _owner) Ownable(_owner) {}

    ////////////////////////////////
    //     External Functions     //
    ////////////////////////////////
    function setLendingPool(address _pool) external onlyOwner {
        _setAddress(LENDING_POOL, _pool);
        emit LendingPoolUpdated(_pool);
    }

    function setLendingPoolCore(address _lendingPoolCore) external onlyOwner {
        _setAddress(LENDING_POOL_CORE, _lendingPoolCore);
        emit LendingPoolCoreUpdated(_lendingPoolCore);
    }

    function setLendingPoolConfigurator(address _configurator) external onlyOwner {
        _setAddress(LENDING_POOL_CONFIGURATOR, _configurator);
        emit LendingPoolConfiguratorUpdated(_configurator);
    }

    function setLendingPoolDataProvider(address _provider) external onlyOwner {
        _setAddress(DATA_PROVIDER, _provider);
        emit LendingPoolDataProviderUpdated(_provider);
    }

    function setPriceOracle(address _priceOracle) external onlyOwner {
        _setAddress(PRICE_ORACLE, _priceOracle);
        emit PriceOracleUpdated(_priceOracle);
    }

    function setFeeProvider(address _feeProvider) external onlyOwner {
        _setAddress(FEE_PROVIDER, _feeProvider);
        emit FeeProviderUpdated(_feeProvider);
    }

    function setLendingPoolParametersProvider(address _parametersProvider) external onlyOwner {
        _setAddress(LENDING_POOL_PARAMETERS_PROVIDER, _parametersProvider);
        emit LendingPoolParametersProviderUpdated(_parametersProvider);
    }

    function setTokenDistributor(address _tokenDistributor) external onlyOwner {
        _setAddress(TOKEN_DISTRIBUTOR, _tokenDistributor);
        emit TokenDistributorUpdated(_tokenDistributor);
    }

    function setLendingPoolLiquidationManager(address _manager) external onlyOwner {
        _setAddress(LENDING_POOL_LIQUIDATION_MANAGER, _manager);
        emit LendingPoolLiquidationManagerUpdated(_manager);
    }

    ////////////////////////////////
    //       Public Functions     //
    ////////////////////////////////
    /////////////////////////////////
    //       Private Functions     //
    /////////////////////////////////
    //////////////////////////////////////////////////////
    //     Private & Internal View & Pure Functions     //
    //////////////////////////////////////////////////////
    //////////////////////////////////////////////////////
    //      External & Public View & Pure Functions     //
    //////////////////////////////////////////////////////
    function getLendingPool() external view returns (address) {
        return getAddress(LENDING_POOL);
    }

    function getLendingPoolCore() external view returns (address) {
        return getAddress(LENDING_POOL_CORE);
    }

    function getLendingPoolConfigurator() public view returns (address) {
        return getAddress(LENDING_POOL_CONFIGURATOR);
    }

    function getLendingPoolDataProvider() external view returns (address) {
        return getAddress(DATA_PROVIDER);
    }

    function getPriceOracle() external view returns (address) {
        return getAddress(PRICE_ORACLE);
    }

    function getFeeProvider() external view returns (address) {
        return getAddress(FEE_PROVIDER);
    }

    function getLendingPoolParametersProvider() external view returns (address) {
        return getAddress(LENDING_POOL_PARAMETERS_PROVIDER);
    }

    function getTokenDistributor() external view returns (address) {
        return getAddress(TOKEN_DISTRIBUTOR);
    }

    function getLendingPoolLiquidationManager() external view returns (address) {
        return getAddress(LENDING_POOL_LIQUIDATION_MANAGER);
    }
}
