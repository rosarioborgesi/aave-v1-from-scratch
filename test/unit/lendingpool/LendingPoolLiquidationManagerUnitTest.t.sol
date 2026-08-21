// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {MockLendingPoolAddressesProvider} from "../../mocks/MockLendingPoolAddressesProvider.sol";
import {MockLendingPoolCore} from "../../mocks/MockLendingPoolCore.sol";
import {MockERC20} from "../../mocks/tokens/MockERC20.sol";
import {MockPriceOracle} from "../../mocks/oracle/MockPriceOracle.sol";

import {LendingPoolLiquidationManager} from "src/lendingpool/LendingPoolLiquidationManager.sol";

contract LendingPoolLiquidationManagerHarness is LendingPoolLiquidationManager {
    constructor(address addressesProvider, address core) {
        // LendingPoolLiquidationManager stores these private references in slots 0 and 1.
        // This test-only harness initializes them without changing the production contract.
        assembly {
            sstore(0, addressesProvider)
            sstore(1, core)
        }
    }

    function calculateAvailableCollateralToLiquidate(
        address collateral,
        address principal,
        uint256 purchaseAmount,
        uint256 userCollateralBalance
    ) external view returns (uint256 collateralAmount, uint256 principalAmountNeeded) {
        return _calculateAvailableCollateralToLiquidate(collateral, principal, purchaseAmount, userCollateralBalance);
    }
}

contract LendingPoolLiquidationManagerUnitTest is Test {
    uint256 private constant LIQUIDATION_BONUS = 105;

    MockERC20 private collateral;
    MockERC20 private principal;

    MockLendingPoolAddressesProvider private addressesProvider;
    MockLendingPoolCore private core;
    MockPriceOracle private oracle;
    LendingPoolLiquidationManagerHarness private manager;

    function setUp() external {
        addressesProvider = new MockLendingPoolAddressesProvider(makeAddr("lendingPool"), makeAddr("configurator"));
        core = new MockLendingPoolCore();
        oracle = new MockPriceOracle();
        collateral = new MockERC20("Wrapped Ether", "WETH");
        principal = new MockERC20("Dai Stablecoin", "DAI");

        addressesProvider.setLendingPoolCore(address(core));
        addressesProvider.setPriceOracle(address(oracle));
        core.setReserveLiquidationBonus(address(collateral), LIQUIDATION_BONUS);

        // Prices are denominated in ETH: 1 WETH = 1 ETH and 1 DAI = $1 = 1/2,000 ETH.
        oracle.setAssetPrice(address(principal), 0.0005 ether);
        oracle.setAssetPrice(address(collateral), 1e18);

        manager = new LendingPoolLiquidationManagerHarness(address(addressesProvider), address(core));
    }

    /////////////////////////////////////////////////////////////
    //        _calculateAvailableCollateralToLiquidate         //
    /////////////////////////////////////////////////////////////

    // The test verifies the “borrower has enough collateral” path of _calculateAvailableCollateralToLiquidate.
    function testCalculateAvailableCollateralToLiquidateWithSufficientCollateral() external view {
        uint256 purchaseAmount = 100 ether;
        uint256 userCollateral = 0.0525 ether;

        // The setup is:
        //  - Repay (purchaseAmount): 100 DAI
        //  - DAI price: 0.0005 ETH -> 100 DAI is worth 0.05 ETH
        //  - WETH price: 1 ETH
        //  - Liquidation bonus: 105 %

        (uint256 collateralAmount, uint256 principalAmountNeeded) = manager.calculateAvailableCollateralToLiquidate(
            address(collateral), address(principal), purchaseAmount, userCollateral
        );

        // So the collateral a liquidator earns is:
        // maxCollateral = ( principal price x repayment / collateral price) x liquidation bonus / 100
        // (0.0005 ETH x 100 DAI / 1 ETH) x 105 / 100 = 0.0525 WETH

        assertEq(collateralAmount, 0.0525 ether);
        assertEq(principalAmountNeeded, purchaseAmount);
    }

    // This test verifies the liquidation path where the borrower cannot provide enough collateral to support the requested debt repayment.
    function testCalculateAvailableCollateralToLiquidateWithInsufficientCollateral() external view {
        uint256 purchaseAmount = 100 ether;
        uint256 userCollateral = 0.05 ether;
        // 100 DAI is requested for repayment
        // 1 DAI = 0.0005 ETH, so 100 DAI = 0.05 ETH
        // 1 WETH = 1 ETH
        // The liquidation bonus is 105 %, so rapying 100 DAI would seize: 0.05 WETH x 1.05 = 0.0525 WETH

        // But the borrower only has 0.05 WETH , less than the required 0.0525 WETH.
        // So the internal calculation takes the insufficient-collateral branch
        //  1. It caps the seized collateral at the borrower’s whole balance: 0.05 WETH
        //  2. It works backward to find how much DAI that collateral supports once the 5% bonus is honored:
        //      0.05 ETH / 0.0005 ETH/DAI * 100 / 105 = 95.238095238095238095 DAI
        (uint256 collateralAmount, uint256 principalAmountNeeded) = manager.calculateAvailableCollateralToLiquidate(
            address(collateral), address(principal), purchaseAmount, userCollateral
        );

        assertEq(collateralAmount, userCollateral);
        assertEq(principalAmountNeeded, 95_238095238095238095);
    }
}
