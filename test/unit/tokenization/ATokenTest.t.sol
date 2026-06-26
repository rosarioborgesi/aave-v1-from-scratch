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

    function setUserIndex(address user, uint256 index) external {
        s_userIndexes[user] = index;
    }
}

contract ATokenTest is Test {
    uint256 private constant RAY = 1e27;

    address private user = makeAddr("user");
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
        core.setNormalizedIncome(105e25);

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
        core.setNormalizedIncome(RAY);

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
        core.setNormalizedIncome(110e25);

        uint256 balance = aToken.exposedCalculateCumulatedBalance(user, principalBalance);

        assertEq(balance, 104_761904761904761905);
    }
}
