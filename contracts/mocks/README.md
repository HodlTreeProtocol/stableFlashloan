## Hodltree stablecoins flashloan module

Сontract is an opportunity to borrow one or more stablecoins (erc-20 token, that are attempt to peg their market value to the U.S. dollar) and return them in the same coins or other supported stablecoin, which can open up opportunities for arbitrage and making money

### Principles
1. Your contract calls LiquidityPool contract, requesting a Flash Loan of certain amounts of tokens specifying encoded callback function using method borrow().

2. LiquidityPool transfers requested amounts of tokens (at this stage LiquidityPool checks it has sufficient balance of each requested token and total requested amount is greater than zero) to your contract and calls specified callback function on your contract.

3. Your contract is now holding the flash loaned amounts, do your desired operations in callback function and transfer back to LiquidityPool amounts + borrow fee in any combination of tokens. Total sum of returned token amounts in normalized decimals 18 form should be greater or equal to total sum of borrowed token amounts plus borrow fee.

4. All of the above happens in single atomic transaction.


### Supported tokens
LiquidityPool currently supports following tokens:
* **sUSD** 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51
* **GUSD** 0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd
* **USDC** 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
* **DAI**  0x6B175474E89094C44Da98b954EedeAC495271d0F
* **TUSD** 0x0000000000085d4780B73119b644AE5ecd22b376

### LiquidityPool Interface:
```solidity
interface ILiquidityPool {
	function TOKENS (uint256) external returns (address);			// returns token contract address, index 0-4
	function TOKENS_MUL (uint256) external returns (uint256);		// returns token multipliers, index 0-4
	function balance (uint256 token_) external returns (uint256);		// return token balance, index 0-4
	function calcBorrowFee (uint256 amount_) external returns (uint256);	// return borrow fee for amount
	function borrow (							// initiates flash loan
		uint256[5] calldata amounts_,
		bytes calldata data_
	) external;
}
```

First you should make sure LiquidityPool has sufficient balance of desired tokens, you can do that by calling balance(index). When you know amounts of each token you are going to borrow, you need to calculate total amount of borrowed tokens in normalised decimals 18 form, you can do that by multiplying corresponding individual token amounts to TOKENS_MUL(index). When you have total sum you can get borrow fee from calcBorrowFee(amount). Now you can call borrow() with your desired token amounts and encoded callback function with parameters making sure it will do the logic and return debt + borrow fee.

### Example contract with return in another currency:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILiquidityPool {
    function TOKENS(uint256) external returns (address);
    function TOKENS_MUL(uint256) external returns (uint256);
    function balance(uint256 token_) external returns (uint256);
    function calcBorrowFee(uint256 amount_) external returns (uint256);
    function borrow(
        uint256[5] calldata amounts_,
        bytes calldata data_
    ) external;
}


contract FlashLoanerWithReturnInAnotherCurrency {

    //Address of Hodltree stablecoin-flashloan contract proxy
    ILiquidityPool liquidityPool;

    //supported tokens
    uint256 constant N_TOKENS = 5;

    IERC20[N_TOKENS] TOKENS;

    constructor(address borrowProxy) {
        liquidityPool = ILiquidityPool(borrowProxy);
        for (uint256 i = 0; i < N_TOKENS; i++)
            TOKENS[i] = IERC20(liquidityPool.TOKENS(i));
    }

    // Call this func initilize flashloan on []amounts of each token
    function flashLoan(
        uint256[N_TOKENS] calldata amounts_,
        uint256[N_TOKENS] calldata payAmounts_
    )
        external
    {
        bytes memory _data = abi.encodeWithSignature("callBack(uint256[5])", payAmounts_);
        liquidityPool.borrow(amounts_, _data);
    }

    // Callback implementing custom logic (there will be arbitrage/trades/market-making/liquidations logic). 
    function callBack(
        uint256[N_TOKENS] calldata payAmounts_
    )
        external
    {
        require(msg.sender == address(liquidityPool), "caller is not the LiquidityPool");

        // Do your logic HERE

        // return flash loan 
        for (uint256 i = 0; i < N_TOKENS; i++) {
            if (payAmounts_[i] != 0) {
                TOKENS[i].transfer(address(liquidityPool), payAmounts_[i]);
            }
        }
    }
}
```

### Example simple contract:

```solidity
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
```