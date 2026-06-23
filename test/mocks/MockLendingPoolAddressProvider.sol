// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract MockLendingPoolAddressProvider {
    error MockLendingPoolAddressProvider__AddressIsZero();

    address private i_lendingPool;
    address private i_lendingPoolConfigurator;

    constructor(address _lendingPool, address _lendingPoolConfigurator) {
        if (_lendingPool == address(0)) {
            revert MockLendingPoolAddressProvider__AddressIsZero();
        }
        if (_lendingPoolConfigurator == address(0)) {
            revert MockLendingPoolAddressProvider__AddressIsZero();
        }
        i_lendingPool = _lendingPool;
        i_lendingPoolConfigurator = _lendingPoolConfigurator;
    }

    function getLendingPool() external view returns (address) {
        return i_lendingPool;
    }

    function getLendingPoolConfigurator() external view returns (address) {
        return i_lendingPoolConfigurator;
    }
}
