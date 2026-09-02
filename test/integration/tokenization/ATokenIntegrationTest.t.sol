// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../../mocks/tokens/MockERC20.sol";
import {FeeProvider} from "src/fees/FeeProvider.sol";
import {MockPriceOracle} from "../../mocks/oracle/MockPriceOracle.sol";
import {MockReserveInterestRateStrategy} from "../../mocks/MockReserveInterestRateStrategy.sol";

import {AToken} from "src/tokenization/AToken.sol";
import {LendingPool} from "src/lendingpool/LendingPool.sol";
import {LendingPoolCore} from "src/lendingpool/LendingPoolCore.sol";
import {LendingPoolDataProvider} from "src/lendingpool/LendingPoolDataProvider.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";
import {CoreLibrary} from "src/libraries/CoreLibrary.sol";
import {LendingPoolParametersProvider} from "src/configuration/LendingPoolParametersProvider.sol";

contract ATokenIntegrationTest is Test {
    address public user = makeAddr("user");
    address public secondUser = makeAddr("secondUser");
    address public configurator = makeAddr("configurator");

    LendingPoolAddressesProvider public addressesProvider;
    LendingPoolCore public core;
    LendingPool public pool;
    LendingPoolDataProvider public dataProvider;

    MockERC20 public dai;
    AToken public aDai;
    MockERC20 public weth;
    AToken public aWeth;
    MockReserveInterestRateStrategy public interestRateStrategy;
    MockPriceOracle public priceOracle;

    function setUp() external {
        addressesProvider = new LendingPoolAddressesProvider(address(this));

        addressesProvider.setLendingPool(makeAddr("temporaryLendingPool"));
        core = new LendingPoolCore(address(addressesProvider));
        addressesProvider.setLendingPoolCore(address(core));

        dataProvider = new LendingPoolDataProvider(address(addressesProvider));
        addressesProvider.setLendingPoolDataProvider(address(dataProvider));
        addressesProvider.setFeeProvider(address(new FeeProvider()));
        addressesProvider.setLendingPoolParametersProvider(address(new LendingPoolParametersProvider()));

        pool = new LendingPool(address(addressesProvider));
        addressesProvider.setLendingPool(address(pool));

        addressesProvider.setLendingPoolConfigurator(configurator);

        dai = new MockERC20("Mock DAI", "DAI");
        weth = new MockERC20("Mock WETH", "WETH");

        aDai = new AToken(address(addressesProvider), address(dai), dai.decimals(), "Aave interest bearing DAI", "aDAI");
        aWeth = new AToken(
            address(addressesProvider), address(weth), weth.decimals(), "Aave interest bearing WETH", "aWETH"
        );

        interestRateStrategy = new MockReserveInterestRateStrategy();
        priceOracle = new MockPriceOracle();
        addressesProvider.setPriceOracle(address(priceOracle));

        vm.startPrank(configurator);
        core.initReserve(address(dai), address(aDai), dai.decimals(), address(interestRateStrategy));
        core.initReserve(address(weth), address(aWeth), weth.decimals(), address(interestRateStrategy));
        core.enableReserveAsCollateral(address(dai), 75, 80, 105);
        core.enableReserveAsCollateral(address(weth), 75, 80, 105);
        core.enableBorrowingOnReserve(address(dai), false);
        vm.stopPrank();

        priceOracle.setAssetPrice(address(dai), 0.0005 ether); // 1 ETH = 2,000 DAI
        priceOracle.setAssetPrice(address(weth), 1 ether);

        dai.mint(user, 100 ether);
    }

    /////////////////////////////////////
    //             redeem              //
    /////////////////////////////////////

    // verifies the basic supply → partial withdrawal lifecycle for DAI.
    // With no time passage or borrowing, no interest has accrued
    function testUserCanDepositAndRedeemUnderlying() external {
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;
        uint256 redeemAmount = 40 ether;

        // The user deposits 100 DAI and redeems 40 DAI
        vm.startPrank(user);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);

        aDai.redeem(redeemAmount);
        vm.stopPrank();

        // No passage of time
        assertEq(dai.balanceOf(user), redeemAmount); // 40
        assertEq(dai.balanceOf(address(core)), depositAmount - redeemAmount); // 100 - 40 = 60
        assertEq(aDai.balanceOf(user), depositAmount - redeemAmount); // 100 - 40 = 60
        assertEq(aDai.principalBalanceOf(user), depositAmount - redeemAmount); // 100 - 40 = 60

        // Core's DAI balance = 100 - 40 = 60
        assertEq(core.getReserveAvailableLiquidity(address(dai)), depositAmount - redeemAmount);
        assertEq(aDai.getUserIndex(user), WadRayMath.ray()); // Unchanged intial index

        (uint256 underlyingBalance,,, bool useAsCollateral) = core.getUserBasicReserveData(address(dai), user);
        assertEq(underlyingBalance, depositAmount - redeemAmount);
        assertTrue(useAsCollateral); // DAI still enabled as collateral
    }

    // checks the “withdraw everything”
    // There is no passage of time, so no interest accrued
    function testUserCanRedeemEntireBalanceWithMaxUintWithoutAccruedInterest() external {
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;

        // The user deposits 100 DAI and redeems everything
        vm.startPrank(user);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);
        aDai.redeem(type(uint256).max);
        vm.stopPrank();

        assertEq(dai.balanceOf(user), depositAmount); // 100
        assertEq(dai.balanceOf(address(core)), 0); // 0
        
        // Core's DAI balance = 0
        assertEq(core.getReserveAvailableLiquidity(address(dai)), 0);

        assertEq(aDai.balanceOf(user), 0); // 0
        assertEq(aDai.principalBalanceOf(user), 0); // 0
        assertEq(aDai.getUserIndex(user), 0);// The user's index is reset under total redeem

        (uint256 underlyingBalance,,, bool useAsCollateral) = core.getUserBasicReserveData(address(dai), user);
        assertEq(underlyingBalance, 0);
        assertFalse(useAsCollateral);
    }

    // proves that a partial redemption first records accrued interest, then burns the amount being withdrawn.
    // There is passage of time, so interest is accrued
    // There is a  borrow so updateCumulativeIndexes can update the cumulative indexes
    function testRedeemCheckpointsAccruedInterestBeforeBurningPartialBalance() external {
        address liquidityProvider = makeAddr("liquidityProvider");
        uint256 depositAmount = 100 ether;
        uint256 borrowAmount = 20 ether;
        uint256 redeemAmount = 40 ether;
        uint256 liquidityRate = 5e25; // 5% annual liquidity rate
        uint16 referralCode = 0;

        interestRateStrategy.setRates(liquidityRate, 0, 0);
        dai.mint(liquidityProvider, depositAmount);
        weth.mint(secondUser, 1 ether);

        vm.startPrank(user);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);
        vm.stopPrank();

        vm.startPrank(secondUser);
        weth.approve(address(core), 1 ether);
        pool.deposit(address(weth), 1 ether, referralCode);
        // This is necessary because updateCumulativeIndexes() only persists index growth while the DAI reserve has outstanding debt.
        pool.borrow(address(dai), borrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), referralCode);
        vm.stopPrank();

        // Initial setup
        // user: deposits 100 DAI
        // liquidityProvider: deposits 100 DAI
        // secondUser: deposits 1 WETH as collateral, then borrows 20 DAI

        vm.warp(block.timestamp + 365 days);

        // After one year the current normalized income is 1.05 ray
        // The user's stored principal aDAI balance is 100
        // aDai.balanceOf(user) live balance is: 100 x 1.05 = 105 aDAI
        assertEq(aDai.balanceOf(user), 105 ether);

        // The user redeems 40 DAI
        vm.prank(user);
        aDai.redeem(redeemAmount);

        // When you do AToken.redeem(40) it happens this:
        //
        // 1. Calculate current balance: 105
        // 2. Materialize accrued interest: mint 5 aDAI
        // 3. Burn the requested 40 aDAI
        // 4. Update the reserve's stored liquidity index to 1.05
        // 5. Transfer 40 DAI to the user

        assertEq(dai.balanceOf(user), redeemAmount); // 40

        // The aDAI user balance is: 100 + 5 accrued - 40 redeemed = 65 aDAI
        assertEq(aDai.principalBalanceOf(user), 65 ether);
        assertEq(aDai.balanceOf(user), 65 ether);

        assertEq(aDai.getUserIndex(user), 105e25); // 1.05 ray

        // Core DAI balance = 100 DAI (user deposit) + 100 DAI (liquidityProvider deposit) - 20 DAI (secondUser borrow) - 40 DAI (user redeem)
        // Core DAI balance = 140 DAI
        assertEq(dai.balanceOf(address(core)), 140 ether);
        assertEq(core.getReserveAvailableLiquidity(address(dai)), 140 ether);
    }
}
