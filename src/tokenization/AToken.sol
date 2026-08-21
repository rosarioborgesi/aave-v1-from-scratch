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

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {LendingPool} from "src/lendingpool/LendingPool.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolDataProvider} from "src/lendingpool/LendingPoolDataProvider.sol";
import {LendingPoolCore} from "src/lendingpool/LendingPoolCore.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";

/**
 * @title Aave ERC20 AToken
 * @dev Implementation of the interest bearing token for the DLP protocol.
 */
contract AToken is ERC20 {
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////
    error AToken__OnlyLendingPool();
    error AToken__ZeroAddress();
    error AToken__AmountIsZero();
    error AToken__AmountToRedeemGreaterThanCurrentBalance();
    error AToken__TransferNotAllowed();
    error AToken__AmountMustBeGreaterThanZero();

    ///////////////////////////////////
    //            Libraries          //
    ///////////////////////////////////
    using WadRayMath for uint256;

    ////////////////////////////////
    //      State Variables       //
    ////////////////////////////////
    uint256 public constant MAX_UINT = type(uint256).max;

    address private immutable i_underlyingAssetAddress;
    uint8 private immutable i_underlyingAssetDecimals;

    // the last reserve normalized income already applied to that user
    mapping(address user => uint256 lastNormalizedIncome) internal s_userIndexes;

    LendingPoolAddressesProvider private immutable i_addressesProvider;
    LendingPoolCore private immutable i_core;
    LendingPool private immutable i_pool;
    LendingPoolDataProvider private immutable i_dataProvider;

    ////////////////////////////////
    //           Events           //
    ////////////////////////////////
    /**
     * @dev emitted after the mint action
     * @param _from the address performing the mint
     * @param _value the amount to be minted
     * @param _fromBalanceIncrease the cumulated balance since the last update of the user
     * @param _fromIndex the last index of the user
     *
     */
    event MintOnDeposit(address indexed _from, uint256 _value, uint256 _fromBalanceIncrease, uint256 _fromIndex);

    /**
     * @dev emitted after the redeem action
     * @param _from the address performing the redeem
     * @param _value the amount to be redeemed
     * @param _fromBalanceIncrease the cumulated balance since the last update of the user
     * @param _fromIndex the last index of the user
     *
     */
    event Redeem(address indexed _from, uint256 _value, uint256 _fromBalanceIncrease, uint256 _fromIndex);

    /**
     * @dev emitted during the transfer action
     * @param _from the address from which the tokens are being transferred
     * @param _to the adress of the destination
     * @param _value the amount to be minted
     * @param _fromBalanceIncrease the cumulated balance since the last update of the user
     * @param _toBalanceIncrease the cumulated balance since the last update of the destination
     * @param _fromIndex the last index of the user
     * @param _toIndex the last index of the liquidator
     *
     */
    event BalanceTransfer(
        address indexed _from,
        address indexed _to,
        uint256 _value,
        uint256 _fromBalanceIncrease,
        uint256 _toBalanceIncrease,
        uint256 _fromIndex,
        uint256 _toIndex
    );

    /**
     * @dev emitted during the liquidation action, when the liquidator reclaims the underlying
     * asset
     * @param _from the address from which the tokens are being burned
     * @param _value the amount to be burned
     * @param _fromBalanceIncrease the cumulated balance since the last update of the user
     * @param _fromIndex the last index of the user
     *
     */
    event BurnOnLiquidation(address indexed _from, uint256 _value, uint256 _fromBalanceIncrease, uint256 _fromIndex);
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

    constructor(
        address _addressesProvider,
        address _underlyingAsset,
        uint8 _underlyingAssetDecimals,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        if (_underlyingAsset == address(0) || _addressesProvider == address(0)) {
            revert AToken__ZeroAddress();
        }
        i_underlyingAssetDecimals = _underlyingAssetDecimals;
        i_addressesProvider = LendingPoolAddressesProvider(_addressesProvider);

        address coreAddress = i_addressesProvider.getLendingPoolCore();
        address poolAddress = i_addressesProvider.getLendingPool();
        address dataProviderAddress = i_addressesProvider.getLendingPoolDataProvider();
        if (coreAddress == address(0) || poolAddress == address(0) || dataProviderAddress == address(0)) {
            revert AToken__ZeroAddress();
        }

        i_core = LendingPoolCore(payable(coreAddress));
        i_pool = LendingPool(poolAddress);
        i_dataProvider = LendingPoolDataProvider(dataProviderAddress);
        i_underlyingAssetAddress = _underlyingAsset;
    }

    ////////////////////////////////
    //     External Functions     //
    ////////////////////////////////

    /**
     * @dev mints token in the event of users depositing the underlying asset into the lending pool
     * only lending pools can call this function
     * @param _account the address receiving the minted tokens
     * @param _amount the amount of tokens to mint
     */
    function mintOnDeposit(address _account, uint256 _amount) external onlyLendingPool {
        // Cumulates the balance of the user
        (,, uint256 balanceIncrease, uint256 index) = _cumulateBalance(_account);

        // Mint an equivalent amount of tokens to cover the new deposit
        _mint(_account, _amount);

        emit MintOnDeposit(_account, _amount, balanceIncrease, index);
    }

    /**
     * @dev redeems aToken for the underlying asset
     * @param _amount the amount being redeemed
     *
     */
    function redeem(uint256 _amount) external {
        if (_amount == 0) {
            revert AToken__AmountIsZero();
        }

        // Cumulate the balance of the user
        (, uint256 currentBalance, uint256 balanceIncrease, uint256 index) = _cumulateBalance(msg.sender);

        uint256 amountToRedeem = _amount;

        // If amount is equal to type(uint256).max, the user wants to redeem everything
        if (_amount == MAX_UINT) {
            amountToRedeem = currentBalance;
        }

        // Check that the amount to redeem is lower or equal then the user balance
        if (amountToRedeem > currentBalance) {
            revert AToken__AmountToRedeemGreaterThanCurrentBalance();
        }

        // Check that the user is allowed to redeem the amount
        if (!isTransferAllowed(msg.sender, amountToRedeem)) {
            revert AToken__TransferNotAllowed();
        }

        // burn tokens equivalent to the amount requested
        _burn(msg.sender, amountToRedeem);

        bool userIndexReset = false;
        // Reset the user data if the remaining balance is 0
        if (currentBalance - amountToRedeem == 0) {
            userIndexReset = _resetDataOnZeroBalance(msg.sender);
        }

        // Executes redeem of the underlying asset
        i_pool.redeemUnderlying(
            i_underlyingAssetAddress, payable(msg.sender), amountToRedeem, currentBalance - amountToRedeem
        );

        emit Redeem(msg.sender, amountToRedeem, balanceIncrease, userIndexReset ? 0 : index);
    }

    /**
     * @dev transfers tokens in the event of a borrow being liquidated, in case the liquidators reclaims the aToken
     *      only lending pools can call this function
     * @param _from the address from which transfer the aTokens
     * @param _to the destination address
     * @param _value the amount to transfer
     *
     */
    function transferOnLiquidation(address _from, address _to, uint256 _value) external onlyLendingPool {
        _executeTransfer(_from, _to, _value);
    }

    /**
     * @dev burns token in the event of a borrow being liquidated, in case the liquidators reclaims the underlying asset
     * Transfer of the liquidated asset is executed by the lending pool contract.
     * only lending pools can call this function
     * @param _account the address from which burn the aTokens
     * @param _value the amount to burn
     *
     */
    function burnOnLiquidation(address _account, uint256 _value) external onlyLendingPool {
        // Realize all interest accrued by _account since its last balance update
        (, uint256 accountBalance, uint256 balanceIncrease, uint256 index) = _cumulateBalance(_account);

        // burns the requested amount of tokens. This is ERC20-burn
        _burn(_account, _value);

        // Initializes a flag used to choose the correct index value for the event.
        bool userIndexReset = false;
        // Reset the user data if the remaining balance is 0
        if (accountBalance - _value == 0) {
            userIndexReset = _resetDataOnZeroBalance(_account);
        }

        emit BurnOnLiquidation(_account, _value, balanceIncrease, userIndexReset ? 0 : index);
    }

    ////////////////////////////////
    //       Public Functions     //
    ////////////////////////////////

    /**
     * @dev calculates the balance of the user, including interest accrued on their principal balance.
     * @param _user the user for which the balance is being calculated
     * @return the total balance of the user
     *
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // Current principal balance of the user
        uint256 currentPrincipalBalance = super.balanceOf(_user);

        if (currentPrincipalBalance == 0) {
            return 0;
        }

        // Accrue the user's interest
        return _calculateCumulatedBalance(_user, currentPrincipalBalance);
    }

    //////////////////////////////////
    //       Internal Functions     //
    //////////////////////////////////

    /**
     * @dev accumulates the accrued interest of the user to the principal balance
     * @param _user the address of the user for which the interest is being accumulated
     * @return the previous principal balance, the new principal balance, the balance increase
     * and the new user index
     */
    function _cumulateBalance(address _user) internal returns (uint256, uint256, uint256, uint256) {
        uint256 previousPrincipalBalance = super.balanceOf(_user);

        // calculate the accrued interest since the last accumulation
        uint256 balanceIncrease = balanceOf(_user) - previousPrincipalBalance;
        // mints an amount of tokens equivalent to the amount accumulated
        _mint(_user, balanceIncrease);
        // updates the user index
        uint256 index = s_userIndexes[_user] = i_core.getReserveNormalizedIncome(i_underlyingAssetAddress);

        return (previousPrincipalBalance, previousPrincipalBalance + balanceIncrease, balanceIncrease, index);
    }

    /**
     * @dev calculate the interest accrued by _user on a specific balance
     * @param _user the address of the user for which the interest is being accumulated
     * @param _balance the balance on which the interest is calculated
     * @return The balance including the interest accrued since the user's last index update
     *
     */
    function _calculateCumulatedBalance(address _user, uint256 _balance) internal view returns (uint256) {
        // currentBalance = principalBalance * currentReserveNormalizedIncome / userIndex
        return _balance.wadToRay().rayMul(i_core.getReserveNormalizedIncome(i_underlyingAssetAddress))
            .rayDiv(s_userIndexes[_user]).rayToWad();
    }

    /**
     * @dev resets the user's normalized-income index when they have no balance left.
     * @param _user the address of the user
     * @return true when the user index has been reset, which is used to emit the proper index value.
     *
     */
    function _resetDataOnZeroBalance(address _user) internal returns (bool) {
        s_userIndexes[_user] = 0;
        return true;
    }

    /**
     * @dev executes the transfer of aTokens, invoked by both _update() and
     *      transferOnLiquidation()
     * @param _from the address from which transfer the aTokens
     * @param _to the destination address
     * @param _value the amount to transfer
     *
     */
    function _executeTransfer(address _from, address _to, uint256 _value) internal {
        if (_value == 0) {
            revert AToken__AmountMustBeGreaterThanZero();
        }

        // Cumulate the balance of the sender:
        // 1. Reads the stored principal aToken balance.
        // 2. Calculates interest accrued since the saved liquidity index
        // 3. Mints the interest as aTokens
        // 4. Updates the saved index to the current reserve normalized income index
        (, uint256 fromBalance, uint256 fromBalanceIncrease, uint256 fromIndex) = _cumulateBalance(_from);

        // Cumulate the balance of the receiver
        (,, uint256 toBalanceIncrease, uint256 toIndex) = _cumulateBalance(_to);

        // Performs the ERC20-transfer
        super._update(_from, _to, _value);

        // Creates a flag used only to report the correct index in the custom event.
        bool fromIndexReset = false;

        // resets the sender’s stored accounting data if remaining balance is zero
        if (fromBalance - _value == 0) {
            fromIndexReset = _resetDataOnZeroBalance(_from);
        }

        emit BalanceTransfer(
            _from, _to, _value, fromBalanceIncrease, toBalanceIncrease, fromIndexReset ? 0 : fromIndex, toIndex
        );
    }

    /**
     * @dev Overrides the ERC20 balance-update hook to apply aToken-specific
     * transfer accounting and collateral-safety validation.
     *
     * Minting and burning are delegated directly to the parent ERC20
     * implementation. This includes interest minted while balances are
     * accumulated by {_cumulateBalance}.
     *
     * For regular transfers, verifies that reducing `from`'s aToken balance does
     * not violate the lending pool's collateral requirements, then realizes
     * accrued interest for both accounts and transfers the tokens.
     *
     * @param _from The address sending tokens. The zero address indicates minting.
     * @param _to The address receiving tokens. The zero address indicates burning.
     * @param _value The amount of aTokens to mint, burn, or transfer.
     */
    function _update(address _from, address _to, uint256 _value) internal override {
        // Preserve ordinary ERC-20 mint/burn behavior.
        if (_from == address(0) || _to == address(0)) {
            super._update(_from, _to, _value);
            return;
        }

        // Normal user transfer only
        if (!isTransferAllowed(_from, _value)) {
            revert AToken__TransferNotAllowed();
        }

        _executeTransfer(_from, _to, _value);
    }

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

    /**
     * @dev returns the last index of the user, used to calculate the balance of the user
     * @param _user address of the user
     * @return the last user index
     *
     */
    function getUserIndex(address _user) external view returns (uint256) {
        return s_userIndexes[_user];
    }

    /**
     * @dev calculates the total supply of the specific aToken
     * since the balance of every single user increases over time, the total supply
     * does that too.
     * @return the current total supply
     *
     */
    function totalSupply() public view override returns (uint256) {
        uint256 currentSupplyPrincipal = super.totalSupply();
        if (currentSupplyPrincipal == 0) {
            return 0;
        }

        return currentSupplyPrincipal.wadToRay().rayMul(i_core.getReserveNormalizedIncome(i_underlyingAssetAddress))
            .rayToWad();
    }

    /**
     * @dev returns the principal balance of the user. The principal balance is the last
     * updated stored balance, which does not consider the perpetually accruing interest.
     * @param _user the address of the user
     * @return the principal balance of the user
     *
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @dev Used to validate transfers before actually executing them.
     * @param _user address of the user to check
     * @param _amount the amount to check
     * @return true if the _user can transfer _amount, false otherwise
     *
     */
    function isTransferAllowed(address _user, uint256 _amount) public view returns (bool) {
        return i_dataProvider.balanceDecreaseAllowed(i_underlyingAssetAddress, _user, _amount);
    }
}
