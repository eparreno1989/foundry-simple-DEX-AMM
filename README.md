# 🔄 Simple AMM — Constant Product Decentralized Exchange

A gas-optimized, production-ready Constant Product Automated Market Maker ($x \cdot y = k$) implemented in Solidity, built with full NatSpec documentation and tested using [Foundry](https://github.com/foundry-rs/foundry).

This repository features deterministic unit test suites (`SimpleAMMUnitary`) alongside stateful invariant fuzzing (`SimpleAMMInvariant`) using a custom Handler architecture (`SimpleAMMHandler`) to guarantee protocol solvency, non-decreasing constant product mechanics, and core reserve invariants under arbitrary call sequences.

---

## ✨ Key Features

* **Core AMM Functionality**: Liquidity provisioning (`addLiquidity`), withdrawal (`removeLiquidity`), and token swaps (`swap`) with an embedded 0.3% protocol fee.
* **Deterministic Token Sorting**: Token pair addresses are sorted deterministically ($token0 < token1$) during initialization to prevent duplicate or inverted pool creation.
* **Custom Errors**: Replaces standard revert strings with gas-efficient custom errors (`InvalidToken`, `InsufficientAmount`, `SharesZero`, `InsufficientLiquidityMinted`).
* **NatSpec Standard**: Complete NatSpec comments (`@title`, `@notice`, `@dev`, `@param`, `@return`) adhering to Ethereum documentation standards.
* **Stateful Invariant Testing**: Built-in `SimpleAMMHandler` ghost-state tracking for stateful fuzz testing using Foundry.

---

## 🏗️ Smart Contract Architecture

* **`src/`**
  * `SimpleAMM.sol` — Core Constant Product AMM implementation
* **`test/`**
  * `SimpleAMMUnitary.sol` — Unit test suite covering edge cases and reverts
  * `SimpleAMMInvariant.sol` — Stateful invariant suite validating protocol properties
  * **`Handlers/`**
    * `SimpleAMMHandler.sol` — Fuzzing Handler wrapper with ghost variables (`kLast`)
  * **`Mocks/`**
    * `MockERC20.sol` — ERC20 mock contract for liquidity and swap testing

---

## 🛡️ Protocol Invariants

The stateful fuzz testing suite validates three fundamental invariants across randomized state transitions:

| Invariant | Method | Description |
| :--- | :--- | :--- |
| **Solvency** | `invariant_solvencyReservesMatchBalances` | ERC20 token balances in the AMM contract must always be greater than or equal to internal accounting reserves (`reserve0`, `reserve1`). |
| **Constant Product ($k$)** | `invariant_constantProductIncreasesOrStaysSame` | Constant product $k = reserve_0 \cdot reserve_1$ must never decrease across swap operations due to accumulated swap fees. |
| **Reserve Integrity** | `invariant_zeroSupplyMeansZeroReserves` | A total share supply of zero strictly implies both reserves must evaluate to zero, preventing stranded liquidity. |

---

## 🚀 Getting Started

### 📋 Prerequisites

* [Git](https://git-scm.com/)
* [Foundry / Forge](https://getfoundry.sh/)

### 🔧 Installation

Clone the repository and install dependencies:

```bash
git clone https://github.com/your-username/foundry-simple-DEX-AMM.git
cd foundry-simple-DEX-AMM
forge build
```

## 🧪 Testing & Verification

### 🎯 Unit Tests
Run all deterministic unit tests across setup, liquidity provisioning, swaps, and revert conditions:

```bash
forge test --match-contract SimpleAMMUnitary -vvv
```

### 🎲 Stateful Invariant Fuzzing
Execute stateful fuzzing through the `SimpleAMMHandler`:

```bash
forge test --match-contract SimpleAMMInvariant -vvv
```
### 📊 Test Coverage
Generate a terminal test coverage summary targeting the core protocol:

```bash
forge coverage --match-path "src/*.sol"
```
To export a detailed HTML coverage report using lcov:

```bash
forge coverage --report lcov
genhtml lcov.info -o coverage-html
open coverage-html/index.html
```
## 📄 License
This project is licensed under the MIT License.

## 👨‍💻 Author

### Erick Parreño
**Computer Engineer & Web3 Smart Contract Developer**

* **Role**: Computer Engineer / Web3 Engineer
* **Core Focus**: EVM Smart Contract Development, Security Auditing Standards, & DeFi Protocols
* **Tech Stack**: Solidity, Foundry (Forge, Cast, Anvil), Remix, Slither, OpenZeppelin, Git
* **GitHub**: [@eparreno1989](https://github.com/eparreno1989)
* **LinkedIn**: [Erick Parreño](https://www.linkedin.com/in/erick-parreño-a3a8271bb/)

> *Project built as part of a Web3 Smart Contract Development & Security Engineering Portfolio.*
