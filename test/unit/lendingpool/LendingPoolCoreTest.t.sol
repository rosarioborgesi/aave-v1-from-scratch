// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockLendingPoolAddressProvider} from "../../mocks/MockLendingPoolAddressProvider.sol";
import {MockReserveInterestRateStrategy} from "../../mocks/MockReserveInterestRateStrategy.sol";

import {LendingPoolCore} from "src/lendingpool/LendingPoolCore.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {CoreLibrary} from "src/libraries/CoreLibrary.sol";
import {IReserveInterestRateStrategy} from "src/interfaces/IReserveInterestRateStrategy.sol";
import {EthAddressLib} from "src/libraries/EthAddressLib.sol";

contract LendingPoolCoreHarness is LendingPoolCore {
    constructor(address _addressesProvider) LendingPoolCore(_addressesProvider) {}

    function getReserveData(address _reserve) external view returns (CoreLibrary.ReserveData memory) {
        return s_reserves[_reserve];
    }

    function getUserReserveData(address _user, address _reserve)
        external
        view
        returns (CoreLibrary.UserReserveData memory)
    {
        return s_usersReserveData[_user][_reserve];
    }

    function setReserveBorrows(address _reserve, uint256 _stableBorrows, uint256 _variableBorrows) external {
        s_reserves[_reserve].totalBorrowsStable = _stableBorrows;

        s_reserves[_reserve].totalBorrowsVariable = _variableBorrows;
    }

    function setUserReserveData(address _user, address _reserve, CoreLibrary.UserReserveData memory _data) external {
        s_usersReserveData[_user][_reserve] = _data;
    }
}

contract LendingPoolCoreTest is Test {
    uint256 public constant RAY = 1e27;
    uint256 public constant DEPOSIT_AMOUNT = 100 ether;

    address public lendingPool = makeAddr("lendingPool");
    address public configurator = makeAddr("configurator");
    address public user = makeAddr("user");
    address public attacker = makeAddr("attacker");
    address public aToken = makeAddr("aToken");

    LendingPoolCoreHarness public core;
    MockERC20 public token;
    MockReserveInterestRateStrategy public strategy;
    MockLendingPoolAddressProvider public addressProvider;

    event ReserveInitialized(address indexed reserve, address aTokenAddress, address interestRateStrategyAddress);

    event ReserveRemoved(address indexed reserve);

    event ReserveUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 stableBorrowRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    function setUp() external {
        addressProvider = new MockLendingPoolAddressProvider(lendingPool, configurator);
        core = new LendingPoolCoreHarness(address(addressProvider));

        token = new MockERC20("Mock Token", "MOCK");
        strategy = new MockReserveInterestRateStrategy();

        token.mint(user, 1_000 ether);
        vm.deal(lendingPool, 100 ether);
        vm.deal(user, 100 ether);
    }

    function _initReserve(address _reserve) public {
        vm.prank(configurator);
        core.initReserve(_reserve, aToken, 18, address(strategy));
    }

    ////////////////////////////////
    //       Access Control       //
    ////////////////////////////////

    function testInitReserveRevertsWhenCallerIsNotConfigurator() external {
        vm.prank(attacker);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPoolConfigurator.selector);

        core.initReserve(address(token), aToken, 18, address(strategy));
    }

    function testUpdateStateOnDepositRevertsWhenCallerIsNotLendingPool() external {
        vm.prank(attacker);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);

        core.updateStateOnDeposit(address(token), user, DEPOSIT_AMOUNT, true);
    }

    function testTransferToReserveRevertsWhenCallerIsNotLendingPool() external {
        vm.prank(attacker);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);

        core.transferToReserve(address(token), payable(user), DEPOSIT_AMOUNT);
    }

    ////////////////////////////////
    //        initReserve         //
    ////////////////////////////////

    function testInitReserveInitializesConfiguration() external {
        vm.expectEmit(true, false, false, true);

        emit ReserveInitialized(address(token), aToken, address(strategy));

        vm.prank(configurator);
        core.initReserve(address(token), aToken, 18, address(strategy));

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        assertEq(reserve.aTokenAddress, aToken);
        assertEq(reserve.decimals, 18);
        assertEq(reserve.interestRateStrategyAddress, address(strategy));

        // Every reserve index begins at 1 ray.
        assertEq(reserve.lastLiquidityCumulativeIndex, RAY);

        assertEq(reserve.lastVariableBorrowCumulativeIndex, RAY);

        assertTrue(reserve.isActive);
        assertFalse(reserve.isFreezed);
    }

    function testInitReserveRevertsWhenReserveAlreadyInitialized() external {
        _initReserve(address(token));

        vm.prank(configurator);

        vm.expectRevert(CoreLibrary.CoreLibrary__ReserveAlreadyInitialized.selector);

        core.initReserve(address(token), makeAddr("anotherAToken"), 6, makeAddr("anotherStrategy"));
    }

    ////////////////////////////////
    //  setUserUseAsCollateral   //
    ////////////////////////////////

    function testSetUserUseReserveAsCollateralEnablesCollateral() external {
        vm.prank(lendingPool);

        core.setUserUseReserveAsCollateral(address(token), user, true);

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        assertTrue(userData.useAsCollateral);
    }

    function testSetUserUseReserveAsCollateralDisablesCollateral() external {
        vm.startPrank(lendingPool);

        core.setUserUseReserveAsCollateral(address(token), user, true);

        core.setUserUseReserveAsCollateral(address(token), user, false);

        vm.stopPrank();

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        assertFalse(userData.useAsCollateral);
    }

    ////////////////////////////////
    //     transferToReserve      //
    ////////////////////////////////

    function testTransferToReserveTransfersERC20IntoCore() external {
        vm.prank(user);
        token.approve(address(core), DEPOSIT_AMOUNT);

        vm.prank(lendingPool);
        core.transferToReserve(address(token), payable(user), DEPOSIT_AMOUNT);

        assertEq(token.balanceOf(user), 1_000 ether - DEPOSIT_AMOUNT);

        assertEq(token.balanceOf(address(core)), DEPOSIT_AMOUNT);
    }

    function testTransferToReserveRevertsWhenEthIsSentWithERC20() external {
        vm.prank(user);
        token.approve(address(core), DEPOSIT_AMOUNT);

        vm.prank(lendingPool);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__CantSendEthAndTransferErc20.selector);

        core.transferToReserve{value: 1 ether}(address(token), payable(user), DEPOSIT_AMOUNT);
    }

    function testTransferToReserveRevertsWhenNotEnoughEthIsSent() external {
        address ethReserve = EthAddressLib.ethAddress();

        vm.prank(lendingPool);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__MsgValueLessThanAmount.selector);

        core.transferToReserve{value: 0.5 ether}(ethReserve, payable(user), 1 ether);
    }

    function testTransferToReserveKeepsExactEthAmount() external {
        address ethReserve = EthAddressLib.ethAddress();

        vm.prank(lendingPool);

        core.transferToReserve{value: 1 ether}(ethReserve, payable(user), 1 ether);

        assertEq(address(core).balance, 1 ether);
    }

    function testTransferToReserveRefundsExcessEth() external {
        address ethReserve = EthAddressLib.ethAddress();

        uint256 userBalanceBefore = user.balance;

        vm.prank(lendingPool);

        core.transferToReserve{value: 1.2 ether}(ethReserve, payable(user), 1 ether);

        // The core retains only the requested deposit.
        assertEq(address(core).balance, 1 ether);

        // The additional 0.2 ETH is refunded to the user.
        assertEq(user.balance, userBalanceBefore + 0.2 ether);
    }

    ////////////////////////////////
    //    updateStateOnDeposit    //
    ////////////////////////////////

    function testUpdateStateOnDepositStoresNewRatesAndTimestamp() external {
        _initReserve(address(token));

        uint256 liquidityRate = 5e25; // 5%
        uint256 stableBorrowRate = 8e25; // 8%
        uint256 variableBorrowRate = 10e25; // 10%

        strategy.setRates(liquidityRate, stableBorrowRate, variableBorrowRate);

        uint256 updateTimestamp = block.timestamp + 30 days;

        vm.warp(updateTimestamp);

        // No tokens have been transferred yet, so current available
        // liquidity is zero. The deposit adds 100 tokens.
        vm.expectCall(
            address(strategy),
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates, (address(token), DEPOSIT_AMOUNT, 0, 0, 0)
            )
        );

        vm.expectEmit(true, false, false, true);

        emit ReserveUpdated(address(token), liquidityRate, stableBorrowRate, variableBorrowRate, RAY, RAY);

        vm.prank(lendingPool);

        core.updateStateOnDeposit(address(token), user, DEPOSIT_AMOUNT, false);

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        assertEq(reserve.currentLiquidityRate, liquidityRate);

        assertEq(reserve.currentStableBorrowRate, stableBorrowRate);

        assertEq(reserve.currentVariableBorrowRate, variableBorrowRate);

        assertEq(reserve.lastUpdateTimestamp, updateTimestamp);
    }

    function testUpdateStateOnFirstDepositEnablesCollateral() external {
        _initReserve(address(token));

        strategy.setRates(0, 0, 0);

        vm.prank(lendingPool);

        core.updateStateOnDeposit(address(token), user, DEPOSIT_AMOUNT, true);

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        assertTrue(userData.useAsCollateral);
    }

    function testUpdateStateOnLaterDepositDoesNotEnableCollateral() external {
        _initReserve(address(token));

        strategy.setRates(0, 0, 0);

        vm.prank(lendingPool);

        core.updateStateOnDeposit(address(token), user, DEPOSIT_AMOUNT, false);

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        assertFalse(userData.useAsCollateral);
    }

    ////////////////////////////////
    //   removeLastAddedReserve   //
    ////////////////////////////////

    function testRemoveLastAddedReserveRevertsWhenListIsEmpty() external {
        vm.prank(configurator);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__ReserveListIsEmpty.selector);

        core.removeLastAddedReserve(address(token));
    }

    function testRemoveLastAddedReserveRevertsWhenRequestedReserveIsNotLast() external {
        MockERC20 secondToken = new MockERC20("Mock Token", "MOCK");

        _initReserve(address(token));
        _initReserve(address(secondToken));

        vm.prank(configurator);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__ReserveToRemoveIsNotLastReserve.selector);

        core.removeLastAddedReserve(address(token));
    }

    function testRemoveLastAddedReserveRevertsWhenReserveHasBorrows() external {
        _initReserve(address(token));

        core.setReserveBorrows(address(token), 100 ether, 50 ether);

        vm.prank(configurator);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__ReserveHasBorrows.selector);

        core.removeLastAddedReserve(address(token));
    }

    function testRemoveLastAddedReserveResetsConfiguration() external {
        _initReserve(address(token));

        vm.expectEmit(true, false, false, false);
        emit ReserveRemoved(address(token));

        vm.prank(configurator);
        core.removeLastAddedReserve(address(token));

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        assertFalse(reserve.isActive);
        assertEq(reserve.aTokenAddress, address(0));
        assertEq(reserve.decimals, 0);

        assertEq(reserve.lastLiquidityCumulativeIndex, 0);

        assertEq(reserve.lastVariableBorrowCumulativeIndex, 0);

        assertFalse(reserve.borrowingEnabled);
        assertFalse(reserve.usageAsCollateralEnabled);

        assertEq(reserve.baseLTVasCollateral, 0);
        assertEq(reserve.liquidationThreshold, 0);
        assertEq(reserve.liquidationBonus, 0);

        assertEq(reserve.interestRateStrategyAddress, address(0));
    }

    function testRemovedReserveCanBeInitializedAgain() external {
        _initReserve(address(token));

        vm.prank(configurator);
        core.removeLastAddedReserve(address(token));

        // This verifies that s_isReserveAdded was reset to false.
        vm.prank(configurator);
        core.initReserve(address(token), aToken, 18, address(strategy));

        assertEq(core.getReserveATokenAddress(address(token)), aToken);
    }

    ////////////////////////////////
    //          Getters           //
    ////////////////////////////////

    function testGetReserveAvailableLiquidityReturnsERC20Balance() external {
        token.mint(address(core), 250 ether);

        assertEq(core.getReserveAvailableLiquidity(address(token)), 250 ether);
    }

    function testGetReserveAvailableLiquidityReturnsEthBalance() external {
        vm.deal(address(core), 3 ether);

        assertEq(core.getReserveAvailableLiquidity(EthAddressLib.ethAddress()), 3 ether);
    }

    function testGetReserveTotalBorrowsReturnsStablePlusVariable() external {
        _initReserve(address(token));

        core.setReserveBorrows(address(token), 100 ether, 250 ether);

        assertEq(core.getReserveTotalBorrows(address(token)), 350 ether);
    }

    function testGetReserveNormalizedIncomeStartsAtOneRay() external {
        _initReserve(address(token));

        assertEq(core.getReserveNormalizedIncome(address(token)), RAY);
    }
}
