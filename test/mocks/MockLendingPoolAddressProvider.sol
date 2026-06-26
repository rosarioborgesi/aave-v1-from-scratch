// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract MockLendingPoolAddressProvider {
    error MockLendingPoolAddressProvider__AddressIsZero();

    address private i_lendingPool;
    address private i_lendingPoolCore;
    address private i_lendingPoolConfigurator;

    constructor(address _lendingPool, address _lendingPoolConfigurator) {
        if (_lendingPool == address(0) || _lendingPoolConfigurator == address(0)) {
            revert MockLendingPoolAddressProvider__AddressIsZero();
        }
        i_lendingPool = _lendingPool;
        i_lendingPoolConfigurator = _lendingPoolConfigurator;
    }

    function setLendingPoolCore(address _lendingPoolCore) external {
        if (_lendingPoolCore == address(0)) {
            revert MockLendingPoolAddressProvider__AddressIsZero();
        }
        i_lendingPoolCore = _lendingPoolCore;
    }

    function getLendingPool() external view returns (address) {
        return i_lendingPool;
    }

    function getLendingPoolCore() external view returns (address) {
        return i_lendingPoolCore;
    }

    function getLendingPoolConfigurator() external view returns (address) {
        return i_lendingPoolConfigurator;
    }
}
