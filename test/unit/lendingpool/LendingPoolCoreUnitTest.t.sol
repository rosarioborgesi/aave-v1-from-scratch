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

    function setReserveCurrentAverageStableBorrowRate(address _reserve, uint256 _averageStableBorrowRate) external {
        s_reserves[_reserve].currentAverageStableBorrowRate = _averageStableBorrowRate;
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

    function setReserveConfiguration(
        address _reserve,
        uint256 _baseLTVasCollateral,
        uint256 _liquidationThreshold,
        bool _usageAsCollateralEnabled
    ) external {
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];
        reserve.baseLTVasCollateral = _baseLTVasCollateral;
        reserve.liquidationThreshold = _liquidationThreshold;
        reserve.usageAsCollateralEnabled = _usageAsCollateralEnabled;
    }

    function exposedUpdateReserveInterestRatesAndTimestamp(
        address _reserve,
        uint256 _liquidityAdded,
        uint256 _liquidityTaken
    ) external {
        _updateReserveInterestRatesAndTimestamp(_reserve, _liquidityAdded, _liquidityTaken);
    }

    function exposedUpdateReserveTotalBorrowsByRateMode(
        address _reserve,
        address _user,
        uint256 _principalBalance,
        uint256 _balanceIncrease,
        uint256 _amountBorrowed,
        CoreLibrary.InterestRateMode _newBorrowRateMode
    ) external {
        _updateReserveTotalBorrowsByRateMode(
            _reserve, _user, _principalBalance, _balanceIncrease, _amountBorrowed, _newBorrowRateMode
        );
    }

    function exposedAddReserveToList(address _reserve) external {
        _addReserveToList(_reserve);
    }
}

contract RejectEthReceiver {
    receive() external payable {
        revert();
    }
}

contract LendingPoolCoreUnitTest is Test {
    using WadRayMath for uint256;

    uint256 public constant RAY = 1e27;
    uint256 public constant DEPOSIT_AMOUNT = 100 ether;
    uint256 public constant USER_INITIAL_TOKEN_BALANCE = 1_000 ether;
    uint256 public constant LENDING_POOL_INITIAL_ETH_BALANCE = 100 ether;

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

    function setUp() external {
        addressProvider = new MockLendingPoolAddressProvider(lendingPool, configurator);
        core = new LendingPoolCoreHarness(address(addressProvider));

        token = new MockERC20("Mock Token", "MOCK");
        secondToken = new MockERC20("Second Mock Token", "SMOCK");
        strategy = new MockReserveInterestRateStrategy();
    }

    modifier withInitReserve(address _reserve) {
        vm.prank(configurator);
        core.initReserve(_reserve, aToken, 18, address(strategy));
        _;
    }

    modifier withUserTokenBalance() {
        token.mint(user, USER_INITIAL_TOKEN_BALANCE);
        _;
    }

    modifier withLendingPoolEthBalance() {
        vm.deal(lendingPool, LENDING_POOL_INITIAL_ETH_BALANCE);
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

    function testTransferToReserveTransfersERC20IntoCore() external withUserTokenBalance {
        vm.prank(user);
        token.approve(address(core), DEPOSIT_AMOUNT);

        vm.prank(lendingPool);
        core.transferToReserve(address(token), payable(user), DEPOSIT_AMOUNT);

        assertEq(token.balanceOf(user), USER_INITIAL_TOKEN_BALANCE - DEPOSIT_AMOUNT);

        assertEq(token.balanceOf(address(core)), DEPOSIT_AMOUNT);
    }

    function testTransferToReserveKeepsExactEthAmount() external withLendingPoolEthBalance {
        address ethReserve = EthAddressLib.ethAddress();

        vm.prank(lendingPool);

        core.transferToReserve{value: 1 ether}(ethReserve, payable(user), 1 ether);

        assertEq(address(core).balance, 1 ether);
    }

    function testTransferToReserveRefundsExcessEth() external withLendingPoolEthBalance {
        address ethReserve = EthAddressLib.ethAddress();

        uint256 userBalanceBefore = user.balance;

        vm.prank(lendingPool);

        core.transferToReserve{value: 1.2 ether}(ethReserve, payable(user), 1 ether);

        // The core retains only the requested deposit.
        assertEq(address(core).balance, 1 ether);

        // The additional 0.2 ETH is refunded to the user.
        assertEq(user.balance, userBalanceBefore + 0.2 ether);
    }

    function testTransferToReserveRevertsWhenEthIsSentWithERC20() external withLendingPoolEthBalance {
        vm.prank(user);
        token.approve(address(core), DEPOSIT_AMOUNT);

        vm.prank(lendingPool);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__CantSendEthAndTransferErc20.selector);

        core.transferToReserve{value: 1 ether}(address(token), payable(user), DEPOSIT_AMOUNT);
    }

    function testTransferToReserveRevertsWhenNotEnoughEthIsSent() external withLendingPoolEthBalance {
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
    //       transferToUser       //
    ////////////////////////////////

    function testTransferToUserTransfersERC20FromCore() external {
        token.mint(address(core), 1 ether);

        vm.prank(lendingPool);
        core.transferToUser(address(token), payable(user), 1 ether);

        assertEq(token.balanceOf(address(core)), 0);
        assertEq(token.balanceOf(user), 1 ether);
    }

    function testTransferToUserTransfersEthFromCore() external {
        vm.deal(address(core), 1 ether);

        vm.prank(lendingPool);
        core.transferToUser(EthAddressLib.ethAddress(), payable(user), 1 ether);

        assertEq(address(core).balance, 0);
        assertEq(user.balance, 1 ether);
    }

    function testTransferToUserRevertsWhenCallerIsNotLendingPool() external {
        vm.prank(attacker);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);

        core.transferToUser(address(token), payable(user), DEPOSIT_AMOUNT);
    }

    function testTransferToUserRevertsWhenEthTransferFails() external {
        RejectEthReceiver receiver = new RejectEthReceiver();

        vm.deal(address(core), 1 ether);

        vm.prank(lendingPool);

        vm.expectRevert(
            abi.encodeWithSelector(
                LendingPoolCore.LendingPoolCore__EthTransferFailed.selector, address(receiver), 1 ether
            )
        );

        core.transferToUser(EthAddressLib.ethAddress(), payable(address(receiver)), 1 ether);
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

        emit LendingPoolCore.ReserveUpdated(
            address(token), liquidityRate, stableBorrowRate, variableBorrowRate, RAY, RAY
        );

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

        // Variable borrows or stable borrows must be greater than zero for the variable
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

    ////////////////////////////////
    //     updateStateOnRedeem    //
    ////////////////////////////////
    // Verifies that a redeem keeps the cumulative indexes unchanged when the
    // previous rates are zero, then stores the new rates and current timestamp.
    function testUpdateStateOnRedeemStoresNewRatesAndTimestamp() external withInitReserve(address(token)) {
        uint256 availableLiquidity = 250 ether;
        uint256 amountRedeemed = 100 ether;

        token.mint(address(core), availableLiquidity);

        uint256 liquidityRate = 5e25; // 5%
        uint256 stableBorrowRate = 8e25; // 8%
        uint256 variableBorrowRate = 10e25; // 10%

        strategy.setRates(liquidityRate, stableBorrowRate, variableBorrowRate);

        uint256 updateTimestamp = block.timestamp + 30 days;

        vm.warp(updateTimestamp);

        vm.expectCall(
            address(strategy),
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates,
                (address(token), availableLiquidity - amountRedeemed, 0, 0, 0)
            )
        );

        vm.expectEmit(true, false, false, true);

        emit LendingPoolCore.ReserveUpdated(
            address(token), liquidityRate, stableBorrowRate, variableBorrowRate, RAY, RAY
        );

        vm.prank(lendingPool);
        core.updateStateOnRedeem(address(token), user, amountRedeemed, false);

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // Before the redeem, the reserve liquidity rate is 0.
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

        // Before the redeem, the reserve variable borrow rate is 0.
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

        assertEq(reserve.currentLiquidityRate, liquidityRate);
        assertEq(reserve.currentStableBorrowRate, stableBorrowRate);
        assertEq(reserve.currentVariableBorrowRate, variableBorrowRate);
        assertEq(reserve.lastUpdateTimestamp, updateTimestamp);
    }

    // Verifies that a redeem updates the cumulative indexes using the old rates,
    // then stores the new rates and the current timestamp.
    function testUpdateStateOnRedeemUpdatesIndexesRatesAndTimestamp() external withInitReserve(address(token)) {
        uint256 availableLiquidity = 250 ether;
        uint256 amountRedeemed = 100 ether;

        token.mint(address(core), availableLiquidity);

        uint256 oldLiquidityRate = 5e25; // 5%
        uint256 oldVariableBorrowRate = 10e25; // 10%

        core.setReserveRates(address(token), oldLiquidityRate, 0, oldVariableBorrowRate);

        // Variable borrows or stable borrows must be greater than zero for the variable
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

        core.updateStateOnRedeem(address(token), user, amountRedeemed, false);

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

    function testUpdateStateOnRedeemDisablesCollateralWhenUserRedeemedEverything()
        external
        withInitReserve(address(token))
    {
        token.mint(address(core), DEPOSIT_AMOUNT);
        strategy.setRates(0, 0, 0);

        vm.startPrank(lendingPool);

        core.setUserUseReserveAsCollateral(address(token), user, true);

        core.updateStateOnRedeem(address(token), user, DEPOSIT_AMOUNT, true);

        vm.stopPrank();

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        assertFalse(userData.useAsCollateral);
    }

    function testUpdateStateOnRedeemKeepsCollateralEnabledWhenUserRedeemedPartially()
        external
        withInitReserve(address(token))
    {
        token.mint(address(core), DEPOSIT_AMOUNT);
        strategy.setRates(0, 0, 0);

        vm.startPrank(lendingPool);

        core.setUserUseReserveAsCollateral(address(token), user, true);

        core.updateStateOnRedeem(address(token), user, DEPOSIT_AMOUNT / 2, false);

        vm.stopPrank();

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        assertTrue(userData.useAsCollateral);
    }

    function testUpdateStateOnRedeemRevertsWhenCallerIsNotLendingPool() external {
        vm.prank(attacker);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);

        core.updateStateOnRedeem(address(token), user, DEPOSIT_AMOUNT, true);
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

        emit LendingPoolCore.ReserveUpdated(
            address(token), liquidityRate, stableBorrowRate, variableBorrowRate, RAY, RAY
        );

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
        emit LendingPoolCore.ReserveRemoved(address(token));

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

    /////////////////////////////////////////////
    // isUserUseReserveAsCollateralEnabled     //
    /////////////////////////////////////////////

    function testIsUserUseReserveAsCollateralEnabledReturnsUserCollateralFlag() external {
        assertFalse(core.isUserUseReserveAsCollateralEnabled(address(token), user));

        vm.prank(lendingPool);
        core.setUserUseReserveAsCollateral(address(token), user, true);

        assertTrue(core.isUserUseReserveAsCollateralEnabled(address(token), user));
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
    //   getReserveConfiguration  //
    ////////////////////////////////
    function testGetReserveConfigurationReturnsConfiguredValues() external withInitReserve(address(token)) {
        core.setReserveConfiguration(address(token), 75, 80, true);

        (uint256 decimals, uint256 baseLTVasCollateral, uint256 liquidationThreshold, bool usageAsCollateralEnabled) =
            core.getReserveConfiguration(address(token));

        assertEq(decimals, 18);
        assertEq(baseLTVasCollateral, 75);
        assertEq(liquidationThreshold, 80);
        assertTrue(usageAsCollateralEnabled);
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

    //////////////////////////////////////////////////
    //  _updateReserveTotalBorrowsByRateMode        //
    //////////////////////////////////////////////////

    // Scenario: a user with no existing debt takes their first loan at a stable rate
    // (`NONE` -> `STABLE`)
    //
    // We verify that the new debt is added only to the stable aggregate, while the
    // existing variable aggregate is untouched. Because both the existing stable debt
    // and the new stable loan use 5%, their weighted average stable rate must stay 5%.
    function testUpdateReserveTotalBorrowsByRateModeAddsFirstStableBorrow() external {
        // Existing stable debt is 1,000 DAI at a 5% average stable rate.
        // Variable debt 500 DAI.
        core.setReserveBorrows(address(token), 1_000 ether, 500 ether);
        core.setReserveCurrentAverageStableBorrowRate(address(token), 5e25);
        core.setReserveRates(address(token), 0, 5e25, 0);

        // Arguments after the reserve and user represent:
        // - 0: the user's previous principal borrow balance;
        // - 0: interest accrued since the user's previous debt update;
        // - 500 DAI: the newly borrowed amount;
        // - STABLE: the rate mode selected for the resulting debt.
        //
        // Therefore, the helper calculates an updated principal of 0 + 0 + 500 = 500 DAI.
        core.exposedUpdateReserveTotalBorrowsByRateMode(
            address(token), user, 0, 0, 500 ether, CoreLibrary.InterestRateMode.STABLE
        );

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // Assert that a first stable borrow is added entirely to the stable-debt bucket.
        // No old debt is removed because the user previously had no debt. The updated
        // principal is 0 + 0 + 500 = 500 DAI, so stable debt becomes 1,000 + 500 = 1,500 DAI.
        assertEq(reserve.totalBorrowsStable, 1_500 ether);

        // Assert that adding the stable position updates the weighted average correctly.
        // The new position and the existing stable debt both use 5%, so their weighted
        // average remains 5%.
        assertEq(reserve.currentAverageStableBorrowRate, 5e25);

        // Assert that a stable borrow does not accidentally change the separate variable-debt bucket.
        // The existing variable aggregate must remain 500 DAI.
        assertEq(reserve.totalBorrowsVariable, 500 ether);
    }

    // Scenario: a user with no existing debt takes their first loan at a variable rate.
    // (`NONE` -> `VARIABLE`)
    //
    // We verify that the new debt is added only to the variable aggregate, while the
    // existing stable aggregate is untouched. Variable debt has no user-specific rate
    // contribution to the reserve's average stable borrow rate.
    function testUpdateReserveTotalBorrowsByRateModeAddsFirstVariableBorrow() external {
        core.setReserveBorrows(address(token), 1_000 ether, 500 ether);

        // Arguments after the reserve and user represent:
        // - 0: the user's previous principal borrow balance;
        // - 0: interest accrued since the user's previous debt update;
        // - 500 DAI: the newly borrowed amount;
        // - VARIABLE: the rate mode selected for the resulting debt.
        //
        // Therefore, the helper calculates an updated principal of 0 + 0 + 500 = 500 DAI.
        core.exposedUpdateReserveTotalBorrowsByRateMode(
            address(token), user, 0, 0, 500 ether, CoreLibrary.InterestRateMode.VARIABLE
        );

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // Assert that a first variable borrow is added entirely to the variable-debt bucket.
        // The updated principal is 0 + 0 + 500 = 500 DAI. It is added to the
        // variable aggregate: 500 + 500 = 1,000 DAI.
        assertEq(reserve.totalBorrowsVariable, 1_000 ether);

        // Assert that a variable borrow does not accidentally change the separate stable-debt bucket.
        // The existing stable aggregate must remain 1,000 DAI.
        assertEq(reserve.totalBorrowsStable, 1_000 ether);
    }

    // Scenario: an existing stable-rate borrower accrues interest and takes an additional
    // stable-rate loan. Their debt remains in the stable aggregate (`STABLE` -> `STABLE`).
    //
    // We verify that the helper first removes the user's old stable principal, then adds
    // their complete updated principal (old principal + accrued interest + new borrow)
    // back to stable debt. Variable debt must remain untouched.
    function testUpdateReserveTotalBorrowsByRateModeKeepsStableDebtInStableAggregate() external {
        // The stable aggregate contains 1,500 DAI. The user owns 1,000 DAI of it at 5%;
        // the remaining 500 DAI also uses 5%, so the reserve average is correctly 5%.
        core.setReserveBorrows(address(token), 1_500 ether, 500 ether);
        core.setReserveCurrentAverageStableBorrowRate(address(token), 5e25);
        core.setReserveRates(address(token), 0, 5e25, 0);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 1_000 ether,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                stableBorrowRate: 5e25,
                lastUpdateTimestamp: 0,
                useAsCollateral: false
            })
        );

        // Arguments after the reserve and user represent:
        // - 1,000 DAI: the user's current stored stable principal;
        // - 20 DAI: interest accrued on that principal since the previous debt update;
        // - 500 DAI: the additional amount the user is borrowing now;
        // - STABLE: the user keeps stable-rate debt after this borrow.
        //
        // Therefore, the helper removes the old 1,000 DAI stable principal and adds an
        // updated stable principal of 1,000 + 20 + 500 = 1,520 DAI.
        core.exposedUpdateReserveTotalBorrowsByRateMode(
            address(token), user, 1_000 ether, 20 ether, 500 ether, CoreLibrary.InterestRateMode.STABLE
        );

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // Remove the old 1,000 DAI stable principal, then add the updated principal:
        // 1,500 - 1,000 + (1,000 + 20 + 500) = 2,020 DAI.
        assertEq(reserve.totalBorrowsStable, 2_020 ether);

        // Both the remaining and newly added stable debt use 5%, so the average remains 5%.
        assertEq(reserve.currentAverageStableBorrowRate, 5e25);

        // The user's debt stayed stable, so variable debt remains unchanged.
        assertEq(reserve.totalBorrowsVariable, 500 ether);
    }

    // Scenario: an existing stable-rate borrower takes another stable-rate loan, but the
    // remaining stable debt, the user's old debt, and the new loan all have different rates.
    //
    // This test isolates the weighted-average calculation performed while the debt stays
    // in the stable aggregate (`STABLE` -> `STABLE`).
    function testUpdateReserveTotalBorrowsByRateModeRecalculatesAverageForStableDebtAtDifferentRates() external {
        // The 1,500 DAI stable aggregate has a 6% weighted average:
        // - user:  1,000 DAI at 5%;
        // - others:  500 DAI at 8%.
        // (1,000 * 5% + 500 * 8%) / 1,500 = 6%.
        core.setReserveBorrows(address(token), 1_500 ether, 500 ether);
        core.setReserveCurrentAverageStableBorrowRate(address(token), 6e25);

        // The current reserve stable rate is 7%, so the user's updated stable position
        // will be added to the aggregate at 7%.
        core.setReserveRates(address(token), 0, 7e25, 0);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 1_000 ether,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                stableBorrowRate: 5e25,
                lastUpdateTimestamp: 0,
                useAsCollateral: false
            })
        );

        // Arguments after the reserve and user represent:
        // - 1,000 DAI: the user's old stable principal at 5%;
        // - 20 DAI: interest accrued on that principal since the previous debt update;
        // - 500 DAI: the additional amount the user is borrowing now;
        // - STABLE: the user remains a stable-rate borrower.
        // The helper therefore removes 1,000 DAI at 5%, then adds a new 7% stable
        // position of 1,000 + 20 + 500 = 1,520 DAI.
        core.exposedUpdateReserveTotalBorrowsByRateMode(
            address(token), user, 1_000 ether, 20 ether, 500 ether, CoreLibrary.InterestRateMode.STABLE
        );

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // The stable aggregate removes the old 1,000 DAI and adds the 1,520 DAI updated debt:
        // 1,500 - 1,000 + 1,520 = 2,020 DAI.
        assertEq(reserve.totalBorrowsStable, 2_020 ether);

        // After removing the user's 1,000 DAI at 5%, the remaining 500 DAI is at 8%.
        // The new stable average is therefore:
        // (500 * 8% + 1,520 * 7%) / 2,020 = 7.2475247524752475247524752%.
        // In ray units, that rate is 72_475_247_524_752_475_247_524_752.
        assertEq(reserve.currentAverageStableBorrowRate, 72_475_247_524_752_475_247_524_752);

        // The user remains stable, so the existing 500 DAI variable aggregate is unchanged.
        assertEq(reserve.totalBorrowsVariable, 500 ether);
    }

    // Scenario: an existing stable-rate borrower accrues interest, borrows more, and
    // selects variable rate for their resulting debt (`STABLE` -> `VARIABLE`).
    //
    // We verify that the helper removes the user's old principal from stable debt, then
    // moves their complete updated principal (old principal + accrued interest + new borrow)
    // into variable debt. The remaining stable debt and its average rate are preserved.
    function testUpdateReserveTotalBorrowsByRateModeMovesStableDebtToVariableAggregate() external {
        // The user owns 1,000 of the 1,500 DAI stable aggregate at 5%. The other 500 DAI
        // is also at 5%, which makes the starting stable average exactly 5%.
        core.setReserveBorrows(address(token), 1_500 ether, 500 ether);
        core.setReserveCurrentAverageStableBorrowRate(address(token), 5e25);
        core.setReserveRates(address(token), 0, 5e25, 0);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 1_000 ether,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                stableBorrowRate: 5e25,
                lastUpdateTimestamp: 0,
                useAsCollateral: false
            })
        );

        // Arguments after the reserve and user represent:
        // - 1,000 DAI: the user's current stored stable principal;
        // - 20 DAI: interest accrued on that principal since the previous debt update;
        // - 500 DAI: the additional amount the user is borrowing now;
        // - VARIABLE: the user switches their resulting debt from stable to variable rate.
        //
        // Therefore, the helper removes the old 1,000 DAI from stable debt and adds an
        // updated principal of 1,000 + 20 + 500 = 1,520 DAI to variable debt.
        core.exposedUpdateReserveTotalBorrowsByRateMode(
            address(token), user, 1_000 ether, 20 ether, 500 ether, CoreLibrary.InterestRateMode.VARIABLE
        );

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // The old principal leaves the stable aggregate: 1,500 - 1,000 = 500 DAI.
        assertEq(reserve.totalBorrowsStable, 500 ether);

        // The complete updated position enters the variable aggregate:
        // 500 + (1,000 + 20 + 500) = 2,020 DAI.
        assertEq(reserve.totalBorrowsVariable, 2_020 ether);

        // The only stable debt left is the other 500 DAI loan at 5%, so the average is 5%.
        assertEq(reserve.currentAverageStableBorrowRate, 5e25);
    }

    // Scenario: an existing variable-rate borrower accrues interest, borrows more, and
    // selects stable rate for their resulting debt (`VARIABLE` -> `STABLE`).
    //
    // We verify that the helper removes the user's old principal from variable debt, then
    // moves their complete updated principal (old principal + accrued interest + new borrow)
    // into stable debt. The remaining variable debt must be preserved.
    function testUpdateReserveTotalBorrowsByRateModeMovesVariableDebtToStableAggregate() external {
        // The reserve has 1,000 DAI of stable debt at a 5% average and 1,500 DAI of variable debt.
        // The user's 1,000 DAI principal is part of the variable aggregate.
        core.setReserveBorrows(address(token), 1_000 ether, 1_500 ether);
        core.setReserveCurrentAverageStableBorrowRate(address(token), 5e25);
        core.setReserveRates(address(token), 0, 5e25, 0);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 1_000 ether,
                lastVariableBorrowCumulativeIndex: 1,
                originationFee: 0,
                stableBorrowRate: 0,
                lastUpdateTimestamp: 0,
                useAsCollateral: false
            })
        );

        // Arguments after the reserve and user represent:
        // - 1,000 DAI: the user's current stored variable principal;
        // - 20 DAI: interest accrued on that principal since the previous debt update;
        // - 500 DAI: the additional amount the user is borrowing now;
        // - STABLE: the user switches their resulting debt from variable to stable rate.
        //
        // Therefore, the helper removes the old 1,000 DAI from variable debt and adds an
        // updated principal of 1,000 + 20 + 500 = 1,520 DAI to stable debt.
        core.exposedUpdateReserveTotalBorrowsByRateMode(
            address(token), user, 1_000 ether, 20 ether, 500 ether, CoreLibrary.InterestRateMode.STABLE
        );

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // The old variable principal is removed: 1,500 - 1,000 = 500 DAI.
        assertEq(reserve.totalBorrowsVariable, 500 ether);

        // The updated principal is 1,000 + 20 + 500 = 1,520 DAI. It moves into stable debt:
        // 1,000 + 1,520 = 2,520 DAI.
        assertEq(reserve.totalBorrowsStable, 2_520 ether);

        // Existing and newly added stable debt both use 5%, preserving the 5% average.
        assertEq(reserve.currentAverageStableBorrowRate, 5e25);
    }

    // Scenario: an existing variable-rate borrower accrues interest and takes an additional
    // variable-rate loan. Their debt remains in the variable aggregate (`VARIABLE` -> `VARIABLE`).
    //
    // We verify that the helper first removes the user's old variable principal, then adds
    // their complete updated principal (old principal + accrued interest + new borrow)
    // back to variable debt. Stable debt must remain untouched.
    function testUpdateReserveTotalBorrowsByRateModeKeepsVariableDebtInVariableAggregate() external {
        // The user's 1,000 DAI principal is included in the reserve's 5,000 DAI variable debt.
        core.setReserveBorrows(address(token), 1_000 ether, 5_000 ether);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 1_000 ether,
                lastVariableBorrowCumulativeIndex: 1,
                originationFee: 0,
                stableBorrowRate: 0,
                lastUpdateTimestamp: 0,
                useAsCollateral: false
            })
        );

        // Arguments after the reserve and user represent:
        // - 1,000 DAI: the user's current stored variable principal;
        // - 20 DAI: interest accrued on that principal since the previous debt update;
        // - 500 DAI: the additional amount the user is borrowing now;
        // - VARIABLE: the user keeps variable-rate debt after this borrow.
        //
        // Therefore, the helper removes the old 1,000 DAI variable principal and adds an
        // updated variable principal of 1,000 + 20 + 500 = 1,520 DAI.
        core.exposedUpdateReserveTotalBorrowsByRateMode(
            address(token), user, 1_000 ether, 20 ether, 500 ether, CoreLibrary.InterestRateMode.VARIABLE
        );

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // Remove 1,000 DAI, then add 1,520 DAI of updated debt:
        // 5,000 - 1,000 + (1,000 + 20 + 500) = 5,520 DAI.
        assertEq(reserve.totalBorrowsVariable, 5_520 ether);

        // The borrow stays variable, so stable debt remains 1,000 DAI.
        assertEq(reserve.totalBorrowsStable, 1_000 ether);
    }

    // Scenario: the user owns all stable debt and switches to variable rate
    // (`STABLE` -> `VARIABLE`).
    //
    // Removing their old principal empties the stable-debt bucket, so the helper must
    // also reset the reserve's average stable borrow rate to zero.
    function testUpdateReserveTotalBorrowsByRateModeResetsAverageWhenLastStableBorrowerSwitchesToVariable()
        external
    {
        // The user is the only stable borrower: 1,000 DAI at 5%.
        core.setReserveBorrows(address(token), 1_000 ether, 500 ether);
        core.setReserveCurrentAverageStableBorrowRate(address(token), 5e25);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 1_000 ether,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                stableBorrowRate: 5e25,
                lastUpdateTimestamp: 0,
                useAsCollateral: false
            })
        );

        // Remove 1,000 DAI from stable debt, then move the updated 1,520 DAI
        // (1,000 principal + 20 interest + 500 new borrow) into variable debt.
        core.exposedUpdateReserveTotalBorrowsByRateMode(
            address(token), user, 1_000 ether, 20 ether, 500 ether, CoreLibrary.InterestRateMode.VARIABLE
        );

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // The user's old principal was all of the stable debt: 1,000 - 1,000 = 0 DAI.
        assertEq(reserve.totalBorrowsStable, 0);

        // An empty stable-debt bucket has no meaningful weighted average rate.
        assertEq(reserve.currentAverageStableBorrowRate, 0);

        // The old 500 DAI variable debt remains, and the updated 1,520 DAI joins it:
        // 500 + 1,520 = 2,020 DAI.
        assertEq(reserve.totalBorrowsVariable, 2_020 ether);
    }

    // Scenario: the user owns all variable debt and switches to stable rate
    // (`VARIABLE` -> `STABLE`) when the reserve has no pre-existing stable debt.
    //
    // The first resulting stable position defines the reserve's average stable rate.
    function testUpdateReserveTotalBorrowsByRateModeSetsAverageWhenFirstStableBorrowerComesFromVariable()
        external
    {
        core.setReserveBorrows(address(token), 0, 1_000 ether);
        core.setReserveRates(address(token), 0, 7e25, 0);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 1_000 ether,
                lastVariableBorrowCumulativeIndex: 1,
                originationFee: 0,
                stableBorrowRate: 0,
                lastUpdateTimestamp: 0,
                useAsCollateral: false
            })
        );

        // Remove the user's 1,000 DAI variable principal and add their updated 1,520 DAI
        // position to stable debt at the reserve's current stable rate of 7%.
        core.exposedUpdateReserveTotalBorrowsByRateMode(
            address(token), user, 1_000 ether, 20 ether, 500 ether, CoreLibrary.InterestRateMode.STABLE
        );

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // The user owned all variable debt: 1,000 - 1,000 = 0 DAI.
        assertEq(reserve.totalBorrowsVariable, 0);

        // The first stable position is the full updated principal: 1,000 + 20 + 500 = 1,520 DAI.
        assertEq(reserve.totalBorrowsStable, 1_520 ether);

        // With only one stable position, the weighted average equals that position's 7% rate.
        assertEq(reserve.currentAverageStableBorrowRate, 7e25);
    }
    
    function testUpdateReserveTotalBorrowsByRateModeRevertsForNoneNewRateMode() external {
        vm.expectRevert(LendingPoolCore.LendingPoolCore__InvalidBorrowRateMode.selector);

        core.exposedUpdateReserveTotalBorrowsByRateMode(
            address(token), user, 0, 0, 500 ether, CoreLibrary.InterestRateMode.NONE
        );
    }
}
