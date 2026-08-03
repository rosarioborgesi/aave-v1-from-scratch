# Repay

The `repay` function lets a borrower pay back an outstanding loan in Aave V1.

It reduces the borrower’s debt balance, including any accrued interest, and transfers the repaid underlying asset—such as DAI—back into the reserve. The protocol then updates the reserve’s borrowing totals and interest rates.

A borrower can repay part or all of their debt. A full repayment clears the debt position, but the borrower’s collateral remains deposited until they redeem it separately.
