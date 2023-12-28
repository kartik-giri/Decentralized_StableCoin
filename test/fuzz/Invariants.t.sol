// SPDX-License-Identifier: MIT

//Have our invarients ala properties hold always right.

//What are our Invarients??
//1.The total supplly of Stablecoin should be less than the collateral value.
//2.Getter view functions should never revert.<- evergreen invarient cause most protocol can have invarient that look like this.

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployOsc} from "../../script/DeployOsc.s.sol";
import {OnChainStableCoin} from "../../src/OnChainStableCoin.sol";
import {OSCEngine} from "../../src/OSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol"; 
import {Handler} from "./Handler.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//open Invarian testing it is calling seqeunce of functions randommly.
contract InvariantsTest is StdInvariant, Test{
    DeployOsc deployer;
    OSCEngine engine;
    OnChainStableCoin osc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;
    
    function setUp() public{
        deployer = new DeployOsc();
         (osc, engine, config) = deployer.run();
        (,, weth,wbtc,) = config.activeNetwork();
        //target contract is handler contract.
        handler = new Handler(engine, osc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreThanTotalSupply() public{
        //get the value of all the collateral in protocol.
        //compare with it to all the dept (osc).
        uint256 totalSupply = osc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth,totalWethDeposited );
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);
        
        uint256 times = handler.MintIsCalled();
        
        console.log("Weth value:", wethValue);
        console.log("Wbtc value:", wbtcValue);
        console.log("total Supply value:", totalSupply);
        console.log("Times mint function is called", times);
        assert (wethValue + wbtcValue >= totalSupply);
    }
    
    //the call to getters functions should not revert and always be true.
    function invariant_gettersShouldNotRevert() public view{
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        engine.getUsdValue(weth,totalWethDeposited);

        engine.getTokenAmountFromUsd(weth,engine.getUsdValue(weth,totalWethDeposited));
        engine.getPrecision();
        engine.getOSC();
        engine.getMinHealthFactor();
        engine.getLiquidationThreshold();
        engine.getLiquidationBonus();
        engine.getLiquidationPrecision();
        engine.getHealthFactor(msg.sender);
        engine.getCollateralTokens();
        engine.getCollateralTokenPriceFeed(weth);
        engine.getAdditionalFeedPrecision();
        engine.getAccountInformation(msg.sender);
        engine.getAccountCollateralValue(msg.sender);

    }
}
