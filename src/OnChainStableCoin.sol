// SPDX-License-Identifier: MIT
// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title OnChainStableCoin
 * @author Kartik Giri
 * Collateral: Exogenous
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 *
 * This is the contract meant to be owned by OSCEngine. It is a ERC20 token that can be minted and burned by the OSCEngine smart contract.
 */
contract OnChainStableCoin is ERC20Burnable, Ownable {
    error OnChainStableCoin__AmountMustBeMoreThanZero();
    error OnChainStableCoin__BurnAmountExceedsBalance();
    error OnChainStableCoin__NotZeroAddress();
    // error OnChainStableCoin__AmountMustBeMoreThanZero();

    constructor() ERC20("OnChainStableCoin", "OSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert OnChainStableCoin__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert OnChainStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount); //super keyowrd say use the burn function from parent contract in this case ERC20Burnable is parent contract. we used super casue we are overriding burn function.
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert OnChainStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert OnChainStableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount); // calling _mint function from ERC20 here we did'nt used super cause we are not overriding any function.
        return true;
    }
}
