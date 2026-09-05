// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Bank} from "../src/Bank.sol";

/// @title Bank Contract Specification & Verification Tests
/// @notice Covers 3 comprehensive verification suites:
///   1. Balance bookkeeping before and after deposits
///   2. Top 3 depositors ranking (1/2/3/4 users + multiple deposits by same user)
///   3. Access control & withdrawal permissions
contract BankChallengeTest is Test {
    Bank bank;
    address user1 = address(0xBEEF);
    address user2 = address(0xCAFE);
    address user3 = address(0xDEAD);
    address user4 = address(0xFEED);

    function setUp() public {
        bank = new Bank(); // Deployer = test contract = admin
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(user4, 100 ether);
    }

    /// Helper: deposit amount v as address u
    function _deposit(address u, uint256 v) internal {
        vm.prank(u);
        bank.deposit{value: v}();
    }

    // ============ Case 1: Deposit Balance Bookkeeping ============

    function testBalanceBeforeAndAfterDeposit() public {
        assertEq(bank.balances(user1), 0); // Before deposit
        _deposit(user1, 1 ether);
        assertEq(bank.balances(user1), 1 ether); // After deposit
        _deposit(user1, 2 ether);
        assertEq(bank.balances(user1), 3 ether); // Multiple deposits accumulate rather than overwrite
    }

    // ============ Case 2: Top 3 Depositors Leaderboard ============

    /// 1 user: ranks 1st, remaining 2 slots empty
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

    /// 2 users: sorted by deposited amount
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

    /// 3 users: descending balance order
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

    /// 3 users with equal deposits: updateTOPDepositors uses !(a < b), so later depositor takes priority
    function testTop3WithThreeUsersTie() public {
        _deposit(user1, 1 ether);
        _deposit(user2, 1 ether);
        _deposit(user3, 1 ether);

        (address[3] memory tops,) = bank.getTOP3Depositor();
        assertEq(tops[0], user3);
        assertEq(tops[1], user2);
        assertEq(tops[2], user1);
    }

    /// 4 users: 4th user with 4.5 ether evicts 3rd place with 3 ether
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

    /// Multiple deposits by same user: a user already in top 3 is not re-sorted on subsequent deposits,
    /// but getTOP3Depositor reads balance dynamically in real time
    function testTop3SameUserDepositsTwice() public {
        _deposit(user1, 3 ether);
        _deposit(user2, 5 ether); // Leaderboard: [user2, user1]
        _deposit(user1, 10 ether); // user1 total is 13 ether (highest), but already ranked -> not re-sorted

        (address[3] memory tops, uint256[3] memory amounts) = bank.getTOP3Depositor();
        assertEq(tops[0], user2);
        assertEq(amounts[0], 5 ether);
        assertEq(tops[1], user1);
        assertEq(amounts[1], 13 ether); // Amounts dynamically reflect cumulative total
        assertEq(tops[2], address(0));
    }

    // ============ Case 3: Withdrawal Access Control ============

    /// Admin (parameterless withdraw()) can sweep all funds
    function testOnlyAdminCanWithdrawAll() public {
        _deposit(user1, 2 ether);
        uint256 before = address(this).balance;
        bank.withdraw(); // Test contract is admin, called directly

        assertEq(address(bank).balance, 0);
        assertEq(address(this).balance, before + 2 ether);
    }

    /// Parameterless withdraw() by non-admin must revert
    function testNonAdminCannotWithdrawAll() public {
        _deposit(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert("only admin can withdraw");
        bank.withdraw();
    }

    /// Regular users cannot withdraw their entire balance (full balance withdrawal is admin-only)
    function testUserCannotWithdrawEntireBalance() public {
        _deposit(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert("only admin can withdraw all money");
        bank.withdraw(1 ether);
    }

    /// Partial balance withdrawal by regular users is permitted
    function testUserCanWithdrawPartial() public {
        _deposit(user1, 1 ether);
        vm.prank(user1);
        bank.withdraw(0.5 ether);

        assertEq(bank.balances(user1), 0.5 ether);
    }

    receive() external payable {}
}
