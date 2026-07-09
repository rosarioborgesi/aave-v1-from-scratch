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
import {LendingPoolDataProvider} from "src/lendingpool/LendingPoolDataProvider.sol";

contract LendingPoolCoreHarness is LendingPoolCore {
    constructor(address addressesProvider) LendingPoolCore(addressesProvider) {}

    function getUserUseReserveAsCollateral(address user, address reserve) external view returns (bool) {
        return s_usersReserveData[user][reserve].useAsCollateral;
    }

    function setReserveActive(address reserve, bool isActive) external {
        s_reserves[reserve].isActive = isActive;
    }

    function setReserveFreeze(address reserve, bool isFreezed) external {
        s_reserves[reserve].isFreezed = isFreezed;
    }

    function setReserveBorrows(address reserve, uint256 stableBorrows, uint256 variableBorrows) external {
        s_reserves[reserve].totalBorrowsStable = stableBorrows;
        s_reserves[reserve].totalBorrowsVariable = variableBorrows;
    }
}

contract LendingPoolIntegrationTest is Test {
    uint256 public constant DEPOSIT_AMOUNT = 100 ether;
    uint16 public constant REFERRAL_CODE = 0;

    address public user = makeAddr("user");
    address public secondUser = makeAddr("secondUser");
    address public configurator = makeAddr("configurator");

    LendingPoolAddressesProvider public addressesProvider;
    LendingPoolCoreHarness public core;
    LendingPool public pool;
    LendingPoolDataProvider public dataProvider;

    MockERC20 public dai;
    AToken public aDai;
    MockReserveInterestRateStrategy public interestRateStrategy;

    function setUp() external {
        addressesProvider = new LendingPoolAddressesProvider(address(this));

        addressesProvider.setLendingPool(makeAddr("temporaryLendingPool"));
        core = new LendingPoolCoreHarness(address(addressesProvider));
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
    //             deposit             //
    /////////////////////////////////////

    // This test checks the complete first-deposit flow.
    //
    // The user starts with 100 DAI and the reserve starts empty:
    //
    // user DAI = DEPOSIT_AMOUNT = 100 ether = 100e18
    // core DAI = 0
    // user aDAI = 0
    //
    // When the user deposits 100 DAI:
    //
    // user DAI = 100e18 - 100e18
    // user DAI = 0
    //
    // core DAI = 0 + 100e18
    // core DAI = 100e18
    //
    // aTokens are minted 1:1 with the deposited underlying amount:
    //
    // user aDAI = 100e18
    //
    // This is the user's first interaction with the reserve, so the aToken
    // user index is initialized to the current normalized income.
    //
    // At reserve initialization:
    //
    // current normalized income = 1 ray
    // user index = RAY = 1e27
    //
    // Because the core contract now holds the deposited DAI, available
    // liquidity is exactly the reserve's underlying balance:
    //
    // available liquidity = core DAI
    // available liquidity = 100e18
    //
    // Since this is the first deposit, the reserve is also enabled as
    // collateral for the user.
    function testDepositTransfersUnderlyingToCoreAndMintsATokens() external {
        vm.startPrank(user);
        dai.approve(address(core), DEPOSIT_AMOUNT);

        pool.deposit(address(dai), DEPOSIT_AMOUNT, REFERRAL_CODE);
        vm.stopPrank();

        assertEq(dai.balanceOf(user), 0);
        assertEq(dai.balanceOf(address(core)), DEPOSIT_AMOUNT);
        assertEq(aDai.balanceOf(user), DEPOSIT_AMOUNT);
        assertEq(aDai.getUserIndex(user), WadRayMath.ray());
        assertEq(core.getReserveAvailableLiquidity(address(dai)), DEPOSIT_AMOUNT);
        (,,, bool useAsCollateral) = core.getUserBasicReserveData(address(dai), user);
        assertTrue(useAsCollateral);
    }

    function testDepositRevertsIfReserveIsInactive() external {
        core.setReserveActive(address(dai), false);

        vm.prank(user);
        vm.expectRevert(LendingPool.LendingPool__ReserveIsNotActive.selector);

        pool.deposit(address(dai), DEPOSIT_AMOUNT, REFERRAL_CODE);
    }

    function testDepositRevertsIfReserveIsFrozen() external {
        core.setReserveFreeze(address(dai), true);

        vm.prank(user);
        vm.expectRevert(LendingPool.LendingPool__ReserveIsFrozen.selector);

        pool.deposit(address(dai), DEPOSIT_AMOUNT, REFERRAL_CODE);
    }

    // This test checks that a second deposit is added to the user's existing
    // aToken balance and to the reserve's available liquidity.
    //
    // The user starts with:
    //
    // user DAI = 150e18
    // core DAI = 0
    // user aDAI = 0
    //
    // First deposit:
    //
    // first deposit amount = 100e18
    //
    // user DAI = 150e18 - 100e18
    // user DAI = 50e18
    //
    // core DAI = 100e18
    //
    // user aDAI = 100e18
    //
    // Second deposit:
    //
    // second deposit amount = 50e18
    //
    // user DAI = 50e18 - 50e18
    // user DAI = 0
    //
    // core DAI = 100e18 + 50e18
    // core DAI = 150e18
    //
    // user aDAI = 100e18 + 50e18
    // user aDAI = 150e18
    //
    // No time passes and no interest accrues between the two deposits:
    //
    // user index after first deposit = 1.00 ray
    // current normalized income at second deposit = 1.00 ray
    // balance increase before second deposit = 0
    //
    // Since the user already has an aToken balance:
    //
    // isFirstDeposit = false
    function testSecondDepositAddsToExistingBalance() external {
        uint256 firstDepositAmount = 100 ether;
        uint256 secondDepositAmount = 50 ether;
        uint256 totalDepositAmount = firstDepositAmount + secondDepositAmount;

        dai.mint(user, secondDepositAmount);

        vm.startPrank(user);
        dai.approve(address(core), totalDepositAmount);

        pool.deposit(address(dai), firstDepositAmount, REFERRAL_CODE);

        pool.deposit(address(dai), secondDepositAmount, REFERRAL_CODE);
        vm.stopPrank();

        assertEq(dai.balanceOf(user), 0);
        assertEq(dai.balanceOf(address(core)), totalDepositAmount);
        assertEq(aDai.balanceOf(user), totalDepositAmount);
        assertEq(core.getReserveAvailableLiquidity(address(dai)), totalDepositAmount);
    }

    // This test checks that already accrued interest is materialized before
    // minting a second deposit.
    //
    // The user first deposits:
    //
    // first deposit = 100e18 DAI
    //
    // Initial aToken state:
    //
    // principal balance = 100e18
    // user index = 1.00 ray
    //
    // The reserve liquidity rate is set to 5% annually:
    //
    // liquidity rate = 0.05 ray
    //
    // One full year passes:
    //
    // time difference = 365 days
    // seconds per year = 365 days
    //
    // Linear interest:
    //
    // linear interest = 1 ray + liquidityRate * timeDifference / secondsPerYear
    //
    // linear interest = 1.00 ray + 0.05 ray * 365 days / 365 days
    // linear interest = 1.05 ray
    //
    // Since the previous liquidity index was 1.00 ray:
    //
    // current normalized income = previous liquidity index * linear interest
    //
    // current normalized income = 1.00 ray * 1.05 ray
    // current normalized income = 1.05 ray
    //
    // Before the second deposit, the user's current balance is:
    //
    // current balance = principalBalance * currentNormalizedIncome / userIndex
    //
    // current balance = 100e18 * 1.05e27 / 1e27
    // current balance = 105e18
    //
    // The accrued interest is:
    //
    // balance increase = current balance - principal balance
    //
    // balance increase = 105e18 - 100e18
    // balance increase = 5e18
    //
    // The user then deposits another:
    //
    // second deposit = 20e18 DAI
    //
    // mintOnDeposit() first materializes the old interest and then mints the
    // new deposit:
    //
    // final principal = old principal + accrued interest + new deposit
    //
    // final principal = 100e18 + 5e18 + 20e18
    // final principal = 125e18
    //
    // Only underlying deposits are transferred to the core:
    //
    // core DAI = first deposit + second deposit
    //
    // core DAI = 100e18 + 20e18
    // core DAI = 120e18
    //
    // The 5e18 interest is accounting growth represented by aTokens. It is
    // not an additional DAI transfer from the user.
    function testSecondDepositAfterAccruedInterestMaterializesOldInterestBeforeMinting() external {
        uint256 secondDepositAmount = 20 ether;
        uint256 liquidityRate = 5e25; // 5%

        interestRateStrategy.setRates(liquidityRate, 0, 0);
        dai.mint(user, secondDepositAmount);

        vm.startPrank(user);
        dai.approve(address(core), DEPOSIT_AMOUNT + secondDepositAmount);
        pool.deposit(address(dai), DEPOSIT_AMOUNT, REFERRAL_CODE);
        vm.stopPrank();

        // We are simulating a borrow so that CoreLibrary.updateCumulativeIndexes can update its stored cumulative indexes
        // because totalBorrows > 0
        core.setReserveBorrows(address(dai), 1 ether, 0);
        vm.warp(block.timestamp + 365 days);

        vm.prank(user);
        pool.deposit(address(dai), secondDepositAmount, REFERRAL_CODE);

        // first deposit = 100 DAI
        // normalized income = 1.05 ray
        // accrued interest = 100 * 1.05 - 100 = 5 aDAI
        // second deposit = 20 DAI
        // final principal = 100 + 5 + 20 = 125 aDAI
        assertEq(aDai.principalBalanceOf(user), 125 ether);

        // Immediately after the second deposit, the user index has been updated
        // to the current normalized income, so no additional unmaterialized
        // interest remains:
        //
        // current balance = 125e18 * 1.05e27 / 1.05e27
        // current balance = 125e18
        assertEq(aDai.balanceOf(user), 125 ether);

        // _cumulateBalance() updates the user's index to the reserve's current
        // normalized income before the new deposit is minted.
        //
        // The reserve started at 1.00 ray and accrued 5% linear interest over one year:
        //
        // current normalized income = 1.00 ray * 1.05
        // current normalized income = 1.05 ray
        // current normalized income = 1.05e27 = 105e25
        //
        // This becomes the user's new checkpoint, so future interest is calculated
        // only from 1.05 ray onward.
        assertEq(aDai.getUserIndex(user), 105e25);

        // Only the two underlying deposits entered the core:
        //
        // core DAI = 100e18 + 20e18
        // core DAI = 120e18
        assertEq(dai.balanceOf(address(core)), 120 ether);
        assertEq(core.getReserveAvailableLiquidity(address(dai)), 120 ether);
    }

    // This test checks that native ETH cannot be sent together with an ERC20
    // deposit.
    //
    // DAI is an ERC20 reserve, so:
    //
    // msg.value must be 0
    //
    // In this test:
    //
    // deposit amount = 100e18 DAI
    // msg.value = 1 ETH
    //
    // LendingPoolCore should reject the operation because an ERC20 transfer
    // and a native ETH transfer cannot be performed in the same deposit.
    function testErc20DepositRevertsIfEthIsSent() external {
        vm.deal(user, 1 ether);

        vm.startPrank(user);
        dai.approve(address(core), DEPOSIT_AMOUNT);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__CantSendEthAndTransferErc20.selector);
        pool.deposit{value: 1 ether}(address(dai), DEPOSIT_AMOUNT, REFERRAL_CODE);
        vm.stopPrank();
    }

    // This test checks the insufficient underlying balance case.
    //
    // The user approves the full deposit amount, so allowance is sufficient.
    //
    // user DAI balance = 100e18
    // approved amount = 101e18
    // requested deposit = 101e18
    //
    // The transfer fails because:
    //
    // user balance < requested deposit
    //
    // 100e18 < 101e18
    function testDepositRevertsIfUserBalanceIsInsufficient() external {
        uint256 amountGreaterThanBalance = DEPOSIT_AMOUNT + 1 ether;

        vm.prank(user);
        dai.approve(address(core), amountGreaterThanBalance);

        vm.prank(user);
        vm.expectRevert();

        pool.deposit(address(dai), amountGreaterThanBalance, REFERRAL_CODE);
    }

    // This test checks that deposits from different users are accounted for
    // independently while reserve liquidity is aggregated.
    //
    // Alice deposits:
    //
    // Alice deposit = 100e18 DAI
    //
    // Alice aDAI = 100e18
    // Alice aDAI = 100e18
    //
    // core liquidity = 100e18
    // core liquidity = 100e18
    //
    // Bob deposits:
    //
    // Bob deposit = 50e18 DAI
    //
    // Bob aDAI = 50e18
    // Bob aDAI = 50e18
    //
    // core liquidity = 100e18 + 50e18
    // core liquidity = 150e18
    //
    // User accounting remains separate:
    //
    // Alice aDAI = 100e18
    // Bob aDAI = 50e18
    //
    // Both users make their first deposit while the normalized income is still
    // 1.00 ray:
    //
    // Alice user index = 1.00 ray
    // Bob user index = 1.00 ray
    //
    // Both users independently enable the reserve as collateral.
    function testTwoDifferentUsersDeposit() external {
        uint256 secondUserDepositAmount = 50 ether;
        uint256 totalDepositAmount = DEPOSIT_AMOUNT + secondUserDepositAmount;

        dai.mint(secondUser, secondUserDepositAmount);

        vm.startPrank(user);
        dai.approve(address(core), DEPOSIT_AMOUNT);
        pool.deposit(address(dai), DEPOSIT_AMOUNT, REFERRAL_CODE);
        vm.stopPrank();

        vm.startPrank(secondUser);
        dai.approve(address(core), secondUserDepositAmount);
        pool.deposit(address(dai), secondUserDepositAmount, REFERRAL_CODE);
        vm.stopPrank();

        // Reserve liquidity aggregates both deposits:
        //
        // total liquidity = 100e18 + 50e18
        // total liquidity = 150e18
        assertEq(dai.balanceOf(address(core)), totalDepositAmount);
        assertEq(core.getReserveAvailableLiquidity(address(dai)), totalDepositAmount);

        // Each user owns only the aTokens minted for their own deposit.
        assertEq(aDai.balanceOf(user), DEPOSIT_AMOUNT);
        assertEq(aDai.balanceOf(secondUser), secondUserDepositAmount);

        // Both users entered at the same 1.00 ray normalized income.
        assertEq(aDai.getUserIndex(user), WadRayMath.ray());
        assertEq(aDai.getUserIndex(secondUser), WadRayMath.ray());

        (,,, bool userUseAsCollateral) = core.getUserBasicReserveData(address(dai), user);
        (,,, bool secondUserUseAsCollateral) = core.getUserBasicReserveData(address(dai), secondUser);

        assertTrue(userUseAsCollateral);
        assertTrue(secondUserUseAsCollateral);
    }

    // This test checks that a zero-amount deposit is rejected.
    //
    // deposit amount = 0
    //
    // onlyAmountGreaterThanZero() should revert before:
    //
    // - reserve state is updated
    // - aTokens are minted
    // - DAI is transferred
    function testDepositRevertsIfAmountIsZero() external {
        vm.prank(user);
        vm.expectRevert(LendingPool.LendingPool__AmountIsZero.selector);

        pool.deposit(address(dai), 0, REFERRAL_CODE);
    }

    // This test checks the missing-approval case.
    //
    // The user owns enough DAI:
    //
    // user DAI balance = 100e18
    //
    // However, the user has not approved LendingPoolCore:
    //
    // allowance to LendingPoolCore = 0
    //
    // The requested deposit is:
    //
    // deposit amount = 100e18
    //
    // transferFrom() should fail because:
    //
    // allowance < deposit amount
    //
    // 0 < 100e18
    function testDepositRevertsIfUserDidNotApproveCore() external {
        vm.prank(user);
        vm.expectRevert();

        pool.deposit(address(dai), DEPOSIT_AMOUNT, REFERRAL_CODE);
    }
}
