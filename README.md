# Countering Arbitrageurs and Resisting Oracle Manipulators in Ethereum Smart Contracts

This repository contains experiments performed for my Bachelor's research project at TU Delft, exploring frontrunning and oracle manipulation vulnerabilities. This project utilises Hardhat to fork Ethereum mainnet and run scripts.

## Frontrunning

The test case `test/frontrun.spec.ts` contains code exemplifying a typical sandwich attack on Uniswap, using frontrunning and backrunning via the PGA mechanism.

## Oracle Manipulation

The scripts `test/vulnerable-price-oracle.spec.ts` and `test/resistant-price-oracle.spec.ts` contain code demonstrating oracle manipulation attacks on the contracts in the `contracts/` directory. `contracts/VulnerableLendingProtocol.sol` is an example lending protocol that uses Uniswap V2 as a price oracle by calculating reserves, and is vulnerable to an oracle manipulation attack defined in `contracts/SimpleOracleAttack.sol`.

`contracts/ResistantLendingProtocol.sol` describes a lending protocol that uses a TWAP price oracle as a countermeasure to oracle manipulation.

## Running Experiments

To run the test cases, use the command `yarn test`.
