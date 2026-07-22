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

import {IReserveInterestRateStrategy} from "src/interfaces/IReserveInterestRateStrategy.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";
import {CoreLibrary} from "src/libraries/CoreLibrary.sol";
import {EthAddressLib} from "src/libraries/EthAddressLib.sol";
import {AToken} from "src/tokenization/AToken.sol";

/**
 * @title LendingPoolCore contract
 * @notice Holds the state of the lending pool and all the funds deposited
 * @dev NOTE: The core does not enforce security checks on the update of the state
 * (eg, updateStateOnBorrow() does not enforce that borrowed is enabled on the reserve).
 * The check that an action can be performed is a duty of the overlying LendingPool contract.
 */
contract LendingPoolCore {
    ////////////////////////////////
    //            Errors          //
    ////////////////////////////////
    error LendingPoolCore__ZeroAddress();
    error LendingPoolCore__OnlyLendingPool();
    error LendingPoolCore__CantSendEthAndTransferErc20();
    error LendingPoolCore__MsgValueLessThanAmount();
    error LendingPoolCore__EthTransferFailed(address _to, uint256 _amount);
    error LendingPoolCore__OnlyLendingPoolConfigurator();
    error LendingPoolCore__ReserveListIsEmpty();
    error LendingPoolCore__ReserveToRemoveIsNotLastReserve();
    error LendingPoolCore__ReserveHasBorrows();
    error LendingPoolCore__InvalidBorrowRateMode();

    ///////////////////////////////////
    //            Libraries          //
    ///////////////////////////////////
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using CoreLibrary for CoreLibrary.ReserveData;
    using CoreLibrary for CoreLibrary.UserReserveData;

    ////////////////////////////////
    //      State Variables       //
    ////////////////////////////////
    LendingPoolAddressesProvider private immutable i_addressesProvider;

    // Maps each underlying asset to its reserve data.
    // asset => ReserveData
    // Example: s_reserves[dai] returns the global DAI reserve state.
    mapping(address asset => CoreLibrary.ReserveData reserveData) internal s_reserves;

    // Maps each user to their data for each reserve.
    // user => reserve => UserReserveData
    // Example: s_usersReserveData[rosario][usdc] returns Rosario's USDC reserve data.
    mapping(address user => mapping(address reserve => CoreLibrary.UserReserveData userReserveData)) internal
        s_usersReserveData;

    // Stores the list of initialized reserves;
    address[] private s_reservesList;

    // Tracks whether a reserve has already been added to the reserves list
    mapping(address reserve => bool isAdded) private s_isReserveAdded;

    ////////////////////////////////
    //           Events           //
    ////////////////////////////////

    /**
     * @dev Emitted when the state of a reserve is updated
     * @param reserve the address of the reserve
     * @param liquidityRate the new liquidity rate
     * @param stableBorrowRate the new stable borrow rate
     * @param variableBorrowRate the new variable borrow rate
     * @param liquidityIndex the new liquidity index
     * @param variableBorrowIndex the new variable borrow index
     *
     */
    event ReserveUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 stableBorrowRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    event ReserveInitialized(address indexed reserve, address aTokenAddress, address interestRateStrategyAddress);

    event ReserveRemoved(address indexed reserve);
    ////////////////////////////////
    //          Modifiers         //
    ////////////////////////////////
    modifier onlyLendingPool() {
        if (msg.sender != i_addressesProvider.getLendingPool()) {
            revert LendingPoolCore__OnlyLendingPool();
        }
        _;
    }

    modifier onlyLendingPoolConfigurator() {
        if (msg.sender != i_addressesProvider.getLendingPoolConfigurator()) {
            revert LendingPoolCore__OnlyLendingPoolConfigurator();
        }
        _;
    }

    ////////////////////////////////
    //          Functions         //
    ////////////////////////////////
    constructor(address _addressesProvider) {
        if (_addressesProvider == address(0)) {
            revert LendingPoolCore__ZeroAddress();
        }
        i_addressesProvider = LendingPoolAddressesProvider(_addressesProvider);
    }

    ////////////////////////////////
    //     External Functions     //
    ////////////////////////////////
    /**
     * @dev updates the state of the core as a result of a deposit action
     * @param _reserve the address of the reserve in which the deposit is happening
     * @param _user the address of the the user depositing
     * @param _amount the amount being deposited
     * @param _isFirstDeposit true if the user is depositing for the first time
     *
     */
    function updateStateOnDeposit(address _reserve, address _user, uint256 _amount, bool _isFirstDeposit)
        external
        onlyLendingPool
    {
        s_reserves[_reserve].updateCumulativeIndexes();
        _updateReserveInterestRatesAndTimestamp(_reserve, _amount, 0);

        if (_isFirstDeposit) {
            // If this is the first deposit of the user, we configure the deposit as enabled to be used as collateral
            setUserUseReserveAsCollateral(_reserve, _user, true);
        }
    }

    /**
     * @dev Transfers reserve funds from a user to the LendingPoolCore.
     *      For ERC20 reserves, the tokens are transferred with safeTransferFrom.
     *      For ETH reserves, msg.value must be at least _amount. Any excess ETH is refunded.
     * @param _reserve The address of the reserve being deposited.
     * @param _user The address of the user making the deposit.
     * @param _amount The amount being transferred to the reserve.
     */
    function transferToReserve(address _reserve, address payable _user, uint256 _amount)
        external
        payable
        onlyLendingPool
    {
        if (_reserve != EthAddressLib.ethAddress()) {
            // ERC20 Transfer
            if (msg.value != 0) {
                revert LendingPoolCore__CantSendEthAndTransferErc20();
            }
            IERC20(_reserve).safeTransferFrom(_user, address(this), _amount);
        } else {
            // Ether transfer
            if (msg.value < _amount) {
                revert LendingPoolCore__MsgValueLessThanAmount();
            }

            if (msg.value > _amount) {
                // Send back excess ETH
                uint256 excessAmount = msg.value - _amount;
                (bool result,) = _user.call{value: excessAmount, gas: 50000}("");
                if (!result) {
                    revert LendingPoolCore__EthTransferFailed(_user, excessAmount);
                }
            }
        }
    }

    /**
     * @dev removes the last added reserve in the reservesList array
     * @param _reserveToRemove the address of the reserve
     *
     */
    function removeLastAddedReserve(address _reserveToRemove) external onlyLendingPoolConfigurator {
        uint256 reservesListLength = s_reservesList.length;

        if (reservesListLength == 0) {
            revert LendingPoolCore__ReserveListIsEmpty();
        }

        address lastReserve = s_reservesList[reservesListLength - 1];

        if (lastReserve != _reserveToRemove) {
            revert LendingPoolCore__ReserveToRemoveIsNotLastReserve();
        }

        // As we can't check if totalLiquidity is 0 (since the reserve added might not be an ERC20) we at least check that there is nothing borrowed
        if (getReserveTotalBorrows(lastReserve) != 0) {
            revert LendingPoolCore__ReserveHasBorrows();
        }

        // Reset the s_reserves[lastReserve] fields
        /* s_reserves[lastReserve].isActive = false;
        s_reserves[lastReserve].aTokenAddress = address(0);
        s_reserves[lastReserve].decimals = 0;
        s_reserves[lastReserve].lastLiquidityCumulativeIndex = 0;
        s_reserves[lastReserve].lastVariableBorrowCumulativeIndex = 0;
        s_reserves[lastReserve].borrowingEnabled = false;
        s_reserves[lastReserve].usageAsCollateralEnabled = false;
        s_reserves[lastReserve].baseLTVasCollateral = 0;
        s_reserves[lastReserve].liquidationThreshold = 0;
        s_reserves[lastReserve].liquidationBonus = 0;
        s_reserves[lastReserve].interestRateStrategyAddress = address(0); */
        delete s_reserves[lastReserve];

        s_isReserveAdded[lastReserve] = false;
        s_reservesList.pop();

        emit ReserveRemoved(lastReserve);
    }

    /**
     * @dev initializes a reserve
     * @param _reserve the address of the reserve
     * @param _aTokenAddress the address of the overlying aToken contract
     * @param _decimals the decimals of the reserve currency
     * @param _interestRateStrategyAddress the address of the interest rate strategy contract
     *
     */
    function initReserve(
        address _reserve,
        address _aTokenAddress,
        uint256 _decimals,
        address _interestRateStrategyAddress
    ) external onlyLendingPoolConfigurator {
        s_reserves[_reserve].init(_aTokenAddress, _decimals, _interestRateStrategyAddress);
        _addReserveToList(_reserve);

        emit ReserveInitialized(_reserve, _aTokenAddress, _interestRateStrategyAddress);
    }

    /**
     * @dev updates the state of the core as a result of a redeem action
     * This function is called by LendingPool when a user redeems underlying liquidity by burning aTokens
     * @param _reserve the address of the reserve in which the redeem is happening
     * @param _user the address of the the user redeeming
     * @param _amountRedeemed the amount being redeemed
     * @param _userRedeemedEverything true if the user is redeeming everything
     *
     */
    function updateStateOnRedeem(address _reserve, address _user, uint256 _amountRedeemed, bool _userRedeemedEverything)
        external
        onlyLendingPool
    {
        // Compound liquidity and variable borrow interest
        // So the protocol accounts for the interest accumulated since the last reserve update
        s_reserves[_reserve].updateCumulativeIndexes();
        _updateReserveInterestRatesAndTimestamp(_reserve, 0, _amountRedeemed);

        // If user redeemed everything the useReserveAsCollateral flag is reset
        if (_userRedeemedEverything) {
            setUserUseReserveAsCollateral(_reserve, _user, false);
        }
    }

    /**
     * @dev transfers to the user a specific amount from the reserve.
     * @param _reserve the address of the reserve where the transfer is happening
     * @param _user the address of the user receiving the transfer
     * @param _amount the amount being transferred
     *
     */
    function transferToUser(address _reserve, address payable _user, uint256 _amount) external onlyLendingPool {
        if (_reserve != EthAddressLib.ethAddress()) {
            IERC20(_reserve).safeTransfer(_user, _amount);
        } else {
            (bool result,) = _user.call{value: _amount, gas: 50000}("");
            if (!result) {
                revert LendingPoolCore__EthTransferFailed(_user, _amount);
            }
        }
    }

    /**
     * @dev updates the state of the core as a consequence of a borrow action.
     * @param _reserve the address of the reserve on which the user is borrowing
     * @param _user the address of the borrower
     * @param _amountBorrowed the new amount borrowed
     * @param _borrowFee the fee on the amount borrowed
     * @param _rateMode the borrow rate mode (stable, variable)
     * @return the new borrow rate for the user
     *
     */
    function updateStateOnBorrow(
        address _reserve,
        address _user,
        uint256 _amountBorrowed,
        uint256 _borrowFee,
        CoreLibrary.InterestRateMode _rateMode
    ) external onlyLendingPool returns (uint256, uint256) {
        // Getting the previous borrow data of the user
        (uint256 principalBorrowBalance,, uint256 balanceIncrease) = getUserBorrowBalances(_reserve, _user);

        // Update the global state of the reserve
        _updateReserveStateOnBorrow(
            _reserve, _user, principalBorrowBalance, balanceIncrease, _amountBorrowed, _rateMode
        );

        // Update the borrower's state
        _updateUserStateOnBorrow(_reserve, _user, _amountBorrowed, balanceIncrease, _borrowFee, _rateMode);

        // Recalculate reserve interest rates
        _updateReserveInterestRatesAndTimestamp(_reserve, 0, _amountBorrowed);

        // Return the results
        // 1. The borrower's final state after the update
        // 2. The interest accumulated before this borrow
        return (_getUserCurrentBorrowRate(_reserve, _user), balanceIncrease);
    }

    ////////////////////////////////
    //       Public Functions     //
    ////////////////////////////////
    /**
     * @dev enables or disables a reserve as collateral
     * @param _reserve the address of the principal reserve where the user deposited
     * @param _user the address of the depositor
     * @param _useAsCollateral true if the depositor wants to use the reserve as collateral
     *
     */
    function setUserUseReserveAsCollateral(address _reserve, address _user, bool _useAsCollateral)
        public
        onlyLendingPool
    {
        CoreLibrary.UserReserveData storage user = s_usersReserveData[_user][_reserve];
        user.useAsCollateral = _useAsCollateral;
    }

    //////////////////////////////////
    //       Internal Functions     //
    //////////////////////////////////
    /**
     * @dev Updates the reserve current stable borrow rate Rf, the current variable borrow rate Rv and the current liquidity rate Rl.
     * Also updates the lastUpdateTimestamp value. Please refer to the whitepaper for further information.
     * @param _reserve the address of the reserve to be updated
     * @param _liquidityAdded the amount of liquidity added to the protocol (deposit or repay) in the previous action
     * @param _liquidityTaken the amount of liquidity taken from the protocol (redeem or borrow)
     *
     */
    function _updateReserveInterestRatesAndTimestamp(address _reserve, uint256 _liquidityAdded, uint256 _liquidityTaken)
        internal
    {
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];
        (uint256 newLiquidityRate, uint256 newStableRate, uint256 newVariableRate) = IReserveInterestRateStrategy(
                reserve.interestRateStrategyAddress
            )
            .calculateInterestRates(
                _reserve,
                getReserveAvailableLiquidity(_reserve) + _liquidityAdded - _liquidityTaken,
                reserve.totalBorrowsStable,
                reserve.totalBorrowsVariable,
                reserve.currentAverageStableBorrowRate
            );

        reserve.currentLiquidityRate = newLiquidityRate;
        reserve.currentStableBorrowRate = newStableRate;
        reserve.currentVariableBorrowRate = newVariableRate;

        reserve.lastUpdateTimestamp = uint40(block.timestamp);

        emit ReserveUpdated(
            _reserve,
            newLiquidityRate,
            newStableRate,
            newVariableRate,
            reserve.lastLiquidityCumulativeIndex,
            reserve.lastVariableBorrowCumulativeIndex
        );
    }

    /**
     * @dev Adds a reserve to the reserves list if it has not already been added.
     * @param _reserve The reserve address to add.
     */
    function _addReserveToList(address _reserve) internal {
        if (s_isReserveAdded[_reserve]) {
            return;
        }
        s_reservesList.push(_reserve);
        s_isReserveAdded[_reserve] = true;
    }

    /**
     * @dev updates the state of a reserve as a consequence of a borrow action.
     * @param _reserve the address of the reserve on which the user is borrowing
     * @param _user the address of the borrower
     * @param _principalBorrowBalance the previous borrow balance of the borrower before the action
     * @param _balanceIncrease the accrued interest of the user on the previous borrowed amount
     * @param _amountBorrowed the new amount borrowed
     * @param _rateMode the borrow rate mode (stable, variable)
     *
     */
    function _updateReserveStateOnBorrow(
        address _reserve,
        address _user,
        uint256 _principalBorrowBalance,
        uint256 _balanceIncrease,
        uint256 _amountBorrowed,
        CoreLibrary.InterestRateMode _rateMode
    ) internal {
        // The protocol updates the reserve's indexes to include all interest accrued since the reserve's previous update.
        // This updates:
        // - the liquidity index, used to calculate deposit interest
        // - the variable borrow index, used to claculate variable debt
        s_reserves[_reserve].updateCumulativeIndexes();

        // Increasing reserve total borrows to account for the new borrow balance of the user
        // NOTE: Depending on the previous borrow mode, the borrow might need to be switched from variable to stable or viceversa
        // Every reserve stores debt in two separate totals:
        // - totalBorrowsStable
        // - totalBorrowsVariable
        // This helper adds:
        // accrued interest + newly borrowed amount
        // tot the appropriate total
        _updateReserveTotalBorrowsByRateMode(
            _reserve, _user, _principalBorrowBalance, _balanceIncrease, _amountBorrowed, _rateMode
        );
    }

    /**
     * @dev Updates the reserve's stable and variable borrow totals
     * after a borrow action.
     * @param _reserve The reserve from which the user is borrowing.
     * @param _user The borrower.
     * @param _principalBalance The user's previous stored principal.
     * @param _balanceIncrease The interest accrued on the previous principal.
     * @param _amountBorrowed The newly borrowed amount.
     * @param _newBorrowRateMode The rate mode selected for the updated debt.
     */
    function _updateReserveTotalBorrowsByRateMode(
        address _reserve,
        address _user,
        uint256 _principalBalance,
        uint256 _balanceIncrease,
        uint256 _amountBorrowed,
        CoreLibrary.InterestRateMode _newBorrowRateMode
    ) internal {
        // This function updates the reserve's total stable and variable debt when a user borrows.
        // Its main strategy is:
        //   1. Remove the user's previous principal from its old rate mode.
        //   2. Add accrued interest and the new borrow.
        //   3. Insert and complete updated principal into the selected rate mode.

        // 1. Determine the previous rate mode

        // The user can previously be: NONE, STABLE, VARIABLE

        // The existing principal is already included in either:
        // reserve.totalBorrowsStable or reserve.totalBorrowsVariable
        CoreLibrary.InterestRateMode previousRateMode = getUserCurrentBorrowRateMode(_reserve, _user);

        // 2. Load the reserve
        // This reserve contains the global debt accounting for the asset:
        // - Total stable debt
        // - Total variable debt
        // - Avarage stable borrow rate
        // - Current stable borrow rate
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];

        // 3. Remove the previous principal

        if (previousRateMode == CoreLibrary.InterestRateMode.STABLE) {
            // Previous mode is stable

            CoreLibrary.UserReserveData storage user = s_usersReserveData[_user][_reserve];
            // The user's principal is removed from the reserve's total stable debt.
            // The reserve's average stable borrow rate must also be recalculated
            // because the removed debt had the user's previous stable rate.
            reserve.decreaseTotalBorrowsStableAndUpdateAverageRate(_principalBalance, user.stableBorrowRate);
        } else if (previousRateMode == CoreLibrary.InterestRateMode.VARIABLE) {
            // Previous mode is variable

            // The principal is removed from the variable debt total.
            // Variable debt doesn't require updating an average rate because every variable
            // borrower follows the reseve's variable borrow index.
            reserve.decreaseTotalBorrowsVariable(_principalBalance);
        }

        // First borrow
        // If the previous mode is NONE, nothing is removed because the user has no existing debt.

        // 4. Calculate the new principal

        // The new principal includes: previous stored principal + accrued interest + new borrowed amount
        uint256 newPrincipalAmount = _principalBalance + _balanceIncrease + _amountBorrowed;

        // 5. Add the complete debt to the new rate mdoe
        if (_newBorrowRateMode == CoreLibrary.InterestRateMode.STABLE) {
            // New mode is stable

            // The complete updated principal is added to the stable debt total using the
            // reserve's current stable rate

            // The average stable borrow rate is recalculated
            reserve.increaseTotalBorrowsStableAndUpdateAverageRate(newPrincipalAmount, reserve.currentStableBorrowRate);
        } else if (_newBorrowRateMode == CoreLibrary.InterestRateMode.VARIABLE) {
            // New mode is variable

            // The complete updated principal is added to the variable debt total
            reserve.increaseTotalBorrowsVariable(newPrincipalAmount);
        } else {
            // Invalid mode

            // NONE is not valid for a new borrow
            revert LendingPoolCore__InvalidBorrowRateMode();
        }
    }

    /**
     * @dev updates the state of a user as a consequence of a borrow action.
     * @param _reserve the address of the reserve on which the user is borrowing
     * @param _user the address of the borrower
     * @param _amountBorrowed the amount borrowed
     * @param _balanceIncrease the accrued interest of the user on the previous borrowed amount
     * @param _fee the origination fee charged for the borrow
     * @param _rateMode the borrow rate mode (stable, variable)
     *
     */
    function _updateUserStateOnBorrow(
        address _reserve,
        address _user,
        uint256 _amountBorrowed,
        uint256 _balanceIncrease,
        uint256 _fee,
        CoreLibrary.InterestRateMode _rateMode
    ) internal {
        // Load the reserve and user
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];
        CoreLibrary.UserReserveData storage user = s_usersReserveData[_user][_reserve];

        if (_rateMode == CoreLibrary.InterestRateMode.STABLE) {
            // Stable mode:
            // - the current reserve stable rate is stored in the user's position
            user.stableBorrowRate = reserve.currentStableBorrowRate;

            // - the variable borrow index is reset
            user.lastVariableBorrowCumulativeIndex = 0;
        } else if (_rateMode == CoreLibrary.InterestRateMode.VARIABLE) {
            // variable mode
            // - the stable rate is reset
            user.stableBorrowRate = 0;
            // -the current variable borrow index is stored as the user's starting index
            user.lastVariableBorrowCumulativeIndex = reserve.lastVariableBorrowCumulativeIndex;
        } else {
            revert LendingPoolCore__InvalidBorrowRateMode();
        }

        // Update the principal
        // New principal = previous principal + accrued interest + newly borrowed amount
        user.principalBorrowBalance += _amountBorrowed + _balanceIncrease;

        // Update the origination fee
        // TODO what is origination fee? Explain it in the docs
        user.originationFee += _fee;

        // Update the timestamp
        user.lastUpdateTimestamp = uint40(block.timestamp);
    }

    /////////////////////////////////
    //       Private Functions     //
    /////////////////////////////////
    //////////////////////////////////////////////////////
    //     Private & Internal View & Pure Functions     //
    //////////////////////////////////////////////////////
    /**
     * @dev gets the current borrow rate of the user
     * @param _reserve the address of the reserve for which the information is needed
     * @param _user the address of the user for which the information is needed
     * @return the borrow rate for the user,
     *
     */
    function _getUserCurrentBorrowRate(address _reserve, address _user) internal view returns (uint256) {
        // Read the user's rate mode (NONE, STABLE, VARIABLE)
        CoreLibrary.InterestRateMode rateMode = getUserCurrentBorrowRateMode(_reserve, _user);

        // No debt
        if (rateMode == CoreLibrary.InterestRateMode.NONE) {
            return 0;
        }

        return rateMode == CoreLibrary.InterestRateMode.STABLE
            ? s_usersReserveData[_user][_reserve].stableBorrowRate
            : s_reserves[_reserve].currentVariableBorrowRate;
    }

    //////////////////////////////////////////////////////
    //      External & Public View & Pure Functions     //
    //////////////////////////////////////////////////////
    /**
     * @dev gets the aToken contract address for the reserve
     * @param _reserve the reserve address
     * @return the address of the aToken contract
     *
     */
    function getReserveATokenAddress(address _reserve) public view returns (address) {
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];
        return reserve.aTokenAddress;
    }

    /**
     * @dev gets the available liquidity in the reserve. The available liquidity is the balance of the core contract
     * @param _reserve the reserve address
     * @return the available liquidity
     *
     */
    function getReserveAvailableLiquidity(address _reserve) public view returns (uint256) {
        uint256 balance = 0;

        if (_reserve == EthAddressLib.ethAddress()) {
            balance = address(this).balance;
        } else {
            balance = IERC20(_reserve).balanceOf(address(this));
        }
        return balance;
    }

    /**
     * @dev gets the normalized income of the reserve. a value of 1e27 means there is no income. A value of 2e27 means there
     * there has been 100% income.
     * @param _reserve the reserve address
     * @return the reserve normalized income
     *
     */
    function getReserveNormalizedIncome(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];
        return reserve.getNormalizedIncome();
    }

    /**
     * @dev gets the reserve total borrows
     * @param _reserve the reserve address
     * @return the total borrows (stable + variable)
     *
     */
    function getReserveTotalBorrows(address _reserve) public view returns (uint256) {
        return s_reserves[_reserve].getTotalBorrows();
    }

    /**
     * @dev returns the list of initialized reserves
     * @return the list of reserve addresses
     */
    function getReserves() external view returns (address[] memory) {
        return s_reservesList;
    }

    /**
     * @dev returns the basic data (balances, fee accrued, reserve enabled/disabled as collateral)
     * needed to calculate the global account data in the LendingPoolDataProvider
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     * @return the user deposited balance, the current compounded borrow balance, the fee, and if the reserve is enabled as collateral or not
     */
    function getUserBasicReserveData(address _reserve, address _user)
        external
        view
        returns (uint256, uint256, uint256, bool)
    {
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];
        CoreLibrary.UserReserveData storage user = s_usersReserveData[_user][_reserve];

        uint256 underlyingBalance = getUserUnderlyingAssetBalance(_reserve, _user);

        if (user.principalBorrowBalance == 0) {
            return (underlyingBalance, 0, 0, user.useAsCollateral);
        }

        return (underlyingBalance, user.getCompoundedBorrowBalance(reserve), user.originationFee, user.useAsCollateral);
    }

    /**
     * @dev gets the underlying asset balance of a user based on the corresponding aToken balance.
     * @param _reserve the reserve address
     * @param _user the user address
     * @return the underlying deposit balance of the user
     *
     */
    function getUserUnderlyingAssetBalance(address _reserve, address _user) public view returns (uint256) {
        AToken aToken = AToken(s_reserves[_reserve].aTokenAddress);
        return aToken.balanceOf(_user);
    }

    /**
     * @dev returns true if the reserve is active
     * @param _reserve the reserve address
     * @return true if the reserve is active, false otherwise
     *
     */
    function getReserveIsActive(address _reserve) external view returns (bool) {
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];
        return reserve.isActive;
    }

    /**
     * @notice returns if a reserve is freezed
     * @param _reserve the reserve for which the information is needed
     * @return true if the reserve is freezed, false otherwise
     *
     */

    function getReserveIsFreezed(address _reserve) external view returns (bool) {
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];
        return reserve.isFreezed;
    }

    /**
     * @dev this function aggregates the configuration parameters of the reserve.
     * It's used in the LendingPoolDataProvider specifically to save gas, and avoid
     * multiple external contract calls to fetch the same data.
     * @param _reserve the reserve address
     * @return the reserve decimals
     * @return the base ltv as collateral
     * @return the liquidation threshold
     * @return if the reserve is used as collateral or not
     *
     */
    function getReserveConfiguration(address _reserve) external view returns (uint256, uint256, uint256, bool) {
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];

        return
            (
                reserve.decimals,
                reserve.baseLTVasCollateral,
                reserve.liquidationThreshold,
                reserve.usageAsCollateralEnabled
            );
    }

    /**
     * @param _reserve the address of the reserve for which the information is needed
     * @param _user the address of the user for which the information is needed
     * @return true if the user has chosen to use the reserve as collateral, false otherwise
     */
    function isUserUseReserveAsCollateralEnabled(address _reserve, address _user) external view returns (bool) {
        CoreLibrary.UserReserveData storage user = s_usersReserveData[_user][_reserve];
        return user.useAsCollateral;
    }

    /**
     * @dev returns true if the reserve is enabled for borrowing
     * @param _reserve the reserve address
     * @return true if the reserve is enabled for borrowing, false otherwise
     *
     */
    function isReserveBorrowingEnabled(address _reserve) external view returns (bool) {
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];
        return reserve.borrowingEnabled;
    }

    /**
     * @dev returns the decimals of the reserve
     * @param _reserve the reserve address
     * @return the reserve decimals
     *
     */
    function getReserveDecimals(address _reserve) external view returns (uint256) {
        return s_reserves[_reserve].decimals;
    }

    /**
     * @dev calculates and returns the borrow balances of the user
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     * @return the principal borrow balance, the compounded balance and the balance increase since the last borrow/repay/swap/rebalance
     *
     */
    function getUserBorrowBalances(address _reserve, address _user) public view returns (uint256, uint256, uint256) {
        // Read user's reserve data
        CoreLibrary.UserReserveData storage user = s_usersReserveData[_user][_reserve];

        // Read the stored principal
        // The principal is the debt stored during the user's last borro-related action.
        // It includes interest that had already been materialized during previous actions, but not
        // interest accrued since the last update
        uint256 principal = user.principalBorrowBalance;

        // Handles users without debt
        if (principal == 0) {
            return (0, 0, 0);
        }

        // Calculate the current debt
        // current debt = stored principal + accrued interest
        // This is a view calculation, it doesn't updated storage
        uint256 compoundedBalance = CoreLibrary.getCompoundedBorrowBalance(user, s_reserves[_reserve]);

        // Calculate the balance increase = compoundedBalance - principal

        // Example
        // principal: 1,000 DAI
        // compounded balance: 1,020 DAI
        // balance increase: 20 DAI
        return (principal, compoundedBalance, compoundedBalance - principal);
    }

    /**
     * @notice Returns the user's current borrow rate mode for a reserve.
     * @dev Returns `NONE` if the user has no debt, `STABLE` if the user
     * has a stable borrow rate, and `VARIABLE` otherwise.
     * @param _reserve The address of the borrowed reserve.
     * @param _user The address of the borrower.
     * @return rateMode The user's current borrow rate mode.
     */
    function getUserCurrentBorrowRateMode(address _reserve, address _user)
        public
        view
        returns (CoreLibrary.InterestRateMode)
    {
        CoreLibrary.UserReserveData storage user = s_usersReserveData[_user][_reserve];

        if (user.principalBorrowBalance == 0) {
            return CoreLibrary.InterestRateMode.NONE;
        }

        return user.stableBorrowRate > 0 ? CoreLibrary.InterestRateMode.STABLE : CoreLibrary.InterestRateMode.VARIABLE;
    }

    /**
     * @dev checks if a user is allowed to borrow at a stable rate
     * @param _reserve the reserve address
     * @param _user the user
     * @param _amount the amount the the user wants to borrow
     * @return true if the user is allowed to borrow at a stable rate, false otherwise
     *
     */
    function isUserAllowedToBorrowAtStable(address _reserve, address _user, uint256 _amount)
        external
        view
        returns (bool)
    {
        CoreLibrary.ReserveData storage reserve = s_reserves[_reserve];
        CoreLibrary.UserReserveData storage user = s_usersReserveData[_user][_reserve];

        // Stable borrowing must be enabled
        if (!reserve.isStableBorrowRateEnabled) {
            return false;
        }

        // Borrowing is allowed if:
        // 1. The user is not using this reserve as collateral
        // 2. The reserve cannot be used as collateral
        // 3. The amount being borrowed is greater than the user's balance of the same asset.

        // Stable borrowing is rejected only when all three are true:
        // - The user uses the reserve as collateral.
        // - The reserve is enabled as collateral
        // - The requested borrow is less than or equal to the user's balance of that asser

        // Example
        // Alice deposited 1,000 DAI and enabled is as collateral
        // If she attempts to borrow 500 DAI at a stable rate:
        // 500 DAI <= 1,000 DAI
        // The function returns false because Alice would be borrowing the same asset that she is using as collateral.
        // If Alice instead borrows another asset, such as USDC, her DAI deposit is irrelevant to this specific check.
        return !user.useAsCollateral || !reserve.usageAsCollateralEnabled
            || _amount > getUserUnderlyingAssetBalance(_reserve, _user);
    }
}
