// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {OracleLib, AggregatorV3Interface} from "./libraries/OracleLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OnChainStableCoin} from "./OnChainStableCoin.sol";

/*
 * @title OSCEngine
 * @author Kartik Giri
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * @notice This contract is the core of the Onchain Stablecoin system. It handles all the logic
 * for minting and redeeming OSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract OSCEngine is ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    error OSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error OSCEngine__NeedsMoreThanZero();
    error OSCEngine__TokenNotAllowed();
    error OSCEngine__TransferFailed();
    error OSCEngine__BreaksHealthFactor();
    error OSCEngine__MintFailed();
    error OSCEngine__HealthFactorOk();
    error OSCEngine__HealthFactorNotImproved();

    ///////////////////
    // Types
    ///////////////////
    //The line "using OracleLib for AggregatorV3Interface;" in the contract means that the contract is using the functions and
    // capabilities provided by the "OracleLib" library for the "AggregatorV3Interface" interface.
    //By using the "using" keyword with "OracleLib for AggregatorV3Interface," the contract gains access to the functions and
    //logic defined in the "OracleLib" library for the "AggregatorV3Interface" interface. This allows the contract to use these
    //functions without having to rewrite them within the contract itself, which promotes code reusability and keeps the contract's
    //codebase cleaner and more modular.
    using OracleLib for AggregatorV3Interface;

    ///////////////////
    // State Variables
    ///////////////////
    //instance of OnChainStableCoin
    OnChainStableCoin private immutable i_Osc;

    //It's set to the value 50, which means that for an account to avoid liquidation, it needs to be 200% over-collateralized.
    //In other words, they need to have collateral worth at least twice the value of their debt
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100; //It's set to 100, which is used to calculate the liquidation bonus. The bonus is a percentage, so this precision factor allows for accurate percentage calculations.
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; //It represents the minimum acceptable health factor for an account to avoid liquidation. A health factor below this value would indicate that the account is in danger of being liquidated.
    uint256 private constant PRECISION = 1e18; //It's used for precision in various calculations. A uint256 with this precision means it has 18 decimal places, which is common in Ethereum for representing values with high precision.
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; //It's used for precision in calculating the value of assets in terms of USD, with additional precision to maintain accuracy.
    uint256 private constant FEED_PRECISION = 1e8; //It's used when obtaining price data for assets. It ensures that the price data maintains eight decimal places of precision.

    /// @dev Mapping of token address to price feed address
    mapping(address collateralToken => address priceFeed) private s_priceFeeds; //Set in the constructor.
    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    /// @dev Amount of OSC minted by user
    mapping(address user => uint256 amount) private s_OSCMinted;
    /// @dev If we know exactly how many tokens we have, we could make this immutable!
    // to store token addresses
    address[] private s_collateralTokens;

    ///////////////////
    // Events
    ///////////////////
    //Event emit when collateral is deposited
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount); // if redeemFrom != redeemedTo, then it was liquidated

    ///////////////////
    // Modifiers
    ///////////////////
    //Collateral amount should be more than 0.
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert OSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert OSCEngine__TokenNotAllowed();
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address oscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert OSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        // These feeds will be the USD pairs
        // For example ETH / USD or MKR / USD
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i]; //setting  s_priceFeeds mapping. if token address has pricefeed than it is allowed collateral otherwise not.
            s_collateralTokens.push(tokenAddresses[i]); // pushing token addresses in to  s_collateralTokens
        }
        i_Osc = OnChainStableCoin(oscAddress); //initalizing i_Osc
    }

    ///////////////////
    // External Functions
    ///////////////////
    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountOscToMint: The amount of OSC you want to mint
     * @notice This function will deposit your collateral and mint OSC in one transaction
     */
    function depositCollateralAndmintOsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountOscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintOsc(amountOscToMint);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountOscToBurn: The amount of OSC you want to burn
     * @notice This function will withdraw your collateral and burn OSC in one transaction
     */
    function redeemCollateralForOSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountOscToBurn)
        external
        moreThanZero(amountCollateral)
    {
        _burnOsc(amountOscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have OSC minted, you will not be able to redeem until you burn your OSC
     * DRY - Don't repeat yourself!
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice careful! You'll burn your OSC here! Make sure you want to do this...
     * @dev you might want to use this if you're nervous you might get liquidated and want to just burn
     * you OSC but keep your collateral in.
     */
    function burnOsc(uint256 amount) external moreThanZero(amount) {
        _burnOsc(amount, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    /*
     * $100 ETH -> $60 threshold
     * $50 DAI
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your OSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of OSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    //collateral is the address of collateral token, user which is going to be liquidate and debttocover is in stablecoin value like 100OSC is the amount which we want to recover to keep our protocol always over-collateralized.
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert OSCEngine__HealthFactorOk();
        }
        // If covering 100 OSC, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 OSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // Burn OSC equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        _burnOsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert OSCEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////
    // Public Functions
    ///////////////////
    /*
     * @param amountOscToMint: The amount of OSC you want to mint
     * You can only mint OSC if you hav enough collateral
     */
    function mintOsc(uint256 amountOscToMint) public moreThanZero(amountOscToMint) nonReentrant {
        s_OSCMinted[msg.sender] += amountOscToMint;
        //revert if user is minting more than collateral
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_Osc.mint(msg.sender, amountOscToMint);
        if (minted != true) {
            revert OSCEngine__MintFailed();
        }
    }

    function revertIfHealthFactorIsBroken(address user) internal view {
        //_healthFactor()-> to check whether they have enough collateral.
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert OSCEngine__BreaksHealthFactor();
        }
    }

    //function to get health factor.
    //returns how close to liquidation a user is.
    // if a user goes below than 1, then they can get liquidated
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalOscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user); //get totalOscMinted and collateralValueInUsd
        return _calculateHealthFactor(totalOscMinted, collateralValueInUsd);
    }

    //get account Information
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalOscMinted, uint256 collateralValueInUsd)
    {
        totalOscMinted = s_OSCMinted[user]; //OSC minted by that user
        collateralValueInUsd = getAccountCollateralValue(user); // get collateral value deposit by user.
    }

    // function to get Collateral value in usd of user
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount); //call _getUsdValue function
        }
        return totalCollateralValueInUsd;
    }
    // get vlaue of token in usd deposited by user

    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _calculateHealthFactor(uint256 totalOscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalOscMinted == 0) return type(uint256).max; // In Solidity, you can access the maximum value of an unsigned integer type using type(uint256).max.
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalOscMinted;

        // 1000* 50 = 50000/100 = 500;
        //5001e18/400=
    }
    /*
     *@notice follows CEI => CHECK, EFFECTS AND INTERACTIONS
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're depositing
     * @param amountCollateral: The amount of collateral you're depositing
     */
    // It is alway good to create external function nonReentrant cause reenterencies are the most common attack. it cost more gas

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert OSCEngine__TransferFailed();
        }
        // In the Solidity function depositCollateral, if the IERC20(tokenCollateralAddress).transferFrom(msg.sender,
        // address(this), amountCollateral) function call fails, it will cause the transaction to revert. When a transaction reverts, it
        //effectively reverts all state changes made within that transaction, including changes to storage variables like the mapping
        // s_collateralDeposited.
    }

    ///////////////////
    // Private Functions
    ///////////////////
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert OSCEngine__TransferFailed();
        }
    }

    function _burnOsc(uint256 amountOscToBurn, address onBehalfOf, address oscFrom) private {
        s_OSCMinted[onBehalfOf] -= amountOscToBurn;
        // we are not updating the miniting mapping of liquiadator because he is liquidating the user.
        bool success = i_Osc.transferFrom(oscFrom, address(this), amountOscToBurn);
        // This conditional is hypothetically unreachable
        if (!success) {
            revert OSCEngine__TransferFailed();
        }
        i_Osc.burn(amountOscToBurn);
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    function calculateHealthFactor(uint256 totalOscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalOscMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalOscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getUsdValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUsdValue(token, amount);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getOSC() external view returns (address) {
        return address(i_Osc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
