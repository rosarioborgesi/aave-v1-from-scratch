// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";

import {MockLendingPoolAddressesProvider} from "../../mocks/MockLendingPoolAddressesProvider.sol";
import {MockLendingPoolCore} from "../../mocks/MockLendingPoolCore.sol";
import {MockLendingPoolDataProvider} from "../../mocks/MockLendingPoolDataProvider.sol";
import {AToken} from "src/tokenization/AToken.sol";

contract ATokenHarness is AToken {
    constructor(address addressesProvider, address underlyingAsset, uint8 underlyingAssetDecimals)
        AToken(addressesProvider, underlyingAsset, underlyingAssetDecimals, "Aave interest bearing DAI", "aDAI")
    {}

    function exposedCalculateCumulatedBalance(address user, uint256 balance) external view returns (uint256) {
        return _calculateCumulatedBalance(user, balance);
    }

    function exposedCumulateBalance(address user) external returns (uint256, uint256, uint256, uint256) {
        return _cumulateBalance(user);
    }

    function exposedExecuteTransfer(address from, address to, uint256 value) external {
        _executeTransfer(from, to, value);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function setUserIndex(address user, uint256 index) external {
        s_userIndexes[user] = index;
    }
}

contract ATokenUnitTest is Test {
    uint256 private constant RAY = 1e27;

    address private user = makeAddr("user");
    address private lendingPool = makeAddr("lendingPool");
    address private configurator = makeAddr("configurator");
    address private underlyingAsset = makeAddr("underlyingAsset");
    MockLendingPoolAddressesProvider private addressesProvider;
    MockLendingPoolCore private core;
    MockLendingPoolDataProvider private dataProvider;
    ATokenHarness private aToken;

    function setUp() external {
        addressesProvider = new MockLendingPoolAddressesProvider(lendingPool, configurator);
        core = new MockLendingPoolCore();
        dataProvider = new MockLendingPoolDataProvider();
        addressesProvider.setLendingPoolCore(address(core));
        addressesProvider.setLendingPoolDataProvider(address(dataProvider));

        aToken = new ATokenHarness(address(addressesProvider), underlyingAsset, 18);
    }

    ///////////////////////////////////////
    //            constructor            //
    ///////////////////////////////////////

    function testConstructorRevertsWhenAddressesProviderIsZero() external {
        vm.expectRevert(AToken.AToken__ZeroAddress.selector);

        new ATokenHarness(address(0), underlyingAsset, 18);
    }

    function testConstructorRevertsWhenUnderlyingAssetIsZero() external {
        vm.expectRevert(AToken.AToken__ZeroAddress.selector);

        new ATokenHarness(address(addressesProvider), address(0), 18);
    }

    function testConstructorRevertsWhenProviderReturnsZeroCore() external {
        MockLendingPoolAddressesProvider provider = new MockLendingPoolAddressesProvider(lendingPool, configurator);
        provider.setLendingPoolDataProvider(address(dataProvider));

        vm.expectRevert(AToken.AToken__ZeroAddress.selector);

        new ATokenHarness(address(provider), underlyingAsset, 18);
    }

    function testConstructorRevertsWhenProviderReturnsZeroPool() external {
        vm.mockCall(
            address(addressesProvider),
            abi.encodeWithSelector(MockLendingPoolAddressesProvider.getLendingPool.selector),
            abi.encode(address(0))
        );

        vm.expectRevert(AToken.AToken__ZeroAddress.selector);

        new ATokenHarness(address(addressesProvider), underlyingAsset, 18);
    }

    function testConstructorRevertsWhenProviderReturnsZeroDataProvider() external {
        MockLendingPoolAddressesProvider provider = new MockLendingPoolAddressesProvider(lendingPool, configurator);
        provider.setLendingPoolCore(address(core));

        vm.expectRevert(AToken.AToken__ZeroAddress.selector);

        new ATokenHarness(address(provider), underlyingAsset, 18);
    }

    ///////////////////////////////////////
    //           mintOnDeposit           //
    ///////////////////////////////////////

    // This test checks the access control on mintOnDeposit.
    //
    // Only the LendingPool configured in the addresses provider can call
    // mintOnDeposit. Any other caller should revert before balances or indexes
    // are touched.
    function testMintOnDepositRevertsWhenCallerIsNotLendingPool() external {
        vm.expectRevert(AToken.AToken__OnlyLendingPool.selector);

        aToken.mintOnDeposit(user, 100 ether);
    }

    // This test checks that the first deposit initializes the user at the
    // current reserve normalized income.
    //
    // The reserve has already grown to 1.05 ray before the user deposits.
    // Since the user had no balance during that previous period, they must
    // not receive the earlier 5% growth.
    //
    // _cumulateBalance returns zero interest and sets:
    //
    // userIndex = 1.05 ray
    //
    // The new 100e18 deposit is then minted:
    //
    // currentBalance = 100e18 * 1.05e27 / 1.05e27
    // currentBalance = 100e18
    function testMintOnDepositDoesNotGivePastInterestOnFirstDeposit() external {
        uint256 depositAmount = 100 ether;
        uint256 currentNormalizedIncome = 105e25;

        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        vm.expectEmit(true, false, false, true, address(aToken));
        emit AToken.MintOnDeposit(user, depositAmount, 0, currentNormalizedIncome);

        vm.prank(lendingPool);
        aToken.mintOnDeposit(user, depositAmount);

        assertEq(aToken.principalBalanceOf(user), depositAmount);
        assertEq(aToken.balanceOf(user), depositAmount);
        assertEq(aToken.getUserIndex(user), currentNormalizedIncome);
    }

    // This test checks the first-deposit case.
    //
    // The user has no previous principal balance.
    // The current reserve normalized income is 1.00 ray.
    //
    // mintOnDeposit first calls _cumulateBalance, which initializes the user
    // index and mints no interest because the user has no balance yet. Then it
    // mints the deposited amount.
    function testMintOnDepositMintsAmountAndInitializesUserIndexOnFirstDeposit() external {
        uint256 depositAmount = 100 ether;

        core.setReserveNormalizedIncome(underlyingAsset, RAY);

        vm.expectEmit(true, false, false, true, address(aToken));
        emit AToken.MintOnDeposit(user, depositAmount, 0, RAY);

        vm.prank(lendingPool);
        aToken.mintOnDeposit(user, depositAmount);

        assertEq(aToken.principalBalanceOf(user), depositAmount);
        assertEq(aToken.balanceOf(user), depositAmount);
        assertEq(aToken.getUserIndex(user), RAY);
    }

    // This test checks that mintOnDeposit materializes accrued interest before
    // minting the new deposit amount.
    //
    // The user's previous principal balance is 100e18.
    // The user index is 1.00 ray and the current normalized income is 1.05 ray.
    //
    // Before the deposit, the user has accrued 5e18 of interest:
    //
    // balanceIncrease = 100e18 * 1.05e27 / 1e27 - 100e18
    // balanceIncrease = 5e18
    //
    // mintOnDeposit first mints that 5e18 interest, updates the index, then
    // mints the new 20e18 deposit.
    function testMintOnDepositCumulatesAccruedInterestBeforeMintingDeposit() external {
        uint256 principalBalance = 100 ether;
        uint256 depositAmount = 20 ether;
        uint256 currentNormalizedIncome = 105e25;

        aToken.mint(user, principalBalance);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        vm.expectEmit(true, false, false, true, address(aToken));
        emit AToken.MintOnDeposit(user, depositAmount, 5 ether, currentNormalizedIncome);

        vm.prank(lendingPool);
        aToken.mintOnDeposit(user, depositAmount);

        assertEq(aToken.principalBalanceOf(user), 125 ether);
        assertEq(aToken.balanceOf(user), 125 ether);
        assertEq(aToken.getUserIndex(user), currentNormalizedIncome);
    }

    ///////////////////////////////////////
    //             balanceOf             //
    ///////////////////////////////////////

    // This test checks the empty-balance case.
    //
    // The user has no principal balance.
    //
    // Because there is no balance that can accrue interest, balanceOf returns
    // zero before doing any normalized-income calculation.
    function testBalanceOfReturnsZeroWhenUserHasNoPrincipalBalance() external view {
        assertEq(aToken.balanceOf(user), 0);
    }

    // This test checks that balanceOf returns the principal balance when no
    // interest has accrued.
    //
    // The user's principal balance is 100e18.
    // The user index is 1.00 ray and the current reserve normalized income is
    // also 1.00 ray.
    //
    // balanceOf accrues on the principal balance only:
    //
    // balance = principalBalance * currentNormalizedIncome / userIndex
    // balance = 100e18 * 1e27 / 1e27
    // balance = 100e18
    function testBalanceOfReturnsPrincipalWhenNoInterestAccrued() external {
        uint256 principalBalance = 100 ether;

        aToken.mint(user, principalBalance);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, RAY);

        assertEq(aToken.balanceOf(user), principalBalance);
    }

    // This test checks that balanceOf accrues interest on the user's principal
    // balance.
    //
    // The user's principal balance is 100e18.
    // The user index is 1.00 ray and the current reserve normalized income is
    // 1.05 ray.
    //
    // balanceOf accrues on the principal balance only:
    //
    // balance = principalBalance * currentNormalizedIncome / userIndex
    // balance = 100e18 * 1.05e27 / 1e27
    // balance = 105e18
    function testBalanceOfAccruesInterestOnPrincipal() external {
        uint256 principalBalance = 100 ether;

        aToken.mint(user, principalBalance);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, 105e25);

        assertEq(aToken.balanceOf(user), 105 ether);
    }

    ///////////////////////////////////////
    //            totalSupply            //
    ///////////////////////////////////////

    // This test checks the empty-supply case.
    //
    // Even if the reserve normalized income has grown, there is no principal
    // supply that can accrue interest, so totalSupply returns zero.
    function testTotalSupplyReturnsZeroWhenPrincipalSupplyIsZero() external {
        core.setReserveNormalizedIncome(underlyingAsset, 105e25);

        assertEq(aToken.totalSupply(), 0);
    }

    // This test checks that totalSupply returns the stored principal supply
    // when no interest has accrued.
    //
    // total principal supply = 100e18 + 40e18
    // current normalized income = 1.00 ray
    //
    // totalSupply = 140e18 * 1.00e27
    // totalSupply = 140e18
    function testTotalSupplyReturnsPrincipalSupplyWhenNoInterestAccrued() external {
        address secondUser = makeAddr("secondUser");

        aToken.mint(user, 100 ether);
        aToken.mint(secondUser, 40 ether);
        core.setReserveNormalizedIncome(underlyingAsset, RAY);

        assertEq(aToken.totalSupply(), 140 ether);
    }

    // This test checks that totalSupply scales the stored principal supply by
    // the current reserve normalized income.
    //
    // total principal supply = 100e18 + 40e18
    // current normalized income = 1.05 ray
    //
    // totalSupply = 140e18 * 1.05e27
    // totalSupply = 147e18
    function testTotalSupplyScalesPrincipalSupplyByCurrentNormalizedIncome() external {
        address secondUser = makeAddr("secondUser");

        aToken.mint(user, 100 ether);
        aToken.mint(secondUser, 40 ether);
        core.setReserveNormalizedIncome(underlyingAsset, 105e25);

        assertEq(aToken.totalSupply(), 147 ether);
    }

    ///////////////////////////////////////
    //         _cumulateBalance          //
    ///////////////////////////////////////

    // This test checks the no-interest accumulation case.
    //
    // The user's principal balance is 100e18.
    // The user index is 1.00 ray and the current reserve normalized income is
    // also 1.00 ray.
    //
    // Since no interest has accrued, _cumulateBalance should mint zero
    // additional tokens and keep the principal balance unchanged:
    //
    // currentBalance = 100e18 * 1e27 / 1e27
    // currentBalance = 100e18
    // balanceIncrease = currentBalance - previousPrincipalBalance
    // balanceIncrease = 100e18 - 100e18
    // balanceIncrease = 0
    function testCumulateBalanceWithNoInterest() external {
        uint256 principalBalance = 100 ether;

        aToken.mint(user, principalBalance);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, RAY);

        (uint256 previousPrincipalBalance, uint256 newPrincipalBalance, uint256 balanceIncrease, uint256 index) =
            aToken.exposedCumulateBalance(user);

        assertEq(previousPrincipalBalance, principalBalance);
        assertEq(newPrincipalBalance, principalBalance);
        assertEq(balanceIncrease, 0);
        assertEq(index, RAY);
        assertEq(aToken.getUserIndex(user), RAY);
        assertEq(aToken.principalBalanceOf(user), principalBalance);
    }

    // This test checks that _cumulateBalance still initializes the user's
    // index even when the user has no principal balance.
    //
    // The user's previous principal balance is 0.
    // The current reserve normalized income is 1.05 ray.
    //
    // Since the user has no principal balance,
    // balanceOf returns 0. That means there is no interest to mint, but the
    // user's index should still be updated to the current reserve normalized
    // income.
    function testCumulateBalanceSetsIndexForUserWithNoBalance() external {
        uint256 currentNormalizedIncome = 105e25;

        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        (uint256 previousPrincipalBalance, uint256 newPrincipalBalance, uint256 balanceIncrease, uint256 index) =
            aToken.exposedCumulateBalance(user);

        assertEq(previousPrincipalBalance, 0);
        assertEq(newPrincipalBalance, 0);
        assertEq(balanceIncrease, 0);
        assertEq(index, currentNormalizedIncome);
        assertEq(aToken.getUserIndex(user), currentNormalizedIncome);
    }

    // This test checks that _cumulateBalance mints the accrued interest into
    // the user's principal balance.
    //
    // The user's previous principal balance is 100e18.
    // The user index is 1.00 ray and the current reserve normalized income is
    // 1.05 ray.
    //
    // The user's current balance is 105e18, so the accrued interest is 5e18.
    // _cumulateBalance should mint exactly that increase and update the user's
    // index to the current reserve normalized income:
    //
    // currentBalance = 100e18 * 1.05e27 / 1e27
    // currentBalance = 105e18
    // balanceIncrease = currentBalance - previousPrincipalBalance
    // balanceIncrease = 105e18 - 100e18
    // balanceIncrease = 5e18
    // newPrincipalBalance = 100e18 + 5e18
    // newPrincipalBalance = 105e18
    function testCumulateBalanceMintsAccruedInterestAndUpdatesUserIndex() external {
        uint256 principalBalance = 100 ether;
        uint256 currentNormalizedIncome = 105e25;

        aToken.mint(user, principalBalance);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        (uint256 previousPrincipalBalance, uint256 newPrincipalBalance, uint256 balanceIncrease, uint256 index) =
            aToken.exposedCumulateBalance(user);

        assertEq(previousPrincipalBalance, principalBalance);
        assertEq(newPrincipalBalance, 105 ether);
        assertEq(balanceIncrease, 5 ether);
        assertEq(index, currentNormalizedIncome);
        assertEq(aToken.getUserIndex(user), currentNormalizedIncome);
        assertEq(aToken.principalBalanceOf(user), 105 ether);
    }

    ///////////////////////////////////////
    //    _calculateCumulatedBalance     //
    ///////////////////////////////////////

    // This test checks the basic interest-accrual case.
    //
    // The user index is 1.00 ray, meaning the user last interacted with the
    // protocol when the reserve normalized income was 1.00.
    //
    // The current reserve normalized income is now 1.05 ray, meaning the reserve
    // has grown by 5% since the user's last action.
    //
    // Therefore the user's balance should grow by 5%:
    //
    // balance = principalBalance * currentNormalizedIncome / userIndex
    // balance = 100e18 * 1.05e27 / 1e27
    // balance = 105e18
    function testCalculateCumulatedBalanceWithFivePercentInterest() external {
        uint256 principalBalance = 100 ether;

        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, 105e25);

        uint256 balance = aToken.exposedCalculateCumulatedBalance(user, principalBalance);

        assertEq(balance, 105 ether);
    }

    // This test checks the no-interest case.
    //
    // The user index is 1.00 ray and the current reserve normalized income is
    // also 1.00 ray.
    //
    // This means no interest has accrued since the user's last action.
    //
    // Therefore the balance should remain unchanged:
    //
    // balance = principalBalance * currentNormalizedIncome / userIndex
    // balance = 100e18 * 1e27 / 1e27
    // balance = 100e18
    function testCalculateCumulatedBalanceWithNoInterest() external {
        uint256 principalBalance = 100 ether;

        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, RAY);

        uint256 balance = aToken.exposedCalculateCumulatedBalance(user, principalBalance);

        assertEq(balance, principalBalance);
    }

    // This test checks that the function only applies the growth that happened
    // since the user's last index update.
    //
    // The user index is 1.05 ray, meaning the user already interacted with the
    // protocol after the reserve had grown to 1.05.
    //
    // The current reserve normalized income is 1.10 ray.
    //
    // The user should not receive the full growth from 1.00 to 1.10.
    // They should only receive the relative growth from 1.05 to 1.10:
    //
    // balance = principalBalance * currentNormalizedIncome / userIndex
    // balance = 100e18 * 1.10e27 / 1.05e27
    // balance = 100e18 * 110 / 105
    // balance = 104.761904761904761904e18
    //
    // Because WadRayMath rounds half up, the final result becomes:
    // 104.761904761904761905e18
    function testCalculateCumulatedBalanceOnlyAppliesGrowthSinceUserIndex() external {
        uint256 principalBalance = 100 ether;

        aToken.setUserIndex(user, 105e25);
        core.setReserveNormalizedIncome(underlyingAsset, 110e25);

        uint256 balance = aToken.exposedCalculateCumulatedBalance(user, principalBalance);

        assertEq(balance, 104_761904761904761905);
    }

    ///////////////////////////////////////
    //          _executeTransfer          //
    ///////////////////////////////////////

    function testExecuteTransferRevertsWhenAmountIsZero() external {
        vm.expectRevert(AToken.AToken__AmountMustBeGreaterThanZero.selector);

        aToken.exposedExecuteTransfer(user, makeAddr("recipient"), 0);
    }

    // verifies that an aToken transfer first realizes accrued interest for both parties, then moves the requested tokens.
    function testExecuteTransferCumulatesBothBalancesBeforeTransfer() external {
        address recipient = makeAddr("recipient");
        uint256 currentNormalizedIncome = 105e25;

        aToken.mint(user, 100 ether);
        aToken.mint(recipient, 40 ether);
        aToken.setUserIndex(user, RAY);
        aToken.setUserIndex(recipient, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        // Before the transfer:
        //
        // Account     Principal   Saved index   Current index   Accrued interest
        // user        100 ether   1.00 (RAY)    1.05            5 ether
        // recipient   40 ether    1.00 (RAY)    1.05            2 ether

        // Because the reserve's normalized-income index rose from RAY (1.00) to 105e25 (1.05): a 5% increase
        // aToken balances include interest:
        // effective balance = principal x current index / user's saved index
        // user:          100 x 1.05 / 1.00 = 105  -> 5 tokens of accrued interest
        // recipient:     40 x 1.05 / 1.00 = 42    -> 2 tokens of accrued interest

        vm.expectEmit(true, true, false, true, address(aToken));
        emit AToken.BalanceTransfer(
            user, recipient, 20 ether, 5 ether, 2 ether, currentNormalizedIncome, currentNormalizedIncome
        );

        aToken.exposedExecuteTransfer(user, recipient, 20 ether);

        // So, before the transfer, their effective balances are 105 and 42 aTokens.
        // exposedExecuteTransfer(user, recipient, 20 ether) calls the internal transfer routine.
        // It:
        //   1. Accumulates the sender: mints 5 accrued aTokens, updates their index to 1.05.
        //   2. Accumulates the recipient: mints 2 accrued aTokens, updates their index to 1.05.
        //   3. Transfers 20 aTokens.
        //
        // That gives:
        //   - Sender:      105 - 20 = 85
        //   - Recipient:   42 + 20 = 62

        assertEq(aToken.principalBalanceOf(user), 85 ether);
        assertEq(aToken.principalBalanceOf(recipient), 62 ether);
        assertEq(aToken.getUserIndex(user), currentNormalizedIncome);
        assertEq(aToken.getUserIndex(recipient), currentNormalizedIncome);
    }

    // This test covers a full-balance transfer after interest has accrued.
    function testExecuteTransferOfEntireAccruedBalanceResetsOnlySenderIndex() external {
        address recipient = makeAddr("recipient");
        uint256 currentNormalizedIncome = 105e25;

        aToken.mint(user, 100 ether);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        // Initial state:
        //  - user has a stored principal of 100 ether
        //  - user's saved index is 1.00 RAY
        //  - The reserve's current normalized-income index is 1.05 RAY
        //
        // The user's effective aToken balance is:
        //   100 x 1.05 / 1.00 = 105 aTokens

        vm.expectEmit(true, true, false, true, address(aToken));
        emit AToken.BalanceTransfer(user, recipient, 105 ether, 5 ether, 0, 0, currentNormalizedIncome);

        aToken.exposedExecuteTransfer(user, recipient, 105 ether);

        // _executeTransfer does this:
        //    1. Cumulate the sender’s balance: mint the 5 ether interest,
        //      making their stored balance 105, and set their index to 1.05.
        //    2. Cumulate the recipient’s balance. They start at zero, so they accrue 0, but their index is initialized to 1.05.
        //    3. Transfer all 105 aTokens to the recipient.
        //    4. Since the sender now has zero balance, reset only their stored index to 0

        assertEq(aToken.principalBalanceOf(user), 0);
        assertEq(aToken.balanceOf(user), 0);
        assertEq(aToken.getUserIndex(user), 0); // because their account is empty and its accounting state is cleared
        assertEq(aToken.principalBalanceOf(recipient), 105 ether);
        assertEq(aToken.balanceOf(recipient), 105 ether);
        assertEq(aToken.getUserIndex(recipient), currentNormalizedIncome); // because they now hold tokens measured from the current index
    }

    function testExecuteTransferRevertsWhenAmountExceedsSenderBalance() external {
        address recipient = makeAddr("recipient");
        uint256 senderBalance = 100 ether;
        uint256 transferAmount = senderBalance + 1;

        aToken.mint(user, senderBalance);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, RAY);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user, senderBalance, transferAmount)
        );

        aToken.exposedExecuteTransfer(user, recipient, transferAmount);
    }

    ///////////////////////////////////////
    //       transferOnLiquidation        //
    ///////////////////////////////////////

    function testTransferOnLiquidationRevertsWhenCallerIsNotLendingPool() external {
        vm.expectRevert(AToken.AToken__OnlyLendingPool.selector);

        aToken.transferOnLiquidation(user, makeAddr("liquidator"), 1 ether);
    }

    ///////////////////////////////////////
    //         burnOnLiquidation          //
    ///////////////////////////////////////

    function testBurnOnLiquidationRevertsWhenCallerIsNotLendingPool() external {
        aToken.mint(user, 100 ether);
        aToken.setUserIndex(user, RAY);

        vm.expectRevert(AToken.AToken__OnlyLendingPool.selector);
        aToken.burnOnLiquidation(user, 40 ether);

        assertEq(aToken.principalBalanceOf(user), 100 ether);
        assertEq(aToken.getUserIndex(user), RAY);
    }

    // It verifies that liquidation burns the user’s balance only after their accrued interest has been realized.
    function testBurnOnLiquidationCumulatesInterestBeforePartiallyBurning() external {
        uint256 currentNormalizedIncome = 105e25;

        aToken.mint(user, 100 ether);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        // Initial state:
        // - The user holds 100 aTokens.
        // - Their saved index is RAY (1.0)
        // - The reserve's current normalized-income index is 105e25 (1.05) meaning the deposit has earned 5% of interest

        // The user's effective aToken balance is:
        //   100 x 1.05 / 1.00 = 105 aTokens

        vm.expectEmit(true, false, false, true, address(aToken));
        emit AToken.BurnOnLiquidation(user, 40 ether, 5 ether, currentNormalizedIncome);

        vm.prank(lendingPool);
        aToken.burnOnLiquidation(user, 40 ether);

        // burnOnLiquidation mints the 5 tokens of interest, updates the user index to 1.05, then burns 40

        // balance before liquidation = 100 stored principal + 5 realized interest = 105
        // remaining balance = 105 balance before liquidation - 40 liquidated = 65 remaining

        assertEq(aToken.principalBalanceOf(user), 65 ether);
        assertEq(aToken.balanceOf(user), 65 ether);
        assertEq(aToken.getUserIndex(user), currentNormalizedIncome);
    }

    // This test covers a full collateral liquidation after interest accrued.
    function testBurnOnLiquidationOfEntireAccruedBalanceResetsUserIndex() external {
        uint256 currentNormalizedIncome = 105e25;

        aToken.mint(user, 100 ether);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        // Starting state:
        //   - The user’s stored aToken balance is 100 ether
        //   - Their saved liquidity index is RAY = 1e27 (1.00).
        //   - The reserve index rises to 105e25 (1.05), meaning 5% interest accrued.

        // The user's effective balance is:
        // 100 x 1.05 / 1.00 = 105 aTokens

        vm.expectEmit(true, false, false, true, address(aToken));
        emit AToken.BurnOnLiquidation(user, 105 ether, 5 ether, 0);

        vm.prank(lendingPool);
        aToken.burnOnLiquidation(user, 105 ether);

        // What burnOnLiquidation does:
        //   1. It calculates the 5 ether accrued interest.
        //   2. It mints that interest, taking the stored balance from 100 to 105.
        //   3. It temporarily updates the user’s index to 1.05.
        //   4. It burns all 105 ether
        //   5. Because no balance remaing the saved user index to 0

        assertEq(aToken.principalBalanceOf(user), 0);
        assertEq(aToken.balanceOf(user), 0);
        assertEq(aToken.getUserIndex(user), 0);
        assertEq(aToken.totalSupply(), 0);
    }

    function testBurnOnLiquidationRevertsWhenAmountExceedsAccruedBalance() external {
        uint256 currentNormalizedIncome = 105e25;
        uint256 accruedBalance = 105 ether;
        uint256 burnAmount = accruedBalance + 1;

        aToken.mint(user, 100 ether);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user, accruedBalance, burnAmount)
        );

        vm.prank(lendingPool);
        aToken.burnOnLiquidation(user, burnAmount);

        // The failed call rolls back the attempted interest materialization.
        assertEq(aToken.principalBalanceOf(user), 100 ether);
        assertEq(aToken.getUserIndex(user), RAY);
    }

    ///////////////////////////////////////
    //              transfer              //
    ///////////////////////////////////////

    // verifies the normal public transfer path correctly realizes accrued interest for both accounts before moving tokens.
    function testTransferCumulatesBothBalancesBeforeTransfer() external {
        address recipient = makeAddr("recipient");
        uint256 currentNormalizedIncome = 105e25;

        aToken.mint(user, 100 ether);
        aToken.mint(recipient, 40 ether);
        aToken.setUserIndex(user, RAY);
        aToken.setUserIndex(recipient, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);
        dataProvider.setBalanceDecreaseAllowed(true);

        vm.expectEmit(true, true, false, true, address(aToken));
        emit AToken.BalanceTransfer(
            user, recipient, 20 ether, 5 ether, 2 ether, currentNormalizedIncome, currentNormalizedIncome
        );

        // Initial accounting:
        //   - Sender stored balance: 100
        //   - Recipient stored balance: 40
        //   - Both saved indexes: 1.00 RAY
        //   - Current reserve income index: 1.05 RAY (105e25)

        // That 5% index growth means their effective balances are already:
        //   - Sender: 100 × 1.05 / 1.00 = 105 → 5 accrued aTokens
        //   - Recipient: 40 × 1.05 / 1.00 = 42 → 2 accrued aTokens

        // balanceDecreaseAllowed returns true, so the sender is permitted to transfer 20 aTokens as collateral.

        vm.prank(user);
        assertTrue(aToken.transfer(recipient, 20 ether));

        // When user.transfer(recipient, 20 ether) runs, AToken._update first checks this permission,
        // then _executeTransfer:
        //  1. Mints the sender’s 5 accrued tokens and updates their saved index to 1.05
        //  2. Mints the recipient’s 2 accrued tokens and updates their saved index to 1.05
        //  3. Transfers 20 tokens.

        // Final stored balances:
        //  - Sender: 105 - 20 = 85
        //  - Recipient: 42 + 20 = 62

        assertEq(aToken.principalBalanceOf(user), 85 ether);
        assertEq(aToken.principalBalanceOf(recipient), 62 ether);
        assertEq(aToken.getUserIndex(user), currentNormalizedIncome);
        assertEq(aToken.getUserIndex(recipient), currentNormalizedIncome);
    }

    function testTransferRevertsWhenCollateralDecreaseIsNotAllowed() external {
        address recipient = makeAddr("recipient");
        uint256 transferAmount = 20 ether;

        aToken.mint(user, 100 ether);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, RAY);
        dataProvider.setBalanceDecreaseAllowed(false);

        vm.prank(user);
        vm.expectRevert(AToken.AToken__TransferNotAllowed.selector);
        aToken.transfer(recipient, transferAmount);

        assertEq(aToken.principalBalanceOf(user), 100 ether);
        assertEq(aToken.principalBalanceOf(recipient), 0);
        assertEq(aToken.getUserIndex(user), RAY);
        assertEq(aToken.getUserIndex(recipient), 0);
        assertEq(aToken.totalSupply(), 100 ether);
    }

    function testTransferRevertsWhenAmountExceedsSenderBalance() external {
        address recipient = makeAddr("recipient");
        uint256 senderBalance = 100 ether;
        uint256 transferAmount = senderBalance + 1;

        aToken.mint(user, senderBalance);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, RAY);
        dataProvider.setBalanceDecreaseAllowed(true);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user, senderBalance, transferAmount)
        );

        vm.prank(user);
        aToken.transfer(recipient, transferAmount);

        assertEq(aToken.principalBalanceOf(user), senderBalance);
        assertEq(aToken.principalBalanceOf(recipient), 0);
        assertEq(aToken.getUserIndex(user), RAY);
        assertEq(aToken.getUserIndex(recipient), 0);
    }

    ///////////////////////////////////////
    //            transferFrom            //
    ///////////////////////////////////////

    function testTransferFromTransfersTokensWhenSpenderIsApproved() external {
        address spender = makeAddr("spender");
        address recipient = makeAddr("recipient");
        uint256 senderBalance = 100 ether;
        uint256 transferAmount = 20 ether;

        aToken.mint(user, senderBalance);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, RAY);
        dataProvider.setBalanceDecreaseAllowed(true);

        vm.prank(user);
        aToken.approve(spender, transferAmount);

        vm.prank(spender);
        assertTrue(aToken.transferFrom(user, recipient, transferAmount));

        assertEq(aToken.principalBalanceOf(user), senderBalance - transferAmount);
        assertEq(aToken.principalBalanceOf(recipient), transferAmount);
        assertEq(aToken.allowance(user, spender), 0);
    }

    function testTransferFromRevertsWhenSpenderIsNotApproved() external {
        address spender = makeAddr("spender");
        address recipient = makeAddr("recipient");
        uint256 senderBalance = 100 ether;
        uint256 transferAmount = 20 ether;

        aToken.mint(user, senderBalance);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, RAY);
        dataProvider.setBalanceDecreaseAllowed(true);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, transferAmount)
        );

        vm.prank(spender);
        aToken.transferFrom(user, recipient, transferAmount);

        assertEq(aToken.principalBalanceOf(user), senderBalance);
        assertEq(aToken.principalBalanceOf(recipient), 0);
        assertEq(aToken.allowance(user, spender), 0);
    }
}
