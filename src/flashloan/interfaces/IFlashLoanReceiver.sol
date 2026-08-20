// SPDX-License-Indentifier: MIT
pragma solidity 0.8.30;

/**
 * @title IFlashLoanReceiver interface
 * @notice Interface for the Aave fee IFlashLoanReceiver.
 * @dev implement this interface to develop a flashloan-compatible flashLoanReceiver contract
 *
 */
interface IFlashLoanReceiver {
    function executeOperation(address _reserve, uint256 _amount, uint256 _fee, bytes calldata _params) external;
}
