# Foundry Quickstart & Developer Handbook (BigBank Project)

> All commands in this guide have been verified against this project repository. Contract addresses correspond to local Anvil test environment deployments.

---

## 0. Project Structure

```
bank/
├── src/            Smart contract sources       Bank.sol / BigBank.sol
├── test/           Automated test suites        *.t.sol (Primary development area)
├── script/         Deployment scripts           *.s.sol
├── lib/            Dependencies (git submodule) forge-std / openzeppelin-contracts
├── out/            Build artifacts (auto-generated, safe to delete)
├── cache/          Build cache (auto-generated, safe to delete)
├── broadcast/      Deployment transaction logs
├── foundry.toml    Foundry project configuration
└── remappings.txt  Import path remappings
```

If artifacts or cache become stale or corrupted, simply run `forge clean`.

---

## 1. Daily Development Loop

Run this single command in a dedicated terminal during development to automatically rerun tests on file saves:

```bash
forge test --watch -vvv
```

The core workflow:
Modify contracts in `src/` → automatic compilation → automatic test execution in `test/` → inspect traces on failure → patch code → rerun. No local nodes, manual deployments, or manual transactions needed during core development.

### Common Commands

| Command | Description |
|---|---|
| `forge build` | Compile contracts and verify syntax / type correctness |
| `forge build --sizes` | Compile and display contract bytecode sizes (24KB limit on Ethereum mainnet) |
| `forge test` | Run entire test suite |
| `forge test --match-test testDeposit` | Run only test functions matching the given name |
| `forge test --match-path test/Bank.t.sol` | Run tests within a specific test file |
| `forge fmt` | Format code (enforced in CI via `forge fmt --check`) |
| `forge clean` | Purge `out/` and `cache/` directories |
| `forge coverage` | Generate test coverage reports |
| `forge test --gas-report` | Generate gas consumption table per function |

### Verbosity Levels

| Flag | Output Detail |
|---|---|
| `forge test` | Summary only (`PASS` / `FAIL`) |
| `-vv` | Includes console output and `console.log` statements |
| `-vvv` | Full execution trace for **failing tests** (Recommended default) |
| `-vvvv` | Full execution traces for all tests (including passing tests) |

---

## 2. Writing Robust Tests

### File Structure & Conventions

Test files are placed in `test/`, named `*.t.sol`, and test function names must begin with `test`.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {BigBank, Admin} from "../src/BigBank.sol";
import {IBank} from "../src/Bank.sol";

contract BigBankTest is Test {
    BigBank bank;
    Admin adm;
    address user1 = address(0xBEEF);
    address user2 = address(0xCAFE);

    // setUp() executes before every individual test function,
    // ensuring an isolated, pristine blockchain state for each test.
    function setUp() public {
        bank = new BigBank();
        adm = new Admin();
        bank.changeAdmin(address(adm));
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    function testDeposit() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        assertEq(bank.balances(user1), 1 ether);
    }

    // Crucial: The test contract must accept ETH, otherwise withdrawals back to this contract will revert
    receive() external payable {}
}
```

> [!IMPORTANT]
> **Always ensure your test contract implements `receive() external payable {}`** if it will receive ETH (e.g. testing withdrawal functions). If the contract cannot accept ETH, transfers back to the test contract will revert with `transfer faild`.

### Assertions

```solidity
assertEq(a, b);                  // Equality check
assertEq(a, b, "Balance mismatch"); // Custom failure message (strongly recommended)
assertTrue(cond);
assertFalse(cond);
assertGt(a, b);                  // a > b
assertGe(a, b);                  // a >= b
assertLt(a, b);  assertLe(a, b);
assertApproxEqAbs(a, b, 1);      // Absolute delta tolerance (useful for rounding/precision)
```

### Cheatcodes (`vm.*`)

Cheatcodes provide EVM-level control within the test environment:

| Cheatcode | Purpose |
|---|---|
| `vm.deal(addr, 1 ether)` | Sets ETH balance of target address |
| `vm.prank(addr)` | Impersonates `addr` for the **next immediate** call |
| `vm.startPrank(addr)` / `vm.stopPrank()` | Impersonates `addr` across multiple sequential calls |
| `vm.expectRevert("error msg")` | Asserts next call reverts with matching error message |
| `vm.expectEmit(true, false, false, true)` | Asserts next call emits the expected event |
| `vm.warp(block.timestamp + 1 days)` | Fast-forwards block timestamp |
| `vm.roll(block.number + 100)` | Fast-forwards block number |
| `vm.assume(x > 0)` | Filters out invalid inputs during fuzz testing |
| `vm.label(addr, "Alice")` | Labels an address for readable call stack traces |

Note that `vm.prank` only applies to the **single next call**. For multiple calls in sequence, use `vm.startPrank` and `vm.stopPrank`.

### Practical Test Examples from BigBank

**1. Testing Minimum Deposit Modifiers:**

```solidity
function testDepositTooSmallReverts() public {
    vm.prank(user1);
    vm.expectRevert("Deposit amount must greater than 0.001 ether");
    bank.deposit{value: 0.0005 ether}();
}
```

The error string in `vm.expectRevert` must match the `require` error message exactly.

**2. Testing Fallback / Direct ETH Transfers (`receive`):**

```solidity
function testReceiveDeposit() public {
    vm.prank(user1);
    (bool ok,) = address(bank).call{value: 1 ether}("");
    assertTrue(ok);
    assertEq(bank.balances(user1), 1 ether);
}
```

**3. Testing Access Control:**

```solidity
function testOnlyOwnerCanChangeAdmin() public {
    vm.prank(user1); // Impersonate non-owner user
    vm.expectRevert("Only owner can change admin");
    bank.changeAdmin(user1);
}
```

**4. Testing Full Administrative Withdrawal Flow (Contract-Controlled Admin Pattern):**

```solidity
function testAdminWithdrawFlow() public {
    vm.prank(user1);
    bank.deposit{value: 0.5 ether}();
    assertEq(address(bank).balance, 0.5 ether);

    adm.adminWithdraw(IBank(address(bank))); // Admin contract sweeps funds from BigBank
    assertEq(address(bank).balance, 0);
    assertEq(address(adm).balance, 0.5 ether);

    uint256 before = address(this).balance;
    adm.withdrawToOwner();                   // Admin contract forwards funds to owner
    assertEq(address(this).balance, before + 0.5 ether);
}
```

**5. Testing Top 3 Depositor Ranking:**

```solidity
function testTop3Ranking() public {
    vm.prank(user1); bank.deposit{value: 3 ether}();
    vm.prank(user2); bank.deposit{value: 1 ether}();

    (address[3] memory tops, uint256[3] memory amounts) = bank.getTOP3Depositor();
    assertEq(tops[0], user1);
    assertEq(amounts[0], 3 ether);
}
```

**6. Testing Event Emissions:**

```solidity
function testDepositEmitsEvent() public {
    vm.expectEmit(true, false, false, true); // Check topic1 (indexed user) and data (amount)
    emit Deposit(user1, 1 ether);            // Declare expected event signature and parameters
    vm.prank(user1);
    bank.deposit{value: 1 ether}();          // Trigger actual call
}

event Deposit(address indexed user, uint256 amount); // Re-declared in test contract
```

### Fuzz Testing

When a test function accepts parameters, Foundry executes property-based fuzzing with pseudo-random inputs (default: **256 runs**):

```solidity
function testFuzz_Deposit(uint96 amount) public {
    vm.assume(amount > 0.001 ether); // Filter inputs that violate the modifier
    vm.deal(user1, amount);
    vm.prank(user1);
    bank.deposit{value: amount}();
    assertEq(bank.balances(user1), amount);
}
```

Using `uint96` instead of `uint256` prevents astronomical integer values that could overflow total ether balance in `vm.deal`.

You can also use `bound` to clamp values into an acceptable range:

```solidity
amount = bound(amount, 0.002 ether, 100 ether);
```

To configure run counts: `forge test --fuzz-runs 10000`

---

## 3. Debugging

### Interpreting Call Stack Traces (`-vvv`)

Example failure trace:

```
[FAIL: transfer faild] testWithdraw()
    ├─ [8790] Bank::withdraw(500000000000000000)
    │   ├─ [43] BankTest::fallback{value: 500000000000000000}()
    │   │   └─ ← [Revert] EvmError: Revert         ← Root failure location
    │   └─ ← [Revert] transfer faild
```

How to read:
- Indentation reflects execution call depth.
- Numbers like `[8790]` indicate gas consumed by that call.
- `← [Return]` / `← [Stop]` denote clean completion; `← [Revert]` indicates a reverted call.
- **Inspect from the innermost `Revert` outward** to identify root causes. In the above trace, the test contract lacked a `receive()` function and could not accept ETH.

### Console Logging

```solidity
import {Test, console} from "forge-std/Test.sol";

console.log("balance:", bank.balances(user1));
console.log("addr:", user1);
console.logBytes32(someHash);
```

View output with `forge test -vv`. Ensure console logs are removed before production deployment to conserve gas.

### Interactive Debugger

Launch the opcode-level TUI debugger to inspect stack, memory, and storage:

```bash
forge test --debug testWithdraw
```

### Replaying On-Chain Transactions

To diagnose a transaction that failed on a testnet or mainnet, replay it locally with full traces:

```bash
cast run <tx_hash> --rpc-url $RPC
```

Add `-d` to open the replayed transaction directly in the interactive debugger.

---

## 4. Deployment

### Deployment Script

`script/BigBank.s.sol`: operations between `vm.startBroadcast()` and `vm.stopBroadcast()` will be recorded and broadcast on-chain:

```solidity
contract BigBankScript is Script {
    function run() external returns (BigBank bigBank, Admin adminContract) {
        vm.startBroadcast();
        bigBank = new BigBank();
        adminContract = new Admin();
        bigBank.changeAdmin(address(adminContract));
        vm.stopBroadcast();
        console.log("BigBank deployed at:", address(bigBank));
    }
}
```

### Step 1: Local Simulation (Dry Run)

Simulates script execution in an ephemeral EVM without broadcasting transactions:

```bash
forge script script/BigBank.s.sol:BigBankScript
```

### Step 2: Deployment to Local Anvil Node

Terminal A: Start the local Anvil node:

```bash
anvil
```

Terminal B: Deploy contracts using Anvil default account #0:

```bash
forge script script/BigBank.s.sol:BigBankScript --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
```

### Step 3: Deployment to Sepolia Testnet

Import private key into an encrypted keystore:

```bash
cast wallet import deployer --interactive
```

Configure `SEPOLIA_RPC_URL` and `ETHERSCAN_API_KEY` in `.env`, then execute:

```bash
source .env && forge script script/BigBank.s.sol:BigBankScript --rpc-url $SEPOLIA_RPC_URL --account deployer --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

`--verify` automatically publishes and verifies the source code on Etherscan. Deployment logs are saved to `broadcast/BigBank.s.sol/<chainId>/run-latest.json`.

---

## 5. Interacting with Contracts via `cast`

`cast` is a command-line utility for interacting with contracts on live chains (local Anvil, testnets, or mainnets).

Set environment variables:

```bash
export RPC=http://127.0.0.1:8545
export BIGBANK=0x5FbDB2315678afecb367f032d93F642f64180aa3
export ADMIN=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
export K0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### Read Operations: `cast call` (Gas-free)

```bash
cast call $BIGBANK "admin()(address)" --rpc-url $RPC
cast call $BIGBANK "balances(address)(uint256)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url $RPC
cast call $BIGBANK "getTOP3Depositor()(address[3],uint256[3])" --rpc-url $RPC
```

### Write Operations: `cast send` (Broadcasts Transactions)

```bash
# Deposit ETH (calls deposit())
cast send $BIGBANK "deposit()" --value 0.5ether --private-key $K0 --rpc-url $RPC

# Direct ETH transfer (triggers receive())
cast send $BIGBANK --value 0.01ether --private-key $K0 --rpc-url $RPC

# Admin withdrawal flow via the Admin contract
cast send $ADMIN "adminWithdraw(address)" $BIGBANK --private-key $K0 --rpc-url $RPC
cast send $ADMIN "withdrawToOwner()" --private-key $K0 --rpc-url $RPC
```

### Utilities

```bash
cast balance $BIGBANK --rpc-url $RPC --ether     # Check ETH balance of contract
cast receipt <tx_hash> --rpc-url $RPC            # Query transaction receipt
cast storage $BIGBANK 0 --rpc-url $RPC           # Inspect storage slot 0
cast sig "deposit()"                             # Calculate 4-byte function selector
cast 4byte-decode 0xd0e30db0                     # Lookup function name by selector
forge inspect BigBank abi                        # Output ABI definition
```

---

## 6. Common Pitfalls & Solutions

| Symptom | Cause | Solution |
|---|---|---|
| VS Code does not show compilation errors | Extension only validates open tabs and workspace root must match project root | Trust `forge build` as single source of truth; run `forge test --watch` |
| `Error: Max retries exceeded HTTP error 503` | Proxy intercepting local `127.0.0.1` requests | Add `export no_proxy=localhost,127.0.0.1,::1` to proxy configuration |
| `error: required arguments were not provided: <PATH>` | `forge script` requires explicit format `path:ContractName` | Use `forge script script/BigBank.s.sol:BigBankScript` |
| `Trying to override non-virtual function` | Parent contract function lacks `virtual` specifier | Add `virtual` to base contract function, `override` to child contract function |
| `Cannot write to immutable here` | `immutable` variables may only be assigned during declaration or inside constructor | Use standard state variable if modification is required post-construction |
| `Revert: transfer faild` | Recipient address or test contract lacks `receive()` / fallback | Add `receive() external payable {}` to the receiving contract |
| Subsequent errors disappear after syntax error | Solidity compiler halts on first syntax error | Fix errors sequentially with repeated `forge build` runs |
| Stale errors persist after edits | Outdated build artifacts or cache | Run `forge clean && forge build` |

---

## 7. Recommended Workflow Summary

```
1. Contract Implementation  -> src/
2. Test Suite Engineering  -> test/ (Primary focus)
3. forge test -vvv         -> Red -> Inspect trace -> Patch -> Repeat loop
4. forge script            -> Local EVM simulation
5. anvil + --broadcast     -> Local node deployment verification
6. cast call/send          -> Live contract interaction & verification
7. Sepolia + --verify      -> Testnet deployment & Etherscan verification
```

**Guiding Principle**: Prioritize automated test coverage over manual command-line checks. Automated tests are repeatable, CI-compatible, deterministic, and serve as verifiable documentation of contract behavior.
