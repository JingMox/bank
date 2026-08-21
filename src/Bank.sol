// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IBank {
    function deposit() external payable;
    function getTOP3Depositor() external view returns (address[3] memory, uint256[3] memory);
    function withdraw(uint256 amount) external;
    function withdraw() external;
}

contract Bank is IBank {
    mapping(address => uint256) public balances;

    address[3] public TOPDepositor;
    address public admin;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    constructor() {
        admin = msg.sender;
    }

    receive() external payable virtual {
        _handleDeposit();
    }

    function deposit() external payable virtual {
        _handleDeposit();
    }

    function _handleDeposit() internal {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
        updateTOPDepositors(msg.sender);
    }

    function updateTOPDepositors(address depositor) internal {
        uint256 depositorBalance = balances[depositor];
        if (depositor == TOPDepositor[0] || depositor == TOPDepositor[1] || depositor == TOPDepositor[2]) {
            return;
        }

        if (!(depositorBalance < balances[TOPDepositor[0]])) {
            TOPDepositor[2] = TOPDepositor[1];
            TOPDepositor[1] = TOPDepositor[0];
            TOPDepositor[0] = depositor;
        } else if (!(depositorBalance < balances[TOPDepositor[1]])) {
            TOPDepositor[2] = TOPDepositor[1];
            TOPDepositor[1] = depositor;
        } else if (!(depositorBalance < balances[TOPDepositor[2]])) {
            TOPDepositor[2] = depositor;
        }
    }

    function getTOP3Depositor() external view returns (address[3] memory, uint256[3] memory) {
        uint256[3] memory amounts;
        for (uint8 i = 0; i < 3; i++) {
            amounts[i] = balances[TOPDepositor[i]];
        }
        return (TOPDepositor, amounts);
    }

    function withdraw() external {
        require(msg.sender == admin, "only admin can withdraw");
        uint256 bal = address(this).balance;
        require(bal > 0, "no balance");
        (bool ok,) = msg.sender.call{value: bal}("");
        require(ok, "transfer faild");
        emit Withdraw(msg.sender, bal);
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "insufficient balance");
        if (amount == balances[msg.sender]) {
            require(admin == msg.sender, "only admin can withdraw all money");
        }
        balances[msg.sender] -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "transfer faild");
        emit Withdraw(msg.sender, amount);
    }
}
