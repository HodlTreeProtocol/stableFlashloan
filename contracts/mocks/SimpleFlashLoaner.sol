// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILiquidityPool {
	function TOKENS (uint256) external returns (address);
	function TOKENS_MUL (uint256) external returns (uint256);
	function balance (uint256 token_) external returns (uint256);
	function calcBorrowFee (uint256 amount_) external returns (uint256);
	function borrow (
		uint256[5] calldata amounts_,
		bytes calldata data_
	) external;
}

contract SimpleFlashLoaner {

	ILiquidityPool liquidityPool = ILiquidityPool(address(0xa4C008D90f2DF3dF6FAdC9ca87C6B1e029f916e1));
	IERC20 gusdToken;
	IERC20 usdcToken;
	uint256 constant gusdTokenIndex = 1;
	uint256 constant usdcTokenIndex = 2;
	
	constructor() {
		gusdToken = IERC20(liquidityPool.TOKENS(gusdTokenIndex));
		usdcToken = IERC20(liquidityPool.TOKENS(usdcTokenIndex));
	}

	function flashLoan ()
		external
	{
		// Normalised amount (1 000 000 tokens) in decimals 18 we want to borrow
		uint256 _borrowAmountNorm = 1e6 * 1e18;
		// Borrow amount in GUSD
		uint256 _borrowAmount = _borrowAmountNorm / liquidityPool.TOKENS_MUL(gusdTokenIndex);
		// Check if LiquidityPool has sufficient GUSD balance
		require (liquidityPool.balance(gusdTokenIndex) >= _borrowAmount, "not enough balance to borrow");
		// Normalised fee for amount we borrow
		uint256 _borrowFeeNorm = liquidityPool.calcBorrowFee(_borrowAmountNorm);
		// Return amount in USDC
		uint256 _returnAmount = (_borrowAmountNorm + _borrowFeeNorm) / liquidityPool.TOKENS_MUL(usdcTokenIndex);
		// Encode callback function with paramenters
		string memory _someParam = "value of param";
		bytes memory _data = abi.encodeWithSignature("callBack(uint256,uint256,string)", _borrowAmount, _returnAmount, _someParam);
		liquidityPool.borrow([0,_borrowAmount,0,0,0], _data);
	}

	function callBack (
		uint256 borrowAmount_,
		uint256 returnAmount_,
		string memory someAnotherParam_
	)
		external
	{
		require(msg.sender == address(liquidityPool), "caller is not the LiquidityPool");
		// Check you have requested GUSD balance
		require (gusdToken.balanceOf(address(this)) >= borrowAmount_, "didn't receive loan");

		// Do your logic HERE, where you can use yours own params

		// Check you have required USDC balance
		require (usdcToken.balanceOf(address(this)) >= returnAmount_, "not enough balance to payback");
		// return flash loan 
		usdcToken.transfer(address(liquidityPool), returnAmount_);
	}

}
