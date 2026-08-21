// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Bank} from "../src/Bank.sol";

contract BankTest is Test {
    function testDeposit() public {
    Bank bank = new Bank();
    vm.deal(address(this), 1 ether);
    bank.deposit{value: 1 ether}();
    assertEq(bank.balances(address(this)), 1 ether);
}

function testDepositRevertsWhenZero() public {
    Bank bank = new Bank();
    vm.expectRevert("must send ETH");
    bank.deposit();
}

function testWithdraw() public {
    Bank bank = new Bank();
    vm.deal(address(this), 1 ether);
    bank.deposit{value: 1 ether}();
    bank.withdraw(0.5 ether);
    assertEq(bank.balances(address(this)), 0.5 ether);
}

function testWithdrawRevertsWhenInsufficient() public {
    Bank bank = new Bank();
    vm.expectRevert("insufficient balance");
    bank.withdraw(1 ether);
}
}
