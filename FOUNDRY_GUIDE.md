# Foundry 速查手册（BigBank 工程）

> 本文里所有命令都在这个工程上实际跑通过。合约地址取自本地 anvil 的部署结果。

---

## 0. 工程结构

```
BigBank/
├── src/            合约源码       Bank.sol / BigBank.sol
├── test/           测试代码       *.t.sol      ← 日常主战场
├── script/         部署脚本       *.s.sol
├── lib/            依赖（git submodule）forge-std / openzeppelin-contracts
├── out/            编译产物（自动生成，可删）
├── cache/          编译缓存（自动生成，可删）
├── broadcast/      部署交易记录
├── foundry.toml    工程配置
└── remappings.txt  import 路径映射
```

`out/` 和 `cache/` 出问题时直接 `forge clean` 重来。

---

## 1. 日常开发循环 ★ 最重要

**95% 的时间只用这一条命令**。开一个终端挂着，保存文件自动重跑：

```bash
forge test --watch -vvv
```

流程是：改 `src/` 里的合约 → 自动编译 → 自动跑 `test/` 里所有测试 → 红了看 trace → 改 → 再跑。全程不需要 anvil、不需要部署、不需要 cast。

### 单独命令

| 命令 | 作用 |
|---|---|
| `forge build` | 只编译，看有没有语法/类型错误 |
| `forge build --sizes` | 编译并显示合约字节码大小（主网上限 24KB） |
| `forge test` | 跑所有测试 |
| `forge test --match-test testDeposit` | 只跑名字匹配的测试函数 |
| `forge test --match-path test/Bank.t.sol` | 只跑某个文件 |
| `forge fmt` | 格式化代码（CI 会用 `forge fmt --check` 卡你） |
| `forge clean` | 清空 out/ 和 cache/ |
| `forge coverage` | 测试覆盖率 |
| `forge test --gas-report` | 每个函数的 gas 消耗表 |

### verbosity 分级 ★ 调试全靠它

| 级别 | 显示什么 |
|---|---|
| `forge test` | 只有 PASS / FAIL |
| `-vv` | 加上 `console.log` 的输出 |
| `-vvv` | **失败用例**的完整调用栈 trace ← 最常用 |
| `-vvvv` | 所有用例的 trace（含成功的） |

---

## 2. 怎么写测试

### 文件骨架

测试文件放 `test/`，命名 `xxx.t.sol`，测试函数必须以 `test` 开头。

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

    // 每个 test 函数跑之前都会重新执行一次 setUp
    // 也就是说：每个测试都从全新的链状态开始，互不干扰
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

    // 这个合约要能收 ETH，否则 withdraw 打钱回来会 revert
    receive() external payable {}
}
```

**`receive() external payable {}` 这行别忘**。测试合约本身如果收不了 ETH，任何"把钱转回来"的测试都会挂在 `transfer faild` 上——这个坑本工程踩过两次（一次在 `Admin` 合约，一次在 `BankTest`）。

### 断言

```solidity
assertEq(a, b);                  // 相等
assertEq(a, b, "余额不对");       // 带失败提示，强烈建议写
assertTrue(cond);
assertFalse(cond);
assertGt(a, b);                  // a > b
assertGe(a, b);                  // a >= b
assertLt(a, b);  assertLe(a, b);
assertApproxEqAbs(a, b, 1);      // 允许误差，处理精度问题时用
```

### Cheatcodes（`vm.*`）★ 测试的核心

这是 Foundry 给你的"上帝权限"，能构造任何场景。

| Cheatcode | 作用 |
|---|---|
| `vm.deal(addr, 1 ether)` | 凭空给地址塞 ETH |
| `vm.prank(addr)` | 伪装成 addr 发起**下一次**调用 |
| `vm.startPrank(addr)` / `vm.stopPrank()` | 伪装成 addr 发起**接下来多次**调用 |
| `vm.expectRevert("错误信息")` | 断言下一次调用会 revert，且信息匹配 |
| `vm.expectEmit(true,false,false,true)` | 断言下一次调用会抛出指定事件 |
| `vm.warp(block.timestamp + 1 days)` | 快进时间 |
| `vm.roll(block.number + 100)` | 快进区块号 |
| `vm.assume(x > 0)` | fuzz 测试里排除不想要的输入 |
| `vm.label(addr, "Alice")` | 给地址起名字，trace 里更好读 |

`vm.prank` 只对**紧接着的一次**调用生效，这是最常见的误用点。要连续多次就用 `startPrank`。

### 针对 BigBank 的实际用例

**测 modifier 限额：**

```solidity
function testDepositTooSmallReverts() public {
    vm.prank(user1);
    vm.expectRevert("Deposit amount must greater than 0.001 ether");
    bank.deposit{value: 0.0005 ether}();
}
```

`vm.expectRevert` 的字符串必须和合约里 `require` 的第二个参数**一字不差**。

**测 receive() 分支**（直接转账，不调函数）：

```solidity
function testReceiveDeposit() public {
    vm.prank(user1);
    (bool ok,) = address(bank).call{value: 1 ether}("");
    assertTrue(ok);
    assertEq(bank.balances(user1), 1 ether);
}
```

**测权限控制：**

```solidity
function testOnlyOwnerCanChangeAdmin() public {
    vm.prank(user1);                                    // 冒充普通用户
    vm.expectRevert("Only owner can change admin");
    bank.changeAdmin(user1);
}
```

**测完整的管理员提款链路**（作业第 04 课的核心要求）：

```solidity
function testAdminWithdrawFlow() public {
    vm.prank(user1);
    bank.deposit{value: 0.5 ether}();
    assertEq(address(bank).balance, 0.5 ether);

    adm.adminWithdraw(IBank(address(bank)));            // Admin 合约收走银行的钱
    assertEq(address(bank).balance, 0);
    assertEq(address(adm).balance, 0.5 ether);

    uint256 before = address(this).balance;
    adm.withdrawToOwner();                              // Admin 再转给 owner
    assertEq(address(this).balance, before + 0.5 ether);
}
```

**测 TOP3 榜单：**

```solidity
function testTop3Ranking() public {
    vm.prank(user1); bank.deposit{value: 3 ether}();
    vm.prank(user2); bank.deposit{value: 1 ether}();

    (address[3] memory tops, uint256[3] memory amounts) = bank.getTOP3Depositor();
    assertEq(tops[0], user1);
    assertEq(amounts[0], 3 ether);
}
```

**测事件：**

```solidity
function testDepositEmitsEvent() public {
    vm.expectEmit(true, false, false, true);   // 校验 topic1(indexed user) 和 data(amount)
    emit Deposit(user1, 1 ether);              // 先声明"期望长这样"
    vm.prank(user1);
    bank.deposit{value: 1 ether}();            // 再执行真实调用
}

event Deposit(address indexed user, uint256 amount);   // 需要在测试合约里重新声明一遍
```

四个 bool 依次是：是否校验 topic1 / topic2 / topic3 / data。

### Fuzz 测试 ★ Foundry 的招牌

函数带参数，Foundry 就自动灌随机值进去，默认 **256 轮**。找边界 bug 比手写用例强得多，而且你不用想测试数据。

```solidity
function testFuzz_Deposit(uint96 amount) public {
    vm.assume(amount > 0.001 ether);       // 排除会被 modifier 拦下的值
    vm.deal(user1, amount);
    vm.prank(user1);
    bank.deposit{value: amount}();
    assertEq(bank.balances(user1), amount);
}
```

用 `uint96` 而不是 `uint256`，是为了避免生成天文数字导致 `vm.deal` 溢出。

也可以用 `bound` 把值压进区间，比 `vm.assume` 效率高（`assume` 是丢弃重来，`bound` 是映射）：

```solidity
amount = bound(amount, 0.002 ether, 100 ether);
```

调轮数：`forge test --fuzz-runs 10000`

---

## 3. 调试

### 读懂 trace（`-vvv`）

真实例子，本工程的失败测试：

```
[FAIL: transfer faild] testWithdraw()
    ├─ [8790] Bank::withdraw(500000000000000000)
    │   ├─ [43] BankTest::fallback{value: 500000000000000000}()
    │   │   └─ ← [Revert] EvmError: Revert         ← 真正的失败点在这层
    │   └─ ← [Revert] transfer faild
```

读法：
- 树形结构 = 调用层级，缩进越深越里层
- `[8790]` = 这次调用消耗的 gas
- `← [Return]` / `← [Stop]` = 正常返回；`← [Revert]` = 回滚
- **从最里层的 Revert 往外看**，那才是根因。上面这例：`BankTest` 没有 `receive()`，收不了 ETH

### console.log 打印变量

```solidity
import {Test, console} from "forge-std/Test.sol";

console.log("balance:", bank.balances(user1));
console.log("addr:", user1);
console.logBytes32(someHash);
```

用 `forge test -vv` 查看输出。合约源码里也能用，但**部署到主网前一定要删掉**（费 gas）。

### 单步调试器

opcode 级别的 TUI，能看栈、内存、storage：

```bash
forge test --debug testWithdraw
```

平时用不上，逻辑彻底卡死时很管用。

### 重放线上失败的交易

测试网/主网上某笔交易失败了，把哈希丢给它，本地重放并打出完整 trace：

```bash
cast run <交易哈希> --rpc-url $RPC
```

加 `-d` 直接把这笔真实交易开进调试器。

---

## 4. 部署

### 部署脚本

`script/BigBank.s.sol`，`vm.startBroadcast()` 和 `vm.stopBroadcast()` 之间的操作会被真实广播上链：

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

### 第一步：本地模拟（不上链）

不需要 anvil，不需要私钥，只在临时 EVM 里跑一遍验证逻辑：

```bash
forge script script/BigBank.s.sol:BigBankScript
```

### 第二步：部署到本地 anvil

终端 A 启动本地节点（一直开着）：

```bash
anvil
```

终端 B 部署（`--broadcast` 才是真发交易）：

```bash
forge script script/BigBank.s.sol:BigBankScript --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
```

那个私钥是 anvil 内置的测试账户 #0，公开的，**只能本地用**。

anvil 一重启数据全清空，要重新部署。因为地址由 `部署者 + nonce` 确定性算出，只要部署顺序不变，合约地址不变。

### 第三步：部署到 Sepolia 测试网

先把私钥存进加密 keystore（别在命令行里明文写私钥）：

```bash
cast wallet import deployer --interactive
```

在 `.env` 里放 `SEPOLIA_RPC_URL` 和 `ETHERSCAN_API_KEY`（`.gitignore` 已忽略 `.env`），然后：

```bash
source .env && forge script script/BigBank.s.sol:BigBankScript --rpc-url $SEPOLIA_RPC_URL --account deployer --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

`--verify` 会自动在 Etherscan 上开源验证。部署记录写在 `broadcast/BigBank.s.sol/<chainId>/run-latest.json`。

---

## 5. cast：和已部署的合约交互

**注意定位**：cast 用来戳"已经在链上的合约"，是验收和运维工具，**不是开发调试工具**。日常开发靠 `forge test`。

先设变量（地址取自本工程 anvil 部署结果）：

```bash
export RPC=http://127.0.0.1:8545 BIGBANK=0x5FbDB2315678afecb367f032d93F642f64180aa3 ADMIN=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 K0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 读：`cast call`（不花 gas，不上链）

函数签名要写全，返回类型写在括号里，cast 才知道怎么解码：

```bash
cast call $BIGBANK "admin()(address)" --rpc-url $RPC
cast call $BIGBANK "balances(address)(uint256)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 --rpc-url $RPC
cast call $BIGBANK "getTOP3Depositor()(address[3],uint256[3])" --rpc-url $RPC
```

### 写：`cast send`（发交易，要私钥）

```bash
# 存款，--value 就是 msg.value
cast send $BIGBANK "deposit()" --value 0.5ether --private-key $K0 --rpc-url $RPC

# 不写函数名、只带 --value → 走 receive() 分支
cast send $BIGBANK --value 0.01ether --private-key $K0 --rpc-url $RPC

# 管理员提款：发给 Admin 合约，不是 BigBank
# 参数类型 IBank 在 ABI 里就是 address
cast send $ADMIN "adminWithdraw(address)" $BIGBANK --private-key $K0 --rpc-url $RPC
cast send $ADMIN "withdrawToOwner()" --private-key $K0 --rpc-url $RPC
```

### 其他常用

```bash
cast balance $BIGBANK --rpc-url $RPC --ether     # 合约持有多少 ETH
cast receipt <交易哈希> --rpc-url $RPC            # 看某笔交易的回执
cast storage $BIGBANK 0 --rpc-url $RPC           # 直接读 storage 槽位
cast sig "deposit()"                             # 算函数选择器
cast 4byte-decode 0xd0e30db0                     # 反查选择器是哪个函数
forge inspect BigBank abi                        # 忘了函数签名就打 ABI
```

---

## 6. 踩过的坑对照表

| 现象 | 原因 | 解决 |
|---|---|---|
| VS Code 不报编译错误 | 插件只校验**打开的标签页**、只报**第一个**错误，且工作区根目录开错层 | 以 `forge build` 为准，用 `--watch` 挂着 |
| `Error: Max retries exceeded HTTP error 503` | `proxy_on` 没设 `no_proxy`，本地 127.0.0.1 请求被丢给代理 | `proxy_on()` 里加 `export no_proxy=localhost,127.0.0.1,::1` |
| `error: required arguments were not provided: <PATH>` | `forge script` 必须指定 `路径:合约名` | `forge script script/BigBank.s.sol:BigBankScript` |
| `Trying to override non-virtual function` | 父合约的函数要被子合约 override，必须标 `virtual` | 父类加 `virtual`，子类加 `override` |
| `Cannot write to immutable here` | `immutable` 只能在声明时或构造函数里赋值 | 需要后续修改就去掉 `immutable` |
| `Revert: transfer faild` | 收款方合约没有 `receive()`，收不了 ETH | 给合约加 `receive() external payable {}` |
| `Expected ';' but got '{'` 之后错误全消失 | 语法错误会让编译器**停在第一个错**，后面的看不到 | 一个个改，反复 `forge build` |
| 改完还是老错误 | 编译缓存 | `forge clean && forge build` |

---

## 7. 最小工作流总结

```
1. 写合约            src/
2. 写测试            test/          ← 大部分时间在这
3. forge test -vvv   红→看trace→改→再跑，循环
4. forge script      本地模拟
5. anvil + --broadcast   本地真部署
6. cast call/send    验收演示
7. Sepolia + --verify    交作业
```

**核心心法**：能用测试验证的，就别手敲命令。测试能重复跑、能进 CI、能自动断言对错；手敲的命令改一行代码就全废了。
