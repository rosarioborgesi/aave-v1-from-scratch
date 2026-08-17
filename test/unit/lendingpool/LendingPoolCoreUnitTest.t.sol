// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockLendingPoolAddressesProvider} from "../../mocks/MockLendingPoolAddressesProvider.sol";
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

    function setReserveVariableBorrowIndex(address _reserve, uint256 _variableBorrowIndex) external {
        s_reserves[_reserve].lastVariableBorrowCumulativeIndex = _variableBorrowIndex;
    }

    function setReserveLastUpdateTimestamp(address _reserve, uint40 _timestamp) external {
        s_reserves[_reserve].lastUpdateTimestamp = _timestamp;
    }

    function setReserveBorrowingEnabled(address _reserve, bool _borrowingEnabled) external {
        s_reserves[_reserve].borrowingEnabled = _borrowingEnabled;
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

    function exposedUpdateReserveStateOnBorrow(
        address _reserve,
        address _user,
        uint256 _principalBorrowBalance,
        uint256 _balanceIncrease,
        uint256 _amountBorrowed,
        CoreLibrary.InterestRateMode _rateMode
    ) external {
        _updateReserveStateOnBorrow(
            _reserve, _user, _principalBorrowBalance, _balanceIncrease, _amountBorrowed, _rateMode
        );
    }

    function exposedUpdateReserveStateOnRepay(
        address _reserve,
        address _user,
        uint256 _paybackAmountMinusFees,
        uint256 _balanceIncrease
    ) external {
        _updateReserveStateOnRepay(_reserve, _user, _paybackAmountMinusFees, _balanceIncrease);
    }

    function exposedUpdatePrincipalReserveStateOnLiquidation(
        address _reserve,
        address _user,
        uint256 _amountToLiquidate,
        uint256 _balanceIncrease
    ) external {
        _updatePrincipalReserveStateOnLiquidation(_reserve, _user, _amountToLiquidate, _balanceIncrease);
    }

    function exposedUpdateCollateralReserveStateOnLiquidation(address _reserve) external {
        _updateCollateralReserveStateOnLiquidation(_reserve);
    }

    function exposedUpdateUserStateOnLiquidation(
        address _reserve,
        address _user,
        uint256 _amountToLiquidate,
        uint256 _feeLiquidated,
        uint256 _balanceIncrease
    ) external {
        _updateUserStateOnLiquidation(_reserve, _user, _amountToLiquidate, _feeLiquidated, _balanceIncrease);
    }

    function exposedUpdateUserStateOnBorrow(
        address _reserve,
        address _user,
        uint256 _amountBorrowed,
        uint256 _balanceIncrease,
        uint256 _fee,
        CoreLibrary.InterestRateMode _rateMode
    ) external {
        _updateUserStateOnBorrow(_reserve, _user, _amountBorrowed, _balanceIncrease, _fee, _rateMode);
    }

    function exposedUpdateUserStateOnRepay(
        address _reserve,
        address _user,
        uint256 _paybackAmountMinusFees,
        uint256 _originationFeeRepaid,
        uint256 _balanceIncrease,
        bool _repaidWholeLoan
    ) external {
        _updateUserStateOnRepay(
            _reserve, _user, _paybackAmountMinusFees, _originationFeeRepaid, _balanceIncrease, _repaidWholeLoan
        );
    }

    function exposedGetUserCurrentBorrowRate(address _reserve, address _user) external view returns (uint256) {
        return _getUserCurrentBorrowRate(_reserve, _user);
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
    address public lendingPool = makeAddr("lendingPool");
    address public configurator = makeAddr("configurator");
    address public user = makeAddr("user");
    address public attacker = makeAddr("attacker");
    address public aToken = makeAddr("aToken");

    LendingPoolCoreHarness public core;
    MockERC20 public token;
    MockERC20 public secondToken;
    MockReserveInterestRateStrategy public strategy;
    MockLendingPoolAddressesProvider public addressProvider;

    function setUp() external {
        addressProvider = new MockLendingPoolAddressesProvider(lendingPool, configurator);
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
        token.mint(user, 1_000 ether);
        _;
    }

    modifier withLendingPoolEthBalance() {
        vm.deal(lendingPool, 100 ether);
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
        uint256 depositAmount = 100 ether;
        uint256 userInitialTokenBalance = 1_000 ether;

        vm.prank(user);
        token.approve(address(core), depositAmount);

        vm.prank(lendingPool);
        core.transferToReserve(address(token), payable(user), depositAmount);

        assertEq(token.balanceOf(user), userInitialTokenBalance - depositAmount);

        assertEq(token.balanceOf(address(core)), depositAmount);
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
        uint256 depositAmount = 100 ether;

        vm.prank(user);
        token.approve(address(core), depositAmount);

        vm.prank(lendingPool);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__CantSendEthAndTransferErc20.selector);

        core.transferToReserve{value: 1 ether}(address(token), payable(user), depositAmount);
    }

    function testTransferToReserveRevertsWhenNotEnoughEthIsSent() external withLendingPoolEthBalance {
        address ethReserve = EthAddressLib.ethAddress();

        vm.prank(lendingPool);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__MsgValueLessThanAmount.selector);

        core.transferToReserve{value: 0.5 ether}(ethReserve, payable(user), 1 ether);
    }

    function testTransferToReserveRevertsWhenCallerIsNotLendingPool() external {
        uint256 depositAmount = 100 ether;

        vm.prank(attacker);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);

        core.transferToReserve(address(token), payable(user), depositAmount);
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
        uint256 transferAmount = 100 ether;

        vm.prank(attacker);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);

        core.transferToUser(address(token), payable(user), transferAmount);
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
        uint256 depositAmount = 100 ether;
        uint256 liquidityRate = 5e25; // 5%
        uint256 stableBorrowRate = 8e25; // 8%
        uint256 variableBorrowRate = 10e25; // 10%

        strategy.setRates(liquidityRate, stableBorrowRate, variableBorrowRate);

        uint256 updateTimestamp = block.timestamp + 30 days;

        vm.warp(updateTimestamp);

        vm.expectCall(
            address(strategy),
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates, (address(token), depositAmount, 0, 0, 0)
            )
        );

        vm.expectEmit(true, false, false, true);

        emit LendingPoolCore.ReserveUpdated(
            address(token), liquidityRate, stableBorrowRate, variableBorrowRate, RAY, RAY
        );

        vm.prank(lendingPool);
        core.updateStateOnDeposit(address(token), user, depositAmount, false);

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
        uint256 depositAmount = 100 ether;
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

        core.updateStateOnDeposit(address(token), user, depositAmount, false);

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
        uint256 depositAmount = 100 ether;
        strategy.setRates(0, 0, 0);

        vm.prank(lendingPool);

        core.updateStateOnDeposit(address(token), user, depositAmount, true);

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        assertTrue(userData.useAsCollateral);
    }

    function testUpdateStateOnLaterDepositDoesNotEnableCollateral() external withInitReserve(address(token)) {
        uint256 depositAmount = 100 ether;
        strategy.setRates(0, 0, 0);

        vm.prank(lendingPool);

        core.updateStateOnDeposit(address(token), user, depositAmount, false);

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        assertFalse(userData.useAsCollateral);
    }

    function testUpdateStateOnDepositRevertsWhenCallerIsNotLendingPool() external {
        uint256 depositAmount = 100 ether;

        vm.prank(attacker);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);

        core.updateStateOnDeposit(address(token), user, depositAmount, true);
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
        uint256 redeemAmount = 100 ether;

        token.mint(address(core), redeemAmount);
        strategy.setRates(0, 0, 0);

        vm.startPrank(lendingPool);

        core.setUserUseReserveAsCollateral(address(token), user, true);

        core.updateStateOnRedeem(address(token), user, redeemAmount, true);

        vm.stopPrank();

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        assertFalse(userData.useAsCollateral);
    }

    function testUpdateStateOnRedeemKeepsCollateralEnabledWhenUserRedeemedPartially()
        external
        withInitReserve(address(token))
    {
        uint256 redeemAmount = 100 ether;

        token.mint(address(core), redeemAmount);
        strategy.setRates(0, 0, 0);

        vm.startPrank(lendingPool);

        core.setUserUseReserveAsCollateral(address(token), user, true);

        core.updateStateOnRedeem(address(token), user, redeemAmount / 2, false);

        vm.stopPrank();

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        assertTrue(userData.useAsCollateral);
    }

    function testUpdateStateOnRedeemRevertsWhenCallerIsNotLendingPool() external {
        uint256 redeemAmount = 100 ether;

        vm.prank(attacker);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);

        core.updateStateOnRedeem(address(token), user, redeemAmount, true);
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
        // Seed the user's existing variable position: 100 tokens of principal at the initial
        // variable index of 1 ray, a 2-token existing fee, and no stable rate. Collateral usage
        // is deliberately true so the test can show that borrowing preserves this unrelated flag.
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
    function testUpdateReserveTotalBorrowsByRateModeResetsAverageWhenLastStableBorrowerSwitchesToVariable() external {
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
    function testUpdateReserveTotalBorrowsByRateModeSetsAverageWhenFirstStableBorrowerComesFromVariable() external {
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

    /////////////////////////////////////
    //     _updateUserStateOnBorrow     //
    /////////////////////////////////////

    // Scenario: a user with no existing debt takes their first stable-rate borrow. (`NONE` -> `STABLE`)
    // The helper creates the principal and fee balances, stores the reserve's stable rate,
    // keeps the variable index at zero, and records when the position was created.
    function testUpdateUserStateOnBorrowFirstStableBorrowStoresRateAndKeepsVariableIndexZero() external {
        // Use a known stable rate that the helper should copy to the new user position.
        uint256 stableRate = 6e25; // 6% per year in ray (0.06 x 1e27)

        // Configure the reserve with that stable rate.
        core.setReserveRates(address(token), 0, stableRate, 0);

        // Set the time that should be recorded for this first borrow.
        vm.warp(3_000);

        // Create a stable position by borrowing 10 DAI, with no previously accrued interest,
        // and charge a 1 DAI origination fee.
        core.exposedUpdateUserStateOnBorrow(
            address(token), user, 10 ether, 0, 1 ether, CoreLibrary.InterestRateMode.STABLE
        );

        // Read the user position that was created by the borrow.
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // With no previous debt or interest, the new principal is exactly the 10 DAI borrowed.
        assertEq(userData.principalBorrowBalance, 10 ether);
        // With no previous fee, the new 1 DAI fee is the complete fee balance.
        assertEq(userData.originationFee, 1 ether);
        // A stable borrow records the reserve's current stable rate.
        assertEq(userData.stableBorrowRate, stableRate);
        // A stable position does not use a variable borrow index.
        assertEq(userData.lastVariableBorrowCumulativeIndex, 0);
        // The helper records when this first borrow occurred.
        assertEq(userData.lastUpdateTimestamp, 3_000);
    }

    // Scenario: a user takes a variable-rate borrow. The helper records the reserve's current
    // variable index as the starting point for the user's variable debt and clears any stable rate. (`NONE` -> `VARIABLE`)
    function testUpdateUserStateOnBorrowVariableStoresReserveIndexAndClearsStableRate() external {
        // Use a known variable borrow index for the reserve.
        // This is a cumulative index expressed in ray units (1e27). 12e26 equals 1.2e27,
        // meaning the index is 1.2. Compared with the initial index of 1e27, it represents
        // 20% accumulated debt growth.
        uint256 variableBorrowIndex = 12e26;

        // Configure the reserve. The stable rate is irrelevant in this variable-rate scenario.
        core.setReserveRates(address(token), 0, 5e25, 0);
        // Set the index that should be copied into the user's variable-rate position.
        core.setReserveVariableBorrowIndex(address(token), variableBorrowIndex);

        // Set the timestamp that the helper should save as the user's last update time.
        vm.warp(2_000);

        // Borrow 10 DAI at variable rate, recognize 5 DAI of previously calculated interest,
        // and charge a 1 DAI origination fee.
        core.exposedUpdateUserStateOnBorrow(
            address(token), user, 10 ether, 5 ether, 1 ether, CoreLibrary.InterestRateMode.VARIABLE
        );

        // Read the newly created user position after the borrow updated it.
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // The user started with zero debt, so 0 principal + 5 interest + 10 borrowed = 15 DAI.
        assertEq(userData.principalBorrowBalance, 15 ether);
        // The user started with no fees, so the new 1 DAI fee is the complete fee balance.
        assertEq(userData.originationFee, 1 ether);
        // A variable-rate borrow clears the stable-rate field.
        assertEq(userData.stableBorrowRate, 0);
        // A variable-rate borrow stores the reserve's current variable borrow index.
        assertEq(userData.lastVariableBorrowCumulativeIndex, variableBorrowIndex);
        // The helper records when the position was updated.
        assertEq(userData.lastUpdateTimestamp, 2_000);
    }

    // Scenario: a user who already has stable-rate debt takes another stable-rate borrow.
    // The helper refreshes the user's stable rate to the reserve's current rate and keeps the
    // variable index at zero while adding the new debt, accrued interest, and fee. (`STABLE` -> `STABLE`)
    function testUpdateUserStateOnBorrowUpdatesExistingStablePosition() external {
        // Use the reserve's new stable rate, which replaces the user's older stable rate.
        uint256 newStableRate = 6e25; // 6% per year in ray (0.06 x 1e27)
        // Configure the reserve with the rate the user should receive for the new stable borrow.
        core.setReserveRates(address(token), 0, newStableRate, 0);

        // Seed a user position that is already borrowing at a stable rate.
        core.setUserReserveData(
            // Store the position for this borrower.
            user,
            // Store the position for the DAI reserve.
            address(token),
            CoreLibrary.UserReserveData({
                // The user already owes 100 DAI of principal.
                principalBorrowBalance: 100 ether,
                // Stable debt does not use a variable borrow index.
                lastVariableBorrowCumulativeIndex: 0,
                // The user already owes 2 DAI in origination fees.
                originationFee: 2 ether,
                // This previous stable rate should be replaced by the reserve's current rate.
                stableBorrowRate: 5e25,
                // This old timestamp should be replaced after the new borrow.
                lastUpdateTimestamp: 1,
                // This unrelated setting should remain unchanged.
                useAsCollateral: true
            })
        );

        // Set the time the helper should save for this additional stable borrow.
        vm.warp(5_000);
        // Borrow another 10 DAI at stable rate, recognize 5 DAI of accrued interest, and charge a 1 DAI fee.
        core.exposedUpdateUserStateOnBorrow(
            address(token), user, 10 ether, 5 ether, 1 ether, CoreLibrary.InterestRateMode.STABLE
        );

        // Read the updated stable-rate position.
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));
        // Previous principal (100) + accrued interest (5) + new borrow (10) = 115 DAI.
        assertEq(userData.principalBorrowBalance, 115 ether);
        // Previous fee (2) + new fee (1) = 3 DAI.
        assertEq(userData.originationFee, 3 ether);
        // The user receives the reserve's current stable rate, replacing the old 5% rate.
        assertEq(userData.stableBorrowRate, newStableRate);
        // The position remains stable, so its variable index stays zero.
        assertEq(userData.lastVariableBorrowCumulativeIndex, 0);
        // The helper records when the stable position was updated.
        assertEq(userData.lastUpdateTimestamp, 5_000);
        // Borrowing does not change whether this deposit is used as collateral.
        assertTrue(userData.useAsCollateral);
    }

    // Scenario: a user who already has variable-rate debt takes another variable-rate borrow.
    // The helper refreshes the user's variable index to the reserve's current index and keeps the
    // stable rate at zero while adding the new debt, accrued interest, and fee. (`VARIABLE` -> `VARIABLE`)
    function testUpdateUserStateOnBorrowUpdatesExistingVariablePosition() external {
        // Use a known reserve variable index that should replace the user's previous index.
        uint256 newVariableBorrowIndex = 13e26; // the variable debt index has grown by 30% since the start (1e27)
        // Configure the reserve with the index that applies to the updated variable position.
        core.setReserveVariableBorrowIndex(address(token), newVariableBorrowIndex);

        // Seed a user position that is already borrowing at a variable rate.
        core.setUserReserveData(
            // Store the position for this borrower.
            user,
            // Store the position for the DAI reserve.
            address(token),
            CoreLibrary.UserReserveData({
                // The user already owes 100 DAI of principal.
                principalBorrowBalance: 100 ether,
                // This older variable index should be replaced by the reserve's current index.
                lastVariableBorrowCumulativeIndex: 11e26,
                // The user already owes 2 DAI in origination fees.
                originationFee: 2 ether,
                // Variable debt does not use a stable borrow rate.
                stableBorrowRate: 0,
                // This old timestamp should be replaced after the new borrow.
                lastUpdateTimestamp: 1,
                // This unrelated setting should remain unchanged.
                useAsCollateral: true
            })
        );

        // Set the time the helper should save for this additional variable borrow.
        vm.warp(6_000);
        // Borrow another 10 DAI at variable rate, recognize 5 DAI of accrued interest, and charge a 1 DAI fee.
        core.exposedUpdateUserStateOnBorrow(
            address(token), user, 10 ether, 5 ether, 1 ether, CoreLibrary.InterestRateMode.VARIABLE
        );

        // Read the updated variable-rate position.
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));
        // Previous principal (100) + accrued interest (5) + new borrow (10) = 115 DAI.
        assertEq(userData.principalBorrowBalance, 115 ether);
        // Previous fee (2) + new fee (1) = 3 DAI.
        assertEq(userData.originationFee, 3 ether);
        // The position remains variable, so its stable rate stays zero.
        assertEq(userData.stableBorrowRate, 0);
        // The user's previous index is refreshed to the reserve's current variable index.
        assertEq(userData.lastVariableBorrowCumulativeIndex, newVariableBorrowIndex);
        // The helper records when the variable position was updated.
        assertEq(userData.lastUpdateTimestamp, 6_000);
        // Borrowing does not change whether this deposit is used as collateral.
        assertTrue(userData.useAsCollateral);
    }

    // Scenario: a user with an existing variable-rate position takes a new stable-rate borrow. (`VARIABLE` -> `STABLE`)
    // The helper adds accrued interest and the new amount to the user's principal, adds the
    // origination fee, clears the old variable index, stores the reserve's stable rate, and
    // records when the position was updated.
    function testUpdateUserStateOnBorrowStableStoresReserveRateAndClearsVariableIndex() external {
        // Use a 5% stable borrow rate for the reserve.
        uint256 stableRate = 5e25;
        // Use a known block timestamp so we can verify it is stored on the user position.
        uint256 timestamp = 1_000;

        // Configure the reserve with the stable rate that should be assigned to the user.
        core.setReserveRates(address(token), 0, stableRate, 0);
        // Give the reserve a variable index; a stable borrow must not copy this value.
        core.setReserveVariableBorrowIndex(address(token), 2e27);

        // Seed a user position that currently has variable-rate debt.
        core.setUserReserveData(
            // Store the position for this borrower.
            user,
            // Store the position for the DAI reserve.
            address(token),
            CoreLibrary.UserReserveData({
                // The user already owes 100 DAI of principal.
                principalBorrowBalance: 100 ether,
                // A non-zero index identifies the existing variable-rate position.
                lastVariableBorrowCumulativeIndex: RAY,
                // The user already owes 2 DAI in origination fees.
                originationFee: 2 ether,
                // This old stable rate should be replaced by the reserve's current rate.
                stableBorrowRate: 3e25,
                // This old timestamp should be replaced by the current block timestamp.
                lastUpdateTimestamp: 1,
                // This unrelated setting should remain unchanged.
                useAsCollateral: true
            })
        );

        // Set the block time that the helper should save as the user's last update time.
        vm.warp(timestamp);

        // Borrow 10 DAI at stable rate, recognize 5 DAI of accrued interest, and charge a 1 DAI fee.
        core.exposedUpdateUserStateOnBorrow(
            address(token), user, 10 ether, 5 ether, 1 ether, CoreLibrary.InterestRateMode.STABLE
        );

        // Read the user's position after the borrow updated it.
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // Previous principal (100) + accrued interest (5) + new borrow (10) = 115 DAI.
        assertEq(userData.principalBorrowBalance, 115 ether);
        // Previous fee (2) + new fee (1) = 3 DAI.
        assertEq(userData.originationFee, 3 ether);
        // A stable borrow uses the reserve's current stable rate.
        assertEq(userData.stableBorrowRate, stableRate);
        // A stable borrow clears the variable-rate index.
        assertEq(userData.lastVariableBorrowCumulativeIndex, 0);
        // The helper records the timestamp of this update.
        assertEq(userData.lastUpdateTimestamp, timestamp);
        // Borrowing does not change whether this deposit is used as collateral.
        assertTrue(userData.useAsCollateral);
    }

    // Scenario: a user with an existing stable-rate position takes a variable-rate borrow.
    // The helper clears the stable rate, copies the reserve's variable index, and adds the
    // new debt, accrued interest, and fee to the user's existing position. (`STABLE` -> `VARIABLE`)
    function testUpdateUserStateOnBorrowSwitchesStablePositionToVariable() external {
        // Use a known reserve variable index that should become the user's starting index.
        // Compared with the initial index of 1e27, it represents 10% accumulated growth in variable debt.
        uint256 variableBorrowIndex = 11e26;

        // Configure the reserve's variable index.
        core.setReserveVariableBorrowIndex(address(token), variableBorrowIndex);

        // Seed a user position that currently has stable-rate debt.
        core.setUserReserveData(
            // Store the position for this borrower.
            user,
            // Store the position for the DAI reserve.
            address(token),
            CoreLibrary.UserReserveData({
                // The user already owes 100 DAI of principal.
                principalBorrowBalance: 100 ether,
                // Stable debt does not use a variable borrow index.
                lastVariableBorrowCumulativeIndex: 0,
                // The user already owes 2 DAI in origination fees.
                originationFee: 2 ether,
                // A non-zero stable rate identifies the existing stable-rate position.
                stableBorrowRate: 5e25,
                // This old timestamp should be replaced after the new borrow.
                lastUpdateTimestamp: 1,
                // This unrelated setting should remain unchanged.
                useAsCollateral: true
            })
        );

        // Set the time the helper should save for the rate-mode switch.
        vm.warp(4_000);

        // Borrow 10 DAI at variable rate, recognize 5 DAI of accrued interest, and charge a 1 DAI fee.
        core.exposedUpdateUserStateOnBorrow(
            address(token), user, 10 ether, 5 ether, 1 ether, CoreLibrary.InterestRateMode.VARIABLE
        );

        // Read the user position after it changed from stable to variable.
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // Previous principal (100) + accrued interest (5) + new borrow (10) = 115 DAI.
        assertEq(userData.principalBorrowBalance, 115 ether);
        // Previous fee (2) + new fee (1) = 3 DAI.
        assertEq(userData.originationFee, 3 ether);
        // A variable-rate borrow clears the stable rate from the old position.
        assertEq(userData.stableBorrowRate, 0);
        // A variable-rate borrow stores the reserve's current variable index.
        assertEq(userData.lastVariableBorrowCumulativeIndex, variableBorrowIndex);
        // The helper records when the position changed rate modes.
        assertEq(userData.lastUpdateTimestamp, 4_000);
        // Borrowing does not change whether this deposit is used as collateral.
        assertTrue(userData.useAsCollateral);
    }

    function testUpdateUserStateOnBorrowRevertsForNoneRateMode() external {
        vm.expectRevert(LendingPoolCore.LendingPoolCore__InvalidBorrowRateMode.selector);

        core.exposedUpdateUserStateOnBorrow(
            address(token), user, 10 ether, 5 ether, 1 ether, CoreLibrary.InterestRateMode.NONE
        );
    }

    /////////////////////////////////////
    //     _getUserCurrentBorrowRate     //
    /////////////////////////////////////

    // Scenario: a user has no principal debt. Their rate mode is NONE, so the helper returns zero.
    function testGetUserCurrentBorrowRateReturnsZeroWhenUserHasNoDebt() external view {
        // The user has no configured position, meaning their principal borrow balance is zero.
        uint256 currentBorrowRate = core.exposedGetUserCurrentBorrowRate(address(token), user);

        // A user with no debt has no active borrow rate.
        assertEq(currentBorrowRate, 0);
    }

    // Scenario: a user has stable-rate debt. The helper returns the rate stored on the user,
    // rather than the reserve's current stable rate, because their existing debt keeps its own rate.
    function testGetUserCurrentBorrowRateReturnsUsersStableRate() external {
        // Use the rate stored on the user's existing stable borrow.
        uint256 userStableRate = 5e25; // 5%
        // Use a different current reserve stable rate to prove it is not returned for existing stable debt.
        uint256 reserveStableRate = 6e25;
        // Configure the reserve with the different current stable rate.
        core.setReserveRates(address(token), 0, reserveStableRate, 0);

        // Seed a user position with principal debt and a non-zero stable rate.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                stableBorrowRate: userStableRate,
                lastUpdateTimestamp: 0,
                useAsCollateral: false
            })
        );

        // Read the current rate for this stable borrower.
        uint256 currentBorrowRate = core.exposedGetUserCurrentBorrowRate(address(token), user);

        // Stable debt uses the stable rate stored in the user's own position.
        assertEq(currentBorrowRate, userStableRate);
    }

    // Scenario: a user has variable-rate debt. The helper returns the reserve's current variable
    // rate, because variable-rate debt changes as the reserve's variable rate changes.
    function testGetUserCurrentBorrowRateReturnsReserveVariableRate() external {
        // Use the reserve's current variable borrow rate that the helper should return.
        uint256 reserveVariableRate = 4e25; // 4%
        // Configure the reserve with that variable rate.
        core.setReserveRates(address(token), 0, 0, reserveVariableRate);

        // Seed a user position with principal debt but no stable rate, which identifies variable debt.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 0,
                stableBorrowRate: 0,
                lastUpdateTimestamp: 0,
                useAsCollateral: false
            })
        );

        // Read the current rate for this variable borrower.
        uint256 currentBorrowRate = core.exposedGetUserCurrentBorrowRate(address(token), user);

        // Variable debt uses the reserve's current variable rate.
        assertEq(currentBorrowRate, reserveVariableRate);
    }

    //////////////////////////////////////////
    //     getUserCurrentBorrowRateMode     //
    //////////////////////////////////////////

    // Scenario: a user has no principal debt. The function reports that the user has no borrow mode.
    function testGetUserCurrentBorrowRateModeReturnsNoneWhenUserHasNoDebt() external view {
        // An uninitialized user position has a principal borrow balance of zero.
        CoreLibrary.InterestRateMode rateMode = core.getUserCurrentBorrowRateMode(address(token), user);

        // Without debt, the user is in the NONE mode.
        assertEq(uint256(rateMode), uint256(CoreLibrary.InterestRateMode.NONE));
    }

    // Scenario: a user has principal debt and a non-zero stable rate. The function identifies it as stable debt.
    function testGetUserCurrentBorrowRateModeReturnsStableForStableDebt() external {
        // Seed a user position with principal debt and a stable rate.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                // A non-zero principal means the user has an active borrow.
                principalBorrowBalance: 100 ether,
                // Stable debt does not use a variable borrow index.
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                // A non-zero stable rate marks this position as stable-rate debt.
                stableBorrowRate: 5e25,
                lastUpdateTimestamp: 0,
                useAsCollateral: false
            })
        );

        // Read the rate mode inferred from the user's position.
        CoreLibrary.InterestRateMode rateMode = core.getUserCurrentBorrowRateMode(address(token), user);

        // Principal debt plus a stable rate means the user is borrowing at a stable rate.
        assertEq(uint256(rateMode), uint256(CoreLibrary.InterestRateMode.STABLE));
    }

    // Scenario: a user has principal debt but no stable rate. The function identifies it as variable debt.
    function testGetUserCurrentBorrowRateModeReturnsVariableForVariableDebt() external {
        // Seed a user position with principal debt and no stable rate.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                // A non-zero principal means the user has an active borrow.
                principalBorrowBalance: 100 ether,
                // A variable position stores a variable borrow index.
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 0,
                // A zero stable rate marks this position as variable-rate debt.
                stableBorrowRate: 0,
                lastUpdateTimestamp: 0,
                useAsCollateral: false
            })
        );

        // Read the rate mode inferred from the user's position.
        CoreLibrary.InterestRateMode rateMode = core.getUserCurrentBorrowRateMode(address(token), user);

        // Principal debt with no stable rate means the user is borrowing at a variable rate.
        assertEq(uint256(rateMode), uint256(CoreLibrary.InterestRateMode.VARIABLE));
    }

    /////////////////////////////////////////
    //     _updateReserveStateOnBorrow     //
    /////////////////////////////////////////

    // Scenario: a user with no debt takes their first stable-rate borrow. There is no prior
    // interest to accrue, so the helper adds the new debt to the stable aggregate only.
    function testUpdateReserveStateOnBorrowAddsFirstStableBorrowToReserveTotals()
        external
        withInitReserve(address(token))
    {
        // The reserve's current stable rate is used to calculate its stable-debt average.
        uint256 stableBorrowRate = 5e25;
        // Configure the reserve with the stable rate.
        core.setReserveRates(address(token), 0, stableBorrowRate, 0);

        // Update the reserve state for a first 100 DAI stable borrow.
        // The previous principal and accrued interest are both zero because the user had no debt.
        core.exposedUpdateReserveStateOnBorrow(
            address(token), user, 0, 0, 100 ether, CoreLibrary.InterestRateMode.STABLE
        );

        // Read the reserve after the borrow updated its global state.
        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // The full new borrow is stable debt.
        assertEq(reserve.totalBorrowsStable, 100 ether);
        // No variable debt was created.
        assertEq(reserve.totalBorrowsVariable, 0);
        // With one stable borrower, the average equals that borrower's 5% rate.
        assertEq(reserve.currentAverageStableBorrowRate, stableBorrowRate);
        // No time elapsed, so both cumulative indexes remain at their initialized value of 1 ray.
        assertEq(reserve.lastLiquidityCumulativeIndex, RAY);
        assertEq(reserve.lastVariableBorrowCumulativeIndex, RAY);
    }

    // Scenario: a user has 100 DAI of variable debt, then changes to a stable-rate borrow after
    // one year. The helper first accrues the reserve indexes using the old rates, then removes the
    // old variable principal and adds the updated 115 DAI position to stable debt. (`VARIABLE` -> `STABLE`)
    function testUpdateReserveStateOnBorrowAccruesIndexesAndMovesVariableDebtToStable()
        external
        withInitReserve(address(token))
    {
        // The old rates apply while the reserve indexes accrue for the elapsed year.
        uint256 oldLiquidityRate = 5e25;
        uint256 oldVariableBorrowRate = 10e25;
        // The current stable rate applies to the user's updated stable position.
        uint256 stableBorrowRate = 7e25;
        // Configure all reserve rates before time passes.
        core.setReserveRates(address(token), oldLiquidityRate, stableBorrowRate, oldVariableBorrowRate);
        // Store the current time as the reserve's last update so the next accrual period is exactly one year.
        uint256 previousTimestamp = block.timestamp;
        // forge-lint: disable-next-line(unsafe-typecast)
        core.setReserveLastUpdateTimestamp(address(token), uint40(previousTimestamp));

        // The reserve initially has exactly the user's 100 DAI variable debt.
        core.setReserveBorrows(address(token), 0, 100 ether);
        // Mark the user's existing position as variable debt: non-zero principal and zero stable rate.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 0,
                stableBorrowRate: 0,
                lastUpdateTimestamp: 0,
                useAsCollateral: false
            })
        );

        // Allow one full year of interest to accrue before the new borrow action.
        vm.warp(previousTimestamp + 365 days);

        // Change the user's rate mode to stable while borrowing 10 more DAI.
        // The caller has already calculated 5 DAI of interest on the old 100 DAI principal.
        core.exposedUpdateReserveStateOnBorrow(
            address(token), user, 100 ether, 5 ether, 10 ether, CoreLibrary.InterestRateMode.STABLE
        );

        // Read the reserve after indexes and borrow totals were updated.
        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));

        // A 5% liquidity rate for one full year applies linear interest: 1.00 * 1.05 = 1.05 ray.
        assertEq(reserve.lastLiquidityCumulativeIndex, 105e25);
        // A 10% variable rate compounds each second for one year.
        // 10e25 / 31,536,000 = 3,170,979,198,376,458,650 ray units per second.
        // This represents the 10% annual rate split into 31,536,000 one-second periods.
        uint256 ratePerSecond = oldVariableBorrowRate / 365 days;
        // RAY + ratePerSecond represents 1.0000000031709792 of growth for one second.
        // 1.0000000031709792 ^ 31,536,000 ≈ 1.105170918, which is about 10.517% yearly growth.
        uint256 compoundedVariableInterest = (RAY + ratePerSecond).rayPow(365 days);
        // The previous variable borrow index was 1 ray (1.00), so ray multiplication gives:
        // RAY.rayMul(compoundedVariableInterest) = 1.00 * 1.105170918... = 1.105170918... ray.
        assertEq(reserve.lastVariableBorrowCumulativeIndex, RAY.rayMul(compoundedVariableInterest));

        // The helper removes the old 100 DAI variable principal from the variable aggregate.
        assertEq(reserve.totalBorrowsVariable, 0);
        // It adds the updated position: 100 previous principal + 5 interest + 10 borrowed = 115 DAI.
        assertEq(reserve.totalBorrowsStable, 115 ether);
        // The first stable position defines the stable-debt average rate.
        assertEq(reserve.currentAverageStableBorrowRate, stableBorrowRate);
    }

    ////////////////////////////////
    //      updateStateOnBorrow    //
    ////////////////////////////////

    // Scenario: a user with no existing debt takes their first stable-rate borrow. (`NONE` -> `STABLE`)
    //
    // A first stable borrow updates both reserve and user state, reprices the reserve
    // using the pending liquidity removal, and returns the user's stable borrow rate.
    function testUpdateStateOnBorrowFirstStableBorrowUpdatesStateAndReturnsStableRate()
        external
        withInitReserve(address(token))
    {
        // The core core holds 1,000 tokens before the user borrows.
        uint256 availableLiquidity = 1_000 ether;
        // The user takes a first loan of 100 DAI and pays a separate 2 DAI origination fee.
        uint256 amountBorrowed = 100 ether;
        uint256 borrowFee = 2 ether;
        // The strategy will provide these new reserve-wide rates after the borrow is recorded.
        uint256 liquidityRate = 3e25; // 3%
        uint256 stableBorrowRate = 6e25; // 6%
        uint256 variableBorrowRate = 7e25; // 7%
        // Use a known timestamp so the test can verify the reserve and user checkpoints.
        uint256 updateTimestamp = block.timestamp + 30 days;

        // Mint the liquidity now so getReserveAvailableLiquidity() can see the pre-borrow balance.
        token.mint(address(core), availableLiquidity);

        // Stable debt is priced at the rate offered before the strategy reprices the reserve.
        // _updateUserStateOnBorrow copies this existing 6% rate to the user's position. The
        // strategy's rate is only stored later for future stable borrows.
        core.setReserveRates(address(token), 0, stableBorrowRate, 0);

        // Configure the mock strategy response that _updateReserveInterestRatesAndTimestamp()
        // should save after the borrow has updated the debt totals.
        strategy.setRates(liquidityRate, stableBorrowRate, variableBorrowRate);

        // Move time forward so both the reserve and the user's last-update timestamps are
        // meaningful assertions. No old debt or rates exist, so no interest is accrued.
        vm.warp(updateTimestamp);

        // The underlying tokens have not yet been transferred to the borrower. Therefore the
        // core starts from 1,000 DAI of actual liquidity and subtracts the pending 100 DAI
        // transfer before asking the strategy to price the reserve: 1,000 - 100 = 900 DAI.
        // This first stable borrow also creates 100 DAI of stable debt, no variable debt, and
        // a stable-debt average equal to the 6% rate assigned to this only stable position.
        vm.expectCall(
            address(strategy),
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates,
                (address(token), availableLiquidity - amountBorrowed, amountBorrowed, 0, stableBorrowRate)
            )
        );

        // With no prior borrow balances, the indexes remain at their initialized value of one
        // ray. The emitted event contains those unchanged indexes and the strategy's new rates.
        vm.expectEmit(true, false, false, true);
        emit LendingPoolCore.ReserveUpdated(
            address(token), liquidityRate, stableBorrowRate, variableBorrowRate, RAY, RAY
        );

        // Call the complete external borrow state-update flow as the LendingPool. This performs,
        // in order: read the user's existing debt (zero), update reserve totals, store the user's
        // new stable position, then reprice the reserve and return the user's borrow rate.
        vm.prank(lendingPool);
        (uint256 userBorrowRate, uint256 balanceIncrease) = core.updateStateOnBorrow(
            address(token), user, amountBorrowed, borrowFee, CoreLibrary.InterestRateMode.STABLE
        );

        // Read both storage records after the full borrow flow has completed.
        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // This is the user's first borrow, so there is no old principal on which interest could
        // have accrued. The returned borrow rate is the stable rate copied to the user position.
        assertEq(userBorrowRate, stableBorrowRate);
        assertEq(balanceIncrease, 0);

        // The 100 DAI loan belongs entirely to stable debt. Since it is the only stable position,
        // its 6% rate is also the reserve's weighted average stable borrow rate.
        assertEq(reserve.totalBorrowsStable, amountBorrowed);
        assertEq(reserve.totalBorrowsVariable, 0);
        assertEq(reserve.currentAverageStableBorrowRate, stableBorrowRate);

        // The reserve persists the rates returned by the strategy for the next interest period
        // and records the timestamp at which those new rates start applying.
        assertEq(reserve.currentLiquidityRate, liquidityRate);
        assertEq(reserve.currentStableBorrowRate, stableBorrowRate);
        assertEq(reserve.currentVariableBorrowRate, variableBorrowRate);
        assertEq(reserve.lastUpdateTimestamp, updateTimestamp);

        // The user's principal records only the borrowed amount. The origination fee is tracked
        // separately, and a stable position stores its personal stable rate rather than a variable
        // index. Finally, the user receives the same update timestamp as the reserve.
        assertEq(userData.principalBorrowBalance, amountBorrowed);
        assertEq(userData.originationFee, borrowFee);
        assertEq(userData.stableBorrowRate, stableBorrowRate);
        assertEq(userData.lastVariableBorrowCumulativeIndex, 0);
        assertEq(userData.lastUpdateTimestamp, updateTimestamp);
    }

    // A first variable borrow updates both reserve and user state, reprices the reserve
    // using the pending liquidity removal, and returns the reserve's variable borrow rate.
    // Scenario: a user with no existing debt takes their first variable-rate borrow. (`NONE` -> `VARIABLE`)
    function testUpdateStateOnBorrowFirstVariableBorrowUpdatesStateAndReturnsVariableRate()
        external
        withInitReserve(address(token))
    {
        // The core holds 1,000 tokens before the user borrows 100 tokens at a variable rate.
        uint256 availableLiquidity = 1_000 ether;
        uint256 amountBorrowed = 100 ether;
        uint256 borrowFee = 2 ether;
        // The strategy returns these new reserve-wide rates after the borrow is recorded.
        uint256 liquidityRate = 3e25; // 3%
        uint256 stableBorrowRate = 6e25; // 6%
        uint256 variableBorrowRate = 7e25; // 7%
        // Use a known timestamp so the test can verify the reserve and user checkpoints.
        uint256 updateTimestamp = block.timestamp + 30 days;

        // Mint the liquidity now so getReserveAvailableLiquidity() can see the pre-borrow balance.
        token.mint(address(core), availableLiquidity);
        // Configure the mock response that is stored after the new variable debt is accounted for.
        strategy.setRates(liquidityRate, stableBorrowRate, variableBorrowRate);
        // Move time forward. There are no old borrow totals or rates, so no interest accrues.
        vm.warp(updateTimestamp);

        // The underlying transfer happens only after this state update. Therefore the strategy
        // receives 900 tokens of liquidity (1,000 held by the core minus the pending 100-token
        // transfer), 100 tokens of variable debt, and no stable debt or stable-rate average.
        vm.expectCall(
            address(strategy),
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates,
                (address(token), availableLiquidity - amountBorrowed, 0, amountBorrowed, 0)
            )
        );

        // No prior debt means neither cumulative index grows; both remain at the initial 1 ray.
        // The event therefore contains unchanged indexes and the rates returned by the strategy.
        vm.expectEmit(true, false, false, true);
        emit LendingPoolCore.ReserveUpdated(
            address(token), liquidityRate, stableBorrowRate, variableBorrowRate, RAY, RAY
        );

        // Call the complete external borrow state-update flow as the LendingPool. It reads the
        // user's previous debt (zero), records reserve and user variable debt, reprices the
        // reserve, and returns the user's current variable borrow rate.
        vm.prank(lendingPool);
        (uint256 userBorrowRate, uint256 balanceIncrease) = core.updateStateOnBorrow(
            address(token), user, amountBorrowed, borrowFee, CoreLibrary.InterestRateMode.VARIABLE
        );

        // Read both storage records after the full borrow flow has completed.
        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // This is the user's first borrow, so there is no previous principal on which interest
        // could have accrued. Variable borrowers return the reserve's newly stored 7% variable rate.
        assertEq(userBorrowRate, variableBorrowRate);
        assertEq(balanceIncrease, 0);

        // The 100-token loan belongs entirely to variable debt. Unlike stable debt, variable debt
        // has no weighted-average borrow-rate field to update.
        assertEq(reserve.totalBorrowsStable, 0);
        assertEq(reserve.totalBorrowsVariable, amountBorrowed);
        assertEq(reserve.currentAverageStableBorrowRate, 0);

        // The reserve persists the rates returned by the strategy for the next interest period
        // and records the timestamp at which those new rates begin applying.
        assertEq(reserve.currentLiquidityRate, liquidityRate);
        assertEq(reserve.currentStableBorrowRate, stableBorrowRate);
        assertEq(reserve.currentVariableBorrowRate, variableBorrowRate);
        assertEq(reserve.lastUpdateTimestamp, updateTimestamp);

        // The user's principal is the borrowed amount and the fee is stored separately. A variable
        // position has no personal stable rate; instead it saves the reserve's current variable
        // index as its checkpoint for calculating future variable interest.
        assertEq(userData.principalBorrowBalance, amountBorrowed);
        assertEq(userData.originationFee, borrowFee);
        assertEq(userData.stableBorrowRate, 0);
        assertEq(userData.lastVariableBorrowCumulativeIndex, RAY);
        assertEq(userData.lastUpdateTimestamp, updateTimestamp);
    }

    // Scenario: a user with existing stable-rate debt takes another stable-rate borrow. (`STABLE` -> `STABLE`)
    // An additional stable borrow first materializes interest at the user's old personal stable
    // rate, then records the complete updated position at the reserve's currently offered rate.
    function testUpdateStateOnBorrowAdditionalStableBorrowAccruesDebtAndUpdatesStableRate()
        external
        withInitReserve(address(token))
    {
        // The core holds 1,000 tokens before the user's additional 50-token stable borrow.
        // The user earned stable interest at their personal old 5% rate during the elapsed year.
        // The reserve currently offers 6% for the user's complete updated stable position.
        uint256 currentStableBorrowRate = 6e25; // 6%
        // The strategy returns these rates after the borrow. Its 8% stable rate affects future
        // stable borrows, but not this user's position, which is recorded at the current 6% rate.
        uint256 newLiquidityRate = 3e25; // 3%
        uint256 newStableBorrowRate = 8e25; // 8%
        uint256 newVariableBorrowRate = 7e25; // 7%
        uint256 amountBorrowed = 50 ether;
        // Set the update time one year ahead so reserve and user interest accrue for exactly one year.
        uint256 updateTimestamp = block.timestamp + 365 days;

        // Mint the liquidity so the strategy calculates rates from the core's real pre-borrow balance.
        token.mint(address(core), 1_000 ether);

        // Before the new borrow, the reserve has the user's 100-token stable debt. The reserve's
        // stable-debt average is also 5%, because this user is the only stable borrower. Its old
        // liquidity and variable rates are used only while checkpointing the elapsed year.
        core.setReserveRates(address(token), 5e25, currentStableBorrowRate, 10e25);
        core.setReserveBorrows(address(token), 100 ether, 0);
        core.setReserveCurrentAverageStableBorrowRate(address(token), 5e25);
        // forge-lint: disable-next-line(unsafe-typecast)
        core.setReserveLastUpdateTimestamp(address(token), uint40(block.timestamp));

        // Seed the user's old stable position. Stable debt uses the user's personal rate and does
        // not use a variable index. The 2-token fee and collateral flag should both be preserved.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 2 ether,
                stableBorrowRate: 5e25,
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: true
            })
        );

        // Advance one year so the old 100-token stable principal accrues at the user's old 5% rate.
        vm.warp(updateTimestamp);
        strategy.setRates(newLiquidityRate, newStableBorrowRate, newVariableBorrowRate);

        // Calculate the same compounded factor used for a stable borrow balance. The balance
        // increase is the one-year growth on the 100-token stored principal at the personal 5% rate.
        uint256 expectedBalanceIncrease =
            uint256(100 ether).rayMul((RAY + uint256(5e25) / 365 days).rayPow(365 days)) - 100 ether;
        // The complete updated position is old principal + materialized interest + new borrow.
        uint256 expectedPrincipal = 100 ether + expectedBalanceIncrease + amountBorrowed;

        // After removing the user's old stable principal, the helper adds this complete updated
        // principal back at 6%. The strategy therefore receives 950 tokens of pending post-borrow
        // liquidity, the new stable total, no variable debt, and a 6% stable-debt average.
        vm.expectCall(
            address(strategy),
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates,
                (address(token), 1_000 ether - amountBorrowed, expectedPrincipal, 0, currentStableBorrowRate)
            )
        );

        // Run the full borrow flow as the LendingPool. The returned rate is the user's stored
        // stable rate, rather than the strategy's newly returned 8% stable rate.
        vm.prank(lendingPool);
        (uint256 userBorrowRate, uint256 balanceIncrease) =
            core.updateStateOnBorrow(address(token), user, amountBorrowed, 1 ether, CoreLibrary.InterestRateMode.STABLE);

        // Read storage after the reserve and user updates have both completed.
        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // The returned balance increase is the interest accumulated at the old 5% personal rate.
        // The user's new stable rate is 6%, the rate offered before the reserve was repriced.
        assertEq(userBorrowRate, currentStableBorrowRate);
        assertEq(balanceIncrease, expectedBalanceIncrease);

        // The position remains entirely stable. Because it is still the only stable position, the
        // reserve's stable total and weighted average respectively equal its complete principal and 6% rate.
        assertEq(reserve.totalBorrowsStable, expectedPrincipal);
        assertEq(reserve.totalBorrowsVariable, 0);
        assertEq(reserve.currentAverageStableBorrowRate, currentStableBorrowRate);

        // The strategy's rates are stored for the future, independently of the user's 6% stable rate.
        assertEq(reserve.currentLiquidityRate, newLiquidityRate);
        assertEq(reserve.currentStableBorrowRate, newStableBorrowRate);
        assertEq(reserve.currentVariableBorrowRate, newVariableBorrowRate);
        assertEq(reserve.lastUpdateTimestamp, updateTimestamp);

        // The user stores the complete debt, adds the new fee to the old 2-token fee, keeps no
        // variable-index checkpoint, receives the 6% stable rate, and retains collateral usage.
        assertEq(userData.principalBorrowBalance, expectedPrincipal);
        assertEq(userData.originationFee, 3 ether);
        assertEq(userData.stableBorrowRate, currentStableBorrowRate);
        assertEq(userData.lastVariableBorrowCumulativeIndex, 0);
        assertEq(userData.lastUpdateTimestamp, updateTimestamp);
        assertTrue(userData.useAsCollateral);
    }

    // Scenario: a user with existing variable-rate debt borrows more at a variable rate. (`VARIABLE` -> `VARIABLE`)
    // An additional variable borrow materializes the user's accrued debt before
    // adding the new amount, checkpoints the variable index, and returns the new
    // reserve variable rate.
    function testUpdateStateOnBorrowAdditionalVariableBorrowAccruesDebtAndReturnsVariableRate()
        external
        withInitReserve(address(token))
    {
        // The core holds 1,000 tokens before the additional 50-token borrow.
        uint256 availableLiquidity = 1_000 ether;
        // The user's existing variable debt accrues for one year at this old 10% rate.
        uint256 oldVariableBorrowRate = 10e25;
        // The strategy returns these rates after the additional borrow updates reserve debt totals.
        uint256 newLiquidityRate = 3e25;
        uint256 newStableBorrowRate = 6e25;
        uint256 newVariableBorrowRate = 7e25;
        // The user borrows another 50 tokens and pays a 1-token additional origination fee.
        uint256 amountBorrowed = 50 ether;
        uint256 borrowFee = 1 ether;
        // Save the starting time so the next update spans exactly one year.
        uint256 previousTimestamp = block.timestamp;

        // Mint the liquidity so the rate calculation begins with the core's real pre-borrow balance.
        token.mint(address(core), availableLiquidity);

        // The old 5% liquidity rate and 10% variable rate apply only to the elapsed year.
        // The reserve has no stable debt and 100 tokens of variable debt, all owned by this user.
        core.setReserveRates(address(token), 5e25, 0, oldVariableBorrowRate);
        core.setReserveBorrows(address(token), 0, 100 ether);
        // Both the reserve and the user's variable-debt checkpoint begin at the same timestamp.
        // forge-lint: disable-next-line(unsafe-typecast)
        core.setReserveLastUpdateTimestamp(address(token), uint40(previousTimestamp));
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 2 ether,
                stableBorrowRate: 0,
                // forge-lint: disable-next-line(unsafe-typecast)
                lastUpdateTimestamp: uint40(previousTimestamp),
                useAsCollateral: true
            })
        );

        // Let exactly one year pass. updateStateOnBorrow must now materialize the interest that
        // accumulated on the user's stored principal during this elapsed period.
        uint256 updateTimestamp = previousTimestamp + 365 days;
        vm.warp(updateTimestamp);
        // Configure the mock rates that become active after this borrow has completed.
        strategy.setRates(newLiquidityRate, newStableBorrowRate, newVariableBorrowRate);

        // Calculate the same one-year compounded variable index used by the protocol:
        // (1 ray + old annual variable rate / seconds per year) ^ seconds per year.
        uint256 expectedIndex = RAY.rayMul((RAY + oldVariableBorrowRate / 365 days).rayPow(365 days));

        // Scale the old 100-token principal by that new index, then subtract the stored principal
        // to isolate the accrued interest that updateStateOnBorrow returns as balanceIncrease.
        uint256 expectedBalanceIncrease = uint256(100 ether).rayMul(expectedIndex);
        expectedBalanceIncrease -= 100 ether;

        // The updated principal includes the old principal, accrued interest, and the 50-token
        // additional loan. The origination fee is tracked separately from principal.
        uint256 expectedPrincipal = 100 ether + expectedBalanceIncrease + amountBorrowed;

        // Execute the complete borrow update as the LendingPool. It checkpoints reserve indexes
        // with the old rates, materializes the user's debt, updates variable totals, reprices the
        // reserve, and returns the user's current variable borrow rate.
        vm.prank(lendingPool);
        (uint256 userBorrowRate, uint256 balanceIncrease) = core.updateStateOnBorrow(
            address(token), user, amountBorrowed, borrowFee, CoreLibrary.InterestRateMode.VARIABLE
        );

        // Read the reserve-wide and user-specific records after the full state transition.
        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // Variable borrowers use the reserve's current variable rate: the new 7% rate returned
        // by the strategy. The returned interest must match the calculated year's growth.
        assertEq(userBorrowRate, newVariableBorrowRate);
        assertEq(balanceIncrease, expectedBalanceIncrease);

        // The position remains variable, so no stable debt exists. The variable total contains
        // the user's previous principal, materialized interest, and new 50-token borrow. The
        // reserve's checkpointed index matches the index used to calculate that interest.
        assertEq(reserve.totalBorrowsStable, 0);
        assertEq(reserve.totalBorrowsVariable, expectedPrincipal);
        assertEq(reserve.lastVariableBorrowCumulativeIndex, expectedIndex);
        // These strategy rates and timestamp apply to all future reserve interest accrual.
        assertEq(reserve.currentLiquidityRate, newLiquidityRate);
        assertEq(reserve.currentStableBorrowRate, newStableBorrowRate);
        assertEq(reserve.currentVariableBorrowRate, newVariableBorrowRate);
        assertEq(reserve.lastUpdateTimestamp, updateTimestamp);
        // The user stores the fully materialized principal, adds the new fee to the existing
        // 2-token fee, remains variable (zero stable rate), and saves the checkpointed variable
        // index for future interest. Borrowing does not affect collateral usage.
        assertEq(userData.principalBorrowBalance, expectedPrincipal);
        assertEq(userData.originationFee, 3 ether);
        assertEq(userData.stableBorrowRate, 0);
        assertEq(userData.lastVariableBorrowCumulativeIndex, expectedIndex);
        assertEq(userData.lastUpdateTimestamp, updateTimestamp);
        assertTrue(userData.useAsCollateral);
    }

    // Scenario: a user with stable-rate debt borrows at a variable rate. (`STABLE` -> `VARIABLE`)
    // A stable borrower can take a new variable-rate borrow. The entire updated position moves
    // from the stable aggregate to the variable aggregate and begins using the variable index.
    function testUpdateStateOnBorrowSwitchesStableDebtToVariableDebt() external withInitReserve(address(token)) {
        // The core holds enough liquidity for the 50-token borrow that will be priced by the strategy.
        uint256 amountBorrowed = 50 ether;
        // The user's old stable debt is 100 tokens at 6%. They are the only stable borrower.
        uint256 oldStableBorrowRate = 6e25; // 6%
        // The reserve also has 200 tokens of pre-existing variable debt owned by other users.
        // The strategy returns these future reserve-wide rates after the mode switch.
        uint256 newLiquidityRate = 3e25; // 3%
        uint256 newStableBorrowRate = 8e25; // 8%
        // The new variable rate is returned to the user after this mode switch.
        uint256 newVariableBorrowRate = 7e25; // 7%

        // The strategy sees the core's actual pre-borrow balance. The 50 tokens are subtracted
        // as pending liquidity removal when updateStateOnBorrow reprices the reserve.
        token.mint(address(core), 1_000 ether);
        // The current stable rate is needed while removing the old stable position. The strategy
        // supplies future rates only after the user has been converted to variable debt.
        core.setReserveRates(address(token), 5e25, oldStableBorrowRate, 10e25);
        core.setReserveBorrows(address(token), 100 ether, 200 ether);
        core.setReserveCurrentAverageStableBorrowRate(address(token), oldStableBorrowRate);
        // forge-lint: disable-next-line(unsafe-typecast)
        core.setReserveLastUpdateTimestamp(address(token), uint40(block.timestamp));
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 2 ether,
                stableBorrowRate: oldStableBorrowRate,
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: true
            })
        );

        // Let the old 100-token stable position accrue for one year at the user's personal 6%
        // stable rate. The reserve's indexes also checkpoint this same year using their old rates.
        uint256 updateTimestamp = block.timestamp + 365 days;
        vm.warp(updateTimestamp);
        strategy.setRates(newLiquidityRate, newStableBorrowRate, newVariableBorrowRate);

        // The stable balance growth is calculated from the user's personal stable rate, not the
        // reserve's variable rate. It is materialized before the complete position changes mode.
        //
        // ratePerSecond = 6% / 365 days
        // compoundedInterest = (1 ray + ratePerSecond) ^ (365 days)
        // compoundedBalance = 100 tokens * compoundedInterest
        // balanceIncrease = compoundedBalance - 100 tokens
        uint256 expectedBalanceIncrease =
            uint256(100 ether).rayMul((RAY + oldStableBorrowRate / 365 days).rayPow(365 days)) - 100 ether;
        uint256 expectedUserPrincipal = 100 ether + expectedBalanceIncrease + amountBorrowed;
        // Pre-existing variable borrowers cause the reserve's variable index to compound at 10%.
        //
        // ratePerSecond = 10% / 365 days
        // compoundedInterest = (1 ray + ratePerSecond) ^ (365 days)
        // newVariableBorrowIndex = previousVariableBorrowIndex * compoundedInterest
        //                         = 1 ray * compoundedInterest
        uint256 expectedVariableBorrowIndex = RAY.rayMul((RAY + uint256(10e25) / 365 days).rayPow(365 days));

        // First remove the user's old 100-token stable principal. Then add their complete
        // variable position: old principal + accrued stable interest + new borrow. The strategy
        // consequently receives 950 liquidity, no stable debt, and all resulting variable debt.
        vm.expectCall(
            address(strategy),
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates,
                (address(token), 1_000 ether - amountBorrowed, 0, 200 ether + expectedUserPrincipal, 0)
            )
        );

        // Call the full external borrow update. It materializes the year's stable interest before
        // moving the user's complete debt position into variable-rate accounting.
        vm.prank(lendingPool);
        (uint256 userBorrowRate, uint256 balanceIncrease) = core.updateStateOnBorrow(
            address(token), user, amountBorrowed, 1 ether, CoreLibrary.InterestRateMode.VARIABLE
        );

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // A variable borrower returns the reserve's newly stored variable rate, not their old
        // personal stable rate. The returned balance increase is the year's old stable-rate interest.
        assertEq(userBorrowRate, newVariableBorrowRate);
        assertEq(balanceIncrease, expectedBalanceIncrease);

        // The user was the only stable borrower, so stable debt and its average both become zero.
        // Their complete updated position joins the other 200 tokens of variable debt.
        assertEq(reserve.totalBorrowsStable, 0);
        assertEq(reserve.currentAverageStableBorrowRate, 0);
        assertEq(reserve.totalBorrowsVariable, 200 ether + expectedUserPrincipal);

        assertEq(reserve.lastVariableBorrowCumulativeIndex, expectedVariableBorrowIndex);
        assertEq(reserve.currentLiquidityRate, newLiquidityRate);
        assertEq(reserve.currentStableBorrowRate, newStableBorrowRate);
        assertEq(reserve.currentVariableBorrowRate, newVariableBorrowRate);
        assertEq(reserve.lastUpdateTimestamp, updateTimestamp);

        // The user's complete debt now uses variable-rate accounting: the stable rate is cleared
        // and the newly checkpointed reserve variable index becomes their future-interest checkpoint.
        assertEq(userData.principalBorrowBalance, expectedUserPrincipal);
        assertEq(userData.originationFee, 3 ether);
        assertEq(userData.stableBorrowRate, 0);
        assertEq(userData.lastVariableBorrowCumulativeIndex, expectedVariableBorrowIndex);
        assertEq(userData.lastUpdateTimestamp, updateTimestamp);

        assertTrue(userData.useAsCollateral);
    }

    // A variable borrower can take a new stable-rate borrow. The entire updated position moves
    // from the variable aggregate to the stable aggregate and receives the current stable rate.
    // Scenario: a user with variable-rate debt borrows at a stable rate. (`VARIABLE` -> `STABLE`)
    function testUpdateStateOnBorrowSwitchesVariableDebtToStableDebt() external withInitReserve(address(token)) {
        uint256 amountBorrowed = 50 ether;
        // The reserve already has 200 tokens of stable debt from other users, priced at a 7% average.
        // The current 6% reserve stable rate is assigned to the user's complete updated position.
        uint256 currentStableBorrowRate = 6e25; // 6%
        // The user's existing variable debt and the reserve's variable index accrue at this old rate.
        uint256 oldVariableBorrowRate = 10e25; // 10%

        token.mint(address(core), 1_000 ether);
        // The user owns all 100 tokens of variable debt. The separate 200-token stable position
        // remains in the stable bucket when the user's updated debt later joins it.
        core.setReserveRates(address(token), 5e25, currentStableBorrowRate, oldVariableBorrowRate);
        core.setReserveBorrows(address(token), 200 ether, 100 ether);
        core.setReserveCurrentAverageStableBorrowRate(address(token), 7e25);
        // forge-lint: disable-next-line(unsafe-typecast)
        core.setReserveLastUpdateTimestamp(address(token), uint40(block.timestamp));
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 2 ether,
                stableBorrowRate: 0,
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: true
            })
        );

        // Advance one year so the user's stored variable principal grows using the old 10% variable
        // rate. updateStateOnBorrow materializes this accrued interest before changing rate modes.
        uint256 updateTimestamp = block.timestamp + 365 days;
        vm.warp(updateTimestamp);

        // ratePerSecond = 10% / 365 days
        // compoundedInterest = (1 ray + ratePerSecond) ^ (365 days)
        // compoundedBalance = 100 tokens * compoundedInterest
        // balanceIncrease = compoundedBalance - 100 tokens
        uint256 expectedBalanceIncrease =
            uint256(100 ether).rayMul((RAY + oldVariableBorrowRate / 365 days).rayPow(365 days)) - 100 ether;

        // The complete updated stable position contains old variable principal, its materialized
        // variable interest, and the 50-token new stable borrow. This position then combines with
        // the other 200 stable tokens at the reserve's current 6% stable rate.
        uint256 updatedUserPrincipal = 100 ether + expectedBalanceIncrease + amountBorrowed;
        uint256 expectedStableDebt = 200 ether + updatedUserPrincipal;
        // The reserve's average stable rate is the debt-weighted average of both stable positions:
        //
        // weightedOtherDebt = 200 tokens * 7%
        // weightedUserDebt = updatedUserPrincipal * 6%
        // averageStableRate = (weightedOtherDebt + weightedUserDebt) / expectedStableDebt
        //
        // Debt amounts are stored in wad precision, while rates use ray precision. wadToRay()
        // converts the amounts before rayMul()/rayDiv() perform the protocol's rounded ray math.
        uint256 expectedAverageStableRate = (uint256(200 ether).wadToRay().rayMul(7e25)
                + updatedUserPrincipal.wadToRay().rayMul(currentStableBorrowRate))
        .rayDiv(expectedStableDebt.wadToRay());
        // The strategy returns these rates after the mode switch for future reserve accrual.
        // This scope lets the setup-only values leave the stack before the borrow call below.
        {
            uint256 newLiquidityRate = 3e25; // 3%
            uint256 newStableBorrowRate = 8e25; // 8%
            uint256 newVariableBorrowRate = 7e25; // 7%
            strategy.setRates(newLiquidityRate, newStableBorrowRate, newVariableBorrowRate);
        }

        // After removing the user's old 100-token variable principal, the strategy sees 950
        // tokens of available liquidity, 350 stable debt, no variable debt, and the new average.
        vm.expectCall(
            address(strategy),
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates,
                (address(token), 1_000 ether - amountBorrowed, expectedStableDebt, 0, expectedAverageStableRate)
            )
        );

        // The mode switch moves the user's old variable principal, its accrued variable interest,
        // and the 50-token borrow into stable debt. The 1-token new fee remains separate from principal.
        vm.prank(lendingPool);
        (uint256 userBorrowRate, uint256 balanceIncrease) =
            core.updateStateOnBorrow(address(token), user, amountBorrowed, 1 ether, CoreLibrary.InterestRateMode.STABLE);

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // Stable borrowers return their personal stored stable rate: the 6% rate available before
        // the strategy repriced the reserve to 8% for future stable borrowers. The returned balance
        // increase is the variable interest accrued during the year before the mode switch.
        //
        // ratePerSecond = 10% / 365 days
        // compoundedInterest = (1 ray + ratePerSecond) ^ (365 days)
        // newVariableBorrowIndex = previousVariableBorrowIndex * compoundedInterest
        //                         = 1 ray * compoundedInterest
        uint256 expectedVariableBorrowIndex = RAY.rayMul((RAY + oldVariableBorrowRate / 365 days).rayPow(365 days));
        assertEq(userBorrowRate, currentStableBorrowRate);
        assertEq(balanceIncrease, expectedBalanceIncrease);

        // The old variable bucket is empty. The stable bucket contains the other users' debt plus
        // the user's 150-token updated position, with the expected weighted stable-rate average.
        assertEq(reserve.totalBorrowsVariable, 0);
        assertEq(reserve.totalBorrowsStable, expectedStableDebt);
        assertEq(reserve.currentAverageStableBorrowRate, expectedAverageStableRate);
        assertEq(reserve.lastVariableBorrowCumulativeIndex, expectedVariableBorrowIndex);

        assertEq(reserve.currentLiquidityRate, 3e25);
        assertEq(reserve.currentStableBorrowRate, 8e25);
        assertEq(reserve.currentVariableBorrowRate, 7e25);
        assertEq(reserve.lastUpdateTimestamp, updateTimestamp);

        // The user now has stable-rate accounting: the variable index is cleared, their complete
        // principal is stored, the fee increases from 2 to 3 tokens, and collateral usage remains set.
        assertEq(userData.principalBorrowBalance, updatedUserPrincipal);
        assertEq(userData.originationFee, 3 ether);
        assertEq(userData.stableBorrowRate, currentStableBorrowRate);
        assertEq(userData.lastVariableBorrowCumulativeIndex, 0);
        assertEq(userData.lastUpdateTimestamp, updateTimestamp);
        assertTrue(userData.useAsCollateral);
    }

    function testUpdateStateOnBorrowRevertsWhenCallerIsNotLendingPool() external {
        vm.prank(attacker);
        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);

        core.updateStateOnBorrow(address(token), user, 1 ether, 0, CoreLibrary.InterestRateMode.STABLE);
    }

    ////////////////////////////////
    // isReserveBorrowingEnabled  //
    ////////////////////////////////

    // An initialized reserve begins with borrowing disabled. The getter must return the borrowing
    // flag stored in the reserve configuration after it is enabled.
    function testIsReserveBorrowingEnabledReturnsStoredBorrowingFlag() external withInitReserve(address(token)) {
        // initReserve does not enable borrowing, so the stored flag is false initially.
        assertFalse(core.isReserveBorrowingEnabled(address(token)));

        // Set the harness's reserve configuration to the state a configurator would create when
        // enabling borrowing, then verify the getter exposes that stored value.
        core.setReserveBorrowingEnabled(address(token), true);

        assertTrue(core.isReserveBorrowingEnabled(address(token)));
    }

    ////////////////////////////////
    //     getReserveDecimals      //
    ////////////////////////////////

    // The getter returns the decimal precision stored in the reserve configuration.
    function testGetReserveDecimalsReturnsStoredDecimals() external {
        uint256 decimals = 6;

        // Write a USDC-like decimal value directly through the harness so this test covers only
        // getReserveDecimals reading reserve storage, without depending on reserve initialization.
        vm.prank(configurator);
        core.setReserveDecimals(address(token), decimals);

        assertEq(core.getReserveDecimals(address(token)), decimals);
    }

    ////////////////////////////////
    //    getUserBorrowBalances    //
    ////////////////////////////////

    // A user without stored principal has no active debt, so all three returned balances are zero.
    function testGetUserBorrowBalancesReturnsZerosWhenUserHasNoDebt() external view {
        (uint256 principal, uint256 compoundedBalance, uint256 balanceIncrease) =
            core.getUserBorrowBalances(address(token), user);

        assertEq(principal, 0);
        assertEq(compoundedBalance, 0);
        assertEq(balanceIncrease, 0);
    }

    // Stable debt compounds at the user's personal stable rate from the user's last-update timestamp.
    function testGetUserBorrowBalancesReturnsCompoundedStableDebt() external {
        uint256 principalBorrowBalance = 100 ether;
        uint256 stableBorrowRate = 5e25; // 5%
        uint256 previousTimestamp = block.timestamp;

        // Seed a stable position directly so this getter test does not depend on a borrow action.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: principalBorrowBalance,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                stableBorrowRate: stableBorrowRate,
                // forge-lint: disable-next-line(unsafe-typecast)
                lastUpdateTimestamp: uint40(previousTimestamp),
                useAsCollateral: false
            })
        );

        // Allow exactly one year of interest to accrue at the user's personal 5% stable rate.
        vm.warp(previousTimestamp + 365 days);

        // ratePerSecond = 5% / 365 days
        // compoundedInterest = (1 ray + ratePerSecond) ^ (365 days)
        // compoundedBalance = 100 tokens * compoundedInterest
        uint256 compoundedInterest = (RAY + stableBorrowRate / 365 days).rayPow(365 days);
        // principalBorrowBalance is stored in wad precision (1e18), while compoundedInterest is
        // expressed in ray precision (1e27). Convert the principal to ray, multiply the two ray
        // values with rayMul(), then convert the resulting token balance back to wad precision.
        uint256 expectedCompoundedBalance = principalBorrowBalance.wadToRay().rayMul(compoundedInterest).rayToWad();

        (uint256 principal, uint256 compoundedBalance, uint256 balanceIncrease) =
            core.getUserBorrowBalances(address(token), user);

        assertEq(principal, principalBorrowBalance);
        assertEq(compoundedBalance, expectedCompoundedBalance);
        assertEq(balanceIncrease, expectedCompoundedBalance - principalBorrowBalance);
    }

    // Variable debt compounds from the user's saved variable-index checkpoint to the reserve's
    // current index, including the growth since the reserve's last update.
    function testGetUserBorrowBalancesReturnsCompoundedVariableDebt() external {
        uint256 principalBorrowBalance = 100 ether;
        uint256 variableBorrowRate = 10e25; // 10%
        uint256 previousTimestamp = block.timestamp;

        // The user starts at the initial variable index of one ray. Configure the reserve directly
        // so this getter test remains independent from reserve initialization and borrow updates.
        core.setReserveVariableBorrowIndex(address(token), RAY);
        core.setReserveRates(address(token), 0, 0, variableBorrowRate);
        // forge-lint: disable-next-line(unsafe-typecast)
        core.setReserveLastUpdateTimestamp(address(token), uint40(previousTimestamp));
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: principalBorrowBalance,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 0,
                stableBorrowRate: 0,
                // forge-lint: disable-next-line(unsafe-typecast)
                lastUpdateTimestamp: uint40(previousTimestamp),
                useAsCollateral: false
            })
        );

        // Let one year pass. The getter calculates the new reserve index in memory; it does not
        // write that index to storage because getUserBorrowBalances is a view function.
        vm.warp(previousTimestamp + 365 days);

        // ratePerSecond = 10% / 365 days
        // compoundedInterest = (1 ray + ratePerSecond) ^ (365 days)
        // currentReserveIndex = 1 ray * compoundedInterest
        // userGrowthFactor = currentReserveIndex / 1 ray = compoundedInterest
        uint256 compoundedInterest = (RAY + variableBorrowRate / 365 days).rayPow(365 days);
        // principalBorrowBalance is stored in wad precision (1e18), while compoundedInterest is
        // expressed in ray precision (1e27). Convert the principal to ray, multiply the two ray
        // values with rayMul(), then convert the resulting token balance back to wad precision.
        uint256 expectedCompoundedBalance = principalBorrowBalance.wadToRay().rayMul(compoundedInterest).rayToWad();

        (uint256 principal, uint256 compoundedBalance, uint256 balanceIncrease) =
            core.getUserBorrowBalances(address(token), user);

        assertEq(principal, principalBorrowBalance);
        assertEq(compoundedBalance, expectedCompoundedBalance);
        assertEq(balanceIncrease, expectedCompoundedBalance - principalBorrowBalance);
    }

    ///////////////////////////////////////
    //  isUserAllowedToBorrowAtStable     //
    ///////////////////////////////////////

    // Stable borrowing is never allowed when the reserve has stable-rate borrowing disabled.
    function testIsUserAllowedToBorrowAtStableReturnsFalseWhenStableBorrowingIsDisabled() external view {
        assertFalse(core.isUserAllowedToBorrowAtStable(address(token), user, 1 ether));
    }

    // Once stable borrowing is enabled, a user who is not using this reserve as collateral passes
    // the same-asset restriction without needing to read an aToken balance.
    function testIsUserAllowedToBorrowAtStableReturnsTrueWhenUserDoesNotUseReserveAsCollateral() external {
        vm.prank(configurator);
        core.enableReserveStableBorrowRate(address(token));
        core.setReserveConfiguration(address(token), 0, 0, true);

        assertTrue(core.isUserAllowedToBorrowAtStable(address(token), user, 1 ether));
    }

    // The same-asset restriction does not apply when this reserve is not configured as collateral,
    // even when the user has marked their position as collateral.
    function testIsUserAllowedToBorrowAtStableReturnsTrueWhenReserveCannotBeUsedAsCollateral() external {
        vm.prank(configurator);
        core.enableReserveStableBorrowRate(address(token));
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 0,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                stableBorrowRate: 0,
                lastUpdateTimestamp: 0,
                useAsCollateral: true
            })
        );

        // usageAsCollateralEnabled is false, so the function returns true before reading aToken.
        core.setReserveConfiguration(address(token), 0, 0, false);

        assertTrue(core.isUserAllowedToBorrowAtStable(address(token), user, 1 ether));
    }

    // When the user uses this collateral-enabled reserve as collateral, a same-asset stable borrow
    // must exceed the user's current underlying balance. Equal or smaller amounts are rejected.
    function testIsUserAllowedToBorrowAtStableRequiresBorrowToExceedSameAssetCollateralBalance() external {
        MockERC20 mockAToken = _initReserveWithMockAToken(address(token));
        uint256 userUnderlyingBalance = 100 ether;

        vm.prank(configurator);
        core.enableReserveStableBorrowRate(address(token));
        core.setReserveConfiguration(address(token), 0, 0, true);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 0,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                stableBorrowRate: 0,
                lastUpdateTimestamp: 0,
                useAsCollateral: true
            })
        );

        // The aToken balance represents the user's underlying deposit balance used by this check.
        mockAToken.mint(user, userUnderlyingBalance);

        // 100 <= 100: borrowing the same collateral asset at stable rate is not allowed.
        assertFalse(core.isUserAllowedToBorrowAtStable(address(token), user, userUnderlyingBalance));
        // 101 > 100: this specific same-asset stable-borrow restriction passes.
        assertTrue(core.isUserAllowedToBorrowAtStable(address(token), user, userUnderlyingBalance + 1));
    }

    ///////////////////////////////////////////////
    //  transferToFeeCollectionAddress            //
    ///////////////////////////////////////////////

    function testTransferToFeeCollectionAddressTransfersERC20FromUserToDestination() external withUserTokenBalance {
        address destination = makeAddr("feeCollector");
        uint256 feeAmount = 10 ether;
        uint256 userInitialTokenBalance = 1_000 ether;

        vm.prank(user);
        token.approve(address(core), feeAmount);

        vm.prank(lendingPool);
        core.transferToFeeCollectionAddress(address(token), user, feeAmount, destination);

        assertEq(token.balanceOf(user), userInitialTokenBalance - feeAmount);
        assertEq(token.balanceOf(destination), feeAmount);
        assertEq(token.balanceOf(address(core)), 0);
    }

    function testTransferToFeeCollectionAddressRevertsWhenERC20TransferIncludesEth() external {
        vm.deal(lendingPool, 1 ether);

        vm.prank(lendingPool);
        vm.expectRevert(LendingPoolCore.LendingPoolCore__CannotSendEthAlongWithErc20Transfer.selector);
        core.transferToFeeCollectionAddress{value: 1 ether}(address(token), user, 1 ether, makeAddr("feeCollector"));
    }

    function testTransferToFeeCollectionAddressTransfersExactEthToDestination() external withLendingPoolEthBalance {
        address destination = makeAddr("feeCollector");
        uint256 feeAmount = 1 ether;

        vm.prank(lendingPool);
        core.transferToFeeCollectionAddress{value: feeAmount}(EthAddressLib.ethAddress(), user, feeAmount, destination);

        assertEq(destination.balance, feeAmount);
        assertEq(address(core).balance, 0);
    }

    function testTransferToFeeCollectionAddressRevertsWhenEthValueIsInsufficient() external withLendingPoolEthBalance {
        uint256 feeAmount = 1 ether;

        vm.prank(lendingPool);
        vm.expectRevert(LendingPoolCore.LendingPoolCore__AmountAndValueSentDoNotMatch.selector);
        core.transferToFeeCollectionAddress{value: 0.5 ether}(
            EthAddressLib.ethAddress(), user, feeAmount, makeAddr("feeCollector")
        );
    }

    function testTransferToFeeCollectionAddressRevertsWhenEthDestinationRejectsPayment()
        external
        withLendingPoolEthBalance
    {
        RejectEthReceiver receiver = new RejectEthReceiver();
        uint256 feeAmount = 1 ether;

        vm.prank(lendingPool);
        vm.expectRevert(
            abi.encodeWithSelector(
                LendingPoolCore.LendingPoolCore__EthTransferFailed.selector, address(receiver), feeAmount
            )
        );
        core.transferToFeeCollectionAddress{value: feeAmount}(
            EthAddressLib.ethAddress(), user, feeAmount, address(receiver)
        );
    }

    function testTransferToFeeCollectionAddressRetainsExcessEth() external withLendingPoolEthBalance {
        address destination = makeAddr("feeCollector");
        uint256 feeAmount = 1 ether;
        uint256 valueSent = 1.2 ether;

        vm.prank(lendingPool);
        core.transferToFeeCollectionAddress{value: valueSent}(EthAddressLib.ethAddress(), user, feeAmount, destination);

        assertEq(destination.balance, feeAmount);
        assertEq(address(core).balance, valueSent - feeAmount);
    }

    function testTransferToFeeCollectionAddressRevertsWhenCallerIsNotLendingPool() external {
        vm.prank(attacker);
        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);
        core.transferToFeeCollectionAddress(address(token), user, 1 ether, makeAddr("feeCollector"));
    }

    ////////////////////////////////////////////
    //  _updateReserveStateOnRepay             //
    ////////////////////////////////////////////

    // This test verifies the reserve-level accounting for a repayment of a variable-rate loan.
    function testUpdateReserveStateOnRepayUpdatesVariableDebtAndCheckpointsIndexes()
        external
        withInitReserve(address(token))
    {
        uint256 oldLiquidityRate = 5e25;
        uint256 oldVariableBorrowRate = 10e25;
        uint256 previousTimestamp = block.timestamp;
        uint256 balanceIncrease = 10 ether; // accrued interest since the user's prior update
        uint256 repaymentAmount = 30 ether; // repayment toward debt

        // User has a variable loan (stableBorrowRate = 0)
        core.setReserveRates(address(token), oldLiquidityRate, 0, oldVariableBorrowRate);
        // Reserve variable debt: 100 ether
        // Reserve stable debt: 50 ether
        core.setReserveBorrows(address(token), 50 ether, 100 ether);
        core.setReserveCurrentAverageStableBorrowRate(address(token), 8e25);
        // forge-lint: disable-next-line(unsafe-typecast)
        core.setReserveLastUpdateTimestamp(address(token), uint40(previousTimestamp));
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 0,
                stableBorrowRate: 0,
                // forge-lint: disable-next-line(unsafe-typecast)
                lastUpdateTimestamp: uint40(previousTimestamp),
                useAsCollateral: false
            })
        );

        // One year passes at
        // - 5% liquidity rate
        // - 10% variable borrow rate
        vm.warp(previousTimestamp + 365 days);
        core.exposedUpdateReserveStateOnRepay(address(token), user, repaymentAmount, balanceIncrease);
        // Calling _updateReserveStateOnRepay(...) should do 2 things
        // 1. Update variable debt:
        //    -  new variable debt = old variable debt + accrued interest - repayment
        //                         = 100 + 10 - 30
        //                         = 80 ether
        //    -  Stable debt remains 50 ether, and its average stable rate remains unchanged because the
        //          repayment was variable-rate
        // 2. Checkpoint the reserve's interest indexes at the current timestamp:
        //    - `lastLiquidityCumulativeIndex` rises from RAY to RAY + oldLiquidityRate because interest uses
        //          a linea one-year calculation
        //    - `lastVariableBorrowCumulativeIndex` compounds for a year at the variable rate

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        uint256 expectedVariableIndex = RAY.rayMul((RAY + oldVariableBorrowRate / 365 days).rayPow(365 days));

        // new variable debt = old variable debt + accrued interest - repayment
        //                   = 100 + 10 - 30
        //                   = 80 ether
        assertEq(reserve.totalBorrowsVariable, 100 ether + balanceIncrease - repaymentAmount);
        // Stable borrow rate is unchanged
        assertEq(reserve.totalBorrowsStable, 50 ether);
        // Average stable borrow rate doesn't change because the repayment was variable-rate
        assertEq(reserve.currentAverageStableBorrowRate, 8e25);
        // newLiquidityIndex = previousLiquidityIndex * (RAY + oldLiquidityRate * elapsedTime / 365 days)
        //                   = RAY * (RAY + oldLiquidityRate * 365 days / 365 days)
        //                   = RAY + oldLiquidityRate
        assertEq(reserve.lastLiquidityCumulativeIndex, RAY + oldLiquidityRate);
        // ratePerSecond = oldVariableBorrowRate / 365 days
        // compoundedInterest = (RAY + ratePerSecond) ^ 365 days
        // newVariableBorrowIndex = previousVariableBorrowIndex * compoundedInterest
        //                         = RAY.rayMul((RAY + oldVariableBorrowRate / 365 days).rayPow(365 days))
        //                         = RAY.rayMul((RAY + 10e25 / 31,536,000).rayPow(31,536,000))
        assertEq(reserve.lastVariableBorrowCumulativeIndex, expectedVariableIndex);
    }

    // This test verifies that repaying a stable-rate loan updates both:
    //      - the reserve’s total stable debt;
    //      - the weighted-average stable borrow rate across all remaining stable borrowers.
    function testUpdateReserveStateOnRepayUpdatesStableDebtAndWeightedAverageRate()
        external
        withInitReserve(address(token))
    {
        // User borrows 100 DAI at 5% stable rate
        uint256 userStableRate = 5e25;
        // Other borrower borrows 100 DAI at 10% stable rate
        uint256 otherBorrowerStableRate = 10e25;
        uint256 userPrincipal = 100 ether;
        uint256 otherBorrowerPrincipal = 100 ether;
        uint256 balanceIncrease = 10 ether;
        uint256 repaymentAmount = 40 ether;
        // The reserve starts with 200 DAI (100 + 100)
        uint256 initialTotalStableDebt = userPrincipal + otherBorrowerPrincipal;
        // The average rate is (100 x 5% + 100 x 10%) / 200 = 7.5%
        uint256 initialAverageStableRate = (userStableRate + otherBorrowerStableRate) / 2;

        core.setReserveBorrows(address(token), initialTotalStableDebt, 0);
        core.setReserveCurrentAverageStableBorrowRate(address(token), initialAverageStableRate);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: userPrincipal,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                stableBorrowRate: userStableRate,
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: false
            })
        );
        // The repayment operation says the user has accrued 10 DAI interest and repays 40 DAI.
        // The core processes these as two stable-debt updates:
        // 1. Add the 10 DAI accrued interest to total stable debt, weighted at the user’s 5% rate.
        //      - User’s effective debt: 100 + 10 = 110 DAI
        // 2. Subtract the 40 DAI repayment, also weighted at 5%.
        //      - Remaining effective debt: 110 - 40 = 70 DAI
        core.exposedUpdateReserveStateOnRepay(address(token), user, repaymentAmount, balanceIncrease);

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        uint256 expectedStableDebt = initialTotalStableDebt + balanceIncrease - repaymentAmount; // 200 + 10 - 40 = 170 DAI

        // expectedAverageStableRate = (70 x 5% + 100 x 10%) / 170 = 13.5 / 170 ≈ 7.941176%
        uint256 expectedAverageStableRate = (uint256(70 ether).wadToRay().rayMul(userStableRate)
                + otherBorrowerPrincipal.wadToRay().rayMul(otherBorrowerStableRate))
        .rayDiv(expectedStableDebt.wadToRay());

        assertEq(reserve.totalBorrowsStable, expectedStableDebt);
        assertEq(reserve.totalBorrowsVariable, 0);
        assertEq(reserve.currentAverageStableBorrowRate, expectedAverageStableRate);
    }

    // This test verifies that repaying the reserve's last stable-rate loan clears
    // both the total stable debt and its average stable borrow rate.
    function testUpdateReserveStateOnRepayResetsAverageStableRateWhenLastStableDebtIsRepaid()
        external
        withInitReserve(address(token))
    {
        uint256 stableRate = 5e25; // 5%
        uint256 principal = 100 ether;

        // The modeled reserve contains exactly one stable loan: 100 DAI at 5%.
        // With only that loan outstanding, the reserve's weighted-average stable
        // rate is also 5%.
        core.setReserveBorrows(address(token), principal, 0);
        core.setReserveCurrentAverageStableBorrowRate(address(token), stableRate);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: principal,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                stableBorrowRate: stableRate,
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: false
            })
        );

        // The borrower repays the whole 100 DAI loan and has no accrued interest.
        // Therefore, total stable debt changes from 100 DAI to zero.
        core.exposedUpdateReserveStateOnRepay(address(token), user, principal, 0);

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        // No stable debt remains in the reserve.
        assertEq(reserve.totalBorrowsStable, 0);
        // An average rate has no meaning when there are no stable loans. The core
        // explicitly resets it to zero instead of attempting a division by zero.
        assertEq(reserve.currentAverageStableBorrowRate, 0);
    }

    // This test verifies that a variable-rate repayment cannot remove more debt
    // from the reserve than is outstanding after accrued interest is included.
    function testUpdateReserveStateOnRepayRevertsWhenVariableRepaymentExceedsDebt()
        external
        withInitReserve(address(token))
    {
        // The reserve has 100 DAI of variable debt and no stable debt.
        core.setReserveBorrows(address(token), 0, 100 ether);
        // stableBorrowRate = 0 identifies this as a variable-rate loan.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 0,
                stableBorrowRate: 0,
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: false
            })
        );

        // First, the core adds the 10 DAI balance increase: 100 + 10 = 110 DAI.
        // It then tries to subtract the 111 DAI repayment. Because 111 exceeds
        // the available 110 DAI, decreasing variable debt would underflow and
        // the core reverts with its explicit validation error.
        vm.expectRevert(CoreLibrary.CoreLibrary__InvalidVariableBorrowDecrease.selector);
        core.exposedUpdateReserveStateOnRepay(address(token), user, 111 ether, 10 ether);
    }

    // This test verifies that a stable-rate repayment cannot remove more debt
    // from the reserve than is outstanding after accrued interest is included.
    function testUpdateReserveStateOnRepayRevertsWhenStableRepaymentExceedsDebt()
        external
        withInitReserve(address(token))
    {
        uint256 stableRate = 5e25; // 5%

        // The reserve has one 100 DAI stable-rate loan and no variable debt.
        // Because it is the only stable loan, the average stable rate is 5% too.
        core.setReserveBorrows(address(token), 100 ether, 0);
        core.setReserveCurrentAverageStableBorrowRate(address(token), stableRate);
        // A non-zero stableBorrowRate identifies the user's loan as stable-rate.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                stableBorrowRate: stableRate,
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: false
            })
        );

        // First, the core adds 10 DAI of accrued interest at 5%: 100 + 10 = 110 DAI.
        // It then tries to remove the 111 DAI repayment at the same rate. Since
        // 111 exceeds the available 110 DAI, the stable-debt decrease is invalid
        // and the core reverts before recalculating the average stable rate.
        vm.expectRevert(CoreLibrary.CoreLibrary__InvalidAmountToDecrease.selector);
        core.exposedUpdateReserveStateOnRepay(address(token), user, 111 ether, 10 ether);
    }

    /////////////////////////////////////
    //     _updateUserStateOnRepay      //
    /////////////////////////////////////

    // This test verifies that a partial repayment updates the borrower's individual position without
    // closing the loan. In particular, it checks the debt and fee calculations, checkpoints the
    // variable-borrow index and timestamp, and preserves data that belongs to the open position.
    function testUpdateUserStateOnRepayPartiallyRepaysDebtAndCheckpointsPosition() external {
        // The user has a stable-rate debt
        uint256 stableRate = 5e25; // 5%, retained while the stable loan remains open
        // The helper should store the reserve's current index as the user's new checkpoint.
        uint256 reserveVariableBorrowIndex = 12e26;

        // Configure the index that is current at the time of repayment.
        core.setReserveVariableBorrowIndex(address(token), reserveVariableBorrowIndex);
        // Seed an open stable-rate loan. The collateral flag is unrelated to repayment and must survive it.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                // The borrower currently owes 100 DAI before newly accrued interest.
                principalBorrowBalance: 100 ether,
                // This stale checkpoint should be replaced with the reserve's current index.
                lastVariableBorrowCumulativeIndex: RAY,
                // The borrower still owes 5 DAI in origination fees.
                originationFee: 5 ether,
                stableBorrowRate: stableRate, // Since stableBorrowRate is non zero the user has a stable-rate debt
                lastUpdateTimestamp: 1,
                useAsCollateral: true
            })
        );

        // The borrower has accrued 10 DAI of interest and repays 40 DAI toward debt plus 2 DAI of fees.
        // Because debt remains after the repayment, `_repaidWholeLoan` is false.
        vm.warp(2_000);
        core.exposedUpdateUserStateOnRepay(address(token), user, 40 ether, 2 ether, 10 ether, false);

        // Read the borrower position after the repayment state update.
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));
        // Principal = previous principal + accrued interest - debt repayment = 100 + 10 - 40 = 70 DAI.
        assertEq(userData.principalBorrowBalance, 70 ether);
        // Remaining fee = 5 - 2 = 3 DAI.
        assertEq(userData.originationFee, 3 ether);
        // This is a partial repayment, so the stable rate remains attached to the open stable loan.
        assertEq(userData.stableBorrowRate, stableRate);
        // The position is checkpointed at the reserve's latest variable borrow index.
        assertEq(userData.lastVariableBorrowCumulativeIndex, reserveVariableBorrowIndex);
        // The user position records the time at which repayment was processed.
        assertEq(userData.lastUpdateTimestamp, 2_000);
        // Repaying debt does not change the user's collateral preference.
        assertTrue(userData.useAsCollateral);
    }

    // This test verifies that repaying the entire debt closes the borrower's loan and clears the
    // rate metadata that is meaningful only while debt remains. It also verifies that fees are
    // fully paid, the timestamp is refreshed, and the collateral preference is left untouched.
    function testUpdateUserStateOnRepayFullyClosesLoanAndClearsRateMetadata() external {
        // Use a non-zero reserve index to prove the full-repayment path clears it instead of checkpointing it.
        core.setReserveVariableBorrowIndex(address(token), 12e26);
        // Seed a stable-rate loan with 100 DAI principal and 3 DAI of remaining origination fees.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                // The borrower owes 100 DAI before the 10 DAI of accrued interest passed to the helper.
                principalBorrowBalance: 100 ether,
                // This existing index must be cleared when the loan is closed.
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 3 ether,
                // A non-zero rate identifies this as stable debt and must also be cleared on close.
                stableBorrowRate: 5e25, // Since stableBorrowRate is non zero the user has a stable-rate debt
                lastUpdateTimestamp: 1,
                useAsCollateral: true
            })
        );

        // Repay the 110 DAI compounded debt (100 principal + 10 interest) and all 3 DAI of fees.
        // `_repaidWholeLoan` is true, so the helper must remove the closed loan's rate metadata.
        vm.warp(3_000);
        core.exposedUpdateUserStateOnRepay(address(token), user, 110 ether, 3 ether, 10 ether, true);

        // Read the position after the full repayment.
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));
        // Principal = 100 + 10 - 110 = 0 DAI; no debt remains.
        assertEq(userData.principalBorrowBalance, 0);
        // All outstanding origination fees were repaid.
        assertEq(userData.originationFee, 0);
        // A closed stable loan must not retain a stable rate.
        assertEq(userData.stableBorrowRate, 0);
        // A closed loan must not retain a variable-borrow index either.
        assertEq(userData.lastVariableBorrowCumulativeIndex, 0);
        // The position records the time of the final repayment.
        assertEq(userData.lastUpdateTimestamp, 3_000);
        // Repayment does not alter the user's collateral preference.
        assertTrue(userData.useAsCollateral);
    }

    function testUpdateUserStateOnRepayRevertsWhenDebtRepaymentExceedsDebt() external {
        // Seed a variable-rate loan with 100 DAI of principal and no outstanding
        // origination fee. A zero stable rate identifies this as variable debt.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                // The user's existing variable-borrow index checkpoint.
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 0,
                stableBorrowRate: 0,
                lastUpdateTimestamp: 1,
                useAsCollateral: true
            })
        );

        // The helper first adds the 10 DAI balance increase, making the debt
        // 110 DAI (100 + 10). Repaying 111 DAI would then underflow when it
        // subtracts the repayment from that debt, so Solidity panics with 0x11.
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        core.exposedUpdateUserStateOnRepay(address(token), user, 111 ether, 0, 10 ether, false);
    }

    ////////////////////////////////
    //    updateStateOnRepay    //
    ////////////////////////////////

    // This test verifies that a partial repayment of a variable-rate loan updates both the borrower's
    // record and the reserve’s aggregate accounting, then reprices the reserve.
    function testUpdateStateOnRepayPartiallyRepaysVariableDebtAndRepricesReserve()
        external
        withInitReserve(address(token))
    {
        uint256 repaymentAmount = 40 ether;
        uint256 balanceIncrease = 10 ether;
        uint256 feeRepaid = 2 ether;
        uint256 updateTimestamp = block.timestamp + 1 days;
        uint256 liquidityRate = 3e25;
        uint256 stableBorrowRate = 6e25;
        uint256 variableBorrowRate = 7e25;
        uint256 oldVariableBorrowRate = 5e25;

        token.mint(address(core), 900 ether);
        // Reserve debt: 50 DAI stable + 100 DAI variable
        core.setReserveBorrows(address(token), 50 ether, 100 ether);
        core.setReserveCurrentAverageStableBorrowRate(address(token), 8e25);
        core.setReserveRates(address(token), 0, 0, oldVariableBorrowRate);

        // User's variable debt 100 DAI
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 5 ether,
                stableBorrowRate: 0, // This marks the debt as variable
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: true
            })
        );
        strategy.setRates(liquidityRate, stableBorrowRate, variableBorrowRate);
        core.setReserveLastUpdateTimestamp(address(token), uint40(block.timestamp));
        // The test moves forward 1 day
        vm.warp(updateTimestamp);

        uint256 expectedVariableBorrowIndex = RAY.rayMul((RAY + oldVariableBorrowRate / 365 days).rayPow(1 days));

        vm.expectCall(
            address(strategy),
            // available liquidity = 900 + 40 = 940 DAI
            // stable debt         = 50 DAI
            // variable debt       = 70 DAI
            // avg stable rate     = 8e25
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates,
                (address(token), 940 ether, 50 ether, 70 ether, 8e25)
            )
        );
        vm.expectEmit(true, false, false, true);
        emit LendingPoolCore.ReserveUpdated(
            address(token), liquidityRate, stableBorrowRate, variableBorrowRate, RAY, expectedVariableBorrowIndex
        );

        // User's accrued interest since their last update: 10 DAI
        // Repayment toward princiapl/debt: 40 DAI
        // Origination-fee repayment : 2 DAI (from 5 DAI)
        vm.prank(lendingPool);
        core.updateStateOnRepay(address(token), user, repaymentAmount, feeRepaid, balanceIncrease, false);

        // Repayment state transition is:
        // User debt:       100 + 10 interest - 40 repayment = 70 DAI
        // Variable total:  100 + 10 interest - 40 repayment = 70 DAI
        // User fee:          5 - 2 = 3 DAI
        // Stable total:      unchanged at 50 DAI

        // Because stableBorrowrate on the user is 0, the user is classified as a variable-rate borrower.
        // Therefore _updateReserveStateOnRepay applies the interest and repayment to totalBorrowsVariable,
        // leaving stable debt and its average rate unchanged.
        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));
        assertEq(reserve.totalBorrowsStable, 50 ether); // unchanged
        assertEq(reserve.totalBorrowsVariable, 70 ether); // 100 + 10 - 40 = 70
        assertEq(reserve.currentAverageStableBorrowRate, 8e25); // unchanged

        // These 3 values are set by interest-rate strategy
        assertEq(reserve.currentLiquidityRate, liquidityRate);
        assertEq(reserve.currentStableBorrowRate, stableBorrowRate);
        assertEq(reserve.currentVariableBorrowRate, variableBorrowRate);

        assertEq(reserve.lastUpdateTimestamp, updateTimestamp); // warped timestamp
        assertEq(userData.principalBorrowBalance, 70 ether); // 100 + 10 - 40 = 70
        assertEq(userData.originationFee, 3 ether); // 5 - 2 = 3
        assertEq(userData.lastVariableBorrowCumulativeIndex, expectedVariableBorrowIndex);
        assertEq(userData.lastUpdateTimestamp, updateTimestamp); // warped timestamp
        assertTrue(userData.useAsCollateral); // unchanged
    }

    // This test verifies that a partial repayment of stable-rate debt updates both the borrower
    // and reserve correctly, including the reserve’s weighted-average stable borrow rate.
    function testUpdateStateOnRepayPartiallyRepaysStableDebtAndRepricesReserve()
        external
        withInitReserve(address(token))
    {
        uint256 userStableRate = 5e25;
        uint256 otherBorrowerStableRate = 10e25;
        uint256 expectedAverageStableRate = (uint256(70 ether).wadToRay().rayMul(userStableRate)
                + uint256(100 ether).wadToRay().rayMul(otherBorrowerStableRate))
        .rayDiv(uint256(170 ether).wadToRay());
        uint256 updateTimestamp = block.timestamp + 1 days;

        token.mint(address(core), 900 ether);
        // The reserve has 200 stable debt and no variable debt
        core.setReserveBorrows(address(token), 200 ether, 0);
        core.setReserveCurrentAverageStableBorrowRate(address(token), (userStableRate + otherBorrowerStableRate) / 2);

        // The reserve’s starting average stable rate is therefore (5e25 + 10e25) / 2 = 7.5e25

        // The user has 100 stable debt at 5%
        // The user owns a 5 ether origination fee
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 5 ether,
                stableBorrowRate: userStableRate, // Stable debt is active
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: true
            })
        );
        strategy.setRates(3e25, 6e25, 7e25);
        vm.warp(updateTimestamp);

        // the rate strategy must receive:
        //      available liquidity = 940
        //      stable debt         = 170
        //      variable debt       = 0
        //      average stable rate = expectedAverageStableRate
        vm.expectCall(
            address(strategy),
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates,
                (address(token), 940 ether, 170 ether, 0, expectedAverageStableRate)
            )
        );
        vm.expectEmit(true, false, false, true);
        emit LendingPoolCore.ReserveUpdated(address(token), 3e25, 6e25, 7e25, RAY, RAY);

        // 10 ether of interest has accrued since the user's last update
        // The user repays 40 ether of debt and 2 ether of fee
        vm.prank(lendingPool);
        core.updateStateOnRepay(address(token), user, 40 ether, 2 ether, 10 ether, false);

        // The core accounting transition is:
        //  User stable debt:      100 + 10 accrued interest - 40 repaid = 70
        //  Reserve stable debt:   200 + 10 accrued interest - 40 repaid = 170
        //  User fee:              5 - 2 = 3

        // The reserve's new weighted average is (70 × 5e25 + 100 × 10e25) / 170

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));
        assertEq(reserve.totalBorrowsStable, 170 ether); // 200 + 10 -40 = 170
        assertEq(reserve.totalBorrowsVariable, 0); // unchanged
        assertEq(reserve.currentAverageStableBorrowRate, expectedAverageStableRate); // (70 × 5e25 + 100 × 10e25) / 170
        assertEq(userData.principalBorrowBalance, 70 ether); // 100 + 10 - 40
        assertEq(userData.originationFee, 3 ether); // 5- 2 = 3

        // The user started at userStableRate (5e25) and still owes 70 ether afterward.
        // Since the loan is still open, its remaining debt continues accruing at that same stable rate.
        // This value would be reset to 0 only when the loan is fully repaid.
        assertEq(userData.stableBorrowRate, userStableRate); // borrowers stable rate doesn't change

        // This checks that the user’s stored variable-borrow index remains the reserve’s initial index (RAY == 1e27).
        assertEq(userData.lastVariableBorrowCumulativeIndex, RAY);

        assertEq(userData.lastUpdateTimestamp, updateTimestamp);
        assertTrue(userData.useAsCollateral);
    }

    // verifies the bookkeeping for repaying a variable-rate loan completely.
    function testUpdateStateOnRepayFullyClosesVariableLoan() external withInitReserve(address(token)) {
        uint256 liquidityRate = 3e25;
        uint256 stableBorrowRate = 6e25;
        uint256 variableBorrowRate = 7e25;
        uint256 balanceIncrease = 10 ether;
        uint256 repaymentAmount = 110 ether;
        uint256 updateTimestamp = block.timestamp + 1 days;

        token.mint(address(core), 900 ether);
        // The reserve has 100 of variable debt and 0 stable borrows
        core.setReserveBorrows(address(token), 0, 100 ether);
        // The user owes 100 principal of variable debt plus 3 origination fee
        // stableBorrowRate = 0 marks this as variable-rate loan
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 3 ether,
                stableBorrowRate: 0,
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: true
            })
        );
        strategy.setRates(liquidityRate, stableBorrowRate, variableBorrowRate);
        vm.warp(updateTimestamp);

        vm.expectCall(
            address(strategy),
            abi.encodeCall(IReserveInterestRateStrategy.calculateInterestRates, (address(token), 1_010 ether, 0, 0, 0))
        );
        vm.prank(lendingPool);
        // The borrower closes 100 ether of principal plus 10 ether of accrued interest.
        // The borrower also repays 3 ether of the outstanding origination fee.
        core.updateStateOnRepay(address(token), user, repaymentAmount, 3 ether, balanceIncrease, true);

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // Debt at reserve level: 100 recorded variable debt + 10 accrued interest - 110 repayment = 0 remaining debt
        // Debt at user level: 100 principal balance + 10 accrued interest - 110 repayment = 0 remaining debt

        assertEq(reserve.totalBorrowsStable, 0); // unchanged: no stable debt exists
        assertEq(reserve.totalBorrowsVariable, 0); // 100 + 10 - 110 = 0
        assertEq(userData.principalBorrowBalance, 0); // 100 + 10 - 110 = 0
        assertEq(userData.originationFee, 0); // 3 - 3 = 0
        assertEq(userData.stableBorrowRate, 0); // cleared because the loan was fully repaid
        assertEq(userData.lastVariableBorrowCumulativeIndex, 0); // cleared because the loan was fully repaid
        assertEq(userData.lastUpdateTimestamp, updateTimestamp);
        assertTrue(userData.useAsCollateral);
    }

    function testUpdateStateOnRepayFullyClosesLastStableLoan() external withInitReserve(address(token)) {
        uint256 userStableRate = 5e25;
        uint256 balanceIncrease = 10 ether;
        uint256 repaymentAmount = 110 ether;
        uint256 updateTimestamp = block.timestamp + 1 days;

        token.mint(address(core), 900 ether);
        // Reserve total stable debt: 100 ether, total variable debt: 0
        core.setReserveBorrows(address(token), 100 ether, 0);
        core.setReserveCurrentAverageStableBorrowRate(address(token), userStableRate);
        // User principal debt is 100 ether
        // Origination fee: 3 ether
        // Debt is stable because stableBorrowRate > 0
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 3 ether,
                stableBorrowRate: userStableRate,
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: true
            })
        );
        strategy.setRates(3e25, 6e25, 7e25);
        vm.warp(updateTimestamp);

        vm.expectCall(
            address(strategy),
            abi.encodeCall(IReserveInterestRateStrategy.calculateInterestRates, (address(token), 1_010 ether, 0, 0, 0))
        );
        vm.prank(lendingPool);
        // The borrower closes 100 ether of principal plus 10 ether of accrued interest,
        // and repays the full 3 ether origination fee.
        core.updateStateOnRepay(address(token), user, repaymentAmount, 3 ether, balanceIncrease, true);

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // The stable-debt accounting is:
        // 100 existsing stable debt + 10 accrued interest - 110 repayment = 0 remaining stable debt
        // Because the user was the last stable borrower, the reserve has no stable loans remaining

        assertEq(reserve.totalBorrowsStable, 0); // The reserve has no stable debt remaining.
        assertEq(reserve.currentAverageStableBorrowRate, 0); // No stable debt remains to calculate an average rate.
        assertEq(userData.principalBorrowBalance, 0); // the user has no debt remaining
        assertEq(userData.originationFee, 0); // the user has no origination fee ramianing
        assertEq(userData.stableBorrowRate, 0); // cleared because the loan was fully rapiad
        assertEq(userData.lastVariableBorrowCumulativeIndex, 0); // cleared becase the loan was fully repaid
        assertEq(userData.lastUpdateTimestamp, updateTimestamp);
        assertTrue(userData.useAsCollateral);
    }

    // This test verifies that paying only an origination fee does not reduce loan debt,
    // but still refreshes the reserve’s interest-rate state.
    function testUpdateStateOnRepayFeeOnlyLeavesDebtUnchangedAndRepricesReserve()
        external
        withInitReserve(address(token))
    {
        uint256 updateTimestamp = block.timestamp + 1 days;
        uint256 liquidityRate = 3e25;
        uint256 stableBorrowRate = 6e25;
        uint256 variableBorrowRate = 7e25;

        token.mint(address(core), 900 ether);
        // The reserve has 100 ether of variable-rate debt
        core.setReserveBorrows(address(token), 0, 100 ether);
        // The user owes 100 ether principal and 5 ether origination fee
        // stableBorrowrate = 0 so the debt is variable-rate
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 5 ether,
                stableBorrowRate: 0,
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: true
            })
        );
        strategy.setRates(liquidityRate, stableBorrowRate, variableBorrowRate);
        vm.warp(updateTimestamp);

        // Expect interest-rate strategy to be called with:
        //  available liquidity: 900
        //  stable debt: 0
        //  variable debt: 100
        //  average stable rate: 0
        vm.expectCall(
            address(strategy),
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates, (address(token), 900 ether, 0, 100 ether, 0)
            )
        );
        vm.expectEmit(true, false, false, true);
        emit LendingPoolCore.ReserveUpdated(
            address(token), liquidityRate, stableBorrowRate, variableBorrowRate, RAY, RAY
        );

        // Repayment applied to debt (_paybackAmountMinusFees) : 0
        // Origination fee paid: 2 ether
        // Accrued interest being realized (_balanceIncrease): 0
        // loan is not closed: false
        vm.prank(lendingPool);
        core.updateStateOnRepay(address(token), user, 0, 2 ether, 0, false);

        // The accounting is:
        // Debt: 100 + 0interest - 0debt repayment = 100
        // Fee: 5 - 2 = 3

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));
        assertEq(reserve.totalBorrowsVariable, 100 ether); // Unchanged
        assertEq(reserve.currentLiquidityRate, liquidityRate); // is updated
        assertEq(reserve.lastUpdateTimestamp, updateTimestamp);
        assertEq(userData.principalBorrowBalance, 100 ether); // Unchanged
        assertEq(userData.originationFee, 3 ether); // 5 - 2 = 3
        assertEq(userData.lastUpdateTimestamp, updateTimestamp);
        assertTrue(userData.useAsCollateral);
    }

    function testUpdateStateOnRepayRevertsWhenCallerIsNotLendingPool() external withInitReserve(address(token)) {
        vm.prank(attacker);
        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);
        core.updateStateOnRepay(address(token), user, 1 ether, 0, 0, false);
    }

    // This test proves that updateStateOnRepay is atomic: if its user-level update fails,
    // all earlier reserve-level updates are reverted too.
    function testUpdateStateOnRepayRollsBackReserveChangesWhenUserUpdateReverts()
        external
        withInitReserve(address(token))
    {
        // Reserve variable debt: 200 ether
        core.setReserveBorrows(address(token), 0, 200 ether);
        // User variable debt: 90 ether
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 90 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 0,
                stableBorrowRate: 0,
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: true
            })
        );
        // Simulated accrued interest: 10 ether
        // Debt repayment: 101 ether

        // The function first updates te reserve: 200 + 10 - 101 = 109 ether
        // Then it updates the user: 90 + 10 -101 = -1 ether -> revert
        vm.prank(lendingPool);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        core.updateStateOnRepay(address(token), user, 101 ether, 0, 10 ether, false);

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // The revert unwinds everything done earlier in the call
        // The assertions confirm the original state remains:
        assertEq(reserve.totalBorrowsVariable, 200 ether);
        assertEq(reserve.lastLiquidityCumulativeIndex, RAY);
        assertEq(reserve.lastVariableBorrowCumulativeIndex, RAY);
        assertEq(userData.principalBorrowBalance, 90 ether);
        assertEq(userData.lastVariableBorrowCumulativeIndex, RAY);
        assertEq(userData.lastUpdateTimestamp, block.timestamp);
        assertTrue(userData.useAsCollateral);
    }

    ///////////////////////////////////////////
    //  _updateUserStateOnLiquidation         //
    ///////////////////////////////////////////

    // This test verifies the user-level bookkeeping performed when a variable-rate loan is partially liquidated.
    function testUpdateUserStateOnLiquidationUpdatesVariableDebtFeeAndCheckpoint() external {
        // Reserve variable-borrow index: 12e26 (1.2 RAY)
        uint256 reserveVariableBorrowIndex = 12e26;
        core.setReserveVariableBorrowIndex(address(token), reserveVariableBorrowIndex);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether, // User debt principal 100 ether
                lastVariableBorrowCumulativeIndex: RAY, // Previous user variable-debt checkpoint: RAY
                originationFee: 5 ether, // Origination fee owed: 5 ether
                stableBorrowRate: 0, // makes the position variable-rate
                lastUpdateTimestamp: 1,
                useAsCollateral: true
            })
        );
        // The time is advanced to 2000
        vm.warp(2_000);
        // The liquidation is simulated with:
        // _amountToLiquidate = 40 ether
        // _feeLiquidated     = 2 ether
        // _balanceIncrease   = 10 ether
        core.exposedUpdateUserStateOnLiquidation(address(token), user, 40 ether, 2 ether, 10 ether);

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));
        // The remaining debt is: 100 + 10 accrued interest - 40 liquidated = 70 ether
        assertEq(userData.principalBorrowBalance, 70 ether);
        assertEq(userData.originationFee, 3 ether); // 5 - 2
        // Asserts that lastVariableBorrowCumulativeIndex is updated from the old RAY checkpoint
        // to the reserve's current index 12e26
        assertEq(userData.lastVariableBorrowCumulativeIndex, reserveVariableBorrowIndex);
        assertEq(userData.stableBorrowRate, 0); // remains zero
        assertEq(userData.lastUpdateTimestamp, 2_000);
        assertTrue(userData.useAsCollateral); // is unchanged
    }

    function testUpdateUserStateOnLiquidationUpdatesStableDebtWithoutChangingCheckpointOrFee() external {
        uint256 stableRate = 5e25;
        uint256 previousVariableBorrowIndex = 11e26;
        core.setReserveVariableBorrowIndex(address(token), 12e26);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: previousVariableBorrowIndex,
                originationFee: 5 ether,
                stableBorrowRate: stableRate,
                lastUpdateTimestamp: 1,
                useAsCollateral: true
            })
        );

        vm.warp(3_000);
        core.exposedUpdateUserStateOnLiquidation(address(token), user, 40 ether, 0, 10 ether);

        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));
        assertEq(userData.principalBorrowBalance, 70 ether);
        assertEq(userData.originationFee, 5 ether);
        assertEq(userData.lastVariableBorrowCumulativeIndex, previousVariableBorrowIndex);
        assertEq(userData.stableBorrowRate, stableRate);
        assertEq(userData.lastUpdateTimestamp, 3_000);
        assertTrue(userData.useAsCollateral);
    }

    function testUpdateUserStateOnLiquidationRevertsWhenLiquidationExceedsDebt() external {
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 0,
                stableBorrowRate: 0,
                lastUpdateTimestamp: 1,
                useAsCollateral: true
            })
        );

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        core.exposedUpdateUserStateOnLiquidation(address(token), user, 111 ether, 0, 10 ether);
    }

    //////////////////////////////////////////////////////////
    //  _updatePrincipalReserveStateOnLiquidation             //
    //////////////////////////////////////////////////////////

    // verifies the reserve-level effects when a variable-rate loan is liquidated.
    function testUpdatePrincipalReserveStateOnLiquidationUpdatesVariableDebtAndCheckpointsIndexes()
        external
        withInitReserve(address(token))
    {
        uint256 oldLiquidityRate = 5e25;
        uint256 oldVariableBorrowRate = 10e25;
        uint256 previousTimestamp = block.timestamp;
        uint256 balanceIncrease = 10 ether; // accrued-interest amount of 10 tokens.
        uint256 liquidatedAmount = 30 ether; // liquidation repayment of 30 tokens.

        // 5% liquidity rate and 10% variable borrow rate.
        core.setReserveRates(address(token), oldLiquidityRate, 0, oldVariableBorrowRate);
        // Reserve has 100 tokens of variable debt (user) and 50 tokens of stable debt
        core.setReserveBorrows(address(token), 50 ether, 100 ether);
        core.setReserveCurrentAverageStableBorrowRate(address(token), 8e25);
        // forge-lint: disable-next-line(unsafe-typecast)
        core.setReserveLastUpdateTimestamp(address(token), uint40(previousTimestamp));
        // User has 100 tokens of variable debt
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 0,
                stableBorrowRate: 0, // makes the position variable-rate
                // forge-lint: disable-next-line(unsafe-typecast)
                lastUpdateTimestamp: uint40(previousTimestamp),
                useAsCollateral: false
            })
        );
        // A full year passes
        vm.warp(previousTimestamp + 365 days);
        core.exposedUpdatePrincipalReserveStateOnLiquidation(address(token), user, liquidatedAmount, balanceIncrease);

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        uint256 expectedVariableIndex = RAY.rayMul((RAY + oldVariableBorrowRate / 365 days).rayPow(365 days));

        // Checks that reserve.increaseTotalBorrowsVariable and reserve.decreaseTotalBorrowsVariable were called
        // The expected variable debt is 100 existing variable debt + 10 accrued interest - 30 liquidated repayment = 80
        assertEq(reserve.totalBorrowsVariable, 100 ether + balanceIncrease - liquidatedAmount); // 80

        // Checks that the STABLE-rate branch was skipped
        assertEq(reserve.totalBorrowsStable, 50 ether); // Stable debt stays at 50
        assertEq(reserve.currentAverageStableBorrowRate, 8e25); // stable weighted-average rate stays at 8%

        // Checks that reserve.updateCumulativeIndexes() was called
        // The liquidity index is expected to increase linearly using the prior 5% liquidity rate: RAY + 5%
        assertEq(reserve.lastLiquidityCumulativeIndex, RAY + oldLiquidityRate);
        // The variable-borrow index is expected to compound for one year using the prior 10% variable rate.
        assertEq(reserve.lastVariableBorrowCumulativeIndex, expectedVariableIndex);
    }

    // The test verifies liquidation accounting for a borrower with stable-rate debt.
    function testUpdatePrincipalReserveStateOnLiquidationUpdatesStableDebtAndWeightedAverageRate()
        external
        withInitReserve(address(token))
    {
        uint256 userStableRate = 5e25; // 5%
        uint256 otherBorrowerStableRate = 10e25;
        uint256 userPrincipal = 100 ether;
        uint256 otherBorrowerPrincipal = 100 ether;
        uint256 balanceIncrease = 10 ether; // accrued interest of 10
        uint256 liquidatedAmount = 40 ether; // liquidator repays 40
        // Total stable debt is: user 100 ether + other borrowers 100 ether = 200 ether
        uint256 initialTotalStableDebt = userPrincipal + otherBorrowerPrincipal;
        // Reserve's average stable rate is: (100 * 5% + 100 * 10%) / 200
        uint256 initialAverageStableRate = (userStableRate + otherBorrowerStableRate) / 2;

        core.setReserveBorrows(address(token), initialTotalStableDebt, 0);
        core.setReserveCurrentAverageStableBorrowRate(address(token), initialAverageStableRate);
        // User owes 100 tokens at 5%.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: userPrincipal,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 0,
                stableBorrowRate: userStableRate, // makes the position stable-rate
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: false
            })
        );

        core.exposedUpdatePrincipalReserveStateOnLiquidation(address(token), user, liquidatedAmount, balanceIncrease);

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        uint256 expectedStableDebt = initialTotalStableDebt + balanceIncrease - liquidatedAmount; // 200 + 10 - 40 = 170
        uint256 remainingUserDebt = userPrincipal + balanceIncrease - liquidatedAmount; // 100 + 10 - 40 = 70
        uint256 expectedAverageStableRate = (remainingUserDebt.wadToRay().rayMul(userStableRate)
                + otherBorrowerPrincipal.wadToRay().rayMul(otherBorrowerStableRate))
        .rayDiv(expectedStableDebt.wadToRay()); // (70 * 5% + 100 * 10%) / 170 = 7.941176.. %

        assertEq(reserve.totalBorrowsStable, expectedStableDebt);
        assertEq(reserve.currentAverageStableBorrowRate, expectedAverageStableRate);
        assertEq(reserve.totalBorrowsVariable, 0);
    }

    //////////////////////////////////////////////////////////
    //  _updateCollateralReserveStateOnLiquidation            //
    //////////////////////////////////////////////////////////

    function testUpdateCollateralReserveStateOnLiquidationUpdatesCumulativeIndexes()
        external
        withInitReserve(address(token))
    {
        uint256 liquidityRate = 5e25;
        uint256 variableBorrowRate = 10e25;
        uint256 initialStableBorrows = 50 ether;
        uint256 initialVariableBorrows = 100 ether;
        uint256 previousTimestamp = block.timestamp;

        core.setReserveRates(address(token), liquidityRate, 0, variableBorrowRate);
        core.setReserveBorrows(address(token), initialStableBorrows, initialVariableBorrows);
        // forge-lint: disable-next-line(unsafe-typecast)
        core.setReserveLastUpdateTimestamp(address(token), uint40(previousTimestamp));

        vm.warp(previousTimestamp + 365 days);
        core.exposedUpdateCollateralReserveStateOnLiquidation(address(token));

        CoreLibrary.ReserveData memory reserve = core.getReserveData(address(token));
        uint256 expectedVariableBorrowIndex = RAY.rayMul((RAY + variableBorrowRate / 365 days).rayPow(365 days));

        assertEq(reserve.lastLiquidityCumulativeIndex, RAY + liquidityRate);
        assertEq(reserve.lastVariableBorrowCumulativeIndex, expectedVariableBorrowIndex);
        assertEq(reserve.totalBorrowsStable, initialStableBorrows);
        assertEq(reserve.totalBorrowsVariable, initialVariableBorrows);
        assertEq(reserve.currentLiquidityRate, liquidityRate);
        assertEq(reserve.currentVariableBorrowRate, variableBorrowRate);
    }

    //////////////////////////////////////////
    //      updateStateOnLiquidation         //
    //////////////////////////////////////////

    // liquidating a borrower with variable-rate debt correctly updates both pool-wide and user-specific accounting,
    // when the liquidator receives aTokens as collateral.
    function testUpdateStateOnLiquidationVariableDebtWithATokenCollateralUpdatesPrincipalAndUserState()
        external
        withInitReserve(address(token))
        withInitReserve(address(secondToken))
    {
        uint256 availableLiquidity = 1_000 ether;
        uint256 amountToLiquidate = 40 ether;
        uint256 balanceIncrease = 10 ether;
        uint256 feeLiquidated = 2 ether;
        uint256 newLiquidityRate = 3e25;
        uint256 newStableBorrowRate = 6e25;
        uint256 newVariableBorrowRate = 7e25;

        token.mint(address(core), availableLiquidity);
        // Reserve debt totals: 50 ether stable + 100 ether variable
        core.setReserveBorrows(address(token), 50 ether, 100 ether);
        core.setReserveCurrentAverageStableBorrowRate(address(token), 8e25);
        // User debt: 100 ether variable debt + 5 ether origination fee.
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 5 ether,
                stableBorrowRate: 0, // this makes user's debt variable-rate
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: true
            })
        );
        strategy.setRates(newLiquidityRate, newStableBorrowRate, newVariableBorrowRate);

        // The mocked interest-rate strategy must be called with:
        //    available liquidity = 1,000 + 40
        //    stable borrows      = 50
        //    variable borrows    = 70
        //    average stable rate = 8e25
        vm.expectCall(
            address(strategy),
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates,
                (address(token), availableLiquidity + amountToLiquidate, 50 ether, 70 ether, 8e25)
            )
        );
        vm.expectEmit(true, false, false, true);
        emit LendingPoolCore.ReserveUpdated(
            address(token), newLiquidityRate, newStableBorrowRate, newVariableBorrowRate, RAY, RAY
        );

        vm.prank(lendingPool);
        // Liquidation repays 40 ether
        // The user has accrued 10 ether interest since their last update
        // 2 ether of the origination fee is liquidated
        core.updateStateOnLiquidation(
            address(token), address(secondToken), user, amountToLiquidate, 0, feeLiquidated, 0, balanceIncrease, true
        );

        CoreLibrary.ReserveData memory principalReserve = core.getReserveData(address(token));
        CoreLibrary.ReserveData memory collateralReserve = core.getReserveData(address(secondToken));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // Debt after accrued interest = 100 + 10 = 110
        // Debt after liquidation      = 110 - 40 = 70

        // Reserve stable debt unchanged = 50
        assertEq(principalReserve.totalBorrowsStable, 50 ether);
        // Reserve variable debt = 100 + 10 - 40 = 70
        assertEq(principalReserve.totalBorrowsVariable, 70 ether);
        assertEq(principalReserve.currentLiquidityRate, newLiquidityRate);
        assertEq(principalReserve.currentStableBorrowRate, newStableBorrowRate);
        assertEq(principalReserve.currentVariableBorrowRate, newVariableBorrowRate);

        // User principal debt = 100 + 10 - 40 = 70
        assertEq(userData.principalBorrowBalance, 70 ether);
        // User fee = 5 - 2 = 3
        assertEq(userData.originationFee, 3 ether);
        // User's variable-borrow index remains RAY because no time has advanced
        assertEq(userData.lastVariableBorrowCumulativeIndex, RAY);
        assertEq(userData.lastUpdateTimestamp, block.timestamp);

        // Since liquidatorReceivesAToken == true, the code skips:
        //      _updateReserveInterestRatesAndTimestamp(_collateralReserve, ...)
        //
        // The collateral remains in the pool; only its aToken ownership changes.
        // With no liquidity leaving the collateral reserve, its utilization and rates
        // should not need recalculation.
        assertEq(collateralReserve.currentLiquidityRate, 0);
        assertEq(collateralReserve.currentStableBorrowRate, 0);
        assertEq(collateralReserve.currentVariableBorrowRate, 0);
    }

    function testUpdateStateOnLiquidationStableDebtWithATokenCollateralUpdatesWeightedAverageRate()
        external
        withInitReserve(address(token))
        withInitReserve(address(secondToken))
    {
        uint256 userStableRate = 5e25;
        uint256 otherBorrowerStableRate = 10e25;
        uint256 amountToLiquidate = 40 ether;
        uint256 balanceIncrease = 10 ether;
        uint256 expectedStableDebt = 170 ether;
        uint256 remainingUserDebt = 70 ether;
        uint256 otherBorrowerDebt = 100 ether;
        uint256 expectedAverageStableRate = (remainingUserDebt.wadToRay().rayMul(userStableRate)
                + otherBorrowerDebt.wadToRay().rayMul(otherBorrowerStableRate))
        .rayDiv(expectedStableDebt.wadToRay());

        token.mint(address(core), 1_000 ether);
        // Total reserve stable debt   = 200
        // Total reserve variable debt = 0
        core.setReserveBorrows(address(token), 200 ether, 0);
        core.setReserveCurrentAverageStableBorrowRate(address(token), (userStableRate + otherBorrowerStableRate) / 2);

        // Other borrowers debt: 100 at 10%

        // User debt = 100 at 5%
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: 0,
                originationFee: 5 ether,
                stableBorrowRate: userStableRate, // > 0 This means user has an active stable debt
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: true
            })
        );
        strategy.setRates(3e25, 6e25, 7e25);

        vm.expectCall(
            address(strategy),
            // available liquidity: 1,040 (1,000 + 40 repayment)
            // stable debt: 170
            // variable debt: 0
            // weighted average: expectedAverageStableRate
            abi.encodeCall(
                IReserveInterestRateStrategy.calculateInterestRates,
                (address(token), 1_000 ether + amountToLiquidate, expectedStableDebt, 0, expectedAverageStableRate)
            )
        );

        // The user has 10 of interest and the liquidator repays 40
        vm.prank(lendingPool);
        core.updateStateOnLiquidation(
            address(token), address(secondToken), user, amountToLiquidate, 0, 0, 0, balanceIncrease, true
        );

        CoreLibrary.ReserveData memory principalReserve = core.getReserveData(address(token));
        CoreLibrary.UserReserveData memory userData = core.getUserReserveData(user, address(token));

        // Expected stable debt = 200 + 10 - 40 = 170

        // The remaining loans are:
        //  - liquidated user: 70 debt and 5% stable rate
        //  - other borrower: 100 debt and 10% stable rate
        assertEq(principalReserve.totalBorrowsStable, expectedStableDebt); // 170 ether
        assertEq(principalReserve.totalBorrowsVariable, 0); // No variable debt
        // Expected reserve average is: (70 x 5% + 100 x 10%) / 170 = 7.941176.. %
        assertEq(principalReserve.currentAverageStableBorrowRate, expectedAverageStableRate);
        assertEq(userData.principalBorrowBalance, 70 ether); // 100 + 10 - 40 = 70 ether
        assertEq(userData.originationFee, 5 ether); // unchanged
        assertEq(userData.stableBorrowRate, userStableRate); // remains at 5%
        assertEq(userData.lastVariableBorrowCumulativeIndex, 0); // unchanged
        assertEq(userData.lastUpdateTimestamp, block.timestamp);

        // liquidatorReceivesAToken = true means collateral stays in the pool,
        // so only aToken ownership transfers; collateral-reserve rates do not need recalculation.
    }

    // an unauthorized account cannot liquidate a position or partially alter the protocol’s accounting.
    function testUpdateStateOnLiquidationRevertsForNonLendingPoolWithoutChangingState()
        external
        withInitReserve(address(token))
        withInitReserve(address(secondToken))
    {
        core.setReserveBorrows(address(token), 50 ether, 100 ether);
        core.setReserveBorrows(address(secondToken), 25 ether, 30 ether);
        core.setUserReserveData(
            user,
            address(token),
            CoreLibrary.UserReserveData({
                principalBorrowBalance: 100 ether,
                lastVariableBorrowCumulativeIndex: RAY,
                originationFee: 5 ether,
                stableBorrowRate: 0,
                lastUpdateTimestamp: uint40(block.timestamp),
                useAsCollateral: true
            })
        );
        CoreLibrary.ReserveData memory principalBefore = core.getReserveData(address(token));
        CoreLibrary.ReserveData memory collateralBefore = core.getReserveData(address(secondToken));
        CoreLibrary.UserReserveData memory userBefore = core.getUserReserveData(user, address(token));

        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);
        vm.prank(attacker);
        core.updateStateOnLiquidation(
            address(token), address(secondToken), user, 40 ether, 0, 2 ether, 0, 10 ether, true
        );

        CoreLibrary.ReserveData memory principalAfter = core.getReserveData(address(token));
        CoreLibrary.ReserveData memory collateralAfter = core.getReserveData(address(secondToken));
        CoreLibrary.UserReserveData memory userAfter = core.getUserReserveData(user, address(token));

        assertEq(principalAfter.totalBorrowsStable, principalBefore.totalBorrowsStable);
        assertEq(principalAfter.totalBorrowsVariable, principalBefore.totalBorrowsVariable);
        assertEq(principalAfter.lastLiquidityCumulativeIndex, principalBefore.lastLiquidityCumulativeIndex);
        assertEq(principalAfter.lastVariableBorrowCumulativeIndex, principalBefore.lastVariableBorrowCumulativeIndex);
        assertEq(collateralAfter.totalBorrowsStable, collateralBefore.totalBorrowsStable);
        assertEq(collateralAfter.totalBorrowsVariable, collateralBefore.totalBorrowsVariable);
        assertEq(collateralAfter.lastLiquidityCumulativeIndex, collateralBefore.lastLiquidityCumulativeIndex);
        assertEq(collateralAfter.lastVariableBorrowCumulativeIndex, collateralBefore.lastVariableBorrowCumulativeIndex);
        assertEq(userAfter.principalBorrowBalance, userBefore.principalBorrowBalance);
        assertEq(userAfter.originationFee, userBefore.originationFee);
        assertEq(userAfter.lastVariableBorrowCumulativeIndex, userBefore.lastVariableBorrowCumulativeIndex);
        assertEq(userAfter.lastUpdateTimestamp, userBefore.lastUpdateTimestamp);
    }

    ////////////////////////////////
    //        liquidateFee         //
    ////////////////////////////////

    function testLiquidateFeeTransfersERC20FromCoreToDestination() external {
        address destination = makeAddr("feeCollector");
        uint256 feeAmount = 10 ether;
        token.mint(address(core), feeAmount);

        vm.prank(lendingPool);
        core.liquidateFee(address(token), feeAmount, payable(destination));

        assertEq(token.balanceOf(address(core)), 0);
        assertEq(token.balanceOf(destination), feeAmount);
    }

    function testLiquidateFeeTransfersEthFromCoreToDestination() external {
        address destination = makeAddr("feeCollector");
        uint256 feeAmount = 1 ether;
        vm.deal(address(core), feeAmount);

        vm.prank(lendingPool);
        core.liquidateFee(EthAddressLib.ethAddress(), feeAmount, payable(destination));

        assertEq(address(core).balance, 0);
        assertEq(destination.balance, feeAmount);
    }

    function testLiquidateFeeRevertsWhenCallerIsNotLendingPool() external {
        vm.prank(attacker);
        vm.expectRevert(LendingPoolCore.LendingPoolCore__OnlyLendingPool.selector);
        core.liquidateFee(address(token), 1 ether, payable(makeAddr("feeCollector")));
    }

    function testLiquidateFeeRevertsWhenEthDestinationRejectsPayment() external {
        RejectEthReceiver receiver = new RejectEthReceiver();
        uint256 feeAmount = 1 ether;
        vm.deal(address(core), feeAmount);

        vm.prank(lendingPool);
        vm.expectRevert(
            abi.encodeWithSelector(
                LendingPoolCore.LendingPoolCore__EthTransferFailed.selector, address(receiver), feeAmount
            )
        );
        core.liquidateFee(EthAddressLib.ethAddress(), feeAmount, payable(address(receiver)));

        assertEq(address(core).balance, feeAmount);
    }

    function testLiquidateFeeRevertsWhenCoreHasInsufficientERC20Balance() external {
        address destination = makeAddr("feeCollector");
        uint256 coreBalance = 1 ether;
        uint256 feeAmount = 2 ether;
        token.mint(address(core), coreBalance);

        vm.prank(lendingPool);
        vm.expectRevert();
        core.liquidateFee(address(token), feeAmount, payable(destination));

        assertEq(token.balanceOf(address(core)), coreBalance);
        assertEq(token.balanceOf(destination), 0);
    }
}
