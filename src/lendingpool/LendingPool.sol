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

import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {AToken} from "src/tokenization/AToken.sol";
import {LendingPoolCore} from "./LendingPoolCore.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolDataProvider} from "./LendingPoolDataProvider.sol";
import {IFeeProvider} from "src/interfaces/IFeeProvider.sol";
import {LendingPoolParametersProvider} from "src/configuration/LendingPoolParametersProvider.sol";
import {CoreLibrary} from "src/libraries/CoreLibrary.sol";
import {EthAddressLib} from "src/libraries/EthAddressLib.sol";

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
    error LendingPool__ATokenOnly();
    error LendingPool__InsufficientLiquidityToRedeem();
    error LendingPool__ReserveNotEnabledForBorrowing();
    error LendingPool__InvalidInterestRateMode();
    error LendingPool__NotEnoughLiquidityInTheReserve();
    error LendingPool__CollateralBalanceIsZero();
    error LendingPool__HealthFactorBelowThreshold();
    error LendingPool__TooSmallAmountToBorrow();
    error LendingPool__InsufficientCollateralToCoverNewBorrow();
    error LendingPool__UserCannotBorrowAmountAtStableRate();
    error LendingPool__UserIsBorrowingTooMuchLiquidityAtStableRate();
    error LendingPool__NoBorrowPending();
    error LendingPool__ExplicitAmountRequiredForRepayOnBehalf();
    error LendingPool__InvalidETHRepaymentAmount();

    //////////////////////////////////
    //      Type declarations       //
    //////////////////////////////////
    /**
     * @dev data structures for local computations in the borrow() method.
     */
    struct BorrowLocalVars {
        uint256 principalBorrowBalance;
        uint256 currentLtv;
        uint256 currentLiquidationThreshold;
        uint256 borrowFee;
        uint256 requestedBorrowAmountETH;
        uint256 amountOfCollateralNeededETH;
        uint256 userCollateralBalanceETH;
        uint256 userBorrowBalanceETH;
        uint256 userTotalFeesETH;
        uint256 borrowBalanceIncrease;
        uint256 currentReserveStableRate;
        uint256 availableLiquidity;
        uint256 reserveDecimals;
        uint256 finalUserBorrowRate;
        CoreLibrary.InterestRateMode rateMode;
        bool healthFactorBelowThreshold;
    }

    /**
     * @dev data structures for local computations in the repay() method.
     */
    struct RepayLocalVars {
        uint256 principalBorrowBalance;
        uint256 compoundedBorrowBalance;
        uint256 borrowBalanceIncrease;
        bool isETH;
        uint256 paybackAmount;
        uint256 paybackAmountMinusFees;
        uint256 currentStableRate;
        uint256 originationFee;
    }

    ////////////////////////////////
    //      State Variables       //
    ////////////////////////////////
    LendingPoolCore private immutable i_core;
    LendingPoolAddressesProvider private immutable i_addressesProvider;
    LendingPoolDataProvider private immutable i_dataProvider;
    IFeeProvider private immutable i_feeProvider;
    LendingPoolParametersProvider private immutable i_parametersProvider;

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

    /**
     * @dev emitted during a redeem action.
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     * @param _amount the amount to be deposited
     * @param _timestamp the timestamp of the action
     *
     */
    event RedeemUnderlying(address indexed _reserve, address indexed _user, uint256 _amount, uint256 _timestamp);

    /**
     * @dev emitted on borrow
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     * @param _amount the amount to be deposited
     * @param _borrowRateMode the rate mode, can be either 1-stable or 2-variable
     * @param _borrowRate the rate at which the user has borrowed
     * @param _originationFee the origination fee to be paid by the user
     * @param _borrowBalanceIncrease the balance increase since the last borrow, 0 if it's the first time borrowing
     * @param _referral the referral number of the action
     * @param _timestamp the timestamp of the action
     *
     */
    event Borrow(
        address indexed _reserve,
        address indexed _user,
        uint256 _amount,
        uint256 _borrowRateMode,
        uint256 _borrowRate,
        uint256 _originationFee,
        uint256 _borrowBalanceIncrease,
        uint16 indexed _referral,
        uint256 _timestamp
    );

    /**
     * @dev emitted on repay
     * @param _reserve the address of the reserve
     * @param _user the address of the user for which the repay has been executed
     * @param _repayer the address of the user that has performed the repay action
     * @param _amountMinusFees the amount repaid minus fees
     * @param _fees the fees repaid
     * @param _borrowBalanceIncrease the balance increase since the last action
     * @param _timestamp the timestamp of the action
     *
     */
    event Repay(
        address indexed _reserve,
        address indexed _user,
        address indexed _repayer,
        uint256 _amountMinusFees,
        uint256 _fees,
        uint256 _borrowBalanceIncrease,
        uint256 _timestamp
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

    /**
     * @dev functions affected by this modifier can only be invoked by the
     * aToken.sol contract
     * @param _reserve the address of the reserve
     *
     */
    modifier onlyOverlyingAToken(address _reserve) {
        if (msg.sender != i_core.getReserveATokenAddress(_reserve)) {
            revert LendingPool__ATokenOnly();
        }
        _;
    }

    ////////////////////////////////
    //          Functions         //
    ////////////////////////////////
    constructor(address _addressesProvider) {
        if (_addressesProvider == address(0)) {
            revert LendingPool__ZeroAddress();
        }
        i_addressesProvider = LendingPoolAddressesProvider(_addressesProvider);

        address coreAddress = i_addressesProvider.getLendingPoolCore();
        address dataProviderAddress = i_addressesProvider.getLendingPoolDataProvider();
        address feeProviderAddress = i_addressesProvider.getFeeProvider();
        address parametersProviderAddress = i_addressesProvider.getLendingPoolParametersProvider();

        if (
            coreAddress == address(0) || dataProviderAddress == address(0) || feeProviderAddress == address(0)
                || parametersProviderAddress == address(0)
        ) {
            revert LendingPool__ZeroAddress();
        }

        i_core = LendingPoolCore(coreAddress);
        i_dataProvider = LendingPoolDataProvider(dataProviderAddress);
        i_feeProvider = IFeeProvider(feeProviderAddress);
        i_parametersProvider = LendingPoolParametersProvider(parametersProviderAddress);
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
        // Get the aToken contract associated with the underlying reserve
        AToken aToken = AToken(i_core.getReserveATokenAddress(_reserve));

        // Check if this is the user's first deposit for this reserve
        bool isFirstDeposit = aToken.balanceOf(msg.sender) == 0;

        // Update reserve and user state before minting:
        // 1. updates cumulative indexes
        // 2. updates reserve interest rates after new liquidity enters
        // 3. enables the reserve as collateral if this is the user's first deposit
        i_core.updateStateOnDeposit(_reserve, msg.sender, _amount, isFirstDeposit);

        // Minting AToken to user 1:1 with the specific exchange rate
        aToken.mintOnDeposit(msg.sender, _amount);

        // Transfer funds (ETH or ERC20) to the core contract
        i_core.transferToReserve{value: msg.value}(_reserve, payable(msg.sender), _amount);

        emit Deposit(_reserve, msg.sender, _amount, _referralCode, block.timestamp);
    }

    /**
     * @dev Redeems the underlying amount of assets requested by _user.
     * This function is executed by the overlying aToken contract in response to a redeem action.
     * @param _reserve the address of the reserve
     * @param _user the address of the user performing the action
     * @param _amount the underlying amount to be redeemed
     *
     */
    function redeemUnderlying(
        address _reserve,
        address payable _user,
        uint256 _amount,
        uint256 _aTokenBalanceAfterRedeem
    )
        external
        nonReentrant
        onlyOverlyingAToken(_reserve)
        onlyActiveReserve(_reserve)
        onlyAmountGreaterThanZero(_amount)
    {
        // Check available liquidity,
        // if the user wants to redeem more liquidity then available revert
        uint256 currentAvailableLiquidity = i_core.getReserveAvailableLiquidity(_reserve);
        if (currentAvailableLiquidity < _amount) {
            revert LendingPool__InsufficientLiquidityToRedeem();
        }

        // Update reserve state:
        // 1. updates cumulative indexes
        // 2. updates reserve interest rates after liquidity leaves
        // 3. disables collateral usage if the user redeemed everything
        i_core.updateStateOnRedeem(_reserve, _user, _amount, _aTokenBalanceAfterRedeem == 0);

        // Transfer underlying asset to the user
        i_core.transferToUser(_reserve, _user, _amount);

        emit RedeemUnderlying(_reserve, _user, _amount, block.timestamp);
    }

    /**
     * @dev Allows users to borrow a specific amount of the reserve currency, provided that the borrowe
     * already deposited enough collateral.
     * @param _reserve the address of the reserve
     * @param _amount the amount to be borrowed
     * @param _interestRateMode the interest rate mode at which the user wants to borrow. Can be 1 (STABLE), 2 (VARIABLE)
     */
    function borrow(address _reserve, uint256 _amount, uint256 _interestRateMode, uint16 _referralCode)
        external
        nonReentrant
        onlyActiveReserve(_reserve)
        onlyUnfreezedReserve(_reserve)
        onlyAmountGreaterThanZero(_amount)
    {
        // Usage of a memory struct of vars to avoid "Stack too deep" errors due to local variables
        BorrowLocalVars memory vars;

        // Check that the reserve is enabled for borrowing
        if (!i_core.isReserveBorrowingEnabled(_reserve)) {
            revert LendingPool__ReserveNotEnabledForBorrowing();
        }

        // Validate the rate mode
        if (
            _interestRateMode != uint256(CoreLibrary.InterestRateMode.VARIABLE)
                && _interestRateMode != uint256(CoreLibrary.InterestRateMode.STABLE)
        ) {
            revert LendingPool__InvalidInterestRateMode();
        }

        // Cast the rateMode to Corelibrary.interestRateMode
        vars.rateMode = CoreLibrary.InterestRateMode(_interestRateMode);

        // Check that the amount is available in the reserve
        vars.availableLiquidity = i_core.getReserveAvailableLiquidity(_reserve);

        // A user cannot borrow more tokens than the reserve currently has available.
        if (vars.availableLiquidity < _amount) {
            revert LendingPool__NotEnoughLiquidityInTheReserve();
        }

        // Read the user’s global position
        (
            ,
            vars.userCollateralBalanceETH,
            vars.userBorrowBalanceETH,
            vars.userTotalFeesETH,
            vars.currentLtv,
            vars.currentLiquidationThreshold,,
            vars.healthFactorBelowThreshold
        ) = i_dataProvider.calculateUserGlobalData(msg.sender);

        // Check that collateral is not zero
        if (vars.userCollateralBalanceETH == 0) {
            revert LendingPool__CollateralBalanceIsZero();
        }

        // Check that the position is healthy
        if (vars.healthFactorBelowThreshold) {
            revert LendingPool__HealthFactorBelowThreshold();
        }

        // Calculate the origination fee
        vars.borrowFee = i_feeProvider.calculateLoanOriginationFee(msg.sender, _amount);
        // If the calculated fee rounds down to zero, the requested borrow is considered too small
        if (vars.borrowFee == 0) {
            revert LendingPool__TooSmallAmountToBorrow();
        }

        // Calculate the required collateral
        vars.amountOfCollateralNeededETH = i_dataProvider.calculateCollateralNeededInETH(
            _reserve, _amount, vars.borrowFee, vars.userBorrowBalanceETH, vars.userTotalFeesETH, vars.currentLtv
        );

        // If the user collateral doesn't cover the amount of collateral needed revert
        if (vars.amountOfCollateralNeededETH > vars.userCollateralBalanceETH) {
            revert LendingPool__InsufficientCollateralToCoverNewBorrow();
        }

        /**
         * Following conditions need to be met if the user is borrowing at a stable rate:
         * 1. Reserve must be enabled for stable rate borrowing
         * 2. Users cannot borrow from the reserve if their collateral is (mostly) the same currency
         *    they are borrowing, to prevent abuses.
         * 3. Users will be able to borrow only a relatively small, configurable amount of the total
         *    liquidity
         *
         */
        if (vars.rateMode == CoreLibrary.InterestRateMode.STABLE) {
            // Verifies that:
            // - stable borrowing is enabled for the reserve
            // - the user is not borrowing the same asset they are using as collateral
            if (!i_core.isUserAllowedToBorrowAtStable(_reserve, msg.sender, _amount)) {
                revert LendingPool__UserCannotBorrowAmountAtStableRate();
            }

            // Calculate the max available loan size in stable rate mode as a percentage of the
            // available liquidity

            // A stable-rate loan can consume only a configured percentage of the reserve’s available liquidity.
            //
            // Example
            // available liquidity = 1,000 tokens
            // maximum percentage = 25%
            // maximum stable borrow = 250 tokens
            uint256 maxLoanPercent = i_parametersProvider.getMaxStableRateBorrowSizePercent();
            uint256 maxLoanSizeStable = vars.availableLiquidity * maxLoanPercent / 100;

            if (_amount > maxLoanSizeStable) {
                revert LendingPool__UserIsBorrowingTooMuchLiquidityAtStableRate();
            }
        }

        // All conditions passed - borrow is accepted
        // Update the the accounting or protocol state on LendingPoolCore
        (vars.finalUserBorrowRate, vars.borrowBalanceIncrease) =
            i_core.updateStateOnBorrow(_reserve, msg.sender, _amount, vars.borrowFee, vars.rateMode);

        // Transfer the borrowed asset.
        // LendingPoolCore sends the underlying ERC20 token or ETH to the borrower
        i_core.transferToUser(_reserve, payable(msg.sender), _amount);

        emit Borrow(
            _reserve,
            msg.sender,
            _amount,
            _interestRateMode,
            vars.finalUserBorrowRate,
            vars.borrowFee,
            vars.borrowBalanceIncrease,
            _referralCode,
            block.timestamp
        );
    }

    /**
     * @notice repays a borrow on the specific reserve, for the specified amount (or for the whole amount, if uint256(-1) is specified).
     * @dev the target user is defined by _onBehalfOf. If there is no repayment on behalf of another account,
     * _onBehalfOf must be equal to msg.sender.
     * @param _reserve the address of the reserve on which the user borrowed
     * @param _amount the amount to repay, or type(uint256).max if the user wants to repay everything
     * @param _onBehalfOf the address for which msg.sender is repaying.
     *
     */
    function repay(address _reserve, uint256 _amount, address payable _onBehalfOf)
        external
        payable
        nonReentrant
        onlyActiveReserve(_reserve)
        onlyAmountGreaterThanZero(_amount)
    {
        // Stores intermediate values in memory and avoids "stack too deep".
        RepayLocalVars memory vars;

        // Get the borrower's current debt position:
        // - principalBorrowBalance: debt before newly accrued interest
        // - compoundedBorrowbalance: total debt including accrued interest
        // - borrowBalanceIncrease: interest accrued since the last update
        (vars.principalBorrowBalance, vars.compoundedBorrowBalance, vars.borrowBalanceIncrease) =
            i_core.getUserBorrowBalances(_reserve, _onBehalfOf);

        // Get the protocol fee still owed by the borrower.
        vars.originationFee = i_core.getUserOriginationFee(_reserve, _onBehalfOf);

        // ETH repayments use msg.value; ERC-20 repayments use transferFrom.
        vars.isETH = EthAddressLib.ethAddress() == _reserve;

        // A user cannot repay if they have no outstanding debt
        if (vars.compoundedBorrowBalance == 0) {
            revert LendingPool__NoBorrowPending();
        }

        // type(uint256).max means "repay everything".
        // This shortcut is allowed only when repaying your own loan.
        // A third party must choose an explicit amount.
        if (_amount == type(uint256).max && msg.sender != _onBehalfOf) {
            revert LendingPool__ExplicitAmountRequiredForRepayOnBehalf();
        }

        // By default, repay the entire debt plus the outstanding origination fee.
        vars.paybackAmount = vars.compoundedBorrowBalance + vars.originationFee;

        // For a partial repayment, use the requested amount if it is lower
        // than the total amount owed
        if (_amount != type(uint256).max && _amount < vars.paybackAmount) {
            vars.paybackAmount = _amount;
        }

        // ETH repayments must incude enough native ETH in the transaction
        if (vars.isETH && msg.value < vars.paybackAmount) {
            revert LendingPool__InvalidETHRepaymentAmount();
        }

        // The origination fee has priority over loan repayment.
        // If the amount is not enough to cover the fee, no debt is repaid.
        if (vars.paybackAmount <= vars.originationFee) {
            // Reduce only the outstanding fee. The debt amount stays unchanged.
            i_core.updateStateOnRepay(_reserve, _onBehalfOf, 0, vars.paybackAmount, vars.borrowBalanceIncrease, false);

            // Send the paid fee to the protocol fee collector.
            i_core.transferToFeeCollectionAddress{value: vars.isETH ? vars.paybackAmount : 0}(
                _reserve, _onBehalfOf, vars.paybackAmount, i_addressesProvider.getTokenDistributor()
            );

            emit Repay(
                _reserve, _onBehalfOf, msg.sender, 0, vars.paybackAmount, vars.borrowBalanceIncrease, block.timestamp
            );

            return;
        }

        // At this point, the fee is fully covered.
        // The remaining amount is used to reduce the borrower's debt.
        vars.paybackAmountMinusFees = vars.paybackAmount - vars.originationFee;

        // Update the borrower's debt, reserve borrow totals, and interest rates.
        // The final bool is true only when all compounded debt was repaid.
        i_core.updateStateOnRepay(
            _reserve,
            _onBehalfOf,
            vars.paybackAmountMinusFees,
            vars.originationFee,
            vars.borrowBalanceIncrease,
            vars.compoundedBorrowBalance == vars.paybackAmountMinusFees
        );

        // Send the paid fee to the protocol fee collector.
        if (vars.originationFee > 0) {
            i_core.transferToFeeCollectionAddress{value: vars.isETH ? vars.originationFee : 0}(
                _reserve, msg.sender, vars.originationFee, i_addressesProvider.getTokenDistributor()
            );
        }

        // Transfer the debt-repayment portion back to the reserve.
        // For ETH, transferToReserve refunds any msg.value sent in excess.
        // For ERC-20 tokens, the payer must have approved LendingPoolCore.
        i_core.transferToReserve{value: vars.isETH ? msg.value - vars.originationFee : 0}(
            _reserve, payable(msg.sender), vars.paybackAmountMinusFees
        );

        emit Repay(
            _reserve,
            _onBehalfOf,
            msg.sender,
            vars.paybackAmountMinusFees,
            vars.originationFee,
            vars.borrowBalanceIncrease,
            block.timestamp
        );
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
