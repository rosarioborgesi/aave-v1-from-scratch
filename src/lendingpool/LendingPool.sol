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
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {AToken} from "src/tokenization/AToken.sol";
import {LendingPoolCore} from "./LendingPoolCore.sol";
import {LendingPoolAddressesProvider} from "src/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolDataProvider} from "./LendingPoolDataProvider.sol";
import {IFeeProvider} from "src/interfaces/IFeeProvider.sol";
import {LendingPoolParametersProvider} from "src/configuration/LendingPoolParametersProvider.sol";
import {CoreLibrary} from "src/libraries/CoreLibrary.sol";
import {EthAddressLib} from "src/libraries/EthAddressLib.sol";
import {ILiquidationManager} from "src/interfaces/ILiquidationManager.sol";
import {IFlashLoanReceiver} from "src/flashloan/interfaces/IFlashLoanReceiver.sol";
import {WadRayMath} from "src/libraries/WadRayMath.sol";

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
    error LendingPool__LiquidationCallFailed();
    error LendingPool__LiquidationFailed(string reason);
    error LendingPool__NoBorrowInProgress();
    error LendingPool__UserCannotBorrowAtStable();
    error LendingPool__InsufficientLiquidityToBorrow();
    error LendingPool__InsufficientAmountForFlashLoan();
    error LendingPool__InconsistentProtocolBalance();
    error LendingPool__NoBorrowForReserve();
    error LendingPool__BorrowRateModeIsNotStable();
    error LendingPool__InterestRateRebalanceConditionsNotMet();
    error LendingPool__NoLiquidityDeposited();
    error DepositAlreadyUseadAsCollateral();

    using WadRayMath for uint256;

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
    LendingPoolAddressesProvider private s_addressesProvider;
    LendingPoolCore private s_core;
    LendingPoolDataProvider private s_dataProvider;
    LendingPoolParametersProvider private s_parametersProvider;
    IFeeProvider private s_feeProvider;

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

    /**
     * @dev emitted when a user performs a rate swap
     * @param _reserve the address of the reserve
     * @param _user the address of the user executing the swap
     * @param _newRateMode the new interest rate mode
     * @param _newRate the new borrow rate
     * @param _borrowBalanceIncrease the balance increase since the last action
     * @param _timestamp the timestamp of the action
     *
     */
    event Swap(
        address indexed _reserve,
        address indexed _user,
        uint256 _newRateMode,
        uint256 _newRate,
        uint256 _borrowBalanceIncrease,
        uint256 _timestamp
    );

    /**
     * @dev emitted when the stable rate of a user gets rebalanced
     * @param _reserve the address of the reserve
     * @param _user the address of the user for which the rebalance has been executed
     * @param _newStableRate the new stable borrow rate after the rebalance
     * @param _borrowBalanceIncrease the balance increase since the last action
     * @param _timestamp the timestamp of the action
     *
     */
    event RebalanceStableBorrowRate(
        address indexed _reserve,
        address indexed _user,
        uint256 _newStableRate,
        uint256 _borrowBalanceIncrease,
        uint256 _timestamp
    );

    /**
     * @dev emitted when a flashloan is executed
     * @param _target the address of the flashLoanReceiver
     * @param _reserve the address of the reserve
     * @param _amount the amount requested
     * @param _totalFee the total fee on the amount
     * @param _protocolFee the part of the fee for the protocol
     * @param _timestamp the timestamp of the action
     *
     */
    event FlashLoan(
        address indexed _target,
        address indexed _reserve,
        uint256 _amount,
        uint256 _totalFee,
        uint256 _protocolFee,
        uint256 _timestamp
    );

    /**
     * @dev emitted when a user enables a reserve as collateral
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     *
     */
    event ReserveUsedAsCollateralEnabled(address indexed _reserve, address indexed _user);

    /**
     * @dev emitted when a user disables a reserve as collateral
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     *
     */
    event ReserveUsedAsCollateralDisabled(address indexed _reserve, address indexed _user);

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
        if (!s_core.getReserveIsActive(_reserve)) {
            revert LendingPool__ReserveIsNotActive();
        }
        _;
    }

    modifier onlyUnfreezedReserve(address _reserve) {
        if (s_core.getReserveIsFreezed(_reserve)) {
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
        if (msg.sender != s_core.getReserveATokenAddress(_reserve)) {
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
        s_addressesProvider = LendingPoolAddressesProvider(_addressesProvider);

        address coreAddress = s_addressesProvider.getLendingPoolCore();
        address dataProviderAddress = s_addressesProvider.getLendingPoolDataProvider();
        address feeProviderAddress = s_addressesProvider.getFeeProvider();
        address parametersProviderAddress = s_addressesProvider.getLendingPoolParametersProvider();

        if (
            coreAddress == address(0) || dataProviderAddress == address(0) || feeProviderAddress == address(0)
                || parametersProviderAddress == address(0)
        ) {
            revert LendingPool__ZeroAddress();
        }

        s_core = LendingPoolCore(coreAddress);
        s_dataProvider = LendingPoolDataProvider(dataProviderAddress);
        s_feeProvider = IFeeProvider(feeProviderAddress);
        s_parametersProvider = LendingPoolParametersProvider(parametersProviderAddress);
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
        AToken aToken = AToken(s_core.getReserveATokenAddress(_reserve));

        // Check if this is the user's first deposit for this reserve
        bool isFirstDeposit = aToken.balanceOf(msg.sender) == 0;

        // Update reserve and user state before minting:
        // 1. updates cumulative indexes
        // 2. updates reserve interest rates after new liquidity enters
        // 3. enables the reserve as collateral if this is the user's first deposit
        s_core.updateStateOnDeposit(_reserve, msg.sender, _amount, isFirstDeposit);

        // Minting AToken to user 1:1 with the specific exchange rate
        aToken.mintOnDeposit(msg.sender, _amount);

        // Transfer funds (ETH or ERC20) to the core contract
        s_core.transferToReserve{value: msg.value}(_reserve, payable(msg.sender), _amount);

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
        uint256 currentAvailableLiquidity = s_core.getReserveAvailableLiquidity(_reserve);
        if (currentAvailableLiquidity < _amount) {
            revert LendingPool__InsufficientLiquidityToRedeem();
        }

        // Update reserve state:
        // 1. updates cumulative indexes
        // 2. updates reserve interest rates after liquidity leaves
        // 3. disables collateral usage if the user redeemed everything
        s_core.updateStateOnRedeem(_reserve, _user, _amount, _aTokenBalanceAfterRedeem == 0);

        // Transfer underlying asset to the user
        s_core.transferToUser(_reserve, _user, _amount);

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
        if (!s_core.isReserveBorrowingEnabled(_reserve)) {
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
        vars.availableLiquidity = s_core.getReserveAvailableLiquidity(_reserve);

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
        ) = s_dataProvider.calculateUserGlobalData(msg.sender);

        // Check that collateral is not zero
        if (vars.userCollateralBalanceETH == 0) {
            revert LendingPool__CollateralBalanceIsZero();
        }

        // Check that the position is healthy
        if (vars.healthFactorBelowThreshold) {
            revert LendingPool__HealthFactorBelowThreshold();
        }

        // Calculate the origination fee
        vars.borrowFee = s_feeProvider.calculateLoanOriginationFee(msg.sender, _amount);
        // If the calculated fee rounds down to zero, the requested borrow is considered too small
        if (vars.borrowFee == 0) {
            revert LendingPool__TooSmallAmountToBorrow();
        }

        // Calculate the required collateral
        vars.amountOfCollateralNeededETH = s_dataProvider.calculateCollateralNeededInETH(
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
            if (!s_core.isUserAllowedToBorrowAtStable(_reserve, msg.sender, _amount)) {
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
            uint256 maxLoanPercent = s_parametersProvider.getMaxStableRateBorrowSizePercent();
            uint256 maxLoanSizeStable = vars.availableLiquidity * maxLoanPercent / 100;

            if (_amount > maxLoanSizeStable) {
                revert LendingPool__UserIsBorrowingTooMuchLiquidityAtStableRate();
            }
        }

        // All conditions passed - borrow is accepted
        // Update the the accounting or protocol state on LendingPoolCore
        (vars.finalUserBorrowRate, vars.borrowBalanceIncrease) =
            s_core.updateStateOnBorrow(_reserve, msg.sender, _amount, vars.borrowFee, vars.rateMode);

        // Transfer the borrowed asset.
        // LendingPoolCore sends the underlying ERC20 token or ETH to the borrower
        s_core.transferToUser(_reserve, payable(msg.sender), _amount);

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
            s_core.getUserBorrowBalances(_reserve, _onBehalfOf);

        // Get the protocol fee still owed by the borrower.
        vars.originationFee = s_core.getUserOriginationFee(_reserve, _onBehalfOf);

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
            s_core.updateStateOnRepay(_reserve, _onBehalfOf, 0, vars.paybackAmount, vars.borrowBalanceIncrease, false);

            // Send the paid fee to the protocol fee collector.
            s_core.transferToFeeCollectionAddress{value: vars.isETH ? vars.paybackAmount : 0}(
                _reserve, _onBehalfOf, vars.paybackAmount, s_addressesProvider.getTokenDistributor()
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
        s_core.updateStateOnRepay(
            _reserve,
            _onBehalfOf,
            vars.paybackAmountMinusFees,
            vars.originationFee,
            vars.borrowBalanceIncrease,
            vars.compoundedBorrowBalance == vars.paybackAmountMinusFees
        );

        // Send the paid fee to the protocol fee collector.
        if (vars.originationFee > 0) {
            s_core.transferToFeeCollectionAddress{value: vars.isETH ? vars.originationFee : 0}(
                _reserve, msg.sender, vars.originationFee, s_addressesProvider.getTokenDistributor()
            );
        }

        // Transfer the debt-repayment portion back to the reserve.
        // For ETH, transferToReserve refunds any msg.value sent in excess.
        // For ERC-20 tokens, the payer must have approved LendingPoolCore.
        s_core.transferToReserve{value: vars.isETH ? msg.value - vars.originationFee : 0}(
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

    /**
     * @dev users can invoke this function to liquidate an undercollateralized position.
     * @param _reserve the address of the collateral to liquidated
     * @param _reserve the address of the principal reserve
     * @param _user the address of the borrower
     * @param _purchaseAmount the amount of principal that the liquidator wants to repay
     * @param _receiveAToken true if the liquidators wants to receive the aTokens, false if
     * he wants to receive the underlying asset directly
     *
     */
    function liquidationCall(
        address _collateral,
        address _reserve,
        address _user,
        uint256 _purchaseAmount,
        bool _receiveAToken
    ) external payable nonReentrant onlyActiveReserve(_reserve) onlyActiveReserve(_collateral) {
        // Get the address of the contract responsible for the actual liquidationlogic
        address liquidationManager = s_addressesProvider.getLendingPoolLiquidationManager();

        // LendingPool executes `liquidationCall` of LiquidationManager in LendingPool context/storage
        (bool success, bytes memory result) = liquidationManager.delegatecall(
            abi.encodeCall(
                ILiquidationManager.liquidationCall, (_collateral, _reserve, _user, _purchaseAmount, _receiveAToken)
            )
        );
        if (!success) {
            revert LendingPool__LiquidationCallFailed();
        }

        // Decodes the manager’s (errorCode, errorMessage) result and reverts if the manager reports an error.
        (uint256 returnCode, string memory returnMessage) = abi.decode(result, (uint256, string));

        if (returnCode != 0) {
            revert LendingPool__LiquidationFailed(returnMessage);
        }
    }

    /**
     * @dev borrowers can user this function to swap between stable and variable borrow rate modes.
     * @param _reserve the address of the reserve on which the user borrowed
     *
     */
    function swapBorrowRateMode(address _reserve)
        external
        nonReentrant
        onlyActiveReserve(_reserve)
        onlyUnfreezedReserve(_reserve)
    {
        // Read the caller's debt:
        //   - principalBorrowBalance: debt recorded at the last user action
        //   - compoundedBorrowbalance: current debt including accrued interest
        //   - borrowBalanceIncrease: accrued interest since the last action
        (uint256 principalBorrowBalance, uint256 compoundedBorrowBalance, uint256 borrowBalanceIncrease) =
            s_core.getUserBorrowBalances(_reserve, msg.sender);

        // The call reverts if the user has no outstanding debt
        if (compoundedBorrowBalance == 0) {
            revert LendingPool__NoBorrowInProgress();
        }

        // Determine the current borrow rate mode:
        //   - a nonzero stableBorrowrate means stable mode;
        //   - otherwise the loan is variable mode.
        CoreLibrary.InterestRateMode currentRateMode = s_core.getUserCurrentBorrowRateMode(_reserve, msg.sender);

        if (currentRateMode == CoreLibrary.InterestRateMode.VARIABLE) {
            /**
             * user wants to swap to stable, before swapping we need to ensure that
             * 1. stable borrow rate is enabled on the reserve
             * 2. user is not trying to abuse the reserve by depositing
             * more collateral than he is borrowing, artificially lowering
             * the interest rate, borrowing at variable, and switching to stable
             *
             */
            if (!s_core.isUserAllowedToBorrowAtStable(_reserve, msg.sender, compoundedBorrowBalance)) {
                revert LendingPool__UserCannotBorrowAtStable();
            }
        }

        // Delegate accounting to LendingPoolCore.updatedStateOnSwapRate
        (CoreLibrary.InterestRateMode newRateMode, uint256 newBorrowRate) = s_core.updateStateOnSwapRate(
            _reserve,
            msg.sender,
            principalBorrowBalance,
            compoundedBorrowBalance,
            borrowBalanceIncrease,
            currentRateMode
        );

        // Emit the Swap event
        emit Swap(_reserve, msg.sender, uint256(newRateMode), newBorrowRate, borrowBalanceIncrease, block.timestamp);
    }

    /**
     * @dev lends reserve liquidity to a receiver contract for the duration of one transaction.
     * The receiver must return the principal plus the required fee before its callback finishes;
     * otherwise, the entire transaction reverts.There are security concerns for developers of flashloan receiver contracts
     * that must be kept into consideration.
     * @param _receiver The address of the contract receiving the funds. The receiver should implement the IFlashLoanReceiver interface.
     * @param _reserve the address of the principal reserve
     * @param _amount the amount requested for this flashloan
     *
     */
    function flashLoan(address _receiver, address _reserve, uint256 _amount, bytes memory _params)
        external
        nonReentrant
        onlyActiveReserve(_reserve)
        onlyAmountGreaterThanZero(_amount)
    {
        // It reads the Core contract's current ETH/ERC-20 balance and it requires to cover _amount
        // Avoid using the getAvailableLiquidity() function in LendingPoolCore to save gas
        uint256 availableLiquidityBefore = _reserve == EthAddressLib.ethAddress()
            ? address(s_core).balance
            : IERC20(_reserve).balanceOf(address(s_core));

        if (availableLiquidityBefore < _amount) {
            revert LendingPool__InsufficientLiquidityToBorrow();
        }

        // Read the parameters FLASHLOAN_FEE_TOTAL and FLASHLOAN_FEE_PROTOCOL
        (uint256 totalFeeBips, uint256 protocolFeeBips) = s_parametersProvider.getFlashLoanFeesInBips();

        // Fees are 0.35 % of the _amount
        uint256 amountFee = _amount * totalFeeBips / 10_000;

        // 30% of amountFee goes to the protocol and 70% of amountFee goes to depositors
        uint256 protocolFee = amountFee * protocolFeeBips / 10_000;

        if (amountFee == 0 || protocolFee == 0) {
            revert LendingPool__InsufficientAmountForFlashLoan();
        }

        // Get the FlashLoanReceiver instance
        IFlashLoanReceiver receiver = IFlashLoanReceiver(_receiver);

        // Transfer _amount from LendingPoolCore to _receiver
        s_core.transferToUser(_reserve, payable(_receiver), _amount);

        // Execute acton of the receiver
        receiver.executeOperation(_reserve, _amount, amountFee, _params);

        // Verifies an exact balance invariant:
        //      corebalanceAfter == coreBalanceBefore + amountFee
        // This means that the loan principal has been returned and precisely the fee was earned.
        // Any shortfall or an unexpected balance change reverts
        uint256 availableLiquidityAfter = _reserve == EthAddressLib.ethAddress()
            ? address(s_core).balance
            : IERC20(_reserve).balanceOf(address(s_core));

        if (availableLiquidityAfter != availableLiquidityBefore + amountFee) {
            revert LendingPool__InconsistentProtocolBalance();
        }

        // Updates the reserve accounting:
        //   - Protocol fee is sent to the token distributor
        //   - The remainder increases the reserve liquidity index, benefiting aToken holders
        //   - The rates/timestamps are refreshed
        s_core.updateStateOnFlashLoan(_reserve, availableLiquidityBefore, amountFee - protocolFee, protocolFee);

        emit FlashLoan(_receiver, _reserve, _amount, amountFee, protocolFee, block.timestamp);
    }

    /**
     * @dev rebalances the stable interest rate of a user if current liquidity rate > user stable rate.
     * this is regulated by Aave to ensure that the protocol is not abused, and the user is paying a fair
     * rate. Anyone can call this function though.
     * @param _reserve the address of the reserve
     * @param _user the address of the user to be rebalanced
     *
     */
    function rebalanceStableBorrowRate(address _reserve, address _user)
        external
        nonReentrant
        onlyActiveReserve(_reserve)
    {
        // lets anyone reset a borrower’s stable interest rate when it has become materially unfair or unsafe for the pool.

        // Reads the compounded balance and the borrow balance increase.
        (, uint256 compoundedBalance, uint256 borrowBalanceIncrease) = s_core.getUserBorrowBalances(_reserve, _user);

        //step 1: user must be borrowing on _reserve at a stable rate
        if (compoundedBalance == 0) {
            revert LendingPool__NoBorrowForReserve();
        }

        if (s_core.getUserCurrentBorrowRateMode(_reserve, _user) != CoreLibrary.InterestRateMode.STABLE) {
            revert LendingPool__BorrowRateModeIsNotStable();
        }

        // Reads:
        //    - the user’s stable rate,
        //    - the reserve’s liquidity (deposit) rate,
        //    - the reserve’s currently quoted stable borrowing rate.
        uint256 userCurrentStableRate = s_core.getUserCurrentStableBorrowRate(_reserve, _user);
        uint256 liquidityRate = s_core.getReserveCurrentLiquidityRate(_reserve);
        uint256 reserveCurrentStableRate = s_core.getReserveCurrentStableBorrowRate(_reserve);
        uint256 rebalanceDownRateThreshold =
            reserveCurrentStableRate.rayMul(WadRayMath.ray() + s_parametersProvider.getRebalanceDownRateDelta());

        //Step 2: we have two possible situations to rebalance:

        //  1. User stable borrow rate is below the current liquidity rate. The loan needs to be rebalanced,
        //      as this situation can be abused (user putting back the borrowed liquidity in the same reserve to earn on it)
        //  2. user stable rate is above the market avg borrow rate of a certain delta, and utilization rate is low.
        //      In this case, the user is paying an interest that is too high, and needs to be rescaled down.
        if (userCurrentStableRate < liquidityRate || userCurrentStableRate > rebalanceDownRateThreshold) {
            // The core contract updates the state:
            //    - Adds accrued interest (borrowBalanceIncrease) into the borrower’s principal.
            //    - Updates reserve stable-borrow accounting.
            //    - Sets the borrower’s rate to the reserve’s current stable borrow rate.
            //    - Updates reserve rate data and timestamps.
            uint256 newStableRate = s_core.updateStateOnRebalance(_reserve, _user, borrowBalanceIncrease);

            emit RebalanceStableBorrowRate(_reserve, _user, newStableRate, borrowBalanceIncrease, block.timestamp);

            return;
        }

        revert LendingPool__InterestRateRebalanceConditionsNotMet();
    }

    /**
     * @dev lets a depositor toggle whether their deposited asset in _reserve counts as borrowing collateral.
     * @param _reserve the address of the reserve
     * @param _useAsCollateral true if the user wants to user the deposit as collateral, false otherwise.
     *
     */
    function setUserUseReserveAsCollateral(address _reserve, bool _useAsCollateral)
        external
        nonReentrant
        onlyActiveReserve(_reserve)
        onlyUnfreezedReserve(_reserve)
    {
        // Require a deposit
        // The "underlying balance" is obtained from the user's aToken balance, which represents their interest-bearing deposit
        uint256 underlyingBalance = s_core.getUserUnderlyingAssetBalance(_reserve, msg.sender);
        if (underlyingBalance == 0) {
            revert LendingPool__NoLiquidityDeposited();
        }

        // Prevent unsafe collateral removal
        // Checks if removing the deposit from collateral keep the position safe.
        // If this asset is currently enabled as collateral and the user has debt,
        // the data provider recalculates the health factor as if the full balance disappeared.
        if (!s_dataProvider.balanceDecreaseAllowed(_reserve, msg.sender, underlyingBalance)) {
            revert DepositAlreadyUseadAsCollateral();
        }

        // STore the preference
        s_core.setUserUseReserveAsCollateral(_reserve, msg.sender, _useAsCollateral);

        if (_useAsCollateral) {
            emit ReserveUsedAsCollateralEnabled(_reserve, msg.sender);
        } else {
            emit ReserveUsedAsCollateralDisabled(_reserve, msg.sender);
        }
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
        return address(s_core);
    }

    function getLendingPoolAddressesProvider() external view returns (address) {
        return address(s_addressesProvider);
    }
}
