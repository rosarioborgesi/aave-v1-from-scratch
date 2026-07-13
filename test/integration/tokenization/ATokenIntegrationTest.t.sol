// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockReserveInterestRateStrategy} from "../../mocks/MockReserveInterestRateStrategy.sol";

import {AToken} from "src/tokenization/AToken.sol";
import {LendingPool} from "src/lendingpool/LendingPool.sol";
import {LendingPoolCore} from "src/lendingpool/LendingPoolCore.sol";
import {LendingPoolDataProvider} from "src/lendingpool/LendingPoolDataProvider.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";

contract ATokenIntegrationTest is Test {
    uint256 public constant DEPOSIT_AMOUNT = 100 ether;
    uint16 public constant REFERRAL_CODE = 0;

    address public user = makeAddr("user");
    address public configurator = makeAddr("configurator");

    LendingPoolAddressesProvider public addressesProvider;
    LendingPoolCore public core;
    LendingPool public pool;
    LendingPoolDataProvider public dataProvider;

    MockERC20 public dai;
    AToken public aDai;
    MockReserveInterestRateStrategy public interestRateStrategy;

    function setUp() external {
        addressesProvider = new LendingPoolAddressesProvider(address(this));

        addressesProvider.setLendingPool(makeAddr("temporaryLendingPool"));
        core = new LendingPoolCore(address(addressesProvider));
        addressesProvider.setLendingPoolCore(address(core));

        pool = new LendingPool(address(addressesProvider));
        addressesProvider.setLendingPool(address(pool));

        dataProvider = new LendingPoolDataProvider(address(addressesProvider));
        addressesProvider.setLendingPoolDataProvider(address(dataProvider));

        addressesProvider.setLendingPoolConfigurator(configurator);

        dai = new MockERC20("Mock DAI", "DAI");

        aDai = new AToken(address(addressesProvider), address(dai), dai.decimals(), "Aave interest bearing DAI", "aDAI");

        interestRateStrategy = new MockReserveInterestRateStrategy();

        vm.startPrank(configurator);
        core.initReserve(address(dai), address(aDai), dai.decimals(), address(interestRateStrategy));
        vm.stopPrank();

        dai.mint(user, DEPOSIT_AMOUNT);
    }

    /////////////////////////////////////
    //             redeem              //
    /////////////////////////////////////

    function testUserCanDepositAndRedeemUnderlying() external {
        uint256 redeemAmount = 40 ether;

        vm.startPrank(user);
        dai.approve(address(core), DEPOSIT_AMOUNT);
        pool.deposit(address(dai), DEPOSIT_AMOUNT, REFERRAL_CODE);

        aDai.redeem(redeemAmount);
        vm.stopPrank();

        assertEq(dai.balanceOf(user), redeemAmount);
        assertEq(dai.balanceOf(address(core)), DEPOSIT_AMOUNT - redeemAmount);
        assertEq(aDai.balanceOf(user), DEPOSIT_AMOUNT - redeemAmount);
        assertEq(aDai.principalBalanceOf(user), DEPOSIT_AMOUNT - redeemAmount);
        assertEq(core.getReserveAvailableLiquidity(address(dai)), DEPOSIT_AMOUNT - redeemAmount);
        assertEq(aDai.getUserIndex(user), WadRayMath.ray());

        (uint256 underlyingBalance,,, bool useAsCollateral) = core.getUserBasicReserveData(address(dai), user);
        assertEq(underlyingBalance, DEPOSIT_AMOUNT - redeemAmount);
        assertTrue(useAsCollateral);
    }
}
