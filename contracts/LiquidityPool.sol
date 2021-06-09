// SPDX-License-Identifier: MIT
pragma solidity 0.7.2;
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ERC20Upgradeable, IERC20Upgradeable, SafeMathUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract LiquidityPoolV3_02 is ReentrancyGuardUpgradeable, AccessControlUpgradeable, PausableUpgradeable, ERC20Upgradeable {

	using SafeMathUpgradeable for uint256;

  bytes32 constant public PAUSER_ROLE = keccak256("PAUSER_ROLE");

	uint256 constant public N_TOKENS = 5; 
	uint256 constant public NORM_BASE = 18;
	uint256 constant public CALC_PRECISION = 1e36;
	uint256 constant public PCT_PRECISION = 1e6;
	IERC20Upgradeable[N_TOKENS] public TOKENS;
	uint256[N_TOKENS] public TOKENS_MUL;
	
	uint256 public depositFee;
	uint256 public borrowFee;
	uint256 public adminFee;
	uint256 public adminBalance;
	address public adminFeeAddress;

	event SetFees(uint256 depositFee, uint256 borrowFee, uint256 adminFee);
	event SetAdminFeeAddress(address adminFeeAddress, address newAdminFeeAddress);
	event WithdrawAdminFee(address indexed addressTo, uint256[N_TOKENS] tokenAmounts, uint256 totalAmount);
	event Deposit(address indexed user, uint256[N_TOKENS] tokenAmounts, uint256 totalAmount, uint256 fee, uint256 mintedAmount);
	event Withdraw(address indexed user, uint256[N_TOKENS] tokenAmounts, uint256 burnedAmount);
	event Borrow(address indexed user, uint256[N_TOKENS] tokenAmounts, uint256 totalAmount, uint256 fee, uint256 adminFee);

	modifier onlyPauser() {
		require(hasRole(PAUSER_ROLE, msg.sender), "must have pauser role");
		_;
	}

	function initialize(
		uint256 depositFee_,
		uint256 borrowFee_,
		uint256 adminFee_
	)
		public
		initializer 
	{
		__ReentrancyGuard_init();
		__AccessControl_init();
		__Pausable_init_unchained();
		__ERC20_init_unchained('HodlTree Flash Loans LP USD Token', 'hFLP-USD');
		TOKENS = [
			IERC20Upgradeable(0x57Ab1ec28D129707052df4dF418D58a2D46d5f51), // sUSD
			IERC20Upgradeable(0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd), // GUSD
			IERC20Upgradeable(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), // USDC
			IERC20Upgradeable(0x6B175474E89094C44Da98b954EedeAC495271d0F), // DAI
			IERC20Upgradeable(0x0000000000085d4780B73119b644AE5ecd22b376)  // TUSD
		];
		TOKENS_MUL = [
			uint256(1),
			uint256(1e16),
			uint256(1e12),
			uint256(1),
			uint256(1)
		];
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setupRole(PAUSER_ROLE, msg.sender);
		_setRoleAdmin(PAUSER_ROLE, PAUSER_ROLE);
		setFees(depositFee_, borrowFee_, adminFee_);
		setAdminFeeAddress(msg.sender);
	}
	
	/***************************************
					ADMIN
	****************************************/
	
	/**
	 * @dev Sets new fees
	 * @param depositFee_ deposit fee in ppm
	 * @param borrowFee_ borrow fee in ppm
	 * @param adminFee_ admin fee in ppm
	 */
	function setFees (
		uint256 depositFee_,
		uint256 borrowFee_,
		uint256 adminFee_
	)
		public
	{
		require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "must have admin role to set fees");
		depositFee = depositFee_;
		borrowFee = borrowFee_;
		adminFee = adminFee_;
		emit SetFees(depositFee_, borrowFee_, adminFee_);
	}

	/**
	 * @dev Sets admin fee address
	 * @param newAdminFeeAddress_ new admin fee address
	 */
	function setAdminFeeAddress (
		address newAdminFeeAddress_
	)
		public
	{
		require(newAdminFeeAddress_ != address(0), "admin fee address is zero");
		require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "must have admin role to set admin fee address");
		emit SetAdminFeeAddress(adminFeeAddress, newAdminFeeAddress_);
		adminFeeAddress = newAdminFeeAddress_;
	}

	/***************************************
					PAUSER
	****************************************/
	
	/**
	 * @dev Pause contract (disable deposit and borrow methods)
	 */
	function pause()
		external
		onlyPauser
	{
		_pause();
	}

	/**
	 * @dev Unause contract (enable deposit and borrow methods)
	 */
	function unpause()
		external
		onlyPauser
	{
		_unpause();
	}

	/***************************************
					PRIVATE
	****************************************/

	/**
	 * @dev Calculates amount to mint internal tokens
	 * @param amount_ normalised deposit amount
	 * @param totalBalance_ normalised total balance of all tokens excluding admin fees
	 * @param totalSupply_ internal token total supply
	 * @return mintAmount_ amount to mint
	 */
	function _calcMint (
		uint256 amount_,
		uint256 totalBalance_,
		uint256 totalSupply_
	) 
		internal
		pure
		returns(uint256 mintAmount_) 
	{
		mintAmount_ = amount_.mul(
			CALC_PRECISION
		).div(
			totalBalance_
		).mul(
			totalSupply_
		).div(
			CALC_PRECISION
		);
	}

	/**
	 * @dev Returns normalised total balance of all tokens including admin fees
	 * @return totalBalanceWithAdminFee_ balance
	 */	
	function _totalBalanceWithAdminFee ()
		internal
		view
		returns (uint256 totalBalanceWithAdminFee_)
	{
		for (uint256 i = 0; i < N_TOKENS; i++) {
			totalBalanceWithAdminFee_ = totalBalanceWithAdminFee_.add(
				(TOKENS[i].balanceOf(address(this))).mul(TOKENS_MUL[i])
			);
		}
	}

	/**
	 * @dev Returns non-normalised token balances including admin fees
	 * @return balancesWithAdminFee_ array of token balances
	 */		
	function _balancesWithAdminFee ()
		internal
		view
		returns (uint256[N_TOKENS] memory balancesWithAdminFee_)
	{
		for (uint256 i = 0; i < N_TOKENS; i++) {
			balancesWithAdminFee_[i] = TOKENS[i].balanceOf(address(this));
		}
	}

	/**
	 * @dev Withdraw tokens
	 * @param amount_ amount of internal token to burn
	 */	
	function _withdraw (
		uint256 amount_,
		uint256[N_TOKENS] memory outAmounts_
	)
		internal
	{
		require(amount_ != 0, "withdraw amount is zero");
		_burn(msg.sender, amount_);
		for (uint256 i = 0; i < N_TOKENS; i++) {
			if (outAmounts_[i] != 0)
				require(TOKENS[i].transfer(msg.sender, outAmounts_[i]), "token transfer failed");
		}
		emit Withdraw(msg.sender, outAmounts_, amount_);
	}

	/***************************************
					ACTIONS
	****************************************/

	function withdrawAdminFee ()
		external
		nonReentrant
		returns (uint256[N_TOKENS] memory outAmounts_)
	{
		uint256 _adminBalance = adminBalance;
		require(_adminBalance != 0, "admin balance is zero");
		uint256 _totalBalance = _totalBalanceWithAdminFee();
		uint256[N_TOKENS] memory _balances = _balancesWithAdminFee();
		for (uint256 i = 0; i < N_TOKENS; i++) {
			if(_balances[i] != 0){
				outAmounts_[i] = _adminBalance.mul(
					CALC_PRECISION
				).div(
					_totalBalance
				).mul(
					_balances[i]
				).div(
					CALC_PRECISION
				);
				require(TOKENS[i].transfer(adminFeeAddress, outAmounts_[i]));
			}
		}
		emit WithdrawAdminFee(adminFeeAddress, outAmounts_, _adminBalance);
		adminBalance = 0;
	}
	
	/**
	 * @dev Deposit tokens and mints internal tokens to sender as share in pool
	 * @param amounts_ amounts of tokens to deposit in array
	 */	
	function deposit (
		uint256[N_TOKENS] calldata amounts_
	)
		external
		nonReentrant
		whenNotPaused
		returns (uint256 mintAmount_)
	{
		uint256 _totalAmount;
		uint256 _totalBalance = totalBalance();
		for (uint256 i = 0; i < N_TOKENS; i++) {
			if (amounts_[i] != 0) {
				require(
					TOKENS[i].transferFrom(msg.sender, address(this), amounts_[i]),
					"token transfer failed"
				);
				_totalAmount = _totalAmount.add(amounts_[i].mul(TOKENS_MUL[i]));
			}
		}
		require(_totalAmount != 0, "total deposit amount is zero");
		uint256 _totalSupply = totalSupply();
		uint256 _fee;
		if(_totalSupply != 0) {
			_fee = _totalAmount.mul(depositFee).div(PCT_PRECISION);
			mintAmount_ = _calcMint(_totalAmount.sub(_fee), _totalBalance, _totalSupply);
		}else{
			mintAmount_ = _totalAmount;
		}
		_mint(msg.sender, mintAmount_);
		emit Deposit(msg.sender, amounts_, _totalAmount, _fee, mintAmount_);
	}

	/**
	 * @dev Withdraw tokens in current pool proportion
	 * @param amount_ amount of internal token to burn
	 * @return outAmounts_ array of tokens amounts that were withdrawn 
	 */	
	function withdraw (
		uint256 amount_
	)
		external
		nonReentrant
		returns (uint256[N_TOKENS] memory outAmounts_)
	{
		outAmounts_ = calcWithdraw(amount_);
		_withdraw(amount_, outAmounts_);
	}

	/**
	 * @dev Withdraw tokens in unbalanced proportion
	 * @param amount_ amount of internal token to burn
	 * @param outAmountPCTs_ array of token amount percentages to withdraw
	 * @return outAmounts_ array of tokens amounts that were withdrawn 
	 */	
	function widthdrawUnbalanced (
		uint256 amount_,
		uint256[N_TOKENS] calldata outAmountPCTs_
	)
		external
		nonReentrant
		returns (uint256[N_TOKENS] memory outAmounts_)
	{
		outAmounts_ = calcWidthdrawUnbalanced(amount_, outAmountPCTs_);
		_withdraw(amount_, outAmounts_);
	}

	/**
	 * @dev Withdraw exact tokens amounts
	 * @param outAmounts_ array of token amount to withdraw
	 * @return amount_ internal token amount burned on withdraw 
	 */	
	function widthdrawUnbalancedExactOut (		
		uint256[N_TOKENS] calldata outAmounts_
	)
		external
		nonReentrant
		returns (uint256 amount_)
	{
		amount_ = calcWidthdrawUnbalancedExactOut(outAmounts_);
		_withdraw(amount_, outAmounts_);
	}

	/**
	 * @dev Flashloans tokens to caller 
	 * @param amounts_ array of token amounts to borrow
	 * @param data_ encoded function callback to caller
	 */	
	function borrow (
		uint256[N_TOKENS] calldata amounts_,
		bytes calldata data_
	)
		external
		nonReentrant
		whenNotPaused
	{
		uint256 _totalAmount;
		uint256 _totalBalance;
		for (uint256 i = 0; i < N_TOKENS; i++) {
			_totalBalance = _totalBalance.add(
				(TOKENS[i].balanceOf(address(this))).mul(TOKENS_MUL[i])
			);
			if(amounts_[i] != 0) {
				_totalAmount = _totalAmount.add(amounts_[i].mul(TOKENS_MUL[i]));
				require(TOKENS[i].transfer(msg.sender, amounts_[i]), "token transfer failed");
			}
		}
		require(_totalAmount != 0, "flashloan total amount is zero");
		(bool _success, ) = address(msg.sender).call(data_);
		require(_success, "flashloan low-level callback failed");
		uint256 _fee = calcBorrowFee(_totalAmount);
		require(
			_totalBalanceWithAdminFee() >= _totalBalance.add(_fee),
			"flashloan is not paid back as expected"
		);
		uint256 _adminFee = _fee.mul(adminFee).div(PCT_PRECISION);
		adminBalance = adminBalance.add(_adminFee);
		emit Borrow(msg.sender, amounts_, _totalAmount, _fee.sub(_adminFee), _adminFee);
	}
	
	/***************************************
					GETTERS
	****************************************/
	
	/**
	 * @dev Returns normalised total balance of all tokens excluding admin fees
	 * @return uint256 balance
	 */	
	function totalBalance ()
		public
		view
		returns (uint256)
	{
		return (_totalBalanceWithAdminFee()).sub(adminBalance);
	}

	/**
	 * @dev Returns non-normalised token balances excluding admin fees
	 * @return balances_ array of token balances
	 */	
	function balances ()
		public
		view
		returns (uint256[N_TOKENS] memory balances_)
	{
		uint256 _totalBalance = _totalBalanceWithAdminFee();
		uint256[N_TOKENS] memory _balances = _balancesWithAdminFee();
		for (uint256 i = 0; i < N_TOKENS; i++) {
			if(_balances[i] != 0){
				balances_[i] = _balances[i].sub(
					adminBalance.mul(
						CALC_PRECISION
					).div(
						_totalBalance
					).mul(
						_balances[i]
					).div(
						CALC_PRECISION
					)
				);
			}
		}
	}

	/**
	 * @dev Returns non-normalised token balance excluding admin fees
	 * @param token_ token index
	 * @return uint256 token balance
	 */	
	function balance (uint256 token_)
		public
		view
		returns (uint256)
	{
		return balances()[token_];
	}

	/**
	 * @dev Calculates withdraw amounts of tokens in current pool proportion
	 * @param amount_ amount of internal token to burn
	 * @return outAmounts_ array of token amounts will be returned on withdraw 
	 */	
	function calcWithdraw (
		uint256 amount_
	)
		public
		view
		returns (uint256[N_TOKENS] memory outAmounts_)
	{
		uint256 _totalSupply = totalSupply();
		uint256[N_TOKENS] memory _balances = balances();
		for (uint256 i = 0; i < N_TOKENS; i++) {
			if (_balances[i] != 0) {
				outAmounts_[i] = amount_.mul(
					CALC_PRECISION
				).div(
					_totalSupply
				).mul(
					_balances[i]
				).div(
					CALC_PRECISION
				);			
			}
		}
	}

	/**
	 * @dev Calculates unbalanced withdraw tokens amounts 
	 * @param amount_ amount of internal token to burn
	 * @param outAmountPCTs_ array of token amount percentages in ppm to withdraw
	 * @return outAmounts_ array of token amounts will be returned on withdraw 
	 */	
	function calcWidthdrawUnbalanced (
		uint256 amount_,
		uint256[N_TOKENS] calldata outAmountPCTs_
	)
		public
		view
		returns (uint256[N_TOKENS] memory outAmounts_)
	{
		uint256 _amount;
		uint256 _outAmountPCT;
		uint256 _totalSupply = totalSupply();
		uint256 _totalBalance = totalBalance();
		for (uint256 i = 0; i < N_TOKENS; i++) {
			if(outAmountPCTs_[i] != 0){
				_amount = amount_.mul(outAmountPCTs_[i]).div(PCT_PRECISION);
				outAmounts_[i] = _amount.mul(
					CALC_PRECISION
				).div(
					_totalSupply
				).mul(
					_totalBalance.div(TOKENS_MUL[i])
				).div(
					CALC_PRECISION
				);
				_outAmountPCT = _outAmountPCT.add(outAmountPCTs_[i]);
			}
		}
		require(_outAmountPCT == PCT_PRECISION, "total percentage is not 100% in ppm");
	}

	/**
	 * @dev Calculates internal token amount to butn for unbalanced withdraw with exact tokens amounts
	 * @param outAmounts_ array of token amount to withdraw
	 * @return amount_ internal token amount will be burned on withdraw 
	 */	
	function calcWidthdrawUnbalancedExactOut (		
		uint256[N_TOKENS] calldata outAmounts_
	)
		public
		view
		returns (uint256 amount_)
	{
		uint256 _totalSupply = totalSupply();
		uint256 _totalBalance = totalBalance();
		for (uint256 i = 0; i < N_TOKENS; i++) {
			if(outAmounts_[i] != 0){
				amount_ = amount_.add(
					outAmounts_[i].mul(
						CALC_PRECISION
					).div(
						_totalBalance.div(TOKENS_MUL[i])
					).mul(
						_totalSupply
					).div(
						CALC_PRECISION
					)
				);
			}
		}
	}


	/**
	 * @dev Calculates fee for flashloan
	 * @param amount_ amount to borrow
	 */	
	function calcBorrowFee (
		uint256 amount_
	)
		public
		view
		returns (uint256)
	{
		return amount_.mul(borrowFee).div(PCT_PRECISION);
	}

	/**
	 * @dev The current virtual price of internal pool token
	 * @return uint256 normalised virtual price
	 */	
	function virtualPrice ()
		public
		view
		returns (uint256)
	{
		return (totalBalance()).mul(10 ** NORM_BASE).div(totalSupply());
	}

}
