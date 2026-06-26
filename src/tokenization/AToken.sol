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
import {LendingPoolCore} from "src/lendingpool/LendingPoolCore.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";

/**
 * @title Aave ERC20 AToken
 * @dev Implementation of the interest bearing token for the DLP protocol.
 */
contract AToken is ERC20 {
    ///////////////////////////////////
    //            Libraries          //
    ///////////////////////////////////
    using WadRayMath for uint256;
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////
    error AToken__OnlyLendingPool();
    error AToken__ZeroAddress();

    ////////////////////////////////
    //      State Variables       //
    ////////////////////////////////
    address private immutable i_underlyingAssetAddress;
    uint8 private immutable i_underlyingAssetDecimals;

    // the last reserve normalized income already applied to that user
    mapping(address user => uint256 lastNormalizedIncome) private s_userIndexes;
    // TODO need to check interestRedirectionAddresses
    mapping(address => address) private s_interestRedirectionAddresses;
    // TODO need to check redirectedBalances
    mapping(address => uint256) private s_redirectedBalances;

    LendingPoolAddressesProvider private immutable i_addressesProvider;
    LendingPoolCore private immutable i_core;
    LendingPool private immutable i_pool;
    //TODO dataProvider

    ////////////////////////////////
    //           Events           //
    ////////////////////////////////
    event MintOnDeposit(address indexed _from, uint256 _value, uint256 _fromBalanceIncrease, uint256 _fromIndex);
    event RedirectedBalanceUpdated(
        address indexed _targetAddress,
        uint256 _targetBalanceIncrease,
        uint256 _targetIndex,
        uint256 _redirectedBalanceAdded,
        uint256 _redirectedBalanceRemoved
    );
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
        if (coreAddress == address(0) || poolAddress == address(0)) {
            revert AToken__ZeroAddress();
        }

        i_core = LendingPoolCore(coreAddress);
        i_pool = LendingPool(poolAddress);

        // TODO dataProvider
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

        // If the user is redirecting his interest towards someone else,
        // we update the redirected balance of the redirection address by adding the accrued interest
        // and the amount deposited
        _updateRedirectedBalanceOfRedirectionAddress(_account, balanceIncrease + _amount, 0);

        // Mint an equivalent amount of tokens to cover the new deposit
        _mint(_account, _amount);

        emit MintOnDeposit(_account, _amount, balanceIncrease, index);
    }

    ////////////////////////////////
    //       Public Functions     //
    ////////////////////////////////

    /**
     * @dev calculates the balance of the user, which is the
     * principal balance + interest generated by the principal balance + interest generated by the redirected balance
     * @param _user the user for which the balance is being calculated
     * @return the total balance of the user
     *
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // Current principal balance of the user
        uint256 currentPrincipalBalance = super.balanceOf(_user);
        // Balance redirected by other users to _user for interest rate accrual
        uint256 redirectedBalance = s_redirectedBalances[_user];

        if (currentPrincipalBalance == 0 && redirectedBalance == 0) {
            return 0;
        }

        // If the _user is not redirecting the interest to anybody, accrues
        // the interest for himself
        if (s_interestRedirectionAddresses[_user] == address(0)) {
            // Accruing for himself means that both the principal balance and
            // the redirected balance partecipate in the interest
            return _calculateCumulatedBalance(_user, currentPrincipalBalance + redirectedBalance) - redirectedBalance;
        } else {
            // If the user redirected the interest, then only the redirected
            // balance generates interest. In that case, the interest generated
            // by the redirected balance is added to the current principal balance.
            return currentPrincipalBalance + _calculateCumulatedBalance(_user, redirectedBalance) - redirectedBalance;
        }
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
     * @dev updates the redirected balance of the user. If the user is not redirecting his
     * interest, nothing is executed.
     * @param _user the address of the user for which the interest is being accumulated
     * @param _balanceToAdd the amount to add to the redirected balance
     * @param _balanceToRemove the amount to remove from the redirected balance
     *
     */
    function _updateRedirectedBalanceOfRedirectionAddress(
        address _user,
        uint256 _balanceToAdd,
        uint256 _balanceToRemove
    ) internal {
        address redirectionAddress = s_interestRedirectionAddresses[_user];
        // If there isn't any redirection, nothing to be done
        if (redirectionAddress == address(0)) {
            return;
        }

        // Compound balances of the redirected address
        (,, uint256 balanceIncrease, uint256 index) = _cumulateBalance(redirectionAddress);

        // Updating the redirected balance
        s_redirectedBalances[redirectionAddress] =
            s_redirectedBalances[redirectionAddress] + _balanceToAdd - _balanceToRemove;

        // If the interest of redirectionAddress is also being redirected, we need to update
        // the redirected balance of the redirection target by adding the balance increase
        address targetOfRedirectionAddress = s_interestRedirectionAddresses[redirectionAddress];

        if (targetOfRedirectionAddress != address(0)) {
            s_redirectedBalances[targetOfRedirectionAddress] =
                s_redirectedBalances[targetOfRedirectionAddress] + balanceIncrease;
        }

        emit RedirectedBalanceUpdated(redirectionAddress, balanceIncrease, index, _balanceToAdd, _balanceToRemove);
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
    function totalSupply() public view returns (uint256) {
        uint256 currentSupplyPrincipal = super.totalSupply();
        if (currentSupplyPrincipal == 0) {
            return 0;
        }

        return currentSupplyPrincipal.wadToRay().rayMul(i_core.getReserveNormalizedIncome(i_underlyingAssetAddress))
            .rayToWad();
    }
}
