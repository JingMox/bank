// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Bank, IBank} from "./Bank.sol";

contract BigBank is Bank {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    modifier depositAmountGreaterThan001() {
        require(msg.value > 0.001 ether, "Deposit amount must greater than 0.001 ether");
        _;
    }

    function deposit() external payable override depositAmountGreaterThan001 {
        _handleDeposit();
    }

    receive() external payable override {
        require(msg.value > 0.001 ether, "Deposit amount must greater than 0.001 ether");
        _handleDeposit();
    }

    function changeAdmin(address newAdmin) public {
        require(msg.sender == owner, "Only owner can change admin");
        require(newAdmin != address(0), "New admin can not be zero address");
        admin = newAdmin;
    }
}

contract Admin {
    address public immutable admin;

    receive() external payable {}

    constructor() {
        admin = msg.sender;
    }

    function adminWithdraw(IBank ibank) external {
        require(msg.sender == admin, "Only admin can withdraw");
        ibank.withdraw();
    }

    function withdrawToOwner() external {
        require(msg.sender == admin, "Only admin can withdraw");
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance can to withDraw");
        (bool success,) = admin.call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
