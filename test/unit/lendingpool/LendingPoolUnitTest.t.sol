// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";

import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockLendingPoolCore} from "../../mocks/MockLendingPoolCore.sol";

import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {EthAddressLib} from "src/libraries/EthAddressLib.sol";
import {LendingPool} from "src/lendingpool/LendingPool.sol";

contract ReentrantRedeemReceiver {
    LendingPool private immutable i_pool;
    address private immutable i_reserve;

    error ReentrantRedeemReceiver__UnexpectedRevert(bytes reason);
    error ReentrantRedeemReceiver__ReentrantCallSucceeded();

    constructor(LendingPool pool, address reserve) {
        i_pool = pool;
        i_reserve = reserve;
    }

    receive() external payable {
        try i_pool.redeemUnderlying(i_reserve, payable(address(this)), 1, 0) {
            revert ReentrantRedeemReceiver__ReentrantCallSucceeded();
        } catch (bytes memory reason) {
            if (bytes4(reason) != ReentrancyGuard.ReentrancyGuardReentrantCall.selector) {
                revert ReentrantRedeemReceiver__UnexpectedRevert(reason);
            }
        }
    }
}

contract LendingPoolUnitTest is Test {
    uint256 private constant REDEEM_AMOUNT = 1 ether;

    address private aToken = makeAddr("aToken");
    address payable private user = payable(makeAddr("user"));

    LendingPoolAddressesProvider private addressesProvider;
    MockLendingPoolCore private core;
    LendingPool private pool;
    MockERC20 private token;

    function setUp() external {
        addressesProvider = new LendingPoolAddressesProvider(address(this));

        addressesProvider.setLendingPool(makeAddr("temporaryLendingPool"));
        core = new MockLendingPoolCore();
        addressesProvider.setLendingPoolCore(address(core));

        pool = new LendingPool(address(addressesProvider));
        addressesProvider.setLendingPool(address(pool));

        token = new MockERC20("Mock DAI", "DAI");

        _initReserve(address(token), aToken);
    }

    function _initReserve(address reserve, address reserveAToken) internal {
        core.addReserve(reserve);
        core.setReserveATokenAddress(reserve, reserveAToken);
        core.setReserveIsActive(reserve, true);
    }

    /////////////////////////////////////
    //        redeemUnderlying         //
    /////////////////////////////////////

    function testRedeemUnderlyingRevertsWhenCallerIsNotOverlyingAToken() external {
        vm.expectRevert(LendingPool.LendingPool__ATokenOnly.selector);

        pool.redeemUnderlying(address(token), user, REDEEM_AMOUNT, 0);
    }

    function testRedeemUnderlyingRevertsWhenReserveIsNotActive() external {
        core.setReserveIsActive(address(token), false);

        vm.prank(aToken);
        vm.expectRevert(LendingPool.LendingPool__ReserveIsNotActive.selector);

        pool.redeemUnderlying(address(token), user, REDEEM_AMOUNT, 0);
    }

    function testRedeemUnderlyingRevertsWhenAmountIsZero() external {
        vm.prank(aToken);
        vm.expectRevert(LendingPool.LendingPool__AmountIsZero.selector);

        pool.redeemUnderlying(address(token), user, 0, 0);
    }

    function testRedeemUnderlyingBlocksReentrantCallDuringEthTransfer() external {
        address ethReserve = EthAddressLib.ethAddress();
        address ethAToken = makeAddr("ethAToken");
        _initReserve(ethReserve, ethAToken);

        ReentrantRedeemReceiver receiver = new ReentrantRedeemReceiver(pool, ethReserve);
        vm.deal(address(core), 2 ether);

        vm.prank(ethAToken);
        pool.redeemUnderlying(ethReserve, payable(address(receiver)), REDEEM_AMOUNT, 0);
    }
}
