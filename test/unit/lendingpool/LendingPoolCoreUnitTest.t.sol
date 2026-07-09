// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockLendingPoolAddressProvider} from "../../mocks/MockLendingPoolAddressProvider.sol";
import {MockReserveInterestRateStrategy} from "../../mocks/MockReserveInterestRateStrategy.sol";

import {LendingPoolCore} from "src/lendingpool/LendingPoolCore.sol";
import {CoreLibrary} from "src/libraries/CoreLibrary.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";
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

    function setReserveRates(
        address _reserve,
        uint256 _liquidityRate,
        uint256 _stableBorrowRate,
        uint256 _variableBorrowRate
    ) external {
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];
        reserve.currentLiquidityRate = _liquidityRate;
        reserve.currentStableBorrowRate = _stableBorrowRate;
        reserve.currentVariableBorrowRate = _variableBorrowRate;
    }

    function setReserveLastUpdateTimestamp(address _reserve, uint40 _timestamp) external {
        s_reserves[_reserve].lastUpdateTimestamp = _timestamp;
    }

    function exposedUpdateReserveInterestRatesAndTimestamp(
        address _reserve,
        uint256 _liquidityAdded,
        uint256 _liquidityTaken
    ) external {
        _updateReserveInterestRatesAndTimestamp(_reserve, _liquidityAdded, _liquidityTaken);
    }

    function exposedAddReserveToList(address _reserve) external {
        _addReserveToList(_reserve);
    }
}

contract LendingPoolCoreUnitTest is Test {
    using WadRayMath for uint256;

    uint256 public constant RAY = 1e27;
    uint256 public constant DEPOSIT_AMOUNT = 100 ether;

    address public lendingPool = makeAddr("lendingPool");
    address public configurator = makeAddr("configurator");
    address public user = makeAddr("user");
    address public attacker = makeAddr("attacker");
    address public aToken = makeAddr("aToken");

    LendingPoolCoreHarness public core;
    MockERC20 public token;
    MockERC20 public secondToken;
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
        secondToken = new MockERC20("Second Mock Token", "SMOCK");
        strategy = new MockReserveInterestRateStrategy();

        token.mint(user, 1_000 ether);
        vm.deal(lendingPool, 100 ether);
        vm.deal(user, 100 ether);
    }

    modifier withInitReserve(address _reserve) {
        vm.prank(configurator);
        core.initReserve(_reserve, aToken, 18, address(strategy));
        _;
    }

    function _initReserveWithMockAToken(address _reserve) internal returns (MockERC20 mockAToken) {
        mockAToken = new MockERC20("Mock AToken", "aMOCK");

        vm.prank(configurator);
        core.initReserve(_reserve, address(mockAToken), 18, address(strategy));
    }

    ////////////////////////////////
    //        initReserve         //
    ////////////////////////////////
    function testInitReserveInitializesConfiguration() external {
        vm.expectEmit(true, false, false, true);

        emit LendingPoolCore.ReserveInitialized(address(token), aToken, address(strategy));

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

        address[] memory reservesList = core.getReserves();

        assertEq(reservesList.length, 1);
        assertEq(reservesList[0], address(token));
    }

    function testInitReserveRevertsWhenCallerIsNotConfigurator() external {
        vm.prank(attacker);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPoolConfigurator.selector);

        core.initReserve(address(token), aToken, 18, address(strategy));
    }

    function testInitReserveRevertsWhenReserveAlreadyInitialized() external withInitReserve(address(token)) {
        vm.prank(configurator);

        vm.expectRevert(CoreLibrary.CoreLibrary__ReserveAlreadyInitialized.selector);

        core.initReserve(address(token), makeAddr("anotherAToken"), 6, makeAddr("anotherStrategy"));
    }

    ////////////////////////////////
    //      _addReserveToList     //
    ////////////////////////////////
    function testAddReserveToListAddsReserveToList() external {
        core.exposedAddReserveToList(address(token));

        address[] memory reservesList = core.getReserves();

        assertEq(reservesList.length, 1);
        assertEq(reservesList[0], address(token));
    }

    function testAddReserveToListDoesNotAddDuplicateReserve() external {
        core.exposedAddReserveToList(address(token));
        core.exposedAddReserveToList(address(token));

        address[] memory reservesList = core.getReserves();

        assertEq(reservesList.length, 1);
        assertEq(reservesList[0], address(token));
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

    function testTransferToReserveRevertsWhenCallerIsNotLendingPool() external {
        vm.prank(attacker);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);

        core.transferToReserve(address(token), payable(user), DEPOSIT_AMOUNT);
    }

    ////////////////////////////////
    //    updateStateOnDeposit    //
    ////////////////////////////////

    // Verifies that a deposit keeps the cumulative indexes unchanged when the
    // previous rates are zero, then stores the new rates and current timestamp.
    function testUpdateStateOnDepositStoresNewRatesAndTimestamp() external withInitReserve(address(token)) {
        uint256 liquidityRate = 5e25; // 5%
        uint256 stableBorrowRate = 8e25; // 8%
        uint256 variableBorrowRate = 10e25; // 10%

        strategy.setRates(liquidityRate, stableBorrowRate, variableBorrowRate);

        uint256 updateTimestamp = block.timestamp + 30 days;

        vm.warp(updateTimestamp);

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

        // Checking that updateCumulativeIndexes() doesn't update lastLiquidityCumulativeIndex and lastVariableBorrowCumulativeIndex

        // Before the deposit, the reserve liquidity rate is 0.
        //
        // linearInterest = 1 + rate * elapsedTime / SECONDS_PER_YEAR
        // linearInterest = 1 + 0 * 30 days / 365 days
        // linearInterest = 1 ray
        //
        // newLiquidityIndex = previousLiquidityIndex * linearInterest
        // newLiquidityIndex = 1 ray * 1 ray
        // newLiquidityIndex = 1 ray
        //
        assertEq(reserve.lastLiquidityCumulativeIndex, RAY);

        // Before the deposit, the reserve variable borrow rate is 0.
        //
        // compoundedInterest = (1 + ratePerSecond) ^ elapsedSeconds
        // compoundedInterest = (1 + 0) ^ 30 days
        // compoundedInterest = 1 ray
        //
        // newVariableBorrowIndex = previousVariableBorrowIndex * compoundedInterest
        // newVariableBorrowIndex = 1 ray * 1 ray
        // newVariableBorrowIndex = 1 ray
        //
        assertEq(reserve.lastVariableBorrowCumulativeIndex, RAY);

        // Check that _updateReserveInterestRatesAndTimestamp() updates: currentLiquidityRate, currentStableBorrowRate,
        // currentVariableBorrowRate and lastUpdateTimestamp
        assertEq(reserve.currentLiquidityRate, liquidityRate);

        assertEq(reserve.currentStableBorrowRate, stableBorrowRate);

        assertEq(reserve.currentVariableBorrowRate, variableBorrowRate);

        assertEq(reserve.lastUpdateTimestamp, updateTimestamp);
    }

    // Verifies that a deposit updates the cumulative indexes using the old rates,
    // then stores the new rates and the current timestamp.
    function testUpdateStateOnDepositUpdatesIndexesRatesAndTimestamp() external withInitReserve(address(token)) {
        uint256 oldLiquidityRate = 5e25; // 5%
        uint256 oldVariableBorrowRate = 10e25; // 10%

        core.setReserveRates(address(token), oldLiquidityRate, 0, oldVariableBorrowRate);

        // Variable borrows must be greater than zero for the variable
        // borrow index to be updated.
        core.setReserveBorrows(address(token), 0, 100 ether);

        uint256 previousTimestamp = block.timestamp;

        // forge-lint: disable-next-line(unsafe-typecast)
        core.setReserveLastUpdateTimestamp(address(token), uint40(previousTimestamp));

        uint256 updateTimestamp = previousTimestamp + 365 days;

        vm.warp(updateTimestamp);

        uint256 newLiquidityRate = 3e25; // 3%
        uint256 newStableBorrowRate = 6e25; // 6%
        uint256 newVariableBorrowRate = 7e25; // 7%

        strategy.setRates(newLiquidityRate, newStableBorrowRate, newVariableBorrowRate);

        vm.prank(lendingPool);

        core.updateStateOnDeposit(address(token), user, DEPOSIT_AMOUNT, false);

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // The liquidity index is updated using linear interest and the old
        // liquidity rate that applied during the elapsed year.
        //
        // linearInterest = 1 ray + oldLiquidityRate * elapsedTime / SECONDS_PER_YEAR
        // linearInterest = 1.00 + 5% * 365 days / 365 days
        // linearInterest = 1.05 ray
        //
        // newLiquidityIndex = previousLiquidityIndex * linearInterest
        // newLiquidityIndex = 1.00 ray * 1.05 ray
        // newLiquidityIndex = 1.05 ray = 105e25
        assertEq(reserve.lastLiquidityCumulativeIndex, 105e25);

        // The variable borrow index is updated using compounded interest
        // and the old variable borrow rate that applied during the year.
        //
        // ratePerSecond = oldVariableBorrowRate / SECONDS_PER_YEAR
        //
        // compoundedInterest = (1 ray + ratePerSecond) ^ elapsedSeconds
        // compoundedInterest = (1 + 10% / 31,536,000) ^ 31,536,000
        // compoundedInterest ≈ 1.10517 ray
        //
        // newVariableBorrowIndex = previousVariableBorrowIndex * compoundedInterest
        // newVariableBorrowIndex = 1.00 ray * 1.10517 ray
        // newVariableBorrowIndex ≈ 1.10517 ray
        uint256 ratePerSecond = oldVariableBorrowRate / 365 days;

        uint256 expectedCompoundedInterest = (RAY + ratePerSecond).rayPow(365 days);

        uint256 expectedVariableBorrowIndex = RAY.rayMul(expectedCompoundedInterest);

        assertEq(reserve.lastVariableBorrowCumulativeIndex, expectedVariableBorrowIndex);

        // After the indexes are updated using the old rates, the rates
        // returned by the strategy are stored for the next interest period.
        assertEq(reserve.currentLiquidityRate, newLiquidityRate);

        assertEq(reserve.currentStableBorrowRate, newStableBorrowRate);

        assertEq(reserve.currentVariableBorrowRate, newVariableBorrowRate);

        // The current block timestamp becomes the starting checkpoint
        // for the next reserve interest calculation.
        assertEq(reserve.lastUpdateTimestamp, updateTimestamp);
    }

    function testUpdateStateOnFirstDepositEnablesCollateral() external withInitReserve(address(token)) {
        strategy.setRates(0, 0, 0);

        vm.prank(lendingPool);

        core.updateStateOnDeposit(address(token), user, DEPOSIT_AMOUNT, true);

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        assertTrue(userData.useAsCollateral);
    }

    function testUpdateStateOnLaterDepositDoesNotEnableCollateral() external withInitReserve(address(token)) {
        strategy.setRates(0, 0, 0);

        vm.prank(lendingPool);

        core.updateStateOnDeposit(address(token), user, DEPOSIT_AMOUNT, false);

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        assertFalse(userData.useAsCollateral);
    }

    function testUpdateStateOnDepositRevertsWhenCallerIsNotLendingPool() external {
        vm.prank(attacker);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);

        core.updateStateOnDeposit(address(token), user, DEPOSIT_AMOUNT, true);
    }

    ////////////////////////////////////////////////
    //  _updateReserveInterestRatesAndTimestamp   //
    ////////////////////////////////////////////////
    function testUpdateReserveInterestRatesAndTimestampUpdatesRatesTimestampAndEmitsEvent()
        external
        withInitReserve(address(token))
    {
        uint256 availableLiquidity = 10 ether;
        uint256 liquidityAdded = 5 ether;
        uint256 liquidityTaken = 2 ether;

        token.mint(address(core), availableLiquidity);

        uint256 liquidityRate = 4e25; // 4%
        uint256 stableBorrowRate = 7e25; // 7%
        uint256 variableBorrowRate = 9e25; // 9%

        strategy.setRates(liquidityRate, stableBorrowRate, variableBorrowRate);

        uint256 updateTimestamp = block.timestamp + 1 days;

        vm.warp(updateTimestamp);

        vm.expectCall(
            address(strategy),
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates,
                (address(token), availableLiquidity + liquidityAdded - liquidityTaken, 0, 0, 0)
            )
        );

        vm.expectEmit(true, false, false, true);

        emit ReserveUpdated(address(token), liquidityRate, stableBorrowRate, variableBorrowRate, RAY, RAY);

        core.exposedUpdateReserveInterestRatesAndTimestamp(address(token), liquidityAdded, liquidityTaken);

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        assertEq(reserve.currentLiquidityRate, liquidityRate);
        assertEq(reserve.currentStableBorrowRate, stableBorrowRate);
        assertEq(reserve.currentVariableBorrowRate, variableBorrowRate);
        assertEq(reserve.lastUpdateTimestamp, updateTimestamp);
    }

    ////////////////////////////////
    //   removeLastAddedReserve   //
    ////////////////////////////////

    function testRemoveLastAddedReserveRemovesLastReserveFromList()
        external
        withInitReserve(address(token))
        withInitReserve(address(secondToken))
    {
        address[] memory reservesListBefore = core.getReserves();

        assertEq(reservesListBefore.length, 2);
        assertEq(reservesListBefore[0], address(token));
        assertEq(reservesListBefore[1], address(secondToken));

        vm.prank(configurator);
        core.removeLastAddedReserve(address(secondToken));

        address[] memory reservesListAfter = core.getReserves();

        assertEq(reservesListAfter.length, 1);
        assertEq(reservesListAfter[0], address(token));
    }

    function testRemoveLastAddedReserveRevertsWhenListIsEmpty() external {
        vm.prank(configurator);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__ReserveListIsEmpty.selector);

        core.removeLastAddedReserve(address(token));
    }

    function testRemoveLastAddedReserveRevertsWhenRequestedReserveIsNotLast()
        external
        withInitReserve(address(token))
        withInitReserve(address(secondToken))
    {
        vm.prank(configurator);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__ReserveToRemoveIsNotLastReserve.selector);

        core.removeLastAddedReserve(address(token));
    }

    function testRemoveLastAddedReserveRevertsWhenReserveHasBorrows() external withInitReserve(address(token)) {
        core.setReserveBorrows(address(token), 100 ether, 50 ether);

        vm.prank(configurator);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__ReserveHasBorrows.selector);

        core.removeLastAddedReserve(address(token));
    }

    function testRemoveLastAddedReserveResetsConfiguration() external withInitReserve(address(token)) {
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

    function testRemovedReserveCanBeInitializedAgain() external withInitReserve(address(token)) {
        vm.prank(configurator);
        core.removeLastAddedReserve(address(token));

        // This verifies that s_isReserveAdded was reset to false.
        vm.prank(configurator);
        core.initReserve(address(token), aToken, 18, address(strategy));

        assertEq(core.getReserveATokenAddress(address(token)), aToken);
    }

    //////////////////////////////////////
    //  setUserUseReserveAsCollateral   //
    //////////////////////////////////////

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

    /////////////////////////////////////
    //  getReserveAvailableLiquidity   //
    /////////////////////////////////////
    function testGetReserveAvailableLiquidityReturnsERC20Balance() external {
        token.mint(address(core), 250 ether);

        assertEq(core.getReserveAvailableLiquidity(address(token)), 250 ether);
    }

    function testGetReserveAvailableLiquidityReturnsEthBalance() external {
        vm.deal(address(core), 3 ether);

        assertEq(core.getReserveAvailableLiquidity(EthAddressLib.ethAddress()), 3 ether);
    }

    ////////////////////////////////
    //    getReserveTotalBorrows  //
    ////////////////////////////////
    function testGetReserveTotalBorrowsReturnsStablePlusVariable() external withInitReserve(address(token)) {
        core.setReserveBorrows(address(token), 100 ether, 250 ether);

        assertEq(core.getReserveTotalBorrows(address(token)), 350 ether);
    }

    ////////////////////////////////
    //  getReserveATokenAddress   //
    ////////////////////////////////
    function testGetReserveATokenAddressReturnsConfiguredAToken() external withInitReserve(address(token)) {
        assertEq(core.getReserveATokenAddress(address(token)), aToken);
    }

    ////////////////////////////////
    //         getReserves        //
    ////////////////////////////////
    function testGetReservesReturnsInitializedReservesInOrder()
        external
        withInitReserve(address(token))
        withInitReserve(address(secondToken))
    {
        address[] memory reservesList = core.getReserves();

        assertEq(reservesList.length, 2);
        assertEq(reservesList[0], address(token));
        assertEq(reservesList[1], address(secondToken));
    }

    ////////////////////////////////
    //  getUserBasicReserveData   //
    ////////////////////////////////
    function testGetUserBasicReserveDataReturnsDepositDataWhenUserHasNoBorrow() external {
        MockERC20 mockAToken = _initReserveWithMockAToken(address(token));
        mockAToken.mint(user, 42 ether);

        vm.prank(lendingPool);
        core.setUserUseReserveAsCollateral(address(token), user, true);

        (uint256 underlyingBalance, uint256 compoundedBorrowBalance, uint256 originationFee, bool useAsCollateral) =
            core.getUserBasicReserveData(address(token), user);

        assertEq(underlyingBalance, 42 ether);
        assertEq(compoundedBorrowBalance, 0);
        assertEq(originationFee, 0);
        assertTrue(useAsCollateral);
    }

    function testGetUserBasicReserveDataReturnsBorrowDataWhenUserHasBorrow() external {
        MockERC20 mockAToken = _initReserveWithMockAToken(address(token));
        mockAToken.mint(user, 75 ether);

        core.setReserveLastUpdateTimestamp(address(token), uint40(block.timestamp));

        CoreLibrary.UserReserveData memory userData = CoreLibrary.UserReserveData({
            principalBorrowBalance: 50 ether,
            lastVariableBorrowCumulativeIndex: RAY,
            originationFee: 1 ether,
            stableBorrowRate: 0,
            lastUpdateTimestamp: uint40(block.timestamp),
            useAsCollateral: true
        });

        core.setUserReserveData(user, address(token), userData);

        (uint256 underlyingBalance, uint256 compoundedBorrowBalance, uint256 originationFee, bool useAsCollateral) =
            core.getUserBasicReserveData(address(token), user);

        assertEq(underlyingBalance, 75 ether);
        assertEq(compoundedBorrowBalance, 50 ether);
        assertEq(originationFee, 1 ether);
        assertTrue(useAsCollateral);
    }

    ////////////////////////////////
    //  getReserveNormalizedIncome //
    ////////////////////////////////
    function testGetReserveNormalizedIncomeStartsAtOneRay() external withInitReserve(address(token)) {
        assertEq(core.getReserveNormalizedIncome(address(token)), RAY);
    }
}
