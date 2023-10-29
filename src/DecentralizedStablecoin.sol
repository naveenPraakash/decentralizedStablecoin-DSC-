// SPDX-License-Identifier: MIT

// Layout of contracts:
// version
// imports
// errors
// interfaces, libraries, contracts
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

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 *   @title DecentralizedStableCoin
 *   @author Naveen Prakash
 *   Collateral: Exogeneous (ETH & BTC)
 *   Minting: Algorithmic
 *   Relative Stability: Pegged to USD
 *
 *   This is a contract meant to be Governed by DSC engine.This contract is just the erc20 implementation of our stablecoin system.
 */

contract DecentralizedStablecoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__MustBeMoreThanBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStablecoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        if (balance < _amount) {
            revert DecentralizedStableCoin__MustBeMoreThanBalance();
        }

        // we are overriding the burn function thats why well have to make the function super, we are saying do all the stuff and then run the regular burn
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        // we are not going to accidently let people mint to the zero address

        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }

        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        // since we are not overriding the mint function we dont need to mention super
        _mint(_to, _amount);
        return true;
    }
}
