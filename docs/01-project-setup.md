# Project Setup

We use Foundry to build, test, and run the project.

## Create the Project

```bash
forge init aave-v1-from-scratch
cd aave-v1-from-scratch
```

## Install OpenZeppelin Contracts

We use OpenZeppelin for standard ERC20 contracts.

```bash
forge install OpenZeppelin/openzeppelin-contracts
```

## Remappings

Add the OpenZeppelin remapping in foundry.toml:

```text
remappings = [
  "openzeppelin-contracts/=lib/openzeppelin-contracts/contracts/"
]
```

## Structure

```text
src/contracts
        ├──tokenization/AToken.sol
        ├── lendingpool/LendingPool.sol

test/
└── LendingPoolTest.t.sol

docs/
├── 00-introduction.md
├── 01-project-setup.md
└── 02-deposit.md
```

// TODO must be reviewed
