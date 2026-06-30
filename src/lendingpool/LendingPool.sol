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

import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {AToken} from "src/tokenization/AToken.sol";
import {LendingPoolCore} from "./LendingPoolCore.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";

/**
 * @title LendingPool contract
 * @notice Implements the actions of the LendingPool, and exposes accessory methods to fetch the users and reserve data
 */
contract LendingPool is ReentrancyGuard {
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////
    error LendingPool__AmountIsZero();
    error LendingPool__ReserveIsNotActive();
    error LendingPool__ReserveIsFrozen();
    error LendingPool__ZeroAddress();

    ////////////////////////////////
    //      State Variables       //
    ////////////////////////////////
    LendingPoolCore private immutable i_core;
    LendingPoolAddressesProvider private immutable i_addressesProvider;

    ////////////////////////////////
    //           Events           //
    ////////////////////////////////
    /**
     * @dev emitted on deposit
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     * @param _amount the amount to be deposited
     * @param _referral the referral number of the action
     * @param _timestamp the timestamp of the action
     *
     */
    event Deposit(
        address indexed _reserve, address indexed _user, uint256 _amount, uint16 indexed _referral, uint256 _timestamp
    );

    ////////////////////////////////
    //          Modifiers         //
    ////////////////////////////////
    modifier onlyAmountGreaterThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert LendingPool__AmountIsZero();
        }
        _;
    }

    modifier onlyActiveReserve(address _reserve) {
        if (!i_core.getReserveIsActive(_reserve)) {
            revert LendingPool__ReserveIsNotActive();
        }
        _;
    }

    modifier onlyUnfreezedReserve(address _reserve) {
        if (i_core.getReserveIsFreezed(_reserve)) {
            revert LendingPool__ReserveIsFrozen();
        }
        _;
    }

    ////////////////////////////////
    //          Functions         //
    ////////////////////////////////
    // TODO replace with initialize for proxy
    constructor(address _addressesProvider) {
        if (_addressesProvider == address(0)) {
            revert LendingPool__ZeroAddress();
        }
        i_addressesProvider = LendingPoolAddressesProvider(_addressesProvider);

        address coreAddress = i_addressesProvider.getLendingPoolCore();

        if (coreAddress == address(0)) {
            revert LendingPool__ZeroAddress();
        }

        i_core = LendingPoolCore(coreAddress);
    }

    ////////////////////////////////
    //     External Functions     //
    ////////////////////////////////
    /**
     * @dev deposits The underlying asset into the reserve. A corresponding amount of the overlying asset (aTokens)
     * is minted.
     * @param _reserve the address of the reserve
     * @param _amount the amount to be deposited
     * @param _referralCode integrators are assigned a referral code and can potentially receive rewards.
     *
     */
    function deposit(address _reserve, uint256 _amount, uint16 _referralCode)
        external
        payable
        nonReentrant
        onlyActiveReserve(_reserve)
        onlyUnfreezedReserve(_reserve)
        onlyAmountGreaterThanZero(_amount)
    {
        AToken aToken = AToken(i_core.getReserveATokenAddress(_reserve));

        bool isFirstDeposit = aToken.balanceOf(msg.sender) == 0;

        i_core.updateStateOnDeposit(_reserve, msg.sender, _amount, isFirstDeposit);

        // Minting AToken to user 1:1 with the specific exchange rate
        aToken.mintOnDeposit(msg.sender, _amount);

        // Transfer ETH to the core contract
        i_core.transferToReserve{value: msg.value}(_reserve, payable(msg.sender), _amount);

        emit Deposit(_reserve, msg.sender, _amount, _referralCode, block.timestamp);
    }

    ////////////////////////////////
    //       Public Functions     //
    ////////////////////////////////

    //////////////////////////////////
    //       Internal Functions     //
    //////////////////////////////////

    /////////////////////////////////
    //       Private Functions     //
    /////////////////////////////////

    //////////////////////////////////////////////////////
    //     Private & Internal View & Pure Functions     //
    //////////////////////////////////////////////////////

    //////////////////////////////////////////////////////
    //      External & Public View & Pure Functions     //
    //////////////////////////////////////////////////////
    function getLendingPoolCoreAddress() external view returns (address) {
        return address(i_core);
    }

    function getLendingPoolAddressesProvider() external view returns (address) {
        return address(i_addressesProvider);
    }
}
