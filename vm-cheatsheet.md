# Foundry Cheatcode 速查表（vm 魔术笔）

> 配套练习：Bank 合约测试
>
> 一句话原理：`vm` 是 `Test.sol` 里预置的一个**特殊地址常量**，Foundry 的 EVM 对它开了特权通道——调用它不执行任何合约代码，而是直接执行内部功能（改余额、换身份、预判回滚……）。真实链上它只是一个空地址：**作弊能力只存在于测试环境**。

## 黄金套路：四动作

| 步骤 | 语法 | 干什么 | Bank 场景 |
|---|---|---|---|
| 1 发钱 | `vm.deal(addr, 10 ether)` | 把 addr 的 ETH 余额**设置**为 10 ether（覆盖式，不是 +10） | 用户兜里没钱就存不了款 |
| 2 换身份 | `vm.prank(addr)` | 下一笔调用伪装成 addr 发出（只生效一次） | 让 user1 去存款 |
| 3 调用 | `bank.deposit{value: 1 ether}()` | 走**真实 EVM 路径**：msg.value 真扣调用者余额、真更新合约状态 | 存款逻辑必须真实 |
| 4 对账 | `assertEq(a, b)` | 断言相等，不等则测试失败 | 余额是否如预期更新 |

精髓一句话：**环境可以作弊，逻辑必须真实。**

## 常用 cheatcode 一览

| cheatcode | 作用 | 示例 |
|---|---|---|
| `vm.deal(addr, amount)` | 设置 addr 的 ETH 余额（覆盖式） | `vm.deal(user1, 10 ether)` |
| `vm.prank(addr)` | 下一笔调用以 addr 身份发出（一次性） | `vm.prank(user1); bank.deposit{value: 1 ether}();` |
| `vm.startPrank(addr)` | 之后所有调用都以 addr 身份，直到 `stopPrank` | 同一个用户连续多次存款 |
| `vm.stopPrank()` | 结束 startPrank 的身份伪装 | |
| `vm.expectRevert("msg")` | 断言**下一笔**调用必然回滚，且错误信息匹配 | `vm.expectRevert("only admin can withdraw");` |
| `vm.expectRevert()` | 只断言会回滚，不校验信息 | 不关心报错文案时 |
| `vm.expectEmit(...)` | 断言下一笔调用发出某个事件 | 见下方案例 |
| `vm.assume(cond)` | fuzz 测试时过滤输入 | `vm.assume(amount > 0.001 ether)` |

完整列表：`lib/forge-std/src/Vm.sol`（接口定义），或文档 https://book.getfoundry.sh/cheatcodes/

## 高频易混点

### 1. vm.deal ≠ 转账

deal 只改测试环境里的一笔余额账：**不产生交易、不触发 receive()、不发事件、不经过合约任何代码**。

想模拟一笔真实存款，必须三步缺一不可：

```solidity
vm.deal(user1, 10 ether);                 // 发钱（作弊）
vm.prank(user1);                          // 换身份（作弊）
bank.deposit{value: 1 ether}();           // 调用（真实 EVM 路径）
```

### 2. prank 只生效一次，startPrank 一直生效

```solidity
vm.prank(user1);                          // 只伪装这一笔
bank.deposit{value: 1 ether}();           // ✅ 记在 user1 头上
bank.deposit{value: 1 ether}();           // ❌ 这笔记回测试合约自己头上！

vm.startPrank(user1);                     // 之后全部伪装成 user1
bank.deposit{value: 1 ether}();
bank.deposit{value: 1 ether}();           // ✅ 连续多笔都是 user1
vm.stopPrank();
```

### 3. expectRevert 是「预判」，必须紧贴下一笔调用

```solidity
vm.expectRevert("only admin can withdraw");  // 先立预判
bank.withdraw();                             // 下一笔必须回滚
// 中间不能插其他调用，否则预判会落到那一笔上
```

### 4. expectEmit：想断言「事件被发出」

```solidity
event Deposit(address indexed user, uint256 amount);

vm.expectEmit(true, false, false, true);  // 四个布尔 = 是否校验：签名/indexed/indexed/data
emit Deposit(user1, 1 ether);             // 声明「我期待这个事件」
vm.prank(user1);
bank.deposit{value: 1 ether}();           // 实际调用必须发出匹配的事件，否则断言失败
```

记不住四个布尔就照抄 `(true, false, false, true)`：签名和数据必须对，indexed 参数不校验。

## 本题（Bank 测试）组合拳

```solidity
// 存款前后余额
assertEq(bank.balances(user1), 0);        // 存款前对账
vm.deal(user1, 10 ether);
vm.prank(user1);
bank.deposit{value: 1 ether}();
assertEq(bank.balances(user1), 1 ether);  // 存款后对账

// 非管理员取款被拒
vm.prank(user1);
vm.expectRevert("only admin can withdraw");
bank.withdraw();
```