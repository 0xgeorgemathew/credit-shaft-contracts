// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SimplifiedLPToken is ERC20, Ownable {
    // Events
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        emit Mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
        emit Burn(from, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6; // USDC has 6 decimals
    }
}
