// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";

contract LendingPoolAddressesProviderUnitTest is Test {
    address private owner = makeAddr("owner");
    address private attacker = makeAddr("attacker");
    address private lendingPool = makeAddr("lendingPool");
    address private lendingPoolCore = makeAddr("lendingPoolCore");
    address private lendingPoolConfigurator = makeAddr("lendingPoolConfigurator");
    address private lendingPoolDataProvider = makeAddr("lendingPoolDataProvider");
    address private priceOracle = makeAddr("priceOracle");

    LendingPoolAddressesProvider private addressesProvider;

    function setUp() external {
        addressesProvider = new LendingPoolAddressesProvider(owner);
    }

    ////////////////////////////////
    //          constructor       //
    ////////////////////////////////
    function testConstructorSetsOwner() external view {
        assertEq(addressesProvider.owner(), owner);
    }

    function testConstructorRevertsWhenOwnerIsZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));

        new LendingPoolAddressesProvider(address(0));
    }

    ////////////////////////////////
    //        setLendingPool      //
    ////////////////////////////////
    function testSetLendingPoolStoresAddressAndEmitsEvent() external {
        vm.expectEmit(true, false, false, true, address(addressesProvider));
        emit LendingPoolAddressesProvider.LendingPoolUpdated(lendingPool);

        vm.prank(owner);
        addressesProvider.setLendingPool(lendingPool);

        assertEq(addressesProvider.getLendingPool(), lendingPool);
    }

    function testSetLendingPoolRevertsWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));

        vm.prank(attacker);
        addressesProvider.setLendingPool(lendingPool);
    }

    function testSetLendingPoolRevertsWhenAddressIsZero() external {
        vm.expectRevert(LendingPoolAddressesProvider.LendingPoolAddressesProvider__ZeroAddress.selector);

        vm.prank(owner);
        addressesProvider.setLendingPool(address(0));
    }

    ////////////////////////////////
    //      setLendingPoolCore    //
    ////////////////////////////////
    function testSetLendingPoolCoreStoresAddressAndEmitsEvent() external {
        vm.expectEmit(true, false, false, true, address(addressesProvider));
        emit LendingPoolAddressesProvider.LendingPoolCoreUpdated(lendingPoolCore);

        vm.prank(owner);
        addressesProvider.setLendingPoolCore(lendingPoolCore);

        assertEq(addressesProvider.getLendingPoolCore(), lendingPoolCore);
    }

    function testSetLendingPoolCoreRevertsWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));

        vm.prank(attacker);
        addressesProvider.setLendingPoolCore(lendingPoolCore);
    }

    function testSetLendingPoolCoreRevertsWhenAddressIsZero() external {
        vm.expectRevert(LendingPoolAddressesProvider.LendingPoolAddressesProvider__ZeroAddress.selector);

        vm.prank(owner);
        addressesProvider.setLendingPoolCore(address(0));
    }

    /////////////////////////////////////////
    //    setLendingPoolConfigurator       //
    /////////////////////////////////////////
    function testSetLendingPoolConfiguratorStoresAddressAndEmitsEvent() external {
        vm.expectEmit(true, false, false, true, address(addressesProvider));
        emit LendingPoolAddressesProvider.LendingPoolConfiguratorUpdated(lendingPoolConfigurator);

        vm.prank(owner);
        addressesProvider.setLendingPoolConfigurator(lendingPoolConfigurator);

        assertEq(addressesProvider.getLendingPoolConfigurator(), lendingPoolConfigurator);
    }

    function testSetLendingPoolConfiguratorRevertsWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));

        vm.prank(attacker);
        addressesProvider.setLendingPoolConfigurator(lendingPoolConfigurator);
    }

    function testSetLendingPoolConfiguratorRevertsWhenAddressIsZero() external {
        vm.expectRevert(LendingPoolAddressesProvider.LendingPoolAddressesProvider__ZeroAddress.selector);

        vm.prank(owner);
        addressesProvider.setLendingPoolConfigurator(address(0));
    }

    ///////////////////////////////////////
    //    setLendingPoolDataProvider     //
    ///////////////////////////////////////
    function testSetLendingPoolDataProviderStoresAddressAndEmitsEvent() external {
        vm.expectEmit(true, false, false, true, address(addressesProvider));
        emit LendingPoolAddressesProvider.LendingPoolDataProviderUpdated(lendingPoolDataProvider);

        vm.prank(owner);
        addressesProvider.setLendingPoolDataProvider(lendingPoolDataProvider);

        assertEq(addressesProvider.getLendingPoolDataProvider(), lendingPoolDataProvider);
    }

    function testSetLendingPoolDataProviderRevertsWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));

        vm.prank(attacker);
        addressesProvider.setLendingPoolDataProvider(lendingPoolDataProvider);
    }

    function testSetLendingPoolDataProviderRevertsWhenAddressIsZero() external {
        vm.expectRevert(LendingPoolAddressesProvider.LendingPoolAddressesProvider__ZeroAddress.selector);

        vm.prank(owner);
        addressesProvider.setLendingPoolDataProvider(address(0));
    }

    ////////////////////////////////
    //        setPriceOracle      //
    ////////////////////////////////
    function testSetPriceOracleStoresAddressAndEmitsEvent() external {
        vm.expectEmit(true, false, false, true, address(addressesProvider));
        emit LendingPoolAddressesProvider.PriceOracleUpdated(priceOracle);

        vm.prank(owner);
        addressesProvider.setPriceOracle(priceOracle);

        assertEq(addressesProvider.getPriceOracle(), priceOracle);
    }

    function testSetPriceOracleRevertsWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));

        vm.prank(attacker);
        addressesProvider.setPriceOracle(priceOracle);
    }

    function testSetPriceOracleRevertsWhenAddressIsZero() external {
        vm.expectRevert(LendingPoolAddressesProvider.LendingPoolAddressesProvider__ZeroAddress.selector);

        vm.prank(owner);
        addressesProvider.setPriceOracle(address(0));
    }

    ////////////////////////////////
    //          getAddress        //
    ////////////////////////////////
    function testGetAddressReturnsZeroForUnknownKey() external view {
        assertEq(addressesProvider.getAddress("UNKNOWN_KEY"), address(0));
    }
}
