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

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

interface ILendingPool {}

contract AToken is ERC20 {
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////
    error AToken__UnderlyingAssetDecimalsIsZero();
    error AToken__OnlyLendingPool();

    ////////////////////////////////
    //      State Variables       //
    ////////////////////////////////
    ILendingPool private immutable i_pool;
    address private immutable i_underlyingAssetAddress;
    uint8 private immutable i_underlyingAssetDecimals;

    ////////////////////////////////
    //           Events           //
    ////////////////////////////////
    event MintOnDeposit(address indexed _from, uint256 _value, uint256 _fromBalanceIncrease, uint256 _fromIndex);

    ////////////////////////////////
    //          Modifiers         //
    ////////////////////////////////
    modifier onlyLendingPool() {
        if (msg.sender != address(i_pool)) {
            revert AToken__OnlyLendingPool();
        }
        _;
    }

    ////////////////////////////////
    //          Functions         //
    ////////////////////////////////

    // TODO replace address _lendingPool with LendingPoolAddressesProvider _addressesProvider
    constructor(
        address _lendingPool,
        address _underlyingAsset,
        uint8 _underlyingAssetDecimals,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        if (_underlyingAssetDecimals == 0) {
            revert AToken__UnderlyingAssetDecimalsIsZero();
        }
        i_underlyingAssetDecimals = _underlyingAssetDecimals;
        i_pool = ILendingPool(_lendingPool);
        i_underlyingAssetAddress = _underlyingAsset;
    }

    ////////////////////////////////
    //     External Functions     //
    ////////////////////////////////

    // TODO must be updated with cumalted balance and redirection address
    function mintOnDeposit(address _account, uint256 _amount) external onlyLendingPool {
        _mint(_account, _amount);
        emit MintOnDeposit(_account, _amount, 0, 0);
    }

    ////////////////////////////////
    //       Public Functions     //
    ////////////////////////////////

    /////////////////////////////////
    //       Private Functions     //
    /////////////////////////////////

    //////////////////////////////////////////////////////
    //     Private & Internal View & Pure Functions     //
    //////////////////////////////////////////////////////

    //////////////////////////////////////////////////////
    //      External & Public View & Pure Functions     //
    //////////////////////////////////////////////////////
    function decimals() public view override returns (uint8) {
        return i_underlyingAssetDecimals;
    }

    function getPoolAddress() external view returns (address) {
        return address(i_pool);
    }

    function getUnderlyingAssetAddress() external view returns (address) {
        return i_underlyingAssetAddress;
    }
}
