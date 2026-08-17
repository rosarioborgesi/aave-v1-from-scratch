# Aave V1 From Scratch

The goal of this project is to rebuild the core ideas of Aave V1 from scratch using Solidity and Foundry.

This is not a production-ready implementation. The goal is educational: to understand how a lending protocol works by implementing one feature at a time and writing tests for each step.

Aave V1 is based on a pool-based lending model. Users deposit assets into a shared pool, and other users can borrow from that pool by providing collateral.

In the original Aave V1 architecture, the main user-facing contract is the `LendingPool`. Users interact with it to deposit, redeem, borrow, repay, swap rates, liquidate positions, and use flash loans.

In this project, we will start with the simplest possible flow:

```text
User deposits ERC20 tokens
User receives aTokens
```
// TODO complete

## NOTE on changes from the original version of the protocol
With respect to the original version of the protocl I have chosen to not use the proxy patter that is used for the contract replacing the initialize method with a simple constructor and to remove the redirection of interest from the AToken that has been deprecated in newver version of AAve V2 because it only made harder to udnerstand the function of the contract.

Furthemore also the stable rate borrowing has been depreacted on the newver version but I chose to keep it because there is the swap rate feature

I decided to use modern solidity 0.8.30 and to build it with Foundry instead of Hardhat.
Using modern day solidity means that we don't need SafeMath anymore because the uint256 now handles the overflow, underflow by default.

I have also chosen to replace require with if + reverts and custom errors because this is a good practise as it consumes less gas.

Obviously some changes are required when using newver version of Open Zeppelin contracts (v5.6.1) that are different from the original (v. 2.3.0)

I have also tried to write as many unit tests as possible to understan how each single function works as well as integration tests to undertsand how the contracts work together and to undertsnad how the overall operations of deposit, redeem, borrow, etc. work.