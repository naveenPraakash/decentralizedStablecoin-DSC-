// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

// other contracts that our system interacts with should also be checked like
// price feeds
// weth
// wbtc

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStablecoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        //targetContract(address(dsce));
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
        // well have to make sure that this calls functions from the DSCE contracts in an order that makes sense
        // for example : dont call redeem collateral unless there are collateral to redeem
        // so we are going to create a handler which is going to handle how we are making calls to the dsce
        // so instead of us just calling redeem collateral we are only going to call redeem collateral if there are collateral to redeem
        // because otherwise the transaction is going to revert and that is just a waste of function call
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        // compare it to all the debt (dsc)

        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalBtcdeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdvalue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdvalue(wbtc, totalBtcdeposited);

        console.log("Times mint called ", handler.ctr());
        console.log("Times mint called ", handler.ct());
        console.log("Times mint called ", handler.c());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    // our getters should never revert

    function invariant_gettersshouldNotRevert() public view {
        // if any of the function combinations break any of our getters we know that we have a broken invariant.
    }
}
