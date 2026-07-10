// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract MockLendingPoolCore {
    // Stores the return values of getReserveConfiguration()
    struct ReserveConfiguration {
        uint256 decimals;
        uint256 baseLtv;
        uint256 liquidationThreshold;
        bool usageAsCollateralEnabled;
    }

    // Stores the return values getUserBasicReserveData()
    struct UserBasicReserveData {
        uint256 liquidityBalance;
        uint256 borrowBalance;
        uint256 originationFee;
        bool useAsCollateral;
    }

    address[] private s_reserves;
    mapping(address reserve => bool isAdded) private s_isReserveAdded;
    mapping(address reserve => ReserveConfiguration configuration) private s_configurations;
    mapping(address user => mapping(address reserve => UserBasicReserveData data)) private s_userData;
    mapping(address reserve => uint256 normalizedIncome) private s_reserveNormalizedIncome;

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
        s_configurations[reserve] = ReserveConfiguration(
            decimals, baseLtv, liquidationThreshold, usageAsCollateralEnabled
        );
    }

    function setUserBasicReserveData(
        address user,
        address reserve,
        uint256 liquidityBalance,
        uint256 borrowBalance,
        uint256 originationFee,
        bool useAsCollateral
    ) external {
        s_userData[user][reserve] = UserBasicReserveData(
            liquidityBalance, borrowBalance, originationFee, useAsCollateral
        );
    }

    function setReserveNormalizedIncome(address reserve, uint256 normalizedIncome) external {
        s_reserveNormalizedIncome[reserve] = normalizedIncome;
    }

    function getReserves() external view returns (address[] memory) {
        return s_reserves;
    }

    function getReserveConfiguration(address reserve) external view returns (uint256, uint256, uint256, bool) {
        ReserveConfiguration memory configuration = s_configurations[reserve];

        return (
            configuration.decimals,
            configuration.baseLtv,
            configuration.liquidationThreshold,
            configuration.usageAsCollateralEnabled
        );
    }

    function getUserBasicReserveData(address reserve, address user)
        external
        view
        returns (uint256, uint256, uint256, bool)
    {
        UserBasicReserveData memory data = s_userData[user][reserve];

        return (data.liquidityBalance, data.borrowBalance, data.originationFee, data.useAsCollateral);
    }

    function getReserveNormalizedIncome(address reserve) external view returns (uint256) {
        return s_reserveNormalizedIncome[reserve];
    }

    function isUserUseReserveAsCollateralEnabled(address reserve, address user) external view returns (bool) {
        return s_userData[user][reserve].useAsCollateral;
    }
}
