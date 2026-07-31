// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockFeeProvider} from "../../mocks/MockFeeProvider.sol";
import {MockPriceOracle} from "../../mocks/MockPriceOracle.sol";
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
        addressesProvider.setFeeProvider(address(new MockFeeProvider()));
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

    // TODO add more tests to extends coverage and edge cases

    function testUserCanDepositAndRedeemUnderlying() external {
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;
        uint256 redeemAmount = 40 ether;

        vm.startPrank(user);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);

        aDai.redeem(redeemAmount);
        vm.stopPrank();

        assertEq(dai.balanceOf(user), redeemAmount);
        assertEq(dai.balanceOf(address(core)), depositAmount - redeemAmount);
        assertEq(aDai.balanceOf(user), depositAmount - redeemAmount);
        assertEq(aDai.principalBalanceOf(user), depositAmount - redeemAmount);
        assertEq(core.getReserveAvailableLiquidity(address(dai)), depositAmount - redeemAmount);
        assertEq(aDai.getUserIndex(user), WadRayMath.ray());

        (uint256 underlyingBalance,,, bool useAsCollateral) = core.getUserBasicReserveData(address(dai), user);
        assertEq(underlyingBalance, depositAmount - redeemAmount);
        assertTrue(useAsCollateral);
    }

    function testUserCanRedeemEntireBalanceWithMaxUintWithoutAccruedInterest() external {
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;
        
        vm.startPrank(user);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);
        aDai.redeem(type(uint256).max);
        vm.stopPrank();

        assertEq(dai.balanceOf(user), depositAmount);
        assertEq(dai.balanceOf(address(core)), 0);
        assertEq(core.getReserveAvailableLiquidity(address(dai)), 0);
        assertEq(aDai.balanceOf(user), 0);
        assertEq(aDai.principalBalanceOf(user), 0);
        assertEq(aDai.getUserIndex(user), 0);

        (uint256 underlyingBalance,,, bool useAsCollateral) = core.getUserBasicReserveData(address(dai), user);
        assertEq(underlyingBalance, 0);
        assertFalse(useAsCollateral);
    }

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
        // 2. Materialize accred interest: mint 5 aDAI
        // 3. Burn the requested 40 aDAI
        // 4. Update the reserve's stored liquidity index to 1.05
        // 5. Transfer 40 DAI to the user

        // The aDAI user balance is: 100 + 5 accrued - 40 redeemed = 65 aDAI

        assertEq(dai.balanceOf(user), redeemAmount);
        assertEq(aDai.principalBalanceOf(user), 65 ether);
        assertEq(aDai.balanceOf(user), 65 ether);
        assertEq(aDai.getUserIndex(user), 105e25); // 1.05 ray

        // Core DAI balance = 100 DAI (user deposit) + 100 DAI (liquidityProvider deposit) - 20 DAI (secondUser borrow) - 40 DAI (user redeem)
        // Core DAI balance = 140 DAI
        assertEq(dai.balanceOf(address(core)), 140 ether);
        assertEq(core.getReserveAvailableLiquidity(address(dai)), 140 ether);
    }
}
