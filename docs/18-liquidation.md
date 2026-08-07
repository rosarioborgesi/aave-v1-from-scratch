# Liquidation

A **liquidation call** is the action that repairs an unsafe loan in Aave V1.

If a borrower’s health factor falls below `1`—usually because their collateral has lost value—anyone can become a liquidator and:

1. Repay part of the borrower’s outstanding debt (up to 50% in Aave V1).
2. Receive an equivalent portion of the borrower’s collateral.
3. Receive that collateral with a **liquidation bonus**.

The bonus gives external liquidators an incentive to repay risky debt. The borrower loses some collateral, but their debt is reduced, helping bring their health factor back above `1` and protecting the protocol from bad debt.
