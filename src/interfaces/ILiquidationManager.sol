// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ILiquidationManager {
    function liquidationCall(
        address _collateral,
        address _reserve,
        address _user,
        uint256 _purchaseAmount,
        bool _receiveAToken
    ) external payable returns (uint256, string memory);
}
