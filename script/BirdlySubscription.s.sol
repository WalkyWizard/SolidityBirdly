pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BirdlySubscription} from "../src/BirdlySubscription.sol";

contract BirdlySubscriptionScript is Script {
    function setUp() public {}

    function run() public returns (BirdlySubscription subscription) {
        uint256 deployerPrivateKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );

        vm.startBroadcast(deployerPrivateKey);

        subscription = new BirdlySubscription();

        vm.stopBroadcast();

        console.log("BirdlySubscription deployed at:", address(subscription));
    }
}
