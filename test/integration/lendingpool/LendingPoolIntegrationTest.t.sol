// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";

import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockFeeProvider} from "../../mocks/MockFeeProvider.sol";
import {MockPriceOracle} from "../../mocks/MockPriceOracle.sol";
import {MockReserveInterestRateStrategy} from "../../mocks/MockReserveInterestRateStrategy.sol";

import {AToken} from "src/tokenization/AToken.sol";
import {LendingPool} from "src/lendingpool/LendingPool.sol";
import {LendingPoolCore} from "src/lendingpool/LendingPoolCore.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";
import {LendingPoolDataProvider} from "src/lendingpool/LendingPoolDataProvider.sol";
import {LendingPoolParametersProvider} from "src/configuration/LendingPoolParametersProvider.sol";
import {CoreLibrary} from "src/libraries/CoreLibrary.sol";

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

    function setReserveConfiguration(
        address reserve,
        uint256 baseLtv,
        uint256 liquidationThreshold,
        bool usageAsCollateral
    ) external {
        s_reserves[reserve].baseLTVasCollateral = baseLtv;
        s_reserves[reserve].liquidationThreshold = liquidationThreshold;
        s_reserves[reserve].usageAsCollateralEnabled = usageAsCollateral;
    }
}

contract LendingPoolIntegrationTest is Test {
    using WadRayMath for uint256;

    address public user = makeAddr("user");
    address public secondUser = makeAddr("secondUser");
    address public configurator = makeAddr("configurator");
    address public feeCollector = makeAddr("feeCollector");

    LendingPoolAddressesProvider public addressesProvider;
    LendingPoolCoreHarness public core;
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
        core = new LendingPoolCoreHarness(address(addressesProvider));
        addressesProvider.setLendingPoolCore(address(core));

        dataProvider = new LendingPoolDataProvider(address(addressesProvider));
        addressesProvider.setLendingPoolDataProvider(address(dataProvider));
        addressesProvider.setFeeProvider(address(new MockFeeProvider()));
        addressesProvider.setLendingPoolParametersProvider(address(new LendingPoolParametersProvider()));
        addressesProvider.setTokenDistributor(feeCollector);

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
        vm.stopPrank();

        // DAI is configured because it is the test user's collateral:
        // - baseLTVasCollateral = 75: deposited DAI supports borrowing up to 75% of its ETH value.
        // - liquidationThreshold = 80: liquidation begins once debt exceeds 80% of DAI collateral value.
        // - usageAsCollateralEnabled = true: DAI deposits are automatically usable as collateral.
        core.setReserveConfiguration(address(dai), 75, 80, true);
        vm.prank(configurator);
        // WETH is the borrowable asset:
        // - needs borrowing enabled
        // - it doesn't need collateral parameters (core.setReserveConfiguration) unless a test deposits 
        //   WETH and uses that deposit as a collateral   
        core.enableBorrowingOnReserve(address(weth), true);

        // 1 ETH = 2,000 DAI, so 1 DAI = 0.0005 ETH.
        priceOracle.setAssetPrice(address(dai), 0.0005 ether);
        priceOracle.setAssetPrice(address(weth), 1 ether);

        dai.mint(user, 100 ether);
    }

    /////////////////////////////////////
    //             deposit             //
    /////////////////////////////////////

    // TODO add more tests to extends coverage and edge cases

    // This test checks the complete first-deposit flow.
    //
    // The user starts with 100 DAI and the reserve starts empty:
    //
    // user DAI = 100 ether = 100e18
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
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;

        vm.startPrank(user);
        dai.approve(address(core), depositAmount);

        pool.deposit(address(dai), depositAmount, referralCode);
        vm.stopPrank();

        assertEq(dai.balanceOf(user), 0);
        assertEq(dai.balanceOf(address(core)), depositAmount);
        assertEq(aDai.balanceOf(user), depositAmount);
        assertEq(aDai.getUserIndex(user), WadRayMath.ray());
        assertEq(core.getReserveAvailableLiquidity(address(dai)), depositAmount);
        (,,, bool useAsCollateral) = core.getUserBasicReserveData(address(dai), user);
        assertTrue(useAsCollateral);
    }

    function testDepositRevertsIfReserveIsInactive() external {
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;

        core.setReserveActive(address(dai), false);

        vm.prank(user);
        vm.expectRevert(LendingPool.LendingPool__ReserveIsNotActive.selector);

        pool.deposit(address(dai), depositAmount, referralCode);
    }

    function testDepositRevertsIfReserveIsFrozen() external {
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;

        core.setReserveFreeze(address(dai), true);

        vm.prank(user);
        vm.expectRevert(LendingPool.LendingPool__ReserveIsFrozen.selector);

        pool.deposit(address(dai), depositAmount, referralCode);
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
        uint16 referralCode = 0;

        dai.mint(user, secondDepositAmount);

        vm.startPrank(user);
        dai.approve(address(core), totalDepositAmount);

        pool.deposit(address(dai), firstDepositAmount, referralCode);

        pool.deposit(address(dai), secondDepositAmount, referralCode);
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
        uint256 firstDepositAmount = 100 ether;
        uint256 secondDepositAmount = 20 ether;
        uint256 liquidityRate = 5e25; // 5%
        uint16 referralCode = 0;

        interestRateStrategy.setRates(liquidityRate, 0, 0);
        dai.mint(user, secondDepositAmount);

        vm.startPrank(user);
        dai.approve(address(core), firstDepositAmount + secondDepositAmount);
        pool.deposit(address(dai), firstDepositAmount, referralCode);
        vm.stopPrank();

        // We are simulating a borrow so that CoreLibrary.updateCumulativeIndexes can update its stored cumulative indexes
        // because totalBorrows > 0
        core.setReserveBorrows(address(dai), 1 ether, 0);
        vm.warp(block.timestamp + 365 days);

        vm.prank(user);
        pool.deposit(address(dai), secondDepositAmount, referralCode);

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
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;

        vm.deal(user, 1 ether);

        vm.startPrank(user);
        dai.approve(address(core), depositAmount);

        vm.expectRevert(LendingPoolCore.LendingPoolCore__CantSendEthAndTransferErc20.selector);
        pool.deposit{value: 1 ether}(address(dai), depositAmount, referralCode);
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
        uint256 depositAmount = 100 ether;
        uint256 amountGreaterThanBalance = depositAmount + 1 ether;
        uint16 referralCode = 0;

        vm.prank(user);
        dai.approve(address(core), amountGreaterThanBalance);

        vm.prank(user);
        vm.expectRevert();

        pool.deposit(address(dai), amountGreaterThanBalance, referralCode);
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
        uint256 userDepositAmount = 100 ether;
        uint256 secondUserDepositAmount = 50 ether;
        uint256 totalDepositAmount = userDepositAmount + secondUserDepositAmount;
        uint16 referralCode = 0;

        dai.mint(secondUser, secondUserDepositAmount);

        vm.startPrank(user);
        dai.approve(address(core), userDepositAmount);
        pool.deposit(address(dai), userDepositAmount, referralCode);
        vm.stopPrank();

        vm.startPrank(secondUser);
        dai.approve(address(core), secondUserDepositAmount);
        pool.deposit(address(dai), secondUserDepositAmount, referralCode);
        vm.stopPrank();

        // Reserve liquidity aggregates both deposits:
        //
        // total liquidity = 100e18 + 50e18
        // total liquidity = 150e18
        assertEq(dai.balanceOf(address(core)), totalDepositAmount);
        assertEq(core.getReserveAvailableLiquidity(address(dai)), totalDepositAmount);

        // Each user owns only the aTokens minted for their own deposit.
        assertEq(aDai.balanceOf(user), userDepositAmount);
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
        uint16 referralCode = 0;

        vm.prank(user);
        vm.expectRevert(LendingPool.LendingPool__AmountIsZero.selector);

        pool.deposit(address(dai), 0, referralCode);
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
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;

        vm.prank(user);
        vm.expectRevert();

        pool.deposit(address(dai), depositAmount, referralCode);
    }

    /////////////////////////////////////
    //              borrow             //
    /////////////////////////////////////

    // Alice deposits 100 DAI as collateral. Bob supplies 1 WETH, giving the
    // WETH reserve enough liquidity for Alice to borrow 0.02 WETH.
    //
    // 1 ETH = 2,000 DAI, so Alice's collateral is worth 0.05 ETH. Since DAI
    // has a 75% LTV, she can borrow up to 0.0375 ETH worth of assets. Her
    // 0.02 WETH borrow plus its 0.25% origination fee remains safely
    // collateralized.
    function testUserCanBorrowAtVariableRateUsingDepositedCollateral() external {
        uint256 depositAmount = 100 ether;
        uint256 wethLiquidity = 1 ether;
        uint256 borrowAmount = 0.02 ether;
        uint256 expectedBorrowFee = 0.00005 ether;
        uint16 referralCode = 0;

        vm.startPrank(user);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);
        vm.stopPrank();

        weth.mint(secondUser, wethLiquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), wethLiquidity);
        pool.deposit(address(weth), wethLiquidity, referralCode);
        vm.stopPrank();

        vm.prank(user);
        pool.borrow(address(weth), borrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), referralCode);

        // The borrowed WETH is transferred from the core to Alice.
        assertEq(weth.balanceOf(user), borrowAmount);

        // Alice has variable-rate debt equal to the amount borrowed.
        (uint256 principalBorrowBalance, uint256 compoundedBorrowBalance,) =
            core.getUserBorrowBalances(address(weth), user);
        assertEq(principalBorrowBalance, borrowAmount);
        assertEq(compoundedBorrowBalance, borrowAmount);
        assertEq(
            uint256(core.getUserCurrentBorrowRateMode(address(weth), user)),
            uint256(CoreLibrary.InterestRateMode.VARIABLE)
        );

        // Her DAI remains deposited and continues to be used as collateral.
        assertEq(aDai.balanceOf(user), depositAmount);
        (,,, bool usesDaiAsCollateral) = core.getUserBasicReserveData(address(dai), user);
        assertTrue(usesDaiAsCollateral);

        // The fee is recorded on Alice's WETH borrow position.
        (,, uint256 originationFee,) = core.getUserBasicReserveData(address(weth), user);
        assertEq(originationFee, expectedBorrowFee);

        // The borrowed WETH leaves the reserve, reducing available liquidity.
        assertEq(core.getReserveAvailableLiquidity(address(weth)), wethLiquidity - borrowAmount);
        assertEq(weth.balanceOf(address(core)), wethLiquidity - borrowAmount);
    }

    // Alice deposits DAI as collateral and borrows WETH at the reserve's
    // configured stable rate. Bob supplies the WETH liquidity.
    function testUserCanBorrowAtStableRateUsingDepositedCollateral() external {
        uint256 depositAmount = 100 ether;
        uint256 wethLiquidity = 1 ether;
        uint256 borrowAmount = 0.02 ether;
        uint256 stableBorrowRate = 0.05e27;
        uint256 expectedBorrowFee = 0.00005 ether;
        uint16 referralCode = 0;

        interestRateStrategy.setRates(0, stableBorrowRate, 0);

        vm.startPrank(user);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);
        vm.stopPrank();

        weth.mint(secondUser, wethLiquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), wethLiquidity);
        pool.deposit(address(weth), wethLiquidity, referralCode);
        vm.stopPrank();

        vm.prank(user);
        pool.borrow(address(weth), borrowAmount, uint256(CoreLibrary.InterestRateMode.STABLE), referralCode);

        (uint256 principalBorrowBalance, uint256 compoundedBorrowBalance,) =
            core.getUserBorrowBalances(address(weth), user);
        assertEq(weth.balanceOf(user), borrowAmount);
        assertEq(principalBorrowBalance, borrowAmount);
        assertEq(compoundedBorrowBalance, borrowAmount);
        assertEq(
            uint256(core.getUserCurrentBorrowRateMode(address(weth), user)),
            uint256(CoreLibrary.InterestRateMode.STABLE)
        );
        assertEq(core.getReserveTotalBorrowsStable(address(weth)), borrowAmount);
        assertEq(core.getReserveTotalBorrowsVariable(address(weth)), 0);
        assertEq(core.getReserveCurrentAverageStableBorrowRate(address(weth)), stableBorrowRate);

        (,, uint256 originationFee,) = core.getUserBasicReserveData(address(weth), user);
        assertEq(originationFee, expectedBorrowFee);
        assertEq(core.getReserveAvailableLiquidity(address(weth)), wethLiquidity - borrowAmount);
        assertEq(weth.balanceOf(address(core)), wethLiquidity - borrowAmount);
    }

    // The user redeems the maximum collateral possible that keeps health factor > 1
    function testBorrowerCanRedeemMaximumCollateralThatKeepsHealthFactorAboveOne() external {
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;

        uint256 wethLiquidity = 1 ether;
        uint256 borrowAmount = 0.02 ether;

        vm.startPrank(user);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);
        vm.stopPrank();

        weth.mint(secondUser, wethLiquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), wethLiquidity);
        pool.deposit(address(weth), wethLiquidity, referralCode);
        vm.stopPrank();

        vm.prank(user);
        pool.borrow(address(weth), borrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), referralCode);

        // borrowed WETH            = 0.02 ETH
        // origination fee (0.25%)  = 0.00005 ETH
        // total debt               = 0.02005 ETH
        // liquidation threshold    = 80%
        // minimum collateral       = 0.02005 / 0.80 = 0.0250625 ETH
        //
        // since 1 ETH = 2,000 DAI -> 1 DAI = 0.0005 ETH
        // minimum collateral       = 0.0250625 / 0.0005 = 50,125 DAI
        //
        // Alice deposited 100 DAI
        // maximum amount to redeem = 100 DAI - 50,125 DAI = 49,875
        //
        // -4,000 (DAI wei) is a tiny rounding safety buffer

        uint256 maximumSafeRedeemAmount = 49.875 ether - 4_000;

        assertTrue(aDai.isTransferAllowed(user, maximumSafeRedeemAmount));

        vm.prank(user);
        aDai.redeem(maximumSafeRedeemAmount);

        (,,,,,, uint256 healthFactor,) = dataProvider.calculateUserGlobalData(user);
        assertGt(healthFactor, WadRayMath.wad()); // healthFactor = 1000000000000000050 > 1e18
        assertEq(aDai.balanceOf(user), depositAmount - maximumSafeRedeemAmount);
    }

    // The user is trying to redeem a little bit more of the maximum collateral redeemable so health factor goes < 1
    function testBorrowerCannotRedeemCollateralThatMakesHealthFactorAtMostOne() external {
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;

        uint256 wethLiquidity = 1 ether;
        uint256 borrowAmount = 0.02 ether;

        vm.startPrank(user);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);
        vm.stopPrank();

        weth.mint(secondUser, wethLiquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), wethLiquidity);
        pool.deposit(address(weth), wethLiquidity, referralCode);
        vm.stopPrank();

        vm.prank(user);
        pool.borrow(address(weth), borrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), referralCode);

        // This leaves collateral at the health-factor boundary after rounding.
        // The maximum amout that can be redeemed is 49.875 ether - 4_000, so health factor goes < 1
        uint256 unsafeRedeemAmount = 49.875 ether - 2_000;

        vm.prank(user);
        vm.expectRevert(AToken.AToken__TransferNotAllowed.selector);
        aDai.redeem(unsafeRedeemAmount);
    }

    function testBorrowerCannotRedeemAllCollateralWhileDebtIsOutstanding() external {
        uint256 depositAmount = 100 ether;
        uint16 referralCode = 0;

        uint256 wethLiquidity = 1 ether;
        uint256 borrowAmount = 0.02 ether;

        vm.startPrank(user);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);
        vm.stopPrank();

        weth.mint(secondUser, wethLiquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), wethLiquidity);
        pool.deposit(address(weth), wethLiquidity, referralCode);
        vm.stopPrank();

        vm.prank(user);
        pool.borrow(address(weth), borrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), referralCode);

        vm.prank(user);
        vm.expectRevert(AToken.AToken__TransferNotAllowed.selector);
        aDai.redeem(type(uint256).max);
    }

    // A second variable-rate borrow checkpoints interest accrued since the first
    // borrow, adds that interest to the user's stored debt, and advances the
    // reserve variable-borrow index before adding the new loan.
    function testUserCanBorrowAgainAfterTimePassesAndAccruesVariableDebt() external {
        uint256 depositAmount = 100 ether;
        uint256 wethLiquidity = 1 ether;
        uint256 firstBorrowAmount = 0.02 ether;
        uint256 secondBorrowAmount = 0.005 ether;
        uint256 variableBorrowRate = 0.1e27;
        uint16 referralCode = 0;

        // The mock strategy supplies a 10% annual variable rate. This rate is
        // stored on the WETH reserve by the first borrow and applies for the
        // full year before the second one.
        interestRateStrategy.setRates(0, 0, variableBorrowRate);

        vm.startPrank(user);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);
        vm.stopPrank();

        weth.mint(secondUser, wethLiquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), wethLiquidity);
        pool.deposit(address(weth), wethLiquidity, referralCode);
        vm.stopPrank();

        vm.prank(user);
        pool.borrow(address(weth), firstBorrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), referralCode);

        vm.warp(block.timestamp + 365 days);

        {
            // This is the same compounded index calculation used by the reserve
            // when it checkpoints the elapsed year during the second borrow.

            // expectedVariableBorrowIndex = 1 × (1 + annualInterestRate / secondsInOneYear) ^ secondsInOneYear
            // expectedVariableBorrowIndex = 1 × (1 + 0.10 / 31,536,000) ^ 31,536,000 ≈ 1.1051709

            // Remeber the compound-interest formula
            // A = P x (1 + r / n) ^ n
            //
            // where:
            // - P = starting value, initial borrow index = 1
            // - r = annual rate, 0.10 (10%)
            // - n = number of compounding periods in one year, here 365 days = 31,536,00 seconds
            uint256 expectedVariableBorrowIndex =
                WadRayMath.ray().rayMul((WadRayMath.ray() + variableBorrowRate / 365 days).rayPow(365 days)); //≈ 1.1051709e27
            uint256 expectedAccruedDebt = firstBorrowAmount.rayMul(expectedVariableBorrowIndex); // = 0.02 × 1.1051709 ≈ 0.022103418 WETH
            uint256 expectedBorrowBalanceIncrease = expectedAccruedDebt - firstBorrowAmount; // = 0.022103418 - 0.02 ≈ 0.002103418 WETH
            uint256 expectedPrincipalBorrowBalance = expectedAccruedDebt + secondBorrowAmount;

            // The Borrow event exposes the interest materialized by this repeated
            // borrow as borrowBalanceIncrease.
            vm.expectEmit(true, true, true, true, address(pool));
            emit LendingPool.Borrow(
                address(weth),
                user,
                secondBorrowAmount,
                uint256(CoreLibrary.InterestRateMode.VARIABLE),
                variableBorrowRate,
                0.0000125 ether, // origination fee
                expectedBorrowBalanceIncrease,
                referralCode,
                block.timestamp
            );

            vm.prank(user);
            pool.borrow(address(weth), secondBorrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), referralCode);

            // The reserve index and the user's debt are checkpointed at the second
            // borrow. The new principal contains accrued interest plus both loans.
            (uint256 principalBorrowBalance, uint256 compoundedBorrowBalance, uint256 borrowBalanceIncrease) =
                core.getUserBorrowBalances(address(weth), user);
            assertEq(core.getReserveVariableBorrowsCumulativeIndex(address(weth)), expectedVariableBorrowIndex);
            assertEq(principalBorrowBalance, expectedPrincipalBorrowBalance);
            assertEq(compoundedBorrowBalance, expectedPrincipalBorrowBalance);

            // No time has passed since the second borrow, so its interest has not yet accrued.
            assertEq(borrowBalanceIncrease, 0);

            // Variable borrow totals include the materialized interest and the
            // second loan; no stable-rate debt was created.
            assertEq(core.getReserveTotalBorrowsStable(address(weth)), 0);
            assertEq(core.getReserveTotalBorrowsVariable(address(weth)), expectedPrincipalBorrowBalance);

            // The reserve stores the current variable borrow rate returned by the interest-rate strategy.
            assertEq(core.getReserveCurrentVariableBorrowRate(address(weth)), variableBorrowRate);
            assertEq(weth.balanceOf(user), firstBorrowAmount + secondBorrowAmount);
        }

        // The global account data values debt at the WETH price (1 ETH per
        // WETH), includes both origination fees, and retains the DAI collateral.
        (
            uint256 totalLiquidityBalanceETH,
            uint256 totalCollateralBalanceETH,
            uint256 totalBorrowBalanceETH,
            uint256 totalFeesETH,
            uint256 currentLtv,
            uint256 currentLiquidationThreshold,
            uint256 healthFactor,
        ) = dataProvider.calculateUserGlobalData(user);
        uint256 expectedHealthFactor =
            (0.05 ether * currentLiquidationThreshold / 100).wadDiv(totalBorrowBalanceETH + 0.0000625 ether);

        assertEq(totalLiquidityBalanceETH, 0.05 ether);
        assertEq(totalCollateralBalanceETH, 0.05 ether);
        assertEq(totalBorrowBalanceETH, core.getReserveTotalBorrowsVariable(address(weth)));
        assertEq(totalFeesETH, 0.0000625 ether);
        assertEq(currentLtv, 75);
        assertEq(currentLiquidationThreshold, 80);
        assertEq(healthFactor, expectedHealthFactor);
    }

    // A fall in the collateral's oracle price can make an otherwise valid
    // borrow unhealthy. Once that happens, the borrower cannot withdraw any
    // collateral because doing so would worsen an already unsafe position.
    function testOraclePriceShockReportsUnhealthyPositionAndBlocksCollateralWithdrawal() external {
        uint256 depositAmount = 100 ether;
        uint256 wethLiquidity = 1 ether;
        uint256 borrowAmount = 0.02 ether;
        uint256 borrowFee = 0.00005 ether;
        uint256 shockedDaiPrice = 0.00025 ether;
        uint16 referralCode = 0;

        vm.startPrank(user);
        dai.approve(address(core), depositAmount);
        pool.deposit(address(dai), depositAmount, referralCode);
        vm.stopPrank();

        weth.mint(secondUser, wethLiquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), wethLiquidity);
        pool.deposit(address(weth), wethLiquidity, referralCode);
        vm.stopPrank();

        vm.prank(user);
        pool.borrow(address(weth), borrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), referralCode);

        // DAI loses half of its ETH-denominated value: 100 DAI is now worth
        // 0.025 ETH rather than 0.05 ETH.
        priceOracle.setAssetPrice(address(dai), shockedDaiPrice);

        (
            uint256 totalLiquidityBalanceETH,
            uint256 totalCollateralBalanceETH,
            uint256 totalBorrowBalanceETH,
            uint256 totalFeesETH,,
            uint256 currentLiquidationThreshold,
            uint256 healthFactor,
            bool healthFactorBelowThreshold
        ) = dataProvider.calculateUserGlobalData(user);

        // expectedCollateralBalanceETH = depositAmount * shockedDaiPrice / 1 ether;
        // expectedCollateralBalanceETH = 100 DAI * 0.00025 ETH/DAI = 0.025 ETH
        uint256 expectedCollateralBalanceETH = depositAmount * shockedDaiPrice / 1 ether;

        // health factor = (collateral value * liquidation threshold) / (borrowed amount + fee)
        // health factor = (0.025 * 80/100) / (0.02 + 0.00005) =  0.02 / 0.02005 = 0.997506234413965087
        uint256 expectedHealthFactor =
            (expectedCollateralBalanceETH * currentLiquidationThreshold / 100).wadDiv(borrowAmount + borrowFee);

        assertEq(totalLiquidityBalanceETH, expectedCollateralBalanceETH);
        assertEq(totalCollateralBalanceETH, expectedCollateralBalanceETH);
        assertEq(totalBorrowBalanceETH, borrowAmount);
        assertEq(totalFeesETH, borrowFee);
        assertEq(currentLiquidationThreshold, 80);
        assertEq(healthFactor, expectedHealthFactor);
        assertLt(healthFactor, WadRayMath.wad());
        assertTrue(healthFactorBelowThreshold);

        vm.prank(user);
        vm.expectRevert(AToken.AToken__TransferNotAllowed.selector);
        aDai.redeem(1 ether);
    }

    /////////////////////////////////////
    //              repay              //
    /////////////////////////////////////

    // This tests the "everything is paid back correctly" path for a variable-rate loan after
    // interest has had time to grow.
    //
    // In plain terms:
    // 1. A user deposits 100 DAI as collateral.
    // 2. Another user deposits 1 WETH, giving the pool WETH to lend.
    // 3. The first user borrows 0.02 WETH at a 10% variable annual rate.
    // 4. The test advances time by one year, so the debt us now more than 0.02 WETH because
    // interest accrued
    // 5. The borrower repays using `type(uint256).max` meaning "repay my entire outstanding amount"
    // 6. The test confirms that:
    //    - the full debt, including accrued interest, is cleared;
    //    - the origination fee is cleared;
    //    - the borrower no longer has a variable borrow position or borrow rate;
    //    - the reserve's total variable debt becomes zero
    //    - principal plus interest returns to the pool
    //    - the separate borrow fee goes to `feeCollector`, not into the pool's available WETH.
    function testVariableRepayAllAfterAccrualClearsDebtAndSendsFeeToCollector() external {
        uint256 liquidity = 1 ether;
        uint256 borrowAmount = 0.02 ether;
        uint256 borrowFee = 0.00005 ether;
        uint256 variableBorrowRate = 0.1e27;

        // Stable borrowing is unused here; every borrow uses this 10% variable rate.
        interestRateStrategy.setRates(0, 0, variableBorrowRate);

        // `user` first deposits 100 DAI as collateral. At the configured price,
        // that is worth 0.05 ETH; with a 75% LTV it is enough to borrow 0.02 WETH.
        vm.startPrank(user);
        dai.approve(address(core), 100 ether);
        pool.deposit(address(dai), 100 ether, 0);
        vm.stopPrank();

        // `secondUser` supplies 1 WETH, which is the liquidity the pool lends out.
        weth.mint(secondUser, liquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), liquidity);
        pool.deposit(address(weth), liquidity, 0);
        vm.stopPrank();

        // Taking the loan moves 0.02 WETH from the 1 WETH supplied by
        // `secondUser` to `user` and records the principal debt plus its fee.
        vm.prank(user);
        pool.borrow(address(weth), borrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), 0);

        // Let a full year of variable interest accumulate without performing
        // another state-changing action on the reserve.
        //
        // The mock rate strategy returns a 10% annual variable rate. After one
        // year, the user's current debt is greater than the stored 0.02 WETH
        // principal because variable interest is compounded into the borrow
        // balance when the position is read or updated.
        vm.warp(block.timestamp + 365 days);

        // Reading the borrow balances calculates the up-to-date compounded
        // debt. `balanceIncrease` is precisely the interest accrued since the
        // borrow, so compoundedDebt = principalBefore + balanceIncrease.
        (,, uint256 balanceIncrease) = core.getUserBorrowBalances(address(weth), user);
        (uint256 principalBefore, uint256 compoundedDebt,) = core.getUserBorrowBalances(address(weth), user);
        assertGt(compoundedDebt, principalBefore);

        // The user received `borrowAmount` when borrowing. Mint only the extra
        // WETH needed to cover the accrued interest and the separate fee, then
        // approve the core to pull the complete repayment.
        uint256 userBalance = weth.balanceOf(user);
        weth.mint(user, compoundedDebt + borrowFee - userBalance);

        vm.startPrank(user);
        weth.approve(address(core), compoundedDebt + borrowFee);

        // The event distinguishes the amount that reduces the debt from the
        // origination fee. It also exposes the interest that was checkpointed
        // during repayment.
        vm.expectEmit(true, true, true, true, address(pool));
        emit LendingPool.Repay(address(weth), user, user, compoundedDebt, borrowFee, balanceIncrease, block.timestamp);

        // As the borrower is repaying their own loan, max amount is allowed and
        // resolves to compoundedDebt + borrowFee.
        pool.repay(address(weth), type(uint256).max, payable(user));
        vm.stopPrank();

        // A full repayment removes both the user's variable debt and the
        // reserve's aggregate variable debt, and resets the user's rate mode.
        (uint256 principalAfter, uint256 compoundedAfter,) = core.getUserBorrowBalances(address(weth), user);
        assertEq(principalAfter, 0);
        assertEq(compoundedAfter, 0);
        assertEq(core.getUserOriginationFee(address(weth), user), 0);
        assertEq(
            uint256(core.getUserCurrentBorrowRateMode(address(weth), user)), uint256(CoreLibrary.InterestRateMode.NONE)
        );
        assertEq(core.getReserveTotalBorrowsVariable(address(weth)), 0);
        // The core began with 1 WETH, lent out `borrowAmount`, and received
        // `compoundedDebt` back. Therefore it ends with the original liquidity
        // plus only the accrued interest. The fee bypasses the core and goes to
        // the collector, so it is not included in available liquidity.
        assertEq(weth.balanceOf(address(core)), liquidity + balanceIncrease);
        assertEq(core.getReserveAvailableLiquidity(address(weth)), liquidity + balanceIncrease);
        assertEq(weth.balanceOf(feeCollector), borrowFee);
    }

    // Verifies that a partial variable-rate repayment after interest accrues checkpoints the
    // accrued interest, pays the fee first, and leaves the remaining variable debt open.
    function testVariablePartialRepayAfterAccrualKeepsRemainingDebtAndSendsFeeToCollector() external {
        uint256 borrowAmount = 0.02 ether;
        uint256 borrowFee = 0.00005 ether;
        uint256 debtPayment = 0.005 ether;
        uint256 variableBorrowRate = 0.1e27;

        // Set the variable borrow rate to 10% annually 
        interestRateStrategy.setRates(0, 0, variableBorrowRate);

        // User deposits 100 DAI as collateral
        vm.startPrank(user);
        dai.approve(address(core), 100 ether);
        pool.deposit(address(dai), 100 ether, 0);
        vm.stopPrank();

        // Second user supplies 1 WETH as liquidity
        uint256 liquidity = 1 ether;
        weth.mint(secondUser, liquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), liquidity);
        pool.deposit(address(weth), liquidity, 0);
        vm.stopPrank();

        // User borrows 0.02 WETH, variable-rate, creating:
        //    - 0.02 WETH debt
        //    - 0.00005 WETH origination fee 
        vm.prank(user);
        pool.borrow(address(weth), borrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), 0);

        // Advance one year. The current debt is now greater than the original principal because variable interest accrued
        vm.warp(block.timestamp + 365 days);

        // compoundedDebt: principal plus accrued interest 
        //              = 0.02 WETH x (1 + 10% / 31,536,000) ^ 31,536,000
        //              = 0.022103418358008479 WETH
        //
        // balanceIncrease: the accrued-interest component
        //              = 0.022103418358008479 WETH - 0.02 WETH = 0.002103418358008479 WETH        
        (uint256 principalBefore, uint256 compoundedDebt, uint256 balanceIncrease) =
            core.getUserBorrowBalances(address(weth), user);
        assertGt(compoundedDebt, principalBefore);

        // The payment covers the full origination fee first; the remainder reduces debt.
        uint256 payment = borrowFee + debtPayment;
        weth.mint(user, payment);

        vm.startPrank(user);
        weth.approve(address(core), payment);
        vm.expectEmit(true, true, true, true, address(pool));
        emit LendingPool.Repay(address(weth), user, user, debtPayment, borrowFee, balanceIncrease, block.timestamp);
        // Repay borrowFee + 0.005 WETH. Repayment applies the fee first, then applies the remaining 
        // 0.005 WETH to debt
        pool.repay(address(weth), payment, payable(user));
        vm.stopPrank();

        uint256 expectedRemainingDebt = compoundedDebt - debtPayment;
        (uint256 principalAfter, uint256 compoundedAfter,) = core.getUserBorrowBalances(address(weth), user);

        // Remaining user debt is compoundedDebt - 0.005 WETH, meaning accrue dinterest was inlcuded before reducing debt.
        assertEq(principalAfter, expectedRemainingDebt);
        assertEq(compoundedAfter, expectedRemainingDebt);

        // Reserve-wide variable debt equals user debt
        assertEq(core.getReserveTotalBorrowsVariable(address(weth)), expectedRemainingDebt);
        assertEq(core.getUserOriginationFee(address(weth), user), 0); // 0

        // The user remaing in VARIABLE mode, proving this was not treated as a full loan closure
        assertEq(
            uint256(core.getUserCurrentBorrowRateMode(address(weth), user)), uint256(CoreLibrary.InterestRateMode.VARIABLE)
        );

        // Core liquidity rises only by 0.005 WETH
        assertEq(weth.balanceOf(address(core)), liquidity - borrowAmount + debtPayment);
        assertEq(core.getReserveAvailableLiquidity(address(weth)), liquidity - borrowAmount + debtPayment);
        assertEq(weth.balanceOf(feeCollector), borrowFee);
    }

    // verifies that an outstanding loan-origination fee is paid before any partial repayment
    // reduces variable-rate principal.
    //
    // It does a first repayment that partially pays the fees
    // and a second repayment that pays the remaning fees plus a part of the debt
    function testPartialRepayChargesFeesBeforeReducingVariableDebt() external {
        uint256 liquidity = 1 ether;
        uint256 borrowAmount = 0.02 ether;
        uint256 borrowFee = 0.00005 ether;
        uint256 firstFeePayment = 0.00002 ether;
        uint256 debtPayment = 0.005 ether;

        // user deposits 100 DAI as collateral
        vm.startPrank(user);
        dai.approve(address(core), 100 ether);
        pool.deposit(address(dai), 100 ether, 0);
        vm.stopPrank();

        // secondUser supplies 1 ETH, creating borrowable WETH liquidity
        weth.mint(secondUser, liquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), liquidity);
        pool.deposit(address(weth), liquidity, 0);
        vm.stopPrank();

        // user borrows 0.02 WETH at a variable rate
        // The mock fee provider charges 0.25%, so borrowing 0.02 WETH creates
        // a separate 0.00005 WETH fee in addition to the variable debt.
        vm.prank(user);
        pool.borrow(address(weth), borrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), 0);

        // The borrow creates:
        // Variable debt:     0.02000 WETH
        // Origination fee:   0.00005 WETH
        // Total owed:        0.02005 WETH

        // --- First repayment: fee only ---
        //
        // The user repays 0.00002 WETH, less than 0.0005 fee.
        // It must go entirely to the fee collector:
        // neither user debt nor reserve variable borrows change.
        vm.startPrank(user);
        weth.approve(address(core), firstFeePayment);
        pool.repay(address(weth), firstFeePayment, payable(user));
        vm.stopPrank();

        (uint256 principalAfterFeeOnly, uint256 debtAfterFeeOnly,) = core.getUserBorrowBalances(address(weth), user);
        assertEq(principalAfterFeeOnly, borrowAmount); // 0.02000 WETH
        assertEq(debtAfterFeeOnly, borrowAmount); // 0.02000 WETH
        assertEq(core.getReserveTotalBorrowsVariable(address(weth)), borrowAmount); // 0.02000 WETH
        assertEq(core.getUserOriginationFee(address(weth), user), borrowFee - firstFeePayment); // 0.00003 WETH
        assertEq(weth.balanceOf(address(core)), liquidity - borrowAmount); // 0.98000 WETH
        assertEq(weth.balanceOf(feeCollector), firstFeePayment); // 0.00002 WETH

        // --- Second repayment: remaining fee plus debt

        // Pay the remaining 0.00003 WETH fee plus 0.005 WETH of debt. Once the
        // fee is fully covered, only the 0.005 WETH remainder returns to the
        // reserve and reduces the user's and reserve's variable debt.
        uint256 secondPayment = (borrowFee - firstFeePayment) + debtPayment;
        vm.startPrank(user);
        weth.approve(address(core), secondPayment);
        pool.repay(address(weth), secondPayment, payable(user));
        vm.stopPrank();

        (uint256 principalAfterPartial, uint256 debtAfterPartial,) = core.getUserBorrowBalances(address(weth), user);
        assertEq(principalAfterPartial, borrowAmount - debtPayment); // 0.02000 - 0.00500 = 0.01500 WETH
        assertEq(debtAfterPartial, borrowAmount - debtPayment); // 0.02000 - 0.00500 = 0.01500 WETH
        assertEq(core.getReserveTotalBorrowsVariable(address(weth)), borrowAmount - debtPayment); // 0.02000 - 0.00500 = 0.01500 WETH
        assertEq(core.getUserOriginationFee(address(weth), user), 0); // 0
        assertEq(weth.balanceOf(address(core)), liquidity - borrowAmount + debtPayment); // 0.98000 + 0.00500 = 0.98500 WETH
        assertEq(weth.balanceOf(feeCollector), borrowFee); // 0.00005 WETH
    }

    // Verifies two rules for repaying someone else’s ERC-20 loan:
    //  - Anyone can make an explicit repayment on a borrower’s behalf.
    //  - Only the borrower may use type(uint256).max (“repay everything”).
    function testThirdPartyCanRepayExplicitErc20AmountButNotMaxAmount() external {
        uint256 borrowAmount = 0.02 ether;
        uint256 borrowFee = 0.00005 ether;
        uint256 debtPayment = 0.005 ether;
        uint256 payment = borrowFee + debtPayment;

        // User supplies 100 DAI as a collateral
        vm.startPrank(user);
        dai.approve(address(core), 100 ether);
        pool.deposit(address(dai), 100 ether, 0);
        vm.stopPrank();

        // Second user supplies 1 WETH of liquidity
        uint256 liquidity = 1 ether;
        weth.mint(secondUser, liquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), liquidity);
        pool.deposit(address(weth), liquidity, 0);
        vm.stopPrank();

        // `user` is the borrower; `secondUser` will later pay on their behalf.
        // The borrow leaves user owing 0.02 WETH plus a 0.00005 WETH fee.
        vm.prank(user);
        pool.borrow(address(weth), borrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), 0);

        // Give the prospective repayer exactly enough to settle the fee and
        // repay 0.005 WETH of `user`'s debt. The borrower keeps their WETH.
        weth.mint(secondUser, payment);
        uint256 borrowerBalanceBefore = weth.balanceOf(user);
        uint256 repayerBalanceBefore = weth.balanceOf(secondUser);

        // An explicit amount is permitted for a repayment on behalf of another
        // account. Fees are charged first, leaving `debtPayment` to reduce debt.
        vm.startPrank(secondUser);
        weth.approve(address(core), payment);
        pool.repay(address(weth), payment, payable(user));
        vm.stopPrank();

        // The debt belongs to `user`, but the WETH came entirely from
        // `secondUser`; the fee is sent to the collector.
        (, uint256 borrowerDebt,) = core.getUserBorrowBalances(address(weth), user);
        assertEq(borrowerDebt, borrowAmount - debtPayment); // 0.02000 - 0.00500 = 0.01500 WETH
        assertEq(core.getUserOriginationFee(address(weth), user), 0); // 0
        assertEq(weth.balanceOf(user), borrowerBalanceBefore);
        assertEq(weth.balanceOf(secondUser), repayerBalanceBefore - payment);
        assertEq(weth.balanceOf(feeCollector), borrowFee); // 0.00005 ETH

        // `max` asks the pool to infer and settle the entire current debt. That
        // convenience is restricted to self-repayment, so third parties must
        // provide an explicit amount.
        vm.prank(secondUser);
        vm.expectRevert(LendingPool.LendingPool__ExplicitAmountRequiredForRepayOnBehalf.selector);
        pool.repay(address(weth), type(uint256).max, payable(user));
    }

    // Verifies that repaying a stable-rate loan updates both reserve-level stable
    // and its weighted-average stable rate correctly.
    function testStablePartialThenFullRepayUpdatesStableDebtAndAverageRate() external {
        uint256 borrowAmount = 0.02 ether;
        uint256 borrowFee = 0.00005 ether;
        uint256 stableRate = 0.05e27;
        uint256 partialDebtPayment = 0.005 ether;

        // The strategy's stable rate is fixed at 0.05e27 (5% in ray units)
        interestRateStrategy.setRates(0, stableRate, 0);

        // User deposits 100 DAI as a collateral
        vm.startPrank(user);
        dai.approve(address(core), 100 ether);
        pool.deposit(address(dai), 100 ether, 0);
        vm.stopPrank();

        // second user provides 1 WETH liquidity
        uint256 liquidity = 1 ether;
        weth.mint(secondUser, liquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), liquidity);
        pool.deposit(address(weth), liquidity, 0);
        vm.stopPrank();

        // User borrows 0.02 WETH at the stable rate and owes a 0.00005 WETH origination fee.
        vm.prank(user);
        pool.borrow(address(weth), borrowAmount, uint256(CoreLibrary.InterestRateMode.STABLE), 0);

        // The user repays 0.00505 WETH:
        //    - 0.00005 clears the fee first
        //    - 0.005 reduces the principal debt
        //    - Remaining stable debt becomes 0.015 WETH
        uint256 partialPayment = borrowFee + partialDebtPayment;
        vm.startPrank(user);
        weth.approve(address(core), partialPayment);
        pool.repay(address(weth), partialPayment, payable(user));
        vm.stopPrank();

        // totalBorrowsStable == 0.02 ETH - 0.005 ETH = 0.015 WETH
        assertEq(core.getReserveTotalBorrowsStable(address(weth)), borrowAmount - partialDebtPayment);

        // currentAverageStableBorrowRate == 5%
        // The rate stays 5% because this is the only stable borrower,
        // and both the repaid and remaining debt carry the same stable rate.
        // In weighted-average terms, removing part of a position at the average rate leaves
        // the average unchanged.
        assertEq(core.getReserveCurrentAverageStableBorrowRate(address(weth)), stableRate);

        // User rayps all remaining debt (type(uint256).max) which is 0.015 WETH
        uint256 outstandingDebt = borrowAmount - partialDebtPayment;
        weth.mint(user, outstandingDebt - weth.balanceOf(user));
        vm.startPrank(user);
        weth.approve(address(core), outstandingDebt);
        pool.repay(address(weth), type(uint256).max, payable(user));
        vm.stopPrank();

        assertEq(core.getReserveTotalBorrowsStable(address(weth)), 0); // 0
        assertEq(core.getReserveCurrentAverageStableBorrowRate(address(weth)), 0); // 0
        assertEq(
            uint256(core.getUserCurrentBorrowRateMode(address(weth), user)), uint256(CoreLibrary.InterestRateMode.NONE)
        );
        assertEq(weth.balanceOf(feeCollector), borrowFee); // 0.00005 WETH
    }

    // It verifies ETH repayment has 2 safeguards:
    //    - too little `msg.sender` reverts
    //    - too much `msg.sender` is refunded, so the protocol keeps only what is owed.
    function testEthRepayRefundsExcessAndRejectsInsufficientValue() external {
        address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        uint256 borrowAmount = 0.02 ether;
        uint256 borrowFee = 0.00005 ether;
        uint256 excess = 0.01 ether;

        // Initiating the ETH reserve
        AToken aEth = new AToken(address(addressesProvider), eth, 18, "Aave interest bearing ETH", "aETH");
        vm.prank(configurator);
        core.initReserve(eth, address(aEth), 18, address(interestRateStrategy));
        core.setReserveConfiguration(eth, 75, 80, true);
        vm.prank(configurator);
        core.enableBorrowingOnReserve(eth, true);
        priceOracle.setAssetPrice(eth, 1 ether);

        // user deposits 100 DAI as collateral
        vm.startPrank(user);
        dai.approve(address(core), 100 ether);
        pool.deposit(address(dai), 100 ether, 0);
        vm.stopPrank();

        // Second user supplies 1 ETH liquidity
        uint256 liquidity = 1 ether;
        vm.deal(secondUser, liquidity);
        vm.prank(secondUser);
        pool.deposit{value: liquidity}(eth, liquidity, 0);

        // User borrows 0.02 ETH and the loan also has a 0.00005 ETH origination fee.
        vm.prank(user);
        pool.borrow(eth, borrowAmount, uint256(CoreLibrary.InterestRateMode.VARIABLE), 0);

        // The required full repayment is 0.02 ETH + 0.00005 ETH = 0.02005 ETH
        uint256 requiredPayment = borrowAmount + borrowFee;
        vm.deal(user, 1 ether);
        vm.prank(user);
        // This reverts because ETH repayments require msg.value >= paybackAmount
        vm.expectRevert(LendingPool.LendingPool__InvalidETHRepaymentAmount.selector);
        pool.repay{value: requiredPayment - 1}(eth, requiredPayment, payable(user));

        uint256 userBalanceBefore = user.balance;
        uint256 coreBalanceBefore = address(core).balance;
        uint256 collectorBalanceBefore = feeCollector.balance;
        vm.prank(user);
        // It rapays all ()`type(uint256).max`) but adds an extra 0.01 ETH
        pool.repay{value: requiredPayment + excess}(eth, type(uint256).max, payable(user));

        // LendingPoolCore / reserve receives: 0.02 ETH principal
        // Fee collector             receives: 0.00005 ETH fee
        // User's net cost                   : 0.02005 ETH
        // Refunded to user                  : 0.01 ETH excess

        assertEq(address(core).balance, coreBalanceBefore + borrowAmount);
        assertEq(feeCollector.balance, collectorBalanceBefore + borrowFee);
        assertEq(user.balance, userBalanceBefore - requiredPayment);
        (, uint256 debtAfter,) = core.getUserBorrowBalances(eth, user);
        assertEq(debtAfter, 0);
    }

    function testRepayRevertsWithNoOutstandingDebt() external {
        // Repaying 1 WETH with no outstanding WETH debt should revert.
        vm.prank(user);
        vm.expectRevert(LendingPool.LendingPool__NoBorrowPending.selector);
        pool.repay(address(weth), 1, payable(user));
    }

    function testRepayRevertsWithZeroAmount() external {
        // Rapaying 0 WETH should revert
        vm.prank(user);
        vm.expectRevert(LendingPool.LendingPool__AmountIsZero.selector);
        pool.repay(address(weth), 0, payable(user));
    }

    function testRepayRevertsWithInactiveReserve() external {
        // Rapaying an inactive WETH reserve should revert
        core.setReserveActive(address(weth), false);
        vm.prank(user);
        vm.expectRevert(LendingPool.LendingPool__ReserveIsNotActive.selector);
        pool.repay(address(weth), 1, payable(user));
    }

    //  If a reserve is frozen, users can't start new actions like depositing or borrowing, but
    //  people who already borrowed can still repay what they owe.
    function testRepayGuardsAndAllowsFrozenReserve() external {
        // User deposits 100 DAI
        vm.startPrank(user);
        dai.approve(address(core), 100 ether);
        pool.deposit(address(dai), 100 ether, 0);
        vm.stopPrank();

        // Second user deposits 1 WETH
        uint256 liquidity = 1 ether;
        weth.mint(secondUser, liquidity);
        vm.startPrank(secondUser);
        weth.approve(address(core), liquidity);
        pool.deposit(address(weth), liquidity, 0);
        vm.stopPrank();

        // User borrows 0.02 WETH at variable rate
        vm.prank(user);
        pool.borrow(address(weth), 0.02 ether, uint256(CoreLibrary.InterestRateMode.VARIABLE), 0);
        // It freezes WETH after the loan exists
        core.setReserveFreeze(address(weth), true);

        // It proves the borrower can fully repay:
        // The required repayment is 0.02005 WETH (0.02 principal + 0.00005 origination fee)
        uint256 repayment = 0.02005 ether;
        weth.mint(user, repayment - weth.balanceOf(user));
        vm.startPrank(user);
        weth.approve(address(core), repayment);
        pool.repay(address(weth), type(uint256).max, payable(user));
        vm.stopPrank();

        (, uint256 debtAfter,) = core.getUserBorrowBalances(address(weth), user);
        // Confirms the user’s compounded borrow balance is zero
        assertEq(debtAfter, 0);
    }
}
