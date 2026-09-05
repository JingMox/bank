# Foundry Cheatcode Cheatsheet (`vm` Guide)

> Reference Implementation: Bank & BigBank Smart Contract Test Suites
>
> Core Concept: `vm` is a special pre-set constant address in `Test.sol`. Foundry's EVM opens a privileged channel for it—calling it does not execute smart contract bytecode, but instead directly triggers EVM runtime hooks (modifying balances, altering caller identities, asserting reverts, etc.). On a live blockchain it is simply an empty address: **cheatcode capabilities exist strictly within the local test environment**.

## The Core Four-Step Pattern

| Step | Syntax | Purpose | Bank Contract Scenario |
|---|---|---|---|
| 1. Fund | `vm.deal(addr, 10 ether)` | Sets the ETH balance of `addr` to 10 ether (overwrite, not additive) | Fund test account before depositing |
| 2. Impersonate | `vm.prank(addr)` | Impersonates `addr` as `msg.sender` for the **very next** call | Submit transaction as `user1` |
| 3. Execute | `bank.deposit{value: 1 ether}()` | Executes through the **genuine EVM path**: `msg.value` deducts balance, contract state updates | Execute authentic state transition |
| 4. Assert | `assertEq(a, b)` | Asserts equality; fails the test on mismatch | Verify balance and leaderboard state |

Core takeaway: **The environment can be simulated, but business logic must execute genuinely.**

## Common Cheatcodes Overview

| Cheatcode | Purpose | Example |
|---|---|---|
| `vm.deal(addr, amount)` | Set ETH balance for `addr` (overwrite) | `vm.deal(user1, 10 ether)` |
| `vm.prank(addr)` | Impersonate `addr` for the next immediate call (one-shot) | `vm.prank(user1); bank.deposit{value: 1 ether}();` |
| `vm.startPrank(addr)` | Impersonate `addr` for all subsequent calls until `stopPrank` | Sequential operations from the same user |
| `vm.stopPrank()` | Terminate active `startPrank` impersonation | |
| `vm.expectRevert("msg")` | Assert next call reverts with exact error message | `vm.expectRevert("only admin can withdraw");` |
| `vm.expectRevert()` | Assert next call reverts regardless of message | When error message is unconstrained |
| `vm.expectEmit(...)` | Assert next call emits specified event | See event testing pattern below |
| `vm.assume(cond)` | Filter invalid inputs during fuzz testing | `vm.assume(amount > 0.001 ether)` |

Full reference: `lib/forge-std/src/Vm.sol` (interface definition), or the official documentation at https://book.getfoundry.sh/cheatcodes/

## Key Concepts & Common Pitfalls

### 1. `vm.deal` ≠ Transfer

`vm.deal` directly modifies the ledger balance within the testing EVM: **it produces no transaction, triggers no `receive()` hook, emits no events, and bypasses smart contract logic**.

To simulate an authentic user deposit, all three steps are required:

```solidity
vm.deal(user1, 10 ether);                 // 1. Fund test account (simulator)
vm.prank(user1);                          // 2. Impersonate caller (simulator)
bank.deposit{value: 1 ether}();           // 3. Execute call (genuine EVM path)
```

### 2. `prank` is One-Shot; `startPrank` Persists

```solidity
vm.prank(user1);                          // Only applies to the immediate next call
bank.deposit{value: 1 ether}();           // ✅ Recorded as user1
bank.deposit{value: 1 ether}();           // ❌ Reverts to test contract itself as caller!

vm.startPrank(user1);                     // Impersonates user1 for all subsequent calls
bank.deposit{value: 1 ether}();
bank.deposit{value: 1 ether}();           // ✅ Both calls executed as user1
vm.stopPrank();
```

### 3. `expectRevert` is a Precondition; Must Precede the Target Call

```solidity
vm.expectRevert("only admin can withdraw");  // Declare expectation first
bank.withdraw();                             // Target call must revert immediately
// No other calls may be placed in between, otherwise the revert expectation attaches to that call
```

### 4. `expectEmit`: Asserting Event Emissions

```solidity
event Deposit(address indexed user, uint256 amount);

vm.expectEmit(true, false, false, true);  // 4 booleans: check topic1 / topic2 / topic3 / data
emit Deposit(user1, 1 ether);             // Declare expected event signature & parameters
vm.prank(user1);
bank.deposit{value: 1 ether}();           // Actual execution must emit matching event
```

When in doubt, `(true, false, false, true)` matches indexed topic1 (e.g. user address) and unindexed event data (e.g. amount).

## Bank Testing Patterns & Idioms

```solidity
// Deposit balance verification
assertEq(bank.balances(user1), 0);        // Pre-deposit assertion
vm.deal(user1, 10 ether);
vm.prank(user1);
bank.deposit{value: 1 ether}();
assertEq(bank.balances(user1), 1 ether);  // Post-deposit assertion

// Unauthorized withdrawal rejection
vm.prank(user1);
vm.expectRevert("only admin can withdraw");
bank.withdraw();
```