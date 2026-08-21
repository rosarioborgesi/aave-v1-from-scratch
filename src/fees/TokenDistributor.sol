// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";

import {EthAddressLib} from "src/libraries/EthAddressLib.sol";

/// @title TokenDistributor
/// @notice Holds ERC-20 tokens and native ETH, then distributes them to configured recipients.
/// @dev Pass `EthAddressLib.ethAddress()` in a token array to represent native ETH.
contract TokenDistributor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Thrown when two input arrays that must be paired have different lengths.
    /// @param _expectedLength Length of the first array.
    /// @param _actualLength Length of the second array.
    error TokenDistributor__ArrayLengthMismatch(uint256 _expectedLength, uint256 _actualLength);

    /// @notice Thrown when a native ETH transfer to a recipient fails.
    /// @param _receiver Recipient of the failed transfer.
    /// @param _amount Amount of ETH that could not be transferred.
    error TokenDistributor__EthTransferFailed(address _receiver, uint256 _amount);

    struct Distribution {
        address[] receivers;
        uint256[] percentages;
    }

    event DistributionUpdated(address[] receivers, uint256[] percentages);
    event Distributed(address receiver, uint256 percentage, uint256 amount);

    /// @notice Recipient addresses and their shares of each distribution.
    Distribution private distribution;

    /// @notice Denominator used to express each recipient's distribution share.
    uint256 public constant DISTRIBUTION_BASE = 10000;

    /// @notice Legacy token-to-burn address retained for storage compatibility; unused by this implementation.
    address public tokenToBurn;

    /// @notice Creates a distributor with its recipient addresses and distribution shares.
    /// @param _receivers Addresses that receive a share of every distribution.
    /// @param _percentages Shares for each recipient, expressed relative to `DISTRIBUTION_BASE`.
    constructor(address[] memory _receivers, uint256[] memory _percentages) {
        _setTokenDistribution(_receivers, _percentages);
        emit DistributionUpdated(_receivers, _percentages);
    }

    /// @notice Accepts native ETH sent directly to this contract.
    receive() external payable {}

    /// @notice Distributes this contract's entire balance of each specified asset.
    /// @dev Use `EthAddressLib.ethAddress()` to distribute this contract's native ETH balance.
    /// @param _tokens ERC-20 tokens to distribute, or the ETH sentinel address.
    function distribute(IERC20[] memory _tokens) external nonReentrant {
        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 _balanceToDistribute = (address(_tokens[i]) != EthAddressLib.ethAddress())
                ? _tokens[i].balanceOf(address(this))
                : address(this).balance;
            if (_balanceToDistribute <= 0) {
                continue;
            }

            _distributeTokenWithAmount(_tokens[i], _balanceToDistribute);
        }
    }

    /// @notice Distributes a specified amount of each asset.
    /// @dev Use `EthAddressLib.ethAddress()` to distribute native ETH.
    /// @param _tokens ERC-20 tokens to distribute, or the ETH sentinel address.
    /// @param _amounts Amount of each corresponding asset to distribute.
    function distributeWithAmounts(IERC20[] memory _tokens, uint256[] memory _amounts) external nonReentrant {
        if (_tokens.length != _amounts.length) {
            revert TokenDistributor__ArrayLengthMismatch(_tokens.length, _amounts.length);
        }
        for (uint256 i = 0; i < _tokens.length; i++) {
            _distributeTokenWithAmount(_tokens[i], _amounts[i]);
        }
    }

    /// @notice Distributes a percentage of this contract's balance for each specified asset.
    /// @dev Each percentage uses 100 as its denominator. Use `EthAddressLib.ethAddress()` for native ETH.
    /// @param _tokens ERC-20 tokens to distribute, or the ETH sentinel address.
    /// @param _percentages Percentages of the corresponding asset balances to distribute.
    function distributeWithPercentages(IERC20[] memory _tokens, uint256[] memory _percentages) external nonReentrant {
        if (_tokens.length != _percentages.length) {
            revert TokenDistributor__ArrayLengthMismatch(_tokens.length, _percentages.length);
        }
        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 _amountToDistribute = (address(_tokens[i]) != EthAddressLib.ethAddress())
                ? (_tokens[i].balanceOf(address(this)) * _percentages[i]) / 100
                : (address(this).balance * _percentages[i]) / 100;
            if (_amountToDistribute <= 0) {
                continue;
            }

            _distributeTokenWithAmount(_tokens[i], _amountToDistribute);
        }
    }

    /// @notice Stores the configured recipients and their distribution shares.
    /// @param _receivers Addresses that receive a share of each distribution.
    /// @param _percentages Shares for each recipient, expressed relative to `DISTRIBUTION_BASE`.
    function _setTokenDistribution(address[] memory _receivers, uint256[] memory _percentages) internal {
        if (_receivers.length != _percentages.length) {
            revert TokenDistributor__ArrayLengthMismatch(_receivers.length, _percentages.length);
        }

        distribution = Distribution({receivers: _receivers, percentages: _percentages});
        emit DistributionUpdated(_receivers, _percentages);
    }

    /// @notice Distributes an asset amount among all configured recipients.
    /// @param _token ERC-20 token to distribute, or the ETH sentinel address.
    /// @param _amountToDistribute Total amount of the asset to split between recipients.
    function _distributeTokenWithAmount(IERC20 _token, uint256 _amountToDistribute) internal {
        address _tokenAddress = address(_token);
        Distribution memory _distribution = distribution;
        for (uint256 j = 0; j < _distribution.receivers.length; j++) {
            uint256 _amount = (_amountToDistribute * _distribution.percentages[j]) / DISTRIBUTION_BASE;

            // Avoid zero-value transfers.
            if (_amount == 0) {
                continue;
            }

            if (_tokenAddress != EthAddressLib.ethAddress()) {
                _token.safeTransfer(_distribution.receivers[j], _amount);
            } else {
                (bool _success,) = payable(_distribution.receivers[j]).call{value: _amount}("");
                if (!_success) {
                    revert TokenDistributor__EthTransferFailed(_distribution.receivers[j], _amount);
                }
            }
            emit Distributed(_distribution.receivers[j], _distribution.percentages[j], _amount);
        }
    }

    /// @notice Returns the configured recipients and their distribution shares.
    /// @return receivers Recipient addresses.
    /// @return percentages Recipient shares, expressed relative to `DISTRIBUTION_BASE`.
    function getDistribution() public view returns (address[] memory receivers, uint256[] memory percentages) {
        receivers = distribution.receivers;
        percentages = distribution.percentages;
    }
}
