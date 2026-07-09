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
    error LendingPoolAddressesProvider__ZeroAddress();
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

    ////////////////////////////////
    //           Events           //
    ////////////////////////////////
    event LendingPoolUpdated(address indexed newAddress);
    event LendingPoolCoreUpdated(address indexed newAddress);
    event LendingPoolConfiguratorUpdated(address indexed newAddress);
    event LendingPoolDataProviderUpdated(address indexed newAddress);
    event PriceOracleUpdated(address indexed newAddress);

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
        if (_pool == address(0)) {
            revert LendingPoolAddressesProvider__ZeroAddress();
        }
        _setAddress(LENDING_POOL, _pool);
        emit LendingPoolUpdated(_pool);
    }

    function setLendingPoolCore(address _lendingPoolCore) external onlyOwner {
        if (_lendingPoolCore == address(0)) {
            revert LendingPoolAddressesProvider__ZeroAddress();
        }
        _setAddress(LENDING_POOL_CORE, _lendingPoolCore);
        emit LendingPoolCoreUpdated(_lendingPoolCore);
    }

    function setLendingPoolConfigurator(address _configurator) external onlyOwner {
        if (_configurator == address(0)) {
            revert LendingPoolAddressesProvider__ZeroAddress();
        }
        _setAddress(LENDING_POOL_CONFIGURATOR, _configurator);
        emit LendingPoolConfiguratorUpdated(_configurator);
    }

    function setLendingPoolDataProvider(address _provider) external onlyOwner {
        if (_provider == address(0)) {
            revert LendingPoolAddressesProvider__ZeroAddress();
        }
        _setAddress(DATA_PROVIDER, _provider);
        emit LendingPoolDataProviderUpdated(_provider);
    }

    function setPriceOracle(address _priceOracle) external onlyOwner {
        if (_priceOracle == address(0)) {
            revert LendingPoolAddressesProvider__ZeroAddress();
        }
        _setAddress(PRICE_ORACLE, _priceOracle);
        emit PriceOracleUpdated(_priceOracle);
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
}
