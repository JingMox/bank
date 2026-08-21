// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {BigBank, Admin} from "../src/BigBank.sol";

contract BigBankScript is Script {
    function run() external returns (BigBank bigBank, Admin adminContract) {
        vm.startBroadcast();

        bigBank = new BigBank();
        adminContract = new Admin();
        bigBank.changeAdmin(address(adminContract));

        vm.stopBroadcast();

        console.log("BigBank deployed at:", address(bigBank));
        console.log("Admin   deployed at:", address(adminContract));
    }
}
