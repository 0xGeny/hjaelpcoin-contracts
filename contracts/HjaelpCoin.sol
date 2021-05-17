// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IBEP20.sol";
import "./interfaces/uniswap/IUniswapV2Factory.sol";
import "./interfaces/uniswap/IUniswapV2Pair.sol";
import "./interfaces/uniswap/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HjaelpCoin is Context, IBEP20, Ownable {
  using SafeMath for uint256;
  
  uint256 private constant MAX = ~uint256(0);
  address private constant routerAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

  mapping (address => uint256) private _balances;
  mapping (address => mapping (address => uint256)) private _allowances;

  uint256 private _totalSupply;
  uint256 private _maxSupply;
  uint8 private _decimals;
  string private _symbol;
  string private _name;

  mapping (address => bool) private _isExcludedFromFee;
  uint256 public _taxFee;
  uint256 public _liquidityFee;

  IUniswapV2Router02 public immutable uniswapV2Router;
  address public immutable uniswapV2Pair;
  
  bool inSwapAndLiquify;
  bool public swapAndLiquifyEnabled = true;
  
  uint256 public _maxHoldAmount;
  uint256 public _maxTxAmount;
  uint256 private _minTokensToAddToLiquidity;

  address private providerAddress;

  event SwapAndLiquifyEnabledUpdated(bool enabled);
  event SwapAndLiquify(
    uint256 tokensSwapped,
    uint256 ethReceived,
    uint256 tokensIntoLiqudity
  );
  
  modifier lockTheSwap {
    inSwapAndLiquify = true;
    _;
    inSwapAndLiquify = false;
  }

  constructor() {
    _name = "HjaelpCoin";
    _symbol = "HJAELP";
    _decimals = 18;
    _maxSupply = 1000000000 * (10 ** 18);    // Max Supply: 1B
    _totalSupply = 0;

    // unit of 0.01%
    _taxFee = 400;
    _liquidityFee = 400;

    _maxHoldAmount = 1000000 * (10 ** 18);   // Holding Limit: 1M (0.1% of Total Supply)
    _maxTxAmount = MAX;                      // Transaction Limit (Max as default)
    _minTokensToAddToLiquidity = 10000 * (10 ** 18);    // 0.1M

    // The service provider wallet that takes tax from transactions
    providerAddress = owner();

    IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(routerAddress);
    // Create a uniswap pair for this new token
    address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
      .createPair(address(this), _uniswapV2Router.WETH());

    // Set the rest of the contract variables
    uniswapV2Router = _uniswapV2Router;
    uniswapV2Pair = _uniswapV2Pair;
    
    // Exclude owner and this contract from fee
    _isExcludedFromFee[owner()] = true;
    _isExcludedFromFee[address(this)] = true;
    _isExcludedFromFee[providerAddress] = true;
    _isExcludedFromFee[routerAddress] = true;
    _isExcludedFromFee[_uniswapV2Pair] = true;
  }

  /**
   * @dev Returns the bep token owner.
   */
  function getOwner() external view override returns (address) {
    return owner();
  }

  /**
   * @dev Returns the token decimals.
   */
  function decimals() external view override returns (uint8) {
    return _decimals;
  }

  /**
   * @dev Returns the token symbol.
   */
  function symbol() external view override returns (string memory) {
    return _symbol;
  }

  /**
  * @dev Returns the token name.
  */
  function name() external view override returns (string memory) {
    return _name;
  }

  /**
   * @dev See {BEP20-totalSupply}.
   */
  function totalSupply() external view override returns (uint256) {
    return _totalSupply;
  }

  /**
   * @dev Maximum Supply of token.
   */
  function maxSupply() external view returns (uint256) {
    return _maxSupply;
  }

  /**
   * @dev See {BEP20-balanceOf}.
   */
  function balanceOf(address account) external view override returns (uint256) {
    return _balances[account];
  }

  /**
   * @dev See {BEP20-transfer}.
   *
   * Requirements:
   *
   * - `recipient` cannot be the zero address.
   * - the caller must have a balance of at least `amount`.
   */
  function transfer(address recipient, uint256 amount) external override returns (bool) {
    _transfer(_msgSender(), recipient, amount);
    return true;
  }

  /**
   * @dev See {BEP20-allowance}.
   */
  function allowance(address owner, address spender) external view override returns (uint256) {
    return _allowances[owner][spender];
  }

  /**
   * @dev See {BEP20-approve}.
   *
   * Requirements:
   *
   * - `spender` cannot be the zero address.
   */
  function approve(address spender, uint256 amount) external override returns (bool) {
    _approve(_msgSender(), spender, amount);
    return true;
  }

  /**
   * @dev See {BEP20-transferFrom}.
   *
   * Emits an {Approval} event indicating the updated allowance. This is not
   * required by the EIP. See the note at the beginning of {BEP20};
   *
   * Requirements:
   * - `sender` and `recipient` cannot be the zero address.
   * - `sender` must have a balance of at least `amount`.
   * - the caller must have allowance for `sender`'s tokens of at least
   * `amount`.
   */
  function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
    _transfer(sender, recipient, amount);
    _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "BEP20: transfer amount exceeds allowance"));
    return true;
  }

  /**
   * @dev Atomically increases the allowance granted to `spender` by the caller.
   *
   * This is an alternative to {approve} that can be used as a mitigation for
   * problems described in {BEP20-approve}.
   *
   * Emits an {Approval} event indicating the updated allowance.
   *
   * Requirements:
   *
   * - `spender` cannot be the zero address.
   */
  function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
    _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
    return true;
  }

  /**
   * @dev Atomically decreases the allowance granted to `spender` by the caller.
   *
   * This is an alternative to {approve} that can be used as a mitigation for
   * problems described in {BEP20-approve}.
   *
   * Emits an {Approval} event indicating the updated allowance.
   *
   * Requirements:
   *
   * - `spender` cannot be the zero address.
   * - `spender` must have allowance for the caller of at least
   * `subtractedValue`.
   */
  function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
    _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "BEP20: decreased allowance below zero"));
    return true;
  }

  /**
   * @dev Creates `amount` tokens and assigns them to `msg.sender`, increasing
   * the total supply.
   *
   * Requirements
   *
   * - `msg.sender` must be the token owner
   */
  function mint(address account, uint256 amount) public onlyOwner returns (bool) {
    _mint(account, amount);
    return true;
  }

  /** @dev Creates `amount` tokens and assigns them to `account`, increasing
   * the total supply.
   *
   * Emits a {Transfer} event with `from` set to the zero address.
   *
   * Requirements
   *
   * - `to` cannot be the zero address.
   */
  function _mint(address account, uint256 amount) internal {
    require(account != address(0), "BEP20: mint to the zero address");

    _totalSupply = _totalSupply.add(amount);
    _balances[account] = _balances[account].add(amount);
    emit Transfer(address(0), account, amount);
  }

  
  /**
   * @dev Destroys `amount` tokens from `account`, reducing the
   * the total supply.
   *
   * Requirements
   *
   * - `msg.sender` must be the token owner
   */
  function burn(address account, uint256 amount) public onlyOwner {
    _burn(account, amount);
  }

  /**
   * @dev Destroys `amount` tokens from `account`, reducing the
   * total supply.
   *
   * Emits a {Transfer} event with `to` set to the zero address.
   *
   * Requirements
   *
   * - `account` cannot be the zero address.
   * - `account` must have at least `amount` tokens.
   */
  function _burn(address account, uint256 amount) internal {
    require(account != address(0), "BEP20: burn from the zero address");

    _balances[account] = _balances[account].sub(amount, "BEP20: burn amount exceeds balance");
    _totalSupply = _totalSupply.sub(amount);
    emit Transfer(account, address(0), amount);
  }

  /**
   * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
   *
   * This is internal function is equivalent to `approve`, and can be used to
   * e.g. set automatic allowances for certain subsystems, etc.
   *
   * Emits an {Approval} event.
   *
   * Requirements:
   *
   * - `owner` cannot be the zero address.
   * - `spender` cannot be the zero address.
   */
  function _approve(address owner, address spender, uint256 amount) internal {
    require(owner != address(0), "BEP20: approve from the zero address");
    require(spender != address(0), "BEP20: approve to the zero address");

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  /**
   * @dev Destroys `amount` tokens from `account`.`amount` is then deducted
   * from the caller's allowance.
   *
   * See {_burn} and {_approve}.
   */
  function _burnFrom(address account, uint256 amount) internal {
    _burn(account, amount);
    _approve(account, _msgSender(), _allowances[account][_msgSender()].sub(amount, "BEP20: burn amount exceeds allowance"));
  }

  function excludeFromFee(address account) public onlyOwner {
    _isExcludedFromFee[account] = true;
  }
  
  function includeInFee(address account) public onlyOwner {
    _isExcludedFromFee[account] = false;
  }
  
  function setTaxFeePercent(uint256 taxFee) external onlyOwner {
    _taxFee = taxFee;
  }
  
  function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
    _liquidityFee = liquidityFee;
  }

  // unit of 0.01%
  function setMaxHoldingPercent(uint256 maxHoldingPercent) external onlyOwner {
    _maxHoldAmount = _totalSupply.mul(maxHoldingPercent).div(10000);
  }

  // unit of 0.01%
  function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
    _maxTxAmount = _totalSupply.mul(maxTxPercent).div(10000);
  }
  
  function setMinTokensToAddToLiquidity(uint256 minTokensToAddToLiquidity) external onlyOwner {
    _minTokensToAddToLiquidity = minTokensToAddToLiquidity;
  }

  function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
    swapAndLiquifyEnabled = _enabled;
    emit SwapAndLiquifyEnabledUpdated(_enabled);
  }

  function setProviderAddress(address newProviderAddress) external onlyOwner {
    // Remove the current provider from Tax Exclusion List.
    includeInFee(providerAddress);

    // Remove the current provider from Tax Exclusion List.
    excludeFromFee(newProviderAddress);
    
    providerAddress = newProviderAddress;
  }

  /**
   * @dev Moves tokens `amount` from `sender` to `recipient`.
   *
   * This is internal function is equivalent to {transfer}, and can be used to
   * e.g. implement automatic token fees, slashing mechanisms, etc.
   *
   * Emits a {Transfer} event.
   *
   * Requirements:
   *
   * - `sender` cannot be the zero address.
   * - `recipient` cannot be the zero address.
   * - `sender` must have a balance of at least `amount`.
   */
  function _transfer(address sender, address recipient, uint256 amount) internal {
    checkTxValid(sender, recipient, amount);

    uint256 totalFee = 0;
    if (!_isExcludedFromFee[sender] && !_isExcludedFromFee[recipient]) {
      // Take tax of transaction and transfer to the provider wallet.
      uint256 taxFeeAmount = amount.mul(_taxFee).div(10000);
      _balances[providerAddress] = _balances[providerAddress].add(taxFeeAmount);
      
      // Take tax of transaction and add to liquidity.
      uint256 liquidityFeeAmount = amount.mul(_liquidityFee).div(10000);
      _balances[address(this)] = _balances[address(this)].add(liquidityFeeAmount);

      // is the token balance of this contract address over the min number of
      // tokens that we need to initiate a swap + liquidity lock?
      // also, don't get caught in a circular liquidity event.
      // also, don't swap & liquify if sender is uniswap pair.
      uint256 contractTokenBalance = _balances[address(this)];
      
      if(contractTokenBalance >= _maxTxAmount)
      {
        contractTokenBalance = _maxTxAmount;
      }
      
      bool overMinTokenBalance = contractTokenBalance >= _minTokensToAddToLiquidity;
      if (
          overMinTokenBalance &&
          !inSwapAndLiquify &&
          sender != uniswapV2Pair &&
          swapAndLiquifyEnabled
      ) {
          contractTokenBalance = _minTokensToAddToLiquidity;
          //add liquidity
          swapAndLiquify(contractTokenBalance);
      }
      
      totalFee = taxFeeAmount.add(liquidityFeeAmount);
    }
    
    _balances[sender] = _balances[sender].sub(amount);
    _balances[recipient] = _balances[recipient].add(amount.sub(totalFee));
    emit Transfer(sender, recipient, amount);
  }
  
  function checkTxValid(address sender, address recipient, uint256 amount) internal view {
    require(sender != address(0), "BEP20: transfer from the zero address");
    require(recipient != address(0), "BEP20: transfer to the zero address");
    require(amount > 0, "Transfer amount must be greater than zero");
    require(_balances[sender] > amount, "Transfer amount exceeds balance");
    require(_balances[recipient].add(amount) <= _maxHoldAmount, "Recipient balance exceeds holding limit");
    if (sender != owner() && recipient != owner())
      require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");
  }
  
  function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
    // split the contract balance into halves
    uint256 half = contractTokenBalance.div(2);
    uint256 otherHalf = contractTokenBalance.sub(half);

    // capture the contract's current ETH balance.
    // this is so that we can capture exactly the amount of ETH that the
    // swap creates, and not make the liquidity event include any ETH that
    // has been manually sent to the contract
    uint256 initialBalance = address(this).balance;

    // swap tokens for ETH
    swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

    // how much ETH did we just swap into?
    uint256 newBalance = address(this).balance.sub(initialBalance);

    // add liquidity to uniswap
    addLiquidity(otherHalf, newBalance);
    
    emit SwapAndLiquify(half, newBalance, otherHalf);
  }

  function swapTokensForEth(uint256 tokenAmount) private {
    // generate the uniswap pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = uniswapV2Router.WETH();

    _approve(address(this), address(uniswapV2Router), tokenAmount);

    // make the swap
    uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount,
      0, // accept any amount of ETH
      path,
      address(this),
      block.timestamp
    );
  }

  function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
    // approve token transfer to cover all possible scenarios
    _approve(address(this), address(uniswapV2Router), tokenAmount);

    // add the liquidity
    uniswapV2Router.addLiquidityETH{value: ethAmount}(
      address(this),
      tokenAmount,
      0, // slippage is unavoidable
      0, // slippage is unavoidable
      owner(),
      block.timestamp
    );
  }

}