// SPDX-License-Identifier: MIT

// Handler is going to narrow down the way we call functions

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStablecoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public ctr = 0;
    uint256 public ct = 0;
    uint256 public c = 0;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    address public USER = makeAddr("user");

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // the max uint96 value

    constructor(DSCEngine _dscEngine, DecentralizedStablecoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        ethUsdPriceFeed = MockV3Aggregator(
            dsce.getCollateralTokenPriceFeeds(address(weth))
        );
    }

    // redeem collateral
    // In your handlers whatever parameters you have is going to be randomized\
    // assasasasasqwqwqw1221212zxzxzxzxddddddddddzxxzxzxzxasasasqwqw12121212asasasasasasasfffffffffffassasasas

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        // dsce.depositCollateral(collateral, amountCollateral);

        // This is so that only the tokens approved could be deposited
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        // if (amountCollateral == 0) {
        //     return;
        // }

        // we need to make sure that msg.sender has the collateral it is depositing so that they can actually deposit it
        // also msg.sender need to approve the transfer from itself to dsce.
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        // Thats why we choose ERC20MOck so that we can mint tokens
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // This might double push but for now for simplicity let it be like the way it is
        usersWithCollateralDeposited.push(msg.sender);
    }

    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(
            address(collateral),
            msg.sender
        );

        // here is where fail on revert == true can be a bit deceptive, rn we are only letting you to nredeem the maxcollateralto redeem.abi
        // lets say there is a bug where a user can redeem more than they have, this fuzz test wouldnt catch it
        //amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        if (amountCollateral == 0) {
            return;
        }
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[
            addressSeed % usersWithCollateralDeposited.length
        ];
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(sender);
        // here we vwill have them always mint the max Dsc they can mint
        uint256 maxDscToMint = (collateralValueInUsd / 2) - totalDSCMinted;
        ctr++;
        if (maxDscToMint < 0) {
            return;
        }
        ct++;
        amount = bound(amount, 0, maxDscToMint);

        if (amount == 0) {
            return;
        }
        c++;
        // console.log("one", USER.balance);
        // console.log(amount);
        vm.startPrank(sender);
        dsce.mintDSC(amount);
        vm.stopPrank();
        // console.log("two", USER.balance);
    }

    // if the price fluctuates too quickly within 1 block the protocol breaks

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceiNT = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceiNT);
    // }
}
