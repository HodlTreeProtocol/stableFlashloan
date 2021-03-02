// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ER20TokenMock is ERC20 {
	
	constructor (
		string memory name_, 
		string memory symbol_,
		uint8 decimals_
	) 
		ERC20(name_, symbol_)
	{
		if(decimals_ != 0)
			_setupDecimals(decimals_);
	}

	function mint (
		address account_, 
		uint256 amount_
	)
		external
	{
		_mint(account_, amount_);
	}
	
}