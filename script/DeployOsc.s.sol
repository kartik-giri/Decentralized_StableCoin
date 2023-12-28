// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {OnChainStableCoin} from "../src/OnChainStableCoin.sol";
import {OSCEngine} from "../src/OSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployOsc is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (OnChainStableCoin, OSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetwork();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast();
        OnChainStableCoin osc = new OnChainStableCoin();

        OSCEngine engine = new OSCEngine(
        tokenAddresses,
        priceFeedAddresses,
        address(osc)
      );
        osc.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (osc, engine, config);
    }
}
