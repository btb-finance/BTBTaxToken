// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockBTB
 * @notice Mock BTB token for testing purposes
 */
contract MockBTB is ERC20 {
    constructor() ERC20("BTB Token", "BTB") {
        // Mint 1 billion tokens for testing
        _mint(msg.sender, 1_000_000_000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
