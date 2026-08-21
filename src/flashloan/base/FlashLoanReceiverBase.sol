// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IFlashLoanReceiver} from "../interfaces/IFlashLoanReceiver.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import {EthAddressLib} from "src/libraries/EthAddressLib.sol";

/// @title Flash Loan Receiver Base
/// @notice Provides shared transfer and balance helpers for flash loan receiver contracts.
/// @dev Inherit from this contract to implement `IFlashLoanReceiver` while reusing pool repayment logic.
abstract contract FlashLoanReceiverBase is IFlashLoanReceiver {
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////
    /// @notice Thrown when an ETH transfer to a destination fails.
    /// @param _to The intended recipient of the ETH transfer.
    /// @param _amount The amount of ETH that could not be transferred.
    error FlashLoanReceiverBase__EthTransferFailed(address _to, uint256 _amount);

    ///////////////////////////////////
    //            Libraries          //
    ///////////////////////////////////
    using SafeERC20 for IERC20;

    ////////////////////////////////
    //      State Variables       //
    ////////////////////////////////
    /// @dev Resolves the current lending pool core used to receive repayments.
    ILendingPoolAddressesProvider private i_addressesProvider;

    //////////////////////////
    //      Functions       //
    //////////////////////////
    /// @param _provider The addresses provider used to locate the lending pool core.
    constructor(ILendingPoolAddressesProvider _provider) {
        i_addressesProvider = _provider;
    }

    /// @notice Accepts native ETH sent directly to this receiver.
    receive() external payable {}

    ////////////////////////////////
    //     Internal Functions     //
    ////////////////////////////////
    /// @notice Transfers borrowed funds back to the lending pool core.
    /// @param _reserve The borrowed asset address, or the ETH sentinel address for native ETH.
    /// @param _amount The amount to repay.
    function _transferFundsBackToPool(address _reserve, uint256 _amount) internal {
        address core = i_addressesProvider.getLendingPoolCore();

        _transfer(payable(core), _reserve, _amount);
    }

    /// @notice Transfers native ETH or an ERC-20 token to a destination.
    /// @param _destination The recipient of the transfer.
    /// @param _reserve The asset address, or the ETH sentinel address for native ETH.
    /// @param _amount The amount to transfer.
    function _transfer(address payable _destination, address _reserve, uint256 _amount) internal {
        if (_reserve == EthAddressLib.ethAddress()) {
            // ETH transfer
            (bool success,) = _destination.call{value: _amount}("");
            if (!success) {
                revert FlashLoanReceiverBase__EthTransferFailed(_destination, _amount);
            }
            return;
        }
        // ERC20 transfer
        IERC20(_reserve).safeTransfer(_destination, _amount);
    }

    //////////////////////////////////////////////////////
    //     Private & Internal View & Pure Functions     //
    //////////////////////////////////////////////////////
    /// @notice Returns an account's balance for a native or ERC-20 reserve.
    /// @param _target The account whose balance is queried.
    /// @param _reserve The asset address, or the ETH sentinel address for native ETH.
    /// @return The account balance denominated in the reserve asset.
    function _getBalance(address _target, address _reserve) internal view returns (uint256) {
        if (_reserve == EthAddressLib.ethAddress()) {
            return _target.balance;
        }
        return IERC20(_reserve).balanceOf(_target);
    }
}
