// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {MockLendingPoolAddressProvider} from "../../mocks/MockLendingPoolAddressProvider.sol";
import {MockLendingPoolCore} from "../../mocks/MockLendingPoolCore.sol";
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

    function exposedUpdateRedirectedBalanceOfRedirectionAddress(
        address user,
        uint256 balanceToAdd,
        uint256 balanceToRemove
    ) external {
        _updateRedirectedBalanceOfRedirectionAddress(user, balanceToAdd, balanceToRemove);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function setUserIndex(address user, uint256 index) external {
        s_userIndexes[user] = index;
    }

    function setInterestRedirectionAddress(address user, address target) external {
        s_interestRedirectionAddresses[user] = target;
    }

    function setRedirectedBalance(address user, uint256 redirectedBalance) external {
        s_redirectedBalances[user] = redirectedBalance;
    }

    function getRedirectedBalance(address user) external view returns (uint256) {
        return s_redirectedBalances[user];
    }
}

contract ATokenTest is Test {
    uint256 private constant RAY = 1e27;

    address private user = makeAddr("user");
    address private redirectionTarget = makeAddr("redirectionTarget");
    address private lendingPool = makeAddr("lendingPool");
    address private configurator = makeAddr("configurator");
    address private underlyingAsset = makeAddr("underlyingAsset");

    MockLendingPoolAddressProvider private addressesProvider;
    MockLendingPoolCore private core;
    ATokenHarness private aToken;

    function setUp() external {
        addressesProvider = new MockLendingPoolAddressProvider(lendingPool, configurator);
        core = new MockLendingPoolCore();
        addressesProvider.setLendingPoolCore(address(core));

        aToken = new ATokenHarness(address(addressesProvider), underlyingAsset, 18);
    }

    ///////////////////////////////////////
    //             balanceOf             //
    ///////////////////////////////////////

    // This test checks the empty-balance case.
    //
    // The user has no principal balance and no redirected balance.
    //
    // Because there is no balance that can accrue interest, balanceOf returns
    // zero before doing any normalized-income calculation.
    function testBalanceOfReturnsZeroWhenUserHasNoPrincipalOrRedirectedBalance() external view {
        assertEq(aToken.balanceOf(user), 0);
    }

    // This test checks that balanceOf returns the principal balance when no
    // interest has accrued.
    //
    // The user's principal balance is 100e18.
    // The user index is 1.00 ray and the current reserve normalized income is
    // also 1.00 ray.
    //
    // The user is not redirecting interest and has no redirected balance, so
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
    // balance when the user has no interest redirection.
    //
    // The user's principal balance is 100e18.
    // The user index is 1.00 ray and the current reserve normalized income is
    // 1.05 ray.
    //
    // The user is not redirecting interest and has no redirected balance, so
    // balanceOf accrues on the principal balance only:
    //
    // balance = principalBalance * currentNormalizedIncome / userIndex
    // balance = 100e18 * 1.05e27 / 1e27
    // balance = 105e18
    function testBalanceOfAccruesInterestOnPrincipalWhenUserHasNoRedirection() external {
        uint256 principalBalance = 100 ether;

        aToken.mint(user, principalBalance);
        aToken.setUserIndex(user, RAY);
        core.setReserveNormalizedIncome(underlyingAsset, 105e25);

        assertEq(aToken.balanceOf(user), 105 ether);
    }

    // This test checks that a user who redirects their own interest keeps only
    // their principal balance when no balance has been redirected to them.
    //
    // principalBalance = 100e18
    // redirectedBalance = 0
    // currentNormalizedIncome = 1.10 ray
    //
    // Since the user's own interest is redirected elsewhere and there is no
    // incoming redirected balance:
    //
    // balance = principalBalance
    // balance = 100e18
    function testBalanceOfReturnsOnlyPrincipalWhenUserRedirectsInterestAndHasNoIncomingRedirection() external {
        uint256 principalBalance = 100 ether;

        aToken.mint(user, principalBalance);
        aToken.setUserIndex(user, RAY);
        aToken.setInterestRedirectionAddress(user, redirectionTarget);

        core.setReserveNormalizedIncome(underlyingAsset, 110e25);

        assertEq(aToken.balanceOf(user), principalBalance);
    }

    // This test checks that balanceOf includes interest generated by balances
    // redirected to the user when the user is not redirecting their own interest.
    //
    // The user's principal balance is 100e18.
    // Another 50e18 has been redirected to the user for interest accrual.
    // The user index is 1.00 ray and the current reserve normalized income is
    // 1.10 ray.
    //
    // Since the user is not redirecting interest, both the principal balance
    // and redirected balance participate in interest accrual. The redirected
    // principal itself is then subtracted because it does not belong to the user:
    //
    // balance = ((principalBalance + redirectedBalance) * currentNormalizedIncome / userIndex) - redirectedBalance
    // balance = ((100e18 + 50e18) * 1.10e27 / 1e27) - 50e18
    // balance = 165e18 - 50e18
    // balance = 115e18
    function testBalanceOfAccruesInterestOnPrincipalAndRedirectedBalanceWhenUserHasNoRedirection() external {
        uint256 principalBalance = 100 ether;
        uint256 redirectedBalance = 50 ether;

        aToken.mint(user, principalBalance);
        aToken.setUserIndex(user, RAY);
        aToken.setRedirectedBalance(user, redirectedBalance);
        core.setReserveNormalizedIncome(underlyingAsset, 110e25);

        assertEq(aToken.balanceOf(user), 115 ether);
    }

    // This test checks that balanceOf does not accrue interest on the user's
    // principal balance when the user redirects their own interest elsewhere.
    //
    // The user's principal balance is 100e18.
    // Another 50e18 has been redirected to the user for interest accrual.
    // The user index is 1.00 ray and the current reserve normalized income is
    // 1.10 ray.
    //
    // Since the user redirects their own interest, their principal balance does
    // not accrue interest for them. Only the redirected balance accrues interest,
    // and only the generated interest is added to the user's principal:
    //
    // balance = principalBalance + ((redirectedBalance * currentNormalizedIncome / userIndex) - redirectedBalance)
    // balance = 100e18 + ((50e18 * 1.10e27 / 1e27) - 50e18)
    // balance = 100e18 + (55e18 - 50e18)
    // balance = 105e18
    function testBalanceOfDoesNotAccruePrincipalInterestWhenUserRedirectsInterest() external {
        uint256 principalBalance = 100 ether;
        uint256 redirectedBalance = 50 ether;

        aToken.mint(user, principalBalance);
        aToken.setUserIndex(user, RAY);
        aToken.setInterestRedirectionAddress(user, redirectionTarget);
        aToken.setRedirectedBalance(user, redirectedBalance);
        core.setReserveNormalizedIncome(underlyingAsset, 110e25);

        assertEq(aToken.balanceOf(user), 105 ether);
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
    // Since the user has no principal balance and no redirected balance,
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

    // This test checks that _cumulateBalance mints the interest generated by
    // both the user's principal balance and the balance redirected to them.
    //
    // The user's previous principal balance is 100e18.
    // Another 50e18 has been redirected to the user for interest accrual.
    // The user index is 1.00 ray and the current reserve normalized income is
    // 1.10 ray.
    //
    // Since the user is not redirecting their own interest, balanceOf first
    // accrues on principal plus redirected balance, then subtracts the
    // redirected principal:
    //
    // currentBalance = ((100e18 + 50e18) * 1.10e27 / 1e27) - 50e18
    // currentBalance = 165e18 - 50e18
    // currentBalance = 115e18
    // balanceIncrease = 115e18 - 100e18
    // balanceIncrease = 15e18
    // newPrincipalBalance = 100e18 + 15e18
    // newPrincipalBalance = 115e18
    function testCumulateBalanceMintsInterestFromPrincipalAndRedirectedBalance() external {
        uint256 principalBalance = 100 ether;
        uint256 redirectedBalance = 50 ether;
        uint256 currentNormalizedIncome = 110e25;

        aToken.mint(user, principalBalance);
        aToken.setUserIndex(user, RAY);
        aToken.setRedirectedBalance(user, redirectedBalance);
        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        (uint256 previousPrincipalBalance, uint256 newPrincipalBalance, uint256 balanceIncrease, uint256 index) =
            aToken.exposedCumulateBalance(user);

        assertEq(previousPrincipalBalance, principalBalance);
        assertEq(newPrincipalBalance, 115 ether);
        assertEq(balanceIncrease, 15 ether);
        assertEq(index, currentNormalizedIncome);
        assertEq(aToken.getUserIndex(user), currentNormalizedIncome);
        assertEq(aToken.principalBalanceOf(user), 115 ether);
    }

    //////////////////////////////////////////////////////////////
    //  _updateRedirectedBalanceOfRedirectionAddress            //
    //////////////////////////////////////////////////////////////

    // This test checks the no-redirection case.
    //
    // The user has no configured interest redirection address.
    //
    // Because there is no target whose redirected balance should be updated
    // (s_interestRedirectionAddresses[user] == address(0)),
    // the function returns immediately. It should not touch the requested
    // target, user indexes, or balances.
    function testUpdateRedirectedBalanceDoesNothingWhenUserHasNoRedirection() external {
        uint256 targetPrincipalBalance = 100 ether;

        aToken.mint(redirectionTarget, targetPrincipalBalance);
        aToken.setUserIndex(redirectionTarget, RAY);
        aToken.setRedirectedBalance(redirectionTarget, 25 ether);
        core.setReserveNormalizedIncome(underlyingAsset, 110e25);

        aToken.exposedUpdateRedirectedBalanceOfRedirectionAddress(user, 50 ether, 10 ether);

        assertEq(aToken.getRedirectedBalance(redirectionTarget), 25 ether);
        assertEq(aToken.getUserIndex(redirectionTarget), RAY);
        assertEq(aToken.principalBalanceOf(redirectionTarget), targetPrincipalBalance);
    }

    // This test checks that the redirection target is still cumulated when it
    // has no principal balance but already has an incoming redirected balance.
    //
    // The user redirects interest to redirectionTarget.
    //
    // redirectionTarget principal balance = 0
    // redirectionTarget existing redirected balance = 50e18
    // redirectionTarget index = 1.00 ray
    // current normalized income = 1.10 ray
    //
    // Before adding the new redirected balance, redirectionTarget has earned
    // interest on the old redirected balance:
    //
    // balance = (50e18 * 1.10e27 / 1e27) - 50e18
    // balance = 5e18
    // balanceIncrease = 5e18 - 0
    // balanceIncrease = 5e18
    //
    // After that, the redirected balance is updated:
    //
    // new redirected balance = 50e18 + 20e18 - 5e18
    // new redirected balance = 65e18
    function testUpdateRedirectedBalanceCumulatesTargetWithZeroPrincipalAndUpdatesRedirectedBalance() external {
        uint256 targetRedirectedBalance = 50 ether;
        uint256 currentNormalizedIncome = 110e25;

        aToken.setInterestRedirectionAddress(user, redirectionTarget);
        aToken.setUserIndex(redirectionTarget, RAY);
        aToken.setRedirectedBalance(redirectionTarget, targetRedirectedBalance);
        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        vm.expectEmit(true, false, false, true, address(aToken));
        emit AToken.RedirectedBalanceUpdated(redirectionTarget, 5 ether, currentNormalizedIncome, 20 ether, 5 ether);

        aToken.exposedUpdateRedirectedBalanceOfRedirectionAddress(user, 20 ether, 5 ether);

        assertEq(aToken.principalBalanceOf(redirectionTarget), 5 ether);
        assertEq(aToken.getUserIndex(redirectionTarget), currentNormalizedIncome);
        assertEq(aToken.getRedirectedBalance(redirectionTarget), 65 ether);
    }

    // This test checks that the redirection target is cumulated before its
    // redirected balance is changed.
    //
    // The user redirects interest to redirectionTarget.
    //
    // redirectionTarget principal balance = 100e18
    // redirectionTarget existing redirected balance = 50e18
    // redirectionTarget index = 1.00 ray
    // current normalized income = 1.10 ray
    //
    // Before adding the new redirected balance, redirectionTarget has earned
    // interest on both its own principal and the old redirected balance:
    //
    // balance = ((100e18 + 50e18) * 1.10e27 / 1e27) - 50e18
    // balance = 115e18
    // balanceIncrease = 115e18 - 100e18
    // balanceIncrease = 15e18
    //
    // After that, the redirected balance is updated:
    //
    // new redirected balance = 50e18 + 20e18 - 5e18
    // new redirected balance = 65e18
    function testUpdateRedirectedBalanceCumulatesTargetAndAddsAndRemovesRedirectedBalance() external {
        uint256 targetPrincipalBalance = 100 ether;
        uint256 targetRedirectedBalance = 50 ether;
        uint256 currentNormalizedIncome = 110e25;

        aToken.setInterestRedirectionAddress(user, redirectionTarget);
        aToken.mint(redirectionTarget, targetPrincipalBalance);
        aToken.setUserIndex(redirectionTarget, RAY);
        aToken.setRedirectedBalance(redirectionTarget, targetRedirectedBalance);
        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        vm.expectEmit(true, false, false, true, address(aToken));
        emit AToken.RedirectedBalanceUpdated(redirectionTarget, 15 ether, currentNormalizedIncome, 20 ether, 5 ether);

        aToken.exposedUpdateRedirectedBalanceOfRedirectionAddress(user, 20 ether, 5 ether);

        assertEq(aToken.principalBalanceOf(redirectionTarget), 115 ether);
        assertEq(aToken.getUserIndex(redirectionTarget), currentNormalizedIncome);
        assertEq(aToken.getRedirectedBalance(redirectionTarget), 65 ether);
    }

    // This test checks the chained-redirection case.
    //
    // user redirects interest to redirectionTarget.
    // redirectionTarget redirects its own interest to secondRedirectionTarget.
    //
    // redirectionTarget has 100e18 principal and 50e18 redirected to it.
    // At 1.10 ray normalized income, redirectionTarget earns 5e18 from the
    // incoming redirected balance. Its own principal interest is redirected
    // away, so only that 5e18 is minted into redirectionTarget by
    // _cumulateBalance.
    //
    // The function then propagates only that newly materialized 5e18 interest
    // to secondRedirectionTarget. It does not propagate user's original
    // redirected principal.
    function testUpdateRedirectedBalancePropagatesOnlyTargetBalanceIncreaseToNextRedirectionTarget() external {
        address secondRedirectionTarget = makeAddr("secondRedirectionTarget");
        uint256 targetPrincipalBalance = 100 ether;
        uint256 targetRedirectedBalance = 50 ether;
        uint256 secondTargetRedirectedBalance = 7 ether;
        uint256 currentNormalizedIncome = 110e25;

        aToken.setInterestRedirectionAddress(user, redirectionTarget);
        aToken.setInterestRedirectionAddress(redirectionTarget, secondRedirectionTarget);
        aToken.mint(redirectionTarget, targetPrincipalBalance);
        aToken.setUserIndex(redirectionTarget, RAY);
        aToken.setRedirectedBalance(redirectionTarget, targetRedirectedBalance);
        aToken.setRedirectedBalance(secondRedirectionTarget, secondTargetRedirectedBalance);
        core.setReserveNormalizedIncome(underlyingAsset, currentNormalizedIncome);

        vm.expectEmit(true, false, false, true, address(aToken));
        emit AToken.RedirectedBalanceUpdated(redirectionTarget, 5 ether, currentNormalizedIncome, 20 ether, 0);

        aToken.exposedUpdateRedirectedBalanceOfRedirectionAddress(user, 20 ether, 0);

        assertEq(aToken.principalBalanceOf(redirectionTarget), 105 ether);
        assertEq(aToken.getUserIndex(redirectionTarget), currentNormalizedIncome);
        assertEq(aToken.getRedirectedBalance(redirectionTarget), 70 ether);
        assertEq(aToken.getRedirectedBalance(secondRedirectionTarget), 12 ether);
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
}
