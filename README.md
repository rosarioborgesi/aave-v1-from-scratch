# Aave V1 From Scratch

This project is an educational rebuild of the core ideas behind Aave V1.

The goal is to recreate the protocol step by step from scratch using:

- Foundry
- Solidity 0.8.30
- OpenZeppelin Contracts

This is not a production implementation and should not be used with real funds. It is a learning project for understanding how a pool-based lending protocol works by implementing the main pieces one feature at a time.

## Inspiration

The original Aave V1 protocol can be found here:

[aave/aave-protocol](https://github.com/aave/aave-protocol)

This project uses the original protocol as a reference, but the code is intentionally simplified and rewritten for learning with modern Solidity and Foundry.

## Project Docs

The project is documented as a sequence of small steps:

- [Introduction](docs/00-introduction.md)
- [Project Setup](docs/01-project-setup.md)
- [Deposit](docs/02-deposit.md)

## Development

Install dependencies:

```bash
forge install
```

Build:

```bash
forge build
```

Run tests:

```bash
forge test
```

## Status

Work in progress. The current focus is rebuilding the first deposit flow before adding the more complex lending protocol mechanics.

## Connect With Me

<p align="left">
  <a href="https://x.com/rosarioborgesi">
    <img src="https://img.shields.io/badge/twitter-000000?style=for-the-badge&logo=x&logoColor=white"/>
  </a>
  <a href="https://www.linkedin.com/in/rosarioborgesi/">
    <img src="https://img.shields.io/badge/LinkedIn-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white"/>
  </a>
  <a href="mailto:borgesiros@gmail.com">
    <img src="https://img.shields.io/badge/Email-D14836?style=for-the-badge&logo=gmail&logoColor=white"/>
  </a>
  <a href="https://www.youtube.com/@rosarioborgesi">
    <img src="https://img.shields.io/badge/YouTube-FF0000?style=for-the-badge&logo=youtube&logoColor=white"/>
  </a>
  <a href="https://farcaster.xyz/rosarioborgesi">
    <img src="https://img.shields.io/badge/Farcaster-855DCD?style=for-the-badge"/>
  </a>
  <a href="https://medium.com/@rosarioborgesi/">
    <img src="https://img.shields.io/badge/Medium-000000?style=for-the-badge&logo=medium&logoColor=white"/>
  </a>
</p>
