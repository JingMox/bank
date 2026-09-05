# Bank & BigBank - Decentralized Smart Banking Protocol

A modular, secure decentralized banking smart contract suite built on Ethereum using Solidity and Foundry. This project showcases core DeFi architectural patterns, including on-chain sorting algorithms for real-time depositor leaderboards, tiered access control, contract-governed administrative fund management, and exhaustive automated test suites with fuzz testing.

---

## Key Features

- **Decentralized Banking (`Bank.sol`)**:
  - Direct ETH deposits via explicit function call (`deposit()`) or fallback handler (`receive()`).
  - Account balance bookkeeping via mapped storage.
  - **Real-Time Top 3 Depositors Leaderboard**: On-chain ranking mechanism that tracks the highest depositors, handles ties deterministically, and dynamically resolves real-time cumulative balances.
  - **Tiered Withdrawal Permissions**: Regular depositors can make partial withdrawals; full contract fund sweeping and complete account withdrawals are strictly reserved for the protocol administrator.

- **Advanced Governance & Constraints (`BigBank.sol` & `Admin.sol`)**:
  - **Deposit Threshold Enforcement**: Inherits and extends `Bank` with a `0.001 ether` minimum deposit requirement applied to both function calls and direct ETH transfers.
  - **Modular Administration**: Administration rights can be safely transferred to a dedicated `Admin` contract, guarding against zero-address configuration.
  - **Two-Step Administrative Withdrawal Pipeline**: `Admin` contract sweeps funds from the bank vault via `adminWithdraw(IBank)` and forwards them to the underlying owner via `withdrawToOwner()`, separating governance logic from core vault state.

- **Robust Testing & Quality Assurance**:
  - **30 test cases across 3 test suites**, achieving a **100% pass rate (0 failures)**.
  - Property-based **fuzz testing** (`testFuzz_Deposit`) with dynamic bound clamping.
  - Strict event emission assertions and revert reason checks.
  - Comprehensive edge-case verification for multi-user ranking transitions.

---

## Project Structure

```
bank/
├── src/
│   ├── Bank.sol             # Core decentralized bank implementation & IBank interface
│   └── BigBank.sol          # Extended bank with deposit threshold & dedicated Admin contract
├── script/
│   └── BigBank.s.sol        # Foundry deployment script for BigBank and Admin
├── test/
│   ├── Bank.t.sol           # Unit test suite for Bank contract
│   ├── BigBank.t.sol        # Extended test suite (thresholds, admin flow, fuzzing)
│   └── BankChallenge.t.sol  # Comprehensive specification verification suite
├── FOUNDRY_GUIDE.md         # Comprehensive Foundry handbook & troubleshooting guide
├── vm-cheatsheet.md         # Foundry cheatcode (`vm`) quick reference
├── foundry.toml             # Foundry build and framework configuration
├── remappings.txt           # OpenZeppelin and Forge dependency remappings
└── test.log                 # Execution output of the 30-test verification run
```

---

## Verification & Test Results

The test suite covers full functional correctness, access control invariants, and boundary conditions:

1. **Balance State Transitions**: Accurate balance recording upon deposit, handling zero initial states, and cumulative additions across multiple deposits.
2. **Top 3 Depositor Ranking**: Deterministic behavior across 1, 2, 3, and 4+ depositors, FIFO ordering on tied amounts, and dynamic balance updates without duplicate entries.
3. **Privilege & Access Control**: Parameterless `withdraw()` restricted exclusively to the admin; regular accounts prohibited from sweeping the entire contract balance while retaining partial withdrawal capabilities.
4. **Fuzz & Revert Validations**: Automated fuzz runs validating arbitrary deposit amounts above the threshold, rejecting under-threshold transfers.

Execution summary from `test.log`:
```
Ran 11 tests for test/BankChallenge.t.sol:BankChallengeTest -> 11 passed, 0 failed
Ran 8 tests for test/Bank.t.sol:BankTest                   -> 8 passed, 0 failed
Ran 11 tests for test/BigBank.t.sol:BigBankTest           -> 11 passed, 0 failed
Total: 30 tests passed, 0 failed, 0 skipped
```

---

## Getting Started

### Prerequisites

Ensure [Foundry](https://book.getfoundry.sh/getting-started/installation) is installed:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Installation

Clone the repository and install submodules:

```bash
git clone <repository_url>
cd bank
git submodule update --init --recursive
```

### Build

Compile contracts and verify bytecode sizes:

```bash
forge build --sizes
```

### Run Tests

Run the complete test suite:

```bash
forge test -vvv
```

Run tests with real-time watch mode during development:

```bash
forge test --watch -vvv
```

Generate test coverage reports:

```bash
forge coverage
```

Generate gas consumption snapshots:

```bash
forge snapshot
```

---

## Deployment & Interaction

### 1. Local Simulation (Dry Run)

Run the deployment script inside an ephemeral local EVM:

```bash
forge script script/BigBank.s.sol:BigBankScript
```

### 2. Deploy to Local Anvil Node

Start local test node:

```bash
anvil
```

Deploy and broadcast contracts:

```bash
forge script script/BigBank.s.sol:BigBankScript \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

### 3. Interacting via `cast`

Once deployed on Anvil or a testnet, interact using `cast`:

```bash
# Query contract administrator
cast call $BIGBANK "admin()(address)" --rpc-url $RPC

# Query depositor balance
cast call $BIGBANK "balances(address)(uint256)" <user_address> --rpc-url $RPC

# Query Top 3 depositors leaderboard
cast call $BIGBANK "getTOP3Depositor()(address[3],uint256[3])" --rpc-url $RPC

# Deposit ETH (calls deposit())
cast send $BIGBANK "deposit()" --value 0.5ether --private-key <private_key> --rpc-url $RPC

# Sweep bank funds via Admin contract
cast send $ADMIN "adminWithdraw(address)" $BIGBANK --private-key <admin_key> --rpc-url $RPC

# Transfer funds from Admin contract to owner
cast send $ADMIN "withdrawToOwner()" --private-key <admin_key> --rpc-url $RPC
```

---

## Guides & References

- [Foundry Developer Handbook](FOUNDRY_GUIDE.md) — Comprehensive guide on daily workflow, debugging traces, and Sepolia deployment.
- [Foundry Cheatcode Cheatsheet](vm-cheatsheet.md) — Reference for `vm` cheatcodes and testing patterns.

---

## License

This project is licensed under the [MIT License](LICENSE).
