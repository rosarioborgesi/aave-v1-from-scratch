// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {EthAddressLib} from "src/libraries/EthAddressLib.sol";

contract MockLendingPoolCore {
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////

    error MockLendingPoolCore__EthTransferFailed(address to, uint256 amount);

    ///////////////////////////////////
    //            Libraries          //
    ///////////////////////////////////
    using SafeERC20 for IERC20;

    ////////////////////////////////
    //      State Variables       //
    ////////////////////////////////
    address[] private s_reserves;
    mapping(address reserve => bool isAdded) private s_isReserveAdded;
    mapping(address reserve => TestReserveData data) private s_testReserveData;
    mapping(address user => mapping(address reserve => TestUserReserveData data)) private s_testUserReserveData;

    /////////////////////////////////
    //      Type declarations      //
    /////////////////////////////////

    // Stores the reserve information used by the mock.
    struct TestReserveData {
        uint256 decimals;
        uint256 baseLtv;
        uint256 liquidationThreshold;
        bool usageAsCollateralEnabled;
        uint256 normalizedIncome;
        address aTokenAddress;
        bool isActive;
    }

    // Stores the user's reserve information used by the mock.
    struct TestUserReserveData {
        uint256 liquidityBalance;
        uint256 borrowBalance;
        uint256 originationFee;
        bool useAsCollateral;
    }

    ////////////////////////////////
    //          Functions         //
    ////////////////////////////////

    receive() external payable {}

    function addReserve(address reserve) external {
        if (s_isReserveAdded[reserve]) {
            return;
        }

        s_reserves.push(reserve);
        s_isReserveAdded[reserve] = true;
    }

    function setReserveConfiguration(
        address reserve,
        uint256 decimals,
        uint256 baseLtv,
        uint256 liquidationThreshold,
        bool usageAsCollateralEnabled
    ) external {
        TestReserveData storage data = s_testReserveData[reserve];
        data.decimals = decimals;
        data.baseLtv = baseLtv;
        data.liquidationThreshold = liquidationThreshold;
        data.usageAsCollateralEnabled = usageAsCollateralEnabled;
    }

    function setTestUserReserveData(
        address user,
        address reserve,
        uint256 liquidityBalance,
        uint256 borrowBalance,
        uint256 originationFee,
        bool useAsCollateral
    ) external {
        s_testUserReserveData[user][reserve] =
            TestUserReserveData(liquidityBalance, borrowBalance, originationFee, useAsCollateral);
    }

    function setReserveNormalizedIncome(address reserve, uint256 normalizedIncome) external {
        s_testReserveData[reserve].normalizedIncome = normalizedIncome;
    }

    function setReserveIsActive(address reserve, bool isActive) external {
        s_testReserveData[reserve].isActive = isActive;
    }

    function setReserveATokenAddress(address reserve, address aTokenAddress) external {
        s_testReserveData[reserve].aTokenAddress = aTokenAddress;
    }

    function getReserves() external view returns (address[] memory) {
        return s_reserves;
    }

    function getReserveConfiguration(address reserve) external view returns (uint256, uint256, uint256, bool) {
        TestReserveData memory data = s_testReserveData[reserve];

        return (data.decimals, data.baseLtv, data.liquidationThreshold, data.usageAsCollateralEnabled);
    }

    function getTestReserveData(address reserve) external view returns (TestReserveData memory) {
        return s_testReserveData[reserve];
    }

    function getTestUserReserveData(address reserve, address user)
        external
        view
        returns (TestUserReserveData memory)
    {
        return s_testUserReserveData[user][reserve];
    }

    function getUserBasicReserveData(address reserve, address user)
        external
        view
        returns (uint256, uint256, uint256, bool)
    {
        TestUserReserveData memory data = s_testUserReserveData[user][reserve];

        return (data.liquidityBalance, data.borrowBalance, data.originationFee, data.useAsCollateral);
    }

    function getReserveNormalizedIncome(address reserve) external view returns (uint256) {
        return s_testReserveData[reserve].normalizedIncome;
    }

    function isUserUseReserveAsCollateralEnabled(address reserve, address user) external view returns (bool) {
        return s_testUserReserveData[user][reserve].useAsCollateral;
    }

    function getReserveATokenAddress(address reserve) external view returns (address) {
        return s_testReserveData[reserve].aTokenAddress;
    }

    function getReserveIsActive(address reserve) external view returns (bool) {
        return s_testReserveData[reserve].isActive;
    }

    function getReserveAvailableLiquidity(address reserve) external view returns (uint256) {
        if (reserve == EthAddressLib.ethAddress()) {
            return address(this).balance;
        }

        return IERC20(reserve).balanceOf(address(this));
    }

    function updateStateOnRedeem(address, address, uint256, bool) external {}

    function transferToUser(address _reserve, address payable _user, uint256 _amount) external {
        if (_reserve != EthAddressLib.ethAddress()) {
            IERC20(_reserve).safeTransfer(_user, _amount);
        } else {
            (bool result,) = _user.call{value: _amount, gas: 50000}("");
            if (!result) {
                revert MockLendingPoolCore__EthTransferFailed(_user, _amount);
            }
        }
    }
}
