// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Bank} from "../src/Bank.sol";

contract BankTest is Test {
    Bank bank;
    address user1 = address(0xBEEF);
    address user2 = address(0xCAFE);

    function setUp() public {
        bank = new Bank(); // Test contract is the deployer, hence the admin
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    function testDeposit() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        assertEq(bank.balances(user1), 1 ether);
    }

    // Direct transfer to contract, triggers receive() fallback
    function testReceiveDeposit() public {
        vm.prank(user1);
        (bool ok,) = address(bank).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(bank.balances(user1), 1 ether);
    }

    function testWithdrawPartial() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        vm.prank(user1);
        bank.withdraw(0.5 ether);
        assertEq(bank.balances(user1), 0.5 ether);
        assertEq(user1.balance, 9.5 ether);
    }

    function testWithdrawRevertsWhenInsufficient() public {
        vm.prank(user1);
        vm.expectRevert("insufficient balance");
        bank.withdraw(1 ether);
    }

    // Withdrawing full balance is restricted to admin only
    function testUserCannotWithdrawEntireBalance() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        vm.prank(user1);
        vm.expectRevert("only admin can withdraw all money");
        bank.withdraw(1 ether);
    }

    // Admin-exclusive parameterless withdraw(), sweeps all contract funds
    function testAdminWithdrawAll() public {
        vm.prank(user1);
        bank.deposit{value: 2 ether}();
        uint256 before = address(this).balance;
        bank.withdraw();
        assertEq(address(bank).balance, 0);
        assertEq(address(this).balance, before + 2 ether);
    }

    function testAdminWithdrawAllRevertsForNonAdmin() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        vm.prank(user1);
        vm.expectRevert("only admin can withdraw");
        bank.withdraw();
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

    receive() external payable {}
}
