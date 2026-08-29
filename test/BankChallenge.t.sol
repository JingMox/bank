// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Bank} from "../src/Bank.sol";

/// @title Bank 合约挑战测试
/// @notice 覆盖三个 case：
///   1. 存款前后余额更新
///   2. TOP3 前三名（1/2/3/4 个用户 + 同一用户多次存款）
///   3. 只有管理员可取款
contract BankChallengeTest is Test {
    Bank bank;
    address user1 = address(0xBEEF);
    address user2 = address(0xCAFE);
    address user3 = address(0xDEAD);
    address user4 = address(0xFEED);

    function setUp() public {
        bank = new Bank(); // 部署者 = 本测试合约 = admin
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(user4, 100 ether);
    }

    /// 辅助：以 u 的身份存 v 金额
    function _deposit(address u, uint256 v) internal {
        vm.prank(u);
        bank.deposit{value: v}();
    }

    // ============ Case 1: 存款前后余额更新 ============

    function testBalanceBeforeAndAfterDeposit() public {
        assertEq(bank.balances(user1), 0); // 存款前
        _deposit(user1, 1 ether);
        assertEq(bank.balances(user1), 1 ether); // 存款后
        _deposit(user1, 2 ether);
        assertEq(bank.balances(user1), 3 ether); // 多次存款累加而非覆盖
    }

    // ============ Case 2: TOP3 前三名 ============

    /// 1 个用户：第一是他，其余两个空位
    function testTop3WithOneUser() public {
        _deposit(user1, 5 ether);

        (address[3] memory tops, uint256[3] memory amounts) = bank.getTOP3Depositor();
        assertEq(tops[0], user1);
        assertEq(amounts[0], 5 ether);
        assertEq(tops[1], address(0));
        assertEq(amounts[1], 0);
        assertEq(tops[2], address(0));
        assertEq(amounts[2], 0);
    }

    /// 2 个用户：按金额排序
    function testTop3WithTwoUsers() public {
        _deposit(user1, 3 ether);
        _deposit(user2, 1 ether);

        (address[3] memory tops, uint256[3] memory amounts) = bank.getTOP3Depositor();
        assertEq(tops[0], user1);
        assertEq(amounts[0], 3 ether);
        assertEq(tops[1], user2);
        assertEq(amounts[1], 1 ether);
        assertEq(tops[2], address(0));
    }

    /// 3 个用户（金额不同）
    function testTop3WithThreeUsers() public {
        _deposit(user1, 1 ether);
        _deposit(user2, 2 ether);
        _deposit(user3, 3 ether);

        (address[3] memory tops, uint256[3] memory amounts) = bank.getTOP3Depositor();
        assertEq(tops[0], user3);
        assertEq(amounts[0], 3 ether);
        assertEq(tops[1], user2);
        assertEq(amounts[1], 2 ether);
        assertEq(tops[2], user1);
        assertEq(amounts[2], 1 ether);
    }

    /// 3 个用户（金额并列）：updateTOPDepositors 用 !(a < b)，并列时后来居上
    function testTop3WithThreeUsersTie() public {
        _deposit(user1, 1 ether);
        _deposit(user2, 1 ether);
        _deposit(user3, 1 ether);

        (address[3] memory tops,) = bank.getTOP3Depositor();
        assertEq(tops[0], user3);
        assertEq(tops[1], user2);
        assertEq(tops[2], user1);
    }

    /// 4 个用户：第 4 人 4.5 ether 把第三名 3 ether 挤出去
    function testTop3WithFourUsers() public {
        _deposit(user1, 5 ether);
        _deposit(user2, 4 ether);
        _deposit(user3, 3 ether);
        _deposit(user4, 4.5 ether);

        (address[3] memory tops, uint256[3] memory amounts) = bank.getTOP3Depositor();
        assertEq(tops[0], user1);
        assertEq(amounts[0], 5 ether);
        assertEq(tops[1], user4);
        assertEq(amounts[1], 4.5 ether);
        assertEq(tops[2], user2);
        assertEq(amounts[2], 4 ether);
    }

    /// 同一用户多次存款：已在榜上的用户再存款不会重排（updateTOPDepositors 直接 return），
    /// 但 getTOP3Depositor 的金额是实时读 balances 的
    function testTop3SameUserDepositsTwice() public {
        _deposit(user1, 3 ether);
        _deposit(user2, 5 ether); // 榜：[user2, user1]
        _deposit(user1, 10 ether); // user1 总额 13，全场最高，但已在榜上 → 不重排

        (address[3] memory tops, uint256[3] memory amounts) = bank.getTOP3Depositor();
        assertEq(tops[0], user2);
        assertEq(amounts[0], 5 ether);
        assertEq(tops[1], user1);
        assertEq(amounts[1], 13 ether); // 金额实时反映累计总额
        assertEq(tops[2], address(0));
    }

    // ============ Case 3: 只有管理员可取款 ============

    /// 管理员（无参 withdraw()）可提走银行全部资金
    function testOnlyAdminCanWithdrawAll() public {
        _deposit(user1, 2 ether);
        uint256 before = address(this).balance;
        bank.withdraw(); // 测试合约即 admin，直接调

        assertEq(address(bank).balance, 0);
        assertEq(address(this).balance, before + 2 ether);
    }

    /// 非管理员调无参 withdraw() 必须回滚
    function testNonAdminCannotWithdrawAll() public {
        _deposit(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert("only admin can withdraw");
        bank.withdraw();
    }

    /// 用户不能取走自己的全部余额（全部余额 = 管理员特权）
    function testUserCannotWithdrawEntireBalance() public {
        _deposit(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert("only admin can withdraw all money");
        bank.withdraw(1 ether);
    }

    /// 但用户取走自己的部分余额是允许的
    function testUserCanWithdrawPartial() public {
        _deposit(user1, 1 ether);
        vm.prank(user1);
        bank.withdraw(0.5 ether);

        assertEq(bank.balances(user1), 0.5 ether);
    }

    receive() external payable {}
}