// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockReserveInterestRateStrategy} from "../../mocks/MockReserveInterestRateStrategy.sol";

import {AToken} from "src/tokenization/AToken.sol";
import {LendingPool} from "src/lendingpool/LendingPool.sol";
import {LendingPoolCore} from "src/lendingpool/LendingPoolCore.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";

contract LendingPoolCoreHarness is LendingPoolCore {
    constructor(address addressesProvider) LendingPoolCore(addressesProvider) {}

    function getUserUseReserveAsCollateral(address user, address reserve) external view returns (bool) {
        return s_usersReserveData[user][reserve].useAsCollateral;
    }
}

contract LendingPoolIntegrationTest is Test {
    uint256 public constant DEPOSIT_AMOUNT = 100 ether;
    uint16 public constant REFERRAL_CODE = 0;

    address public user = makeAddr("user");
    address public configurator = makeAddr("configurator");

    LendingPoolAddressesProvider public addressesProvider;
    LendingPoolCoreHarness public core;
    LendingPool public pool;

    MockERC20 public dai;
    AToken public aDai;
    MockReserveInterestRateStrategy public interestRateStrategy;

    function setUp() external {
        addressesProvider = new LendingPoolAddressesProvider(address(this));

        core = new LendingPoolCoreHarness(address(addressesProvider));
        addressesProvider.setLendingPoolCore(address(core));

        pool = new LendingPool(address(addressesProvider));
        addressesProvider.setLendingPool(address(pool));

        addressesProvider.setLendingPoolConfigurator(configurator);

        dai = new MockERC20("Mock DAI", "DAI");

        aDai = new AToken(address(addressesProvider), address(dai), dai.decimals(), "Aave interest bearing DAI", "aDAI");

        interestRateStrategy = new MockReserveInterestRateStrategy();

        vm.startPrank(configurator);
        core.initReserve(address(dai), address(aDai), dai.decimals(), address(interestRateStrategy));
        vm.stopPrank();

        dai.mint(user, DEPOSIT_AMOUNT);
    }

    // User starts with 100 DAI and the reserve starts empty:
    //
    // userDAI = DEPOSIT_AMOUNT = 100 ether = 100e18
    // coreDAI = 0
    // userADAI = 0
    //
    // When the user deposits 100 DAI:
    //
    // userDAI = 100e18 - 100e18 = 0
    // coreDAI = 0 + 100e18 = 100e18
    //
    // aTokens are minted 1:1 with the deposited underlying amount:
    //
    // userADAI = 0 + 100e18 = 100e18
    //
    // This is the user's first interaction with the reserve, so the aToken
    // user index is initialized to 1 ray:
    //
    // userIndex = RAY = 1e27
    //
    // Because the core contract now holds the deposited DAI, available
    // liquidity is exactly the reserve's underlying balance:
    //
    // availableLiquidity = coreDAI = 100e18
    function testDepositTransfersUnderlyingToCoreAndMintsATokens() external {
        vm.startPrank(user);
        dai.approve(address(core), DEPOSIT_AMOUNT);

        pool.deposit(address(dai), DEPOSIT_AMOUNT, REFERRAL_CODE);
        vm.stopPrank();

        // 1. User DAI balance decreased
        assertEq(dai.balanceOf(user), 0);

        // 2. Core DAI balance increased
        assertEq(dai.balanceOf(address(core)), DEPOSIT_AMOUNT);

        // 3. User received aDAI
        assertEq(aDai.balanceOf(user), DEPOSIT_AMOUNT);

        // 4. User index was initialized to 1 ray
        assertEq(aDai.getUserIndex(user), WadRayMath.ray());

        // 5. Core available liquidity increased
        assertEq(core.getReserveAvailableLiquidity(address(dai)), DEPOSIT_AMOUNT);

        (,,, bool useAsCollateral) = core.getUserBasicReserveData(address(dai), user);

        // 6. User reserve data was updated to use the reserve as collateral
        assertTrue(useAsCollateral);
    }

    function testDepositRevertsIfAmountIsZero() external {
        vm.prank(user);
        vm.expectRevert(LendingPool.LendingPool__AmountIsZero.selector);

        pool.deposit(address(dai), 0, REFERRAL_CODE);
    }

    function testDepositRevertsIfUserDidNotApproveCore() external {
        vm.prank(user);
        vm.expectRevert();

        pool.deposit(address(dai), DEPOSIT_AMOUNT, REFERRAL_CODE);
    }
}
