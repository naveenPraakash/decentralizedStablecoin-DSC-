// SPDX-License-Identifier: MIT

// Layout of contracts:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// state variables
// events
// Modifiers
// Functions

// Layout of functions
// constructor
// receive functions (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view and pure functions

pragma solidity ^0.8.18;

import {DecentralizedStablecoin} from "./DecentralizedStablecoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
//import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title DSCEngine
 * @author Naveen Prakash
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing and withdrawing collateral
 * @notice This contract is based on MakerDAO DSS (DAI) system.
 * This system is designed to be as minimal as possible, and have the token maintain a 1 token == $1 peg
 * This stablecoin has the following properties:
 * -Exogeneous collateral
 * -Dollar Pegged
 * -Algorithmically Stable
 *
 * Is is similar to DAI if DAI had no governance, no fees, and was only backed by wETH and wBTC
 *
 *  Our DSC system should always be "OverCollateralized". At no point should the value of all collateral <= the $ backed value of all the value of the DSC.
 */

contract DSCEngine {
    ////////////
    // Errors //
    ////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAdressAndPriceFeedAdressMustBeOfSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__transferFailed();
    error DSCEngine__BreaksHaelthFactor(uint256 userHealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /////////////////////
    // State Variables //
    /////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200 % overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 100;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStablecoin private immutable i_dsc;

    /////////////////////
    // Events ///////////
    /////////////////////

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amountCollateral
    );

    ///////////////
    //Modifiers////
    ///////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////
    //functions////
    ///////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        // USD pricefeeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAdressAndPriceFeedAdressMustBeOfSameLength();
        }

        // for example ETH/USD BTC/USD

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStablecoin(dscAddress);
    }

    // external functions
    /*
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint the amount of decentralized stablecoin to mint
     * @notice this function will deposit collateral and mint DSC in one transaction
     */

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /*
     * CEI Checks effectsv interactions
     * @param tokenCollateralAddress The adress of the token to deposit as collateral
     * @param amountCollateral The amount of Collateral to deposit
     */

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    //nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;

        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );

        // transfer : When you transfer from yourself
        // transferFrom : when you transfer from somebodyeslse

        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__transferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress The collateral Address To redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of Dsc to burn
     * This function burns DSc and redeems underlying collateral in one transaction
     */

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // Redeemcollateral already checks healthfactor
    }

    // in order to redeem collateral;
    // 1. health factor must be 1 AFTER collateral pulled
    // DRY : Dont repeat yourself

    // our 3rd party user isnt the one with the bad debt, we need to redeem a random persons collateral
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) {
        // here in the next line we are depemdent on the solidity compiler to check if someone does not with draw more than they should
        // like 10-100 = -90
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // Threshold to lets say 150%
    // $100 ETH Collateral -> -> $ 0
    // $0 DSC
    // UNDERCOLLATERALIZED !!!

    // Ill pay back the $50 -> get all your collateral
    // $74 ETH
    // -$50 DSC

    // Do we need to check if it breaks the health factor?
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // may not be required
    }

    // 1. Check if the collateral value is greater than the DSC amount. Pricefeeds, values

    /**
     * @notice follows CEI
     * @param amtDSCToMint the amount of decentralized stablecoin to mint
     * @notice they must have collateral value greater then thre minimum threshold.
     */
    function mintDSC(uint256 amtDSCToMint) public moreThanZero(amtDSCToMint) {
        s_DSCMinted[msg.sender] += amtDSCToMint;
        // the above execution also reverts if the function reverts
        // if they minted too much ($150 DSC , $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amtDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    // this liquidate function is going to be the function that other user can callto remove peoples position to save the protocol
    // If we start nearing undercollateralization, we need someone to liquidate positions
    // $ 100 ETH backing $ 50 DSC
    // $ 20 Eth backing $ 50 DSC <- DSC isnt worth 1 $ .
    //

    // $ 75 Backing $ 50 DSC
    // Liquidator takes $ 75 backing and burns off the $ 50 DSC

    // If someone is almost undercollateralized well pay you to liquidate them

    /**
     *
     * @param collateral The erc20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC to burn to improve the users health factor
     * @notice you can partially liquidate a user
     * @notice Youwill get a liquidation bonus for taking the users funds
     * @notice This function working assumes The protocol will be 200% overCollateralized in order for this to work
     * @notice A known bug will be if the protocol were 100 % or less collateralized, then we wouldnt be able to incentive the liquidators
     * @notice for example the price of the collateral plummeted before anyone can be liquidated
     *
     * Follows CEI: Checks, Effects, Interactions
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) {
        // need to check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        // We want to burn their DSC "debt"
        // And take their collateral
        // bad user: $140 ETH , $100 DSC
        // debtToCover = $100
        // $100 of DSC == how many ETH?

        // we are going to figure out how much of the token we are going to get

        // we have how much eth we have to take away from that collateral as a reward for paying back the DSC

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );

        // ANd give them a 10% bonus
        // we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // and sweep extra amounts into a treasury

        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

        //  Now we need to redeem this amount of collateral for calling the liquidate function and then we also need to burn the DSC from the user as well
        // We need to give them the collateral and burn the DSC that they are covering with their debt to cover

        // We generally want to only redeem collateral from and to the same person however when we are doing a liquidate we are going to redeem to whoever is calling the liquidate

        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );

        _burnDsc(debtToCover, user, msg.sender);

        // since we are doing this internal calls that dont have checks we absolutely need to makle sure we are checking health factor is okay

        uint256 endinguserHealthfactor = _healthFactor(user);
        if (endinguserHealthfactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // this function will allow us to see how healthy people are

    function getHealthFactor() external view {}

    ////////////////
    ////Internal////
    ////////////////

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__transferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @dev Low level internal function , do not call unless the function calling it is checking for health factor being broken
     */

    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );
        // this condition is hypothetically unreachable
        if (!success) {
            revert DSCEngine__transferFailed();
        }

        i_dsc.burn(amountDscToBurn);
        // _revertIfHealthFactorIsBroken(msg.sender); // may not be required
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to liquidation a user is
     * if a user goes below 1, then they can get liquidated
     */

    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral value

        (
            uint256 totalDSCMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);

        // Decimals dosent work in solidity..

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    // 1. Check Health Factor (do they have enough Collateral)
    // 2. Revert if they do not have a healthy health factor

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHaelthFactor(userHealthFactor);
        }
    }

    ///////////////////////////////////////////
    ///Public and external view functions//////
    ///////////////////////////////////////////

    // We have this function where we get the token amount from the usd, we're saying hey we are going to cover 100 dollars of your debt
    // or something like that how much eth is 100 dollars worth of your debt

    function getTokenAmountFromUsd(
        address token,
        uint256 USDamountInWei
    ) public view returns (uint256) {
        // price of ETH(token)
        // $/ETH ETH ???
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            (USDamountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalcollateralValueInUsd) {
        // loop through each collateral token, get amount they have deposited and map it to the price to get the usd value

        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalcollateralValueInUsd += getUsdvalue(token, amount);
        }

        return totalcollateralValueInUsd;
    }

    function getUsdvalue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        // 1ETH = $1000
        // The returned value from Cl will be 1000 * 1e8

        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        (totalDSCMinted, collateralValueInUsd) = _getAccountInformation(user);
    }
}
