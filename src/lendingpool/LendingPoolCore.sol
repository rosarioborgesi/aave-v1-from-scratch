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

//import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

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
    error LendingPoolCore__OnlyLendingPool();
    error LendingPoolCore__CantSendEthAndTransferErc20();
    error LendingPoolCore__MsgValueLessThanAmount();
    error LendingPoolCore__EthTransferFailed(address _to, uint256 _amount);
    error LendingPoolCore__OnlyLendingPoolConfigurator();
    error LendingPoolCore__ReserveListIsEmpty();
    error LendingPoolCore__ReserveToRemoveIsNotLastReserve();
    error LendingPoolCore__ReserveHasBorrows();

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
    LendingPoolAddressesProvider private i_addressesProvider;
    address private i_lendingPoolAddress;

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
        i_addressesProvider = LendingPoolAddressesProvider(_addressesProvider);
        i_lendingPoolAddress = i_addressesProvider.getLendingPool();
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
            if (msg.value != 0) {
                revert LendingPoolCore__CantSendEthAndTransferErc20();
            }
            IERC20(_reserve).safeTransferFrom(_user, address(this), _amount);
        } else {
            if (msg.value < _amount) {
                revert LendingPoolCore__MsgValueLessThanAmount();
            }

            if (msg.value > _amount) {
                // Send back excess ETH
                uint256 excessAmount = msg.value - _amount;
                (bool result,) = _user.call{value: excessAmount}("");
                if (!result) {
                    revert LendingPoolCore__EthTransferFailed(_user, excessAmount);
                }
            }
        }
    }

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
        s_reserves[lastReserve].isActive = false;
        s_reserves[lastReserve].aTokenAddress = address(0);
        s_reserves[lastReserve].decimals = 0;
        s_reserves[lastReserve].lastLiquidityCumulativeIndex = 0;
        s_reserves[lastReserve].lastVariableBorrowCumulativeIndex = 0;
        s_reserves[lastReserve].borrowingEnabled = false;
        s_reserves[lastReserve].usageAsCollateralEnabled = false;
        s_reserves[lastReserve].baseLTVasCollateral = 0;
        s_reserves[lastReserve].liquidationThreshold = 0;
        s_reserves[lastReserve].liquidationBonus = 0;
        s_reserves[lastReserve].interestRateStrategyAddress = address(0);

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

    /////////////////////////////////
    //       Private Functions     //
    /////////////////////////////////
    //////////////////////////////////////////////////////
    //     Private & Internal View & Pure Functions     //
    //////////////////////////////////////////////////////
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
}
