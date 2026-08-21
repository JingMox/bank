// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {BigBank, Admin} from "../src/BigBank.sol";
import {IBank} from "../src/Bank.sol";

contract BigBankTest is Test {
    BigBank bank;
    Admin adm;
    address user1 = address(0xBEEF);
    address user2 = address(0xCAFE);

    event Deposit(address indexed user, uint256 amount);

    function setUp() public {
        bank = new BigBank();
        adm = new Admin();
        bank.changeAdmin(address(adm)); // 管理员转移给 Admin 合约
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    function testAdminIsAdminContract() public view {
        assertEq(bank.admin(), address(adm));
        assertEq(bank.owner(), address(this));
    }

    function testDeposit() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        assertEq(bank.balances(user1), 1 ether);
    }

    // modifier 拦下不足 0.001 ether 的存款
    function testDepositTooSmallReverts() public {
        vm.prank(user1);
        vm.expectRevert("Deposit amount must greater than 0.001 ether");
        bank.deposit{value: 0.0005 ether}();
    }

    // 直接转账走 receive()，同样受限额约束
    function testReceiveDeposit() public {
        vm.prank(user1);
        (bool ok,) = address(bank).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(bank.balances(user1), 1 ether);
    }

    function testOnlyOwnerCanChangeAdmin() public {
        vm.prank(user1);
        vm.expectRevert("Only owner can change admin");
        bank.changeAdmin(user1);
    }

    function testChangeAdminRejectsZeroAddress() public {
        vm.expectRevert("New admin can not be zero address");
        bank.changeAdmin(address(0));
    }

    // 第 04 课核心：Admin 合约提走银行资金，再转给 owner
    function testAdminWithdrawFlow() public {
        vm.prank(user1);
        bank.deposit{value: 0.5 ether}();
        assertEq(address(bank).balance, 0.5 ether);

        adm.adminWithdraw(IBank(address(bank)));
        assertEq(address(bank).balance, 0);
        assertEq(address(adm).balance, 0.5 ether);

        uint256 before = address(this).balance;
        adm.withdrawToOwner();
        assertEq(address(adm).balance, 0);
        assertEq(address(this).balance, before + 0.5 ether);
    }

    function testAdminWithdrawRejectsNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert("Only admin can withdraw");
        adm.adminWithdraw(IBank(address(bank)));
    }

    function testTop3Ranking() public {
        vm.prank(user1);
        bank.deposit{value: 3 ether}();
        vm.prank(user2);
        bank.deposit{value: 1 ether}();

        (address[3] memory tops, uint256[3] memory amounts) = bank.getTOP3Depositor();
        assertEq(tops[0], user1);
        assertEq(amounts[0], 3 ether);
        assertEq(tops[1], user2);
        assertEq(amounts[1], 1 ether);
    }

    function testDepositEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Deposit(user1, 1 ether);
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
    }

    function testFuzz_Deposit(uint96 amount) public {
        vm.assume(amount > 0.001 ether);
        vm.deal(user1, amount);
        vm.prank(user1);
        bank.deposit{value: amount}();
        assertEq(bank.balances(user1), amount);
    }

    receive() external payable {}
}
