// SPDX-License-Identifier: MIT

//Hanlder is gonna to narrow down the way we call function

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {OnChainStableCoin} from "../../src/OnChainStableCoin.sol";
import {OSCEngine} from "../../src/OSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";


contract Handler is Test{
    OSCEngine engine;
    OnChainStableCoin osc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // the max uint96 value
    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    mapping(address user => uint256 amount) public userToCollateralDeposited;
    
    //we are sending whole contract not address so there nor need to typecast it.
    constructor(OSCEngine _engine, OnChainStableCoin _osc){
        engine =_engine;
        osc = _osc;

        address[] memory collateralToken = engine.getCollateralTokens();
        weth = ERC20Mock(collateralToken[0]);
        wbtc = ERC20Mock(collateralToken[1]);

        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 collateralAmount) public{
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        collateralAmount = bound(collateralAmount, 1, MAX_DEPOSIT_SIZE);
        
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, collateralAmount);
        collateral.approve(address(engine),collateralAmount );
        engine.depositCollateral(address(collateral), collateralAmount);
        vm.stopPrank();

        if(userToCollateralDeposited[msg.sender] == 0 ){
            usersWithCollateralDeposited.push(msg.sender);
        }
        userToCollateralDeposited[msg.sender] += collateralAmount;
    }


    function redeemCollateral(uint256 collateralSeed, uint256 redeemAmount) public{
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        //we can't check if user try to redeem more than collateral in this invariant test.
        //but we can do if don not set the max maxCollateralToRedeem and set revert_on_fail to false.
        redeemAmount = bound(redeemAmount, 0, maxCollateralToRedeem);

        if(redeemAmount == 0){
            return;
        }

        vm.prank(msg.sender);
        engine.redeemCollateral(address(collateral), redeemAmount);
    }
    

    function mintOsc(uint256 oscAmount, uint256 addressSeed) public{
        //In invariant testing it calls the target handler contract or invariant_test with tons of sequence of functions and it also call with random addresses as well. 
        //we can hard code the msg.sender but it will just fails the purpose of invariant tesitng so that's why we are making our code this way.
        if(usersWithCollateralDeposited.length == 0){
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalOscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);
        int256 maxOscToMint = (int256(collateralValueInUsd) / 2) - int256(totalOscMinted);
        if(maxOscToMint < 0){
            return;
        }
        oscAmount = bound(oscAmount, 0, uint256(maxOscToMint));
        if(oscAmount == 0){
            return;
        }

        vm.prank(sender);
        engine.mintOsc(oscAmount);
        timesMintIsCalled++;
    }
    
    //THIS WILL BREAK OUR INVARIANT TEST SUITE BECAUSE IF COLLATERAL PRICE CRASHES.
    // function updateCollateralPrice(uint96 newPrice) public{
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt); 
    // }

    // Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns(ERC20Mock){
        if(collateralSeed % 2 ==0){
            return weth;
        }
        else{
            return wbtc;
        }
    }

    function MintIsCalled() public view returns(uint256){
        return timesMintIsCalled;
    }

}