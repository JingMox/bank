## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

---

## 挑战测试（Bank 合约）

为 [decert.me Bank 合约挑战](https://decert.me/challenge/c43324bc-0220-4e81-b533-668fa644c1c3) 编写的测试：

- `test/BankChallenge.t.sol` — 挑战三个 case 全覆盖：
  1. **存款前后余额更新**：存款前为 0、存款后入账、多次存款累加而非覆盖
  2. **TOP3 前三名**：1 / 2 / 3 / 4 个用户、并列金额（后来居上）、同一用户多次存款（榜内不重排、金额实时更新）
  3. **只有管理员可取款**：admin 可提走全部；非 admin 无参取款回滚；用户不可取走全部余额、但可部分取款
- 运行日志见 `test.log`：**30 个用例全部通过，0 失败**

```bash
forge test -vv
```
