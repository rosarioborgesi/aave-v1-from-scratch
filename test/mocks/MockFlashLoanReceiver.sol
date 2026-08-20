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

import {FlashLoanReceiverBase} from "src/flashloan/base/FlashLoanReceiverBase.sol";
import {ILendingPoolAddressesProvider} from "src/interfaces/ILendingPoolAddressesProvider.sol";
import {MockERC20} from "./MockERC20.sol";
import {EthAddressLib} from "src/libraries/EthAddressLib.sol";

contract MockFlashLoanReceiver is FlashLoanReceiverBase {
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////
    error MockFlashLoanReceiver__Invalidbalance();

    /////////////////////////////////////////
    //            State variables          //
    /////////////////////////////////////////
    bool private failExecution = false;

    ////////////////////////////////
    //           Events           //
    ////////////////////////////////
    event ExecutedWithFail(address _reserve, uint256 _amount, uint256 _fee);
    event ExecutedWithSuccess(address _reserve, uint256 _amount, uint256 _fee);

    ////////////////////////////////
    //          Functions         //
    ////////////////////////////////
    constructor(ILendingPoolAddressesProvider _provider) FlashLoanReceiverBase(_provider) {}

    //////////////////////////////////
    //       External Functions     //
    //////////////////////////////////
    function setFailExecutionTransfer(bool _fail) external {
        failExecution = _fail;
    }

    function executeOperation(address _reserve, uint256 _amount, uint256 _fee, bytes memory /*_params*/ ) external override {
        // Cast the _reserve address to a MockERC20
        MockERC20 token = MockERC20(_reserve);

        // Check that the contract has the specified balance
        if (_amount > _getBalance(address(this), _reserve)) {
            revert MockFlashLoanReceiver__Invalidbalance();
        }

        if (failExecution) {
            emit ExecutedWithFail(_reserve, _amount, _fee);
            return;
        }

        // Execution does not fail - mint _fee tokens and return _amount + _fee to the _destination
        // If the reserve is eth, the mock contract must receive at least _fee ETH before calling executeOperation
        if (_reserve != EthAddressLib.ethAddress()) {
            // Mint _fee tokens
            token.mint(address(this), _fee);
        }

        // returning _amount + _fee to the destination
        _transferFundsBackToPool(_reserve, _amount + _fee);
        emit ExecutedWithSuccess(_reserve, _amount, _fee);
    }
}
