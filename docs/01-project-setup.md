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
forge install openzeppelin/openzeppelin-contracts
```

## Foundry Configuration

The project uses Solidity `0.8.30`. The `foundry.toml` file also defines the
OpenZeppelin remapping used by imports throughout the contracts:

```text
solc_version = "0.8.30"

remappings = [
  "openzeppelin-contracts/=lib/openzeppelin-contracts/contracts/"
]
```

## Structure

```text
src/
├── configuration/  # Address and protocol-parameter configuration
├── flashloan/      # Flash-loan receiver base contract and interface
├── interfaces/     # Interfaces for protocol dependencies
├── lendingpool/    # User flows and reserve accounting
├── libraries/      # Fixed-point math and core accounting helpers
└── tokenization/   # Interest-bearing aToken implementation

test/
├── integration/    # End-to-end protocol-flow tests
├── mocks/          # Test doubles for tokens, oracles, and providers
└── unit/           # Focused contract and library tests

docs/
├── 00-introduction.md
├── 01-project-setup.md
├── 01-protocol-architecture.md
├── ...
└── 21-flash-loan.md
```
