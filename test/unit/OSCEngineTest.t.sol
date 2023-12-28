// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployOsc} from "../../script/DeployOsc.s.sol";
import {OnChainStableCoin} from "../../src/OnChainStableCoin.sol";
import {OSCEngine} from "../../src/OSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtOSC} from "../mocks/MockMoreDebtOSC.sol";
contract OSCEngineTest is Test {
    DeployOsc deployer;
    OnChainStableCoin osc;
    OSCEngine engine;
    HelperConfig config;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public collateralToCover = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 5 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 5 ether;
    uint256 public constant MINTED_OSC = 2000 ether;
    uint256 public constant REDEEMED_COLLATERAL = 2 ether;
    uint256 public constant REDEEMED_COLLATERAL_BREAKSHEALTHFACTOR = 4 ether;
    uint256 public constant BURN_OSC = 1000 ether;
     uint256 public constant MIN_HEALTH_FACTOR = 1e18;
      uint256 public constant LIQUIDATION_THRESHOLD = 50;

    function setUp() public {
        deployer = new DeployOsc();
        (osc, engine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth,,) = config.activeNetwork();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////////
    ///CONSTRUCTOR TEST///
    //////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedsAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedsAddresses.push(wethUsdPriceFeed);
        priceFeedsAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(OSCEngine.OSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new OSCEngine(tokenAddresses, priceFeedsAddresses, address(osc));
    }

    //////////////////////
    // USD Price Test////
    /////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18; //15 Weth
        // 15e18 * 2000/Eth = 30,000e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testgetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // if $2000eth /$100 =
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ////////////////////////////
    // depositCollateral Test////
    /////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER); //tx will be done by user address
        //Before calling depositCollateral we have to approve the allowance first!
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(OSCEngine.OSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfTokenIsNotAllowed() public {
        ERC20Mock randomToken = new ERC20Mock();
        randomToken.mint(USER, 10);
        vm.startPrank(USER);
        //Before calling depositCollateral we have to approve the allowance first!
        ERC20Mock(randomToken).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(OSCEngine.OSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(randomToken), 2);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testdepositCollateral() public depositCollateral {
        (uint256 totalOscMinted, uint256 collateralValueinUsd) = engine.getAccountInformation(USER);
        uint256 expectedOscMinted = 0;
        uint256 actualOscMinted = totalOscMinted;
        uint256 expectedCollateralValueInToken = engine.getTokenAmountFromUsd(weth, collateralValueinUsd);
        assertEq(expectedOscMinted, actualOscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedCollateralValueInToken);
    }

    ///////////////////////
    ///test mintOsc////////
    /////////////////////// 

    function testmintRevertIfLessThanZero() public depositCollateral {
        vm.expectRevert(OSCEngine.OSCEngine__NeedsMoreThanZero.selector);
        engine.mintOsc(0);
    }

    function testRevertIfMintIsMoreThanThreshold() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(OSCEngine.OSCEngine__BreaksHealthFactor.selector);
        engine.mintOsc(11000 ether);
        (uint256 totalOscMinted, uint256 collateralValueinUsd) = engine.getAccountInformation(USER);
        vm.stopPrank();
        console.log("Minted osc:", totalOscMinted);
        console.log("Collateral:", collateralValueinUsd);
    }

    modifier mintOscModifier() {
        vm.startPrank(USER);
        engine.mintOsc(MINTED_OSC);
        vm.stopPrank();
        _;
    }

    function testmintOsc() public depositCollateral mintOscModifier {
        (uint256 totalOscMinted, uint256 collateralValueinUsd) = engine.getAccountInformation(USER);
        uint256 expectedOscMinted = MINTED_OSC;
        assertEq(totalOscMinted, expectedOscMinted);
        uint256 expectedValueInUsd = engine.getAccountCollateralValue(USER);
        assertEq(collateralValueinUsd, expectedValueInUsd);
    }

    function testgetAccountCollateralValue() public depositCollateral{
       uint256 collateralValueInUsd = engine.getAccountCollateralValue(USER);
       uint256 expectedUsd = 10000 ether;
       assertEq(collateralValueInUsd, expectedUsd);
    }

    /////////////////////////////////
    //depositCollateralAndmintOsc///
    ///////////////////////////////

    function testdepositCollateralAndmintOsc() public{
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndmintOsc(weth,AMOUNT_COLLATERAL,MINTED_OSC);
        (uint256 totalOscMinted, uint256 collateralValueinUsd) = engine.getAccountInformation(USER);
        assertEq(totalOscMinted,MINTED_OSC);
        uint256 expectedCollateralInCrypto = engine.getTokenAmountFromUsd(weth,collateralValueinUsd);
        assertEq(expectedCollateralInCrypto,AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ////////////////////////////
    ///testredeemCollateral////
    ///////////////////////////

    function testredeemCollateral() public depositCollateral mintOscModifier{
        vm.startPrank(USER);
        engine.redeemCollateral(weth, REDEEMED_COLLATERAL);
        uint256 expectedCollateral = 8 ether;
        (uint256 totalOscMinted, uint256 collateralValueinUsd) = engine.getAccountInformation(USER);
        uint256 expectedCollateralValueInToken = engine.getTokenAmountFromUsd(weth, collateralValueinUsd);
        assertEq(expectedCollateral, expectedCollateral);
        uint256 expectedOSCMinted = MINTED_OSC;
        assertEq(totalOscMinted, expectedOSCMinted);
        vm.stopPrank();
    }

      function testrevertredeemCollateralIfValueisZero() public depositCollateral mintOscModifier{
        vm.startPrank(USER);
        vm.expectRevert(OSCEngine.OSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0 ether);
        vm.stopPrank();
    }

    function testrevertIfReddemCollateralBreaksHealthFactor() public depositCollateral mintOscModifier{
        vm.startPrank(USER);
        vm.expectRevert(OSCEngine.OSCEngine__BreaksHealthFactor.selector);
        engine.redeemCollateral(weth, REDEEMED_COLLATERAL_BREAKSHEALTHFACTOR);
        vm.stopPrank();

    }
    
    ////////////////////
    //burnOsc//////////
    //////////////////

    function testburnOSCRevertsIfAmountIsZero() public depositCollateral mintOscModifier{
        vm.startPrank(USER);
        vm.expectRevert(OSCEngine.OSCEngine__NeedsMoreThanZero.selector);
        engine.burnOsc(0 ether);
        vm.stopPrank();
    }

    function testburnOSC() public depositCollateral mintOscModifier{
        vm.startPrank(USER);
         ERC20Mock(address(osc)).approve(address(engine), BURN_OSC);
        engine.burnOsc(BURN_OSC);
        uint256 expectedOscMinted = 1000 ether;
        (uint256 totalOscMinted, uint256 collateralValueinUsd) = engine.getAccountInformation(USER);
        assertEq(totalOscMinted, expectedOscMinted);
        uint256 expectedCollateralValueInUsd = engine.getAccountCollateralValue(USER);
        assertEq(collateralValueinUsd, expectedCollateralValueInUsd);
        vm.stopPrank();
    }

    ////////////////////////////
    ///redeemCollateralForOSC///
    ///////////////////////////

    function testredeemCollateralForOSC() public depositCollateral mintOscModifier{
        vm.startPrank(USER);
        ERC20Mock(address(osc)).approve(address(engine), BURN_OSC);
        engine.redeemCollateralForOSC(weth,REDEEMED_COLLATERAL,BURN_OSC);
        (uint256 totalOscMinted, uint256 collateralValueinUsd) = engine.getAccountInformation(USER);
        uint256 expectedOscMinted = 1000 ether;
        assertEq(totalOscMinted, expectedOscMinted);
        uint256 expectedCollateralValueInUsd = engine.getAccountCollateralValue(USER);
        assertEq(collateralValueinUsd, expectedCollateralValueInUsd);
        vm.stopPrank();
    }

    function testredeemCollateralForOSCrevertIfAmountIsZero() public depositCollateral mintOscModifier{
        vm.startPrank(USER);
        ERC20Mock(address(osc)).approve(address(engine), BURN_OSC);
        vm.expectRevert(OSCEngine.OSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateralForOSC(weth,0,BURN_OSC);
        vm.stopPrank();
    }

    /////////////////////////////
    ////calculateHealthFactor///
    ////////////////////////////

    function testcalculateHealthFactor() public depositCollateral mintOscModifier{
        (uint256 totalOscMinted, uint256 collateralValueinUsd) = engine.getAccountInformation(USER);
        //collateral -> 10 ether = 10000 ether
        //OscMinted = 2000 ether
        //Healthfactor should be 5000 ether/ 2000 ether -> 5 ether;
        uint256 expectedHealthFactor = 2.5 ether;
        uint256 helathFactor = engine.calculateHealthFactor(totalOscMinted,collateralValueinUsd);
        assertEq(helathFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositCollateral mintOscModifier{
        //we have minted 2000 stablecoin with $10,000 of collateral with 50% of threshold
        //which means we should have the $4,000 as collateral 
        //if collateral goes below than $4,000 than the user is capale of liquidate.
        //Now the challenge is to make our value less than $4,000
        // for this we have to manipulate our mock pricefeed contract.
        int256 ethUsdUpdatedPrice = 799e8; // price of one weth $799 => 5*799 => 3,995
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor(USER);
        assertLe(userHealthFactor, 0.99875 ether);

    }

    function testHealthFactorCanBeEqaualToOne() public depositCollateral mintOscModifier{
        int256 ethUsdUpdatedPrice = 400e8; // price of one weth $400 => 10*400 => 4,000
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor(USER);
        assertLe(userHealthFactor, 1 ether); 
    }

    ///////////////////////
    //liquidate///////////
    /////////////////////

  function  testMustImproveHealthFactorOnLiquidation() public{
    //deploy MockMoreDebtOSC
    MockMoreDebtOSC mockOsc = new MockMoreDebtOSC(wethUsdPriceFeed);
    tokenAddresses =[weth];
    priceFeedsAddresses = [wethUsdPriceFeed];
    address owner = msg.sender;
    vm.prank(owner);
    OSCEngine mockEngine = new OSCEngine(
       tokenAddresses,
       priceFeedsAddresses,
       address(mockOsc)
    );
    //transferOwnership to mockEngine
    mockOsc.transferOwnership(address(mockEngine));
    //Arange user
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(mockEngine), AMOUNT_COLLATERAL);
    mockEngine.depositCollateralAndmintOsc(weth, AMOUNT_COLLATERAL,MINTED_OSC);
    vm.stopPrank();

    //Arrange Liquidator
    //Mint weth
    ERC20Mock(weth).mint(LIQUIDATOR,STARTING_ERC20_BALANCE);

    vm.startPrank(LIQUIDATOR);
    ERC20Mock(weth).approve(address(mockEngine), AMOUNT_COLLATERAL);
    mockEngine.depositCollateralAndmintOsc(weth, AMOUNT_COLLATERAL,MINTED_OSC);

    uint256 debtToCover = 10 ether; // -> 10 osc
    mockOsc.approve(address(mockEngine), debtToCover);

    int256 ethUsdUpdatedPrice = 399e8; //-> 1 weth = $399
    MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
    vm.expectRevert(OSCEngine.OSCEngine__HealthFactorNotImproved.selector);
    mockEngine.liquidate(weth, USER, debtToCover);
    vm.stopPrank();
  }

  modifier depositedCollateralAndMintedoscModifer() {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateralAndmintOsc(weth, AMOUNT_COLLATERAL,MINTED_OSC);
    _;
}

function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedoscModifer {
    ERC20Mock(weth).mint(LIQUIDATOR,collateralToCover);
    vm.startPrank(LIQUIDATOR);
    ERC20Mock(weth).approve(address(engine),collateralToCover);
    engine.depositCollateralAndmintOsc(weth, collateralToCover,MINTED_OSC);
    osc.approve(address(engine),MINTED_OSC);

     vm.expectRevert(OSCEngine.OSCEngine__HealthFactorOk.selector);
     engine.liquidate(weth, USER,MINTED_OSC );
     vm.stopPrank();
}

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
       engine.depositCollateralAndmintOsc(weth, AMOUNT_COLLATERAL, MINTED_OSC);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 799e8; // 1 ETH = $799

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor =engine.getHealthFactor(USER);

        ERC20Mock(weth).mint(LIQUIDATOR, collateralToCover);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), collateralToCover);
       engine.depositCollateralAndmintOsc(weth, collateralToCover, MINTED_OSC);
        osc.approve(address(engine), MINTED_OSC);
       engine.liquidate(weth, USER, MINTED_OSC); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

      function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 expectedWeth = engine.getTokenAmountFromUsd(weth, MINTED_OSC)
            + (engine.getTokenAmountFromUsd(weth, MINTED_OSC ) / engine.getLiquidationBonus());
        // uint256 hardCodedExpected = 6111111111111111110;
        // assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated{
        uint256 amountLiquidated = engine.getTokenAmountFromUsd(weth, MINTED_OSC)
            + (engine.getTokenAmountFromUsd(weth, MINTED_OSC ) / engine.getLiquidationBonus());
        
        uint256 usdAmountLiquidated = engine.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueinUsd = engine.getUsdValue(weth, AMOUNT_COLLATERAL)- (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd)= engine.getAccountInformation(USER);
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueinUsd); 
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated{
       (uint256 liquidatorOscMinted,) = engine.getAccountInformation(LIQUIDATOR);
       assertEq(liquidatorOscMinted, MINTED_OSC);
       }
     function testUserHasNoMoreDebt() public liquidated {
        (uint256 USEROscMinted,) = engine.getAccountInformation(USER);
       assertEq(USEROscMinted, 0 ether);
     }

      ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////
    function testGetCollateralTokenPriceFeed() public {
        address priceFeed = engine.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, wethUsdPriceFeed);
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = engine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public {
        uint256 minHealthFactor = engine.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public {
        uint256 liquidationThreshold = engine.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositCollateral {
        (, uint256 collateralValue) = engine.getAccountInformation(USER);
        uint256 expectedCollateralValue = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = engine.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralValue = engine.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetOsc() public {
        address oscAddress = engine.getOSC();
        assertEq(oscAddress, address(osc));
    }

    function testLiquidationPrecision() public {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = engine.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
}
