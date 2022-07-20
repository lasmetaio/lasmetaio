
/**

* The smart contracts that run LASM implement the latest trend in ETH tokens, 
* AUTO DIVIDEND YIELDING with an AUTO-DEPOSIT feature. 
* By simply buying and holding LASM you are rewarded!
*
* 4% Auto Reflections Rewarded in LASM
* 4% Auto Liquidity
* 2% Team Development
* 
*/

// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IterableMapping.sol";
import "./DividendPayingToken.sol";

pragma solidity ^0.8.0;

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}


// pragma solidity >=0.6.2;

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract LASM is ERC20, ERC20Burnable, Ownable {
    using SafeMath for uint256;

    // The operator
    address private _operator;

    IUniswapV2Router02 public uniswapV2Router;
    address public  uniswapV2Pair;

    bool private swapping;

    LasmDividendTracker public dividendTracker;
    
    mapping(address => bool) public _isBlacklisted;

    // total supply of token
    uint256 public constant E18 = 10 ** 18;
    uint256 private constant initSupply = 800_000_000 * E18;

    uint256 public swapTokensAtAmount = 80_000 * E18;      // 0.01% of initSupply
    bool public swapAndLiquifyEnabled = true;

    // transaction fee allocation
    uint256 public rewardsFee = 4;
    uint256 public liquidityFee = 4;
    uint256 public teamFee = 2;
    uint256 public totalFees = rewardsFee.add(liquidityFee).add(teamFee);
    uint256 public constant MAXIMUM_TRANSFER_TAX_RATE = 10;

    // dead wallet
    address public constant burnAddress = address(0x000000000000000000000000000000000000dEaD);

    // manager, team dev wallets
    address public constant manager             = address(0x5e81892779c28617B066553d25499B9aD2630a47);
    address public teamDevWalletAddress         = address(0x7446F1c8dE6B48D96D91bdb7a58A09c86dDa9Eac);
    address public buyBackWalletAddress         = address(0x54E67697f90b6E4591def23EefcedD8289E18c8B);

    // vesting wallets
    address public constant locked              = address(0x0102aEa1a3D3F100bAd80feF23a2883a0C980833);
    address public constant team                = address(0xef08430d3e53198160D0cd33b0f84358291640bD);
    address public constant partners            = address(0xe5917b2686f9FA32cC88CF360bF03cCa1a223563);
    address public constant marketing           = address(0xB2f33Cb375E21314A991f14c2d93570013E5a0a4);
    address public constant development         = address(0x939Ad272c00efE7e4398b21b6Aa52A3a6B7BADbF);
    address public constant stakingRewards      = address(0x2Ad0ee5E02c7Be7701416925B72808df99D549ED);
    address public constant airdrop             = address(0xFA39969e9083e6Ddf1F18464573B9B5c002B6310);
    address public constant nftAirdropWallet    = address(0x18758Ea1A29e43A840DcB7EB3D9468294F7967dA);

    // vesting contract
    address public vesting;

    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300_000;

     // exlcude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
    event UpdateDividendTracker(address indexed newAddress, address indexed oldAddress);
    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event SwapAndLiquifyEnabledUpdated(bool enabled);

    event SetSwapTokensAtAmount(uint256 value);
    event SetRewardsFee(uint256 value);
    event SetLiquiditFee(uint256 value);
    event SetTeamDevFee(uint256 value);

    event SetTeamDevWallet(address wallet);
    event SetBuyBackWallet(address wallet);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(
        uint256 tokensamount
    );

    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    modifier onlyOperatorOrOwner() {
        require(_operator == msg.sender || owner() == msg.sender, "operator: caller is not the operator or owner");
        _;
    }

    constructor() ERC20("LasMeta", "LASM") {
        dividendTracker = new LasmDividendTracker(address(this));

        // Uniswap Router address in ethereum
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

         // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(owner());
        dividendTracker.excludeFromDividends(burnAddress);
        dividendTracker.excludeFromDividends(address(_uniswapV2Router));

        dividendTracker.excludeFromDividends(manager);
        dividendTracker.excludeFromDividends(teamDevWalletAddress);
        dividendTracker.excludeFromDividends(buyBackWalletAddress);

        dividendTracker.excludeFromDividends(locked);
        dividendTracker.excludeFromDividends(team);
        dividendTracker.excludeFromDividends(partners);
        dividendTracker.excludeFromDividends(marketing);
        dividendTracker.excludeFromDividends(development);
        dividendTracker.excludeFromDividends(stakingRewards);
        dividendTracker.excludeFromDividends(airdrop);

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(burnAddress, true);
        excludeFromFees(address(dividendTracker), true);

        excludeFromFees(manager, true);
        excludeFromFees(teamDevWalletAddress, true);
        excludeFromFees(buyBackWalletAddress, true);

        excludeFromFees(locked, true);
        excludeFromFees(team, true);
        excludeFromFees(partners, true);
        excludeFromFees(marketing, true);
        excludeFromFees(development, true);
        excludeFromFees(stakingRewards, true);
        excludeFromFees(airdrop, true);
    }

    receive() external payable {
    }

    function burn(uint256 amount) public override {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Returns the address of the current operator.
     */
    function operator() public view returns (address) {
        return _operator;
    }

    /**
     * @dev Transfers operator of the contract to a new account (`newOperator`).
     * Can only be called by the current operator.
     */

    function transferOperator(address newOperator) public onlyOwner {
        require(newOperator != address(0), "BloqBall::transferOperator: new operator is the zero address");
        require(newOperator != _operator, "BloqBall::transferOperator: new operator is the zero address");

        emit OperatorTransferred(_operator, newOperator);

        _operator = newOperator;
    }

    function setVestingSchedule(address _vesting) external onlyOwner {
        require(_vesting != address(0), "Wrong address!");
        require(vesting == address(0), "vesting schedule already started!");

        vesting = _vesting;
        _mint(vesting, initSupply);

        dividendTracker.excludeFromDividends(vesting);
        excludeFromFees(vesting, true);
    } 

    /**
     * @notice Update the dividend trancer and exclude from receiving dividends
     */
    function updateDividendTracker(address newAddress) external onlyOwner {
        require(newAddress != address(dividendTracker), "Lasm: The dividend tracker already has that address");

        LasmDividendTracker newDividendTracker = LasmDividendTracker(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "Lasm: The new dividend tracker must be owned by the LASM token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(owner());
        newDividendTracker.excludeFromDividends(burnAddress);
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));
        newDividendTracker.excludeFromDividends(vesting);

        newDividendTracker.excludeFromDividends(manager);
        newDividendTracker.excludeFromDividends(teamDevWalletAddress);
        newDividendTracker.excludeFromDividends(buyBackWalletAddress);

        newDividendTracker.excludeFromDividends(locked);
        newDividendTracker.excludeFromDividends(team);
        newDividendTracker.excludeFromDividends(partners);
        newDividendTracker.excludeFromDividends(marketing);
        newDividendTracker.excludeFromDividends(development);
        newDividendTracker.excludeFromDividends(stakingRewards);
        newDividendTracker.excludeFromDividends(airdrop);

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    /**
     * @notice Update the uniswap router
     */
    function updateUniswapV2Router(address newAddress) external onlyOwner {
        require(newAddress != address(uniswapV2Router), "Lasm: The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    /**
     * @notice Exclude or include from paying fees
     */
    function excludeFromFees(address account, bool excluded) public onlyOperatorOrOwner {
        require(_isExcludedFromFees[account] != excluded, "Lasm: Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    /**
     * @notice Exclude or include multi accounts from paying fees
     */
    function excludeMultipleAccountsFromFees(address[] memory accounts, bool excluded) external onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    /**
     * @notice Set the limit value to make enable swapping token, adding liquidity, 
     *  sending token to dividendtracker and game developer in transfer
     */ 
    function setSwapTokensAtAmount(uint256 value) external onlyOwner{
        swapTokensAtAmount = value;

        emit SetSwapTokensAtAmount(value);
    }

    /**
     * @notice Set the wallet address for team developer
     */ 
    function setTeamDevWallet(address payable wallet) external onlyOwner{
        teamDevWalletAddress = wallet;
    
        emit SetTeamDevWallet(wallet);
    }
    /**
     * @notice Set the wallet address for buyback
     */ 
    function setBuyBackWallet(address payable wallet) external onlyOwner{
        buyBackWalletAddress = wallet;

        emit SetBuyBackWallet(wallet);
    }

    /**
     * @notice Set the rewards fee for token holders
     */ 
    function setRewardsFee(uint256 value) external onlyOwner{
        require(value <= MAXIMUM_TRANSFER_TAX_RATE, "Invalid percentage");
        rewardsFee = value;
        totalFees = rewardsFee.add(liquidityFee).add(teamFee);

        emit SetRewardsFee(value);
    }

    /**
     * @notice Set the liquidity fee
     */ 
    function setLiquiditFee(uint256 value) external onlyOwner{
        require(value <= MAXIMUM_TRANSFER_TAX_RATE, "Invalid percentage");
        liquidityFee = value;
        totalFees = rewardsFee.add(liquidityFee).add(teamFee);

        emit SetLiquiditFee(value);
    }

    /**
     * @notice Set the transaction fee for game developer
     */ 
    function setTeamDevFee(uint256 value) external onlyOwner{
        require(value <= MAXIMUM_TRANSFER_TAX_RATE, "Invalid percentage");
        teamFee = value;
        totalFees = rewardsFee.add(liquidityFee).add(teamFee);

        emit SetTeamDevFee(value);
    }

    /**
     * @notice Set the automated MarketMakerPair
     */ 
    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != uniswapV2Pair, "Lasm: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }
    
    /**
     * @notice Check whether address is in blacklist
     */ 
    function blacklistAddress(address account, bool value) external onlyOwner{
        _isBlacklisted[account] = value;
    }

    /**
     * @notice Internal function to set the automated MarketMakerPair
     */ 
    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "Lasm: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if(value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    /**
     * @notice Update the gas limit for processing the dividend tracker
     */ 
    function updateGasForProcessing(uint256 newValue) external onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, "Lasm: gasForProcessing must be between 200,000 and 500,000");
        require(newValue != gasForProcessing, "Lasm: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    /**
     * @notice Update the claim wait time in dividendtracker
     */ 
    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    /**
     * @notice Get the claim wait time in dividendtracker
     */ 
    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    /**
     * @notice Update the claim wait time in dividendtracker
     */ 
    function updateMinimumTokenBalanceForDividends(uint256 _amount) external onlyOwner {
        dividendTracker.updateMinimumTokenBalanceForDividends(_amount);
    }

    /**
     * @notice Get the total amount of dividend distributed
     */ 
    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    /**
     * @notice Check whether account in exclude from receiving dividends
     */ 
    function isExcludedFromFees(address account) external view returns(bool) {
        return _isExcludedFromFees[account];
    }

    /**
     * @notice View the amount of dividend in wei that an address has earned in total.
     */ 
    function withdrawableDividendOf(address account) external view returns(uint256) {
        return dividendTracker.withdrawableDividendOf(account);
    }

    /**
     * @notice Getthe dividend token balancer in account
     */ 
    function dividendTokenBalanceOf(address account) external view returns (uint256) {
        return dividendTracker.balanceOf(account);
    }

    /**
     * @notice Exclude from receiving dividends
     */ 
    function excludeFromDividends(address account) external onlyOperatorOrOwner{
        dividendTracker.excludeFromDividends(account);
    }

    /**
     * @notice Get the dividend infor for account
     */ 
    function getAccountDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccount(account);
    }

    /**
     * @notice Get the indexed dividend infor
     */ 
    function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccountAtIndex(index);
    }

    /**
     * @notice Withdraws the token distributed to all token holders
     */
    function processDividendTracker(uint256 gas) external {
        (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    /**
     * @notice Withdraws the token distributed to the sender.
     */
    function claim() external {
        dividendTracker.processAccount(payable(msg.sender), false);
    }

    /**
     * @notice Get the last processed info in dividend tracker
     */
    function getLastProcessedIndex() external view returns(uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    /**
     * @notice Get the number of dividend token holders
     */
    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_isBlacklisted[from] && !_isBlacklisted[to], 'Blacklisted address');

        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if( canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            from != owner() &&
            to != owner() &&
            swapAndLiquifyEnabled
        ) {
            swapping = true;

            uint256 teamDevTokens = contractTokenBalance.mul(teamFee).div(totalFees);
            sendToTeamDevAndBuyBackFee(teamDevTokens);

            uint256 swapTokens = contractTokenBalance.mul(liquidityFee).div(totalFees);
            swapAndLiquify(swapTokens);

            uint256 sellTokens = balanceOf(address(this));

            sendDividends(sellTokens);

            swapping = false;
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if (!(from == uniswapV2Pair || to == uniswapV2Pair)) {
             takeFee = false;
        }

        if(takeFee) {
            uint256 fees = amount.mul(totalFees).div(100);
            amount = amount.sub(fees);

            super._transfer(from, address(this), fees);
        }

        super._transfer(from, to, amount);

        try dividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if(!swapping) {
            uint256 gas = gasForProcessing;

            try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
                emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
            }
            catch {
            }
        }
    }

    /**
     * @notice Send Team developer and buyBack fee
     */ 
    function sendToTeamDevAndBuyBackFee(uint256 tokens) private  {
        uint amount = tokens.div(2);
        super._transfer(address(this), teamDevWalletAddress, amount);

        amount = tokens.sub(amount);
        super._transfer(address(this), buyBackWalletAddress, amount);
    }

    function setSwapAndLiquifyEnabled(bool _enabled) external onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    /**
     * @notice Swap tokens for ETH and add liquidity
     */ 
    function swapAndLiquify(uint256 tokens) private {
       // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

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

    /**
     * @notice Swap tokens for ETH
     */        
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


    /**
     * @notice Add liquidity to uniswap
     */
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {

        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            burnAddress,
            block.timestamp
        );
    }

    /**
     * @notice Send transaction fee to dividend trancer.
     */
    function sendDividends(uint256 tokens) private {
        super._transfer(address(this), address(dividendTracker), tokens);

        dividendTracker.distributeCAKEDividends(tokens);
    }


    // Copied and modified from YAM code:
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernanceStorage.sol
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernance.sol
    // Which is copied and modified from COMPOUND:
    // https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol

    /// @dev A record of each accounts delegate
    mapping (address => address) internal _delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice A record of states for signing / validating signatures
    mapping (address => uint) public nonces;

      /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator)
        external
        view
        returns (address)
    {
        return _delegates[delegator];
    }

   /**
    * @notice Delegate votes from `msg.sender` to `delegatee`
    * @param delegatee The address to delegate votes to
    */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }


    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint nonce,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "BloqBall::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "BloqBall::delegateBySig: invalid nonce");
        require(block.timestamp <= expiry, "BloqBall::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account)
        external
        view
        returns (uint256)
    {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber)
        external
        view
        returns (uint256)
    {
        require(blockNumber < block.number, "BloqBall::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee)
        internal
    {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator); // balance of underlying BQBs (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    )
        internal
    {
        uint32 blockNumber = safe32(block.number, "BloqBall::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal view returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}

contract LasmDividendTracker is Ownable, DividendPayingToken {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;

    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public minimumTokenBalanceForDividends;

    event ExcludeFromDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor(address _cake) DividendPayingToken("Lasm_Dividend_Tracker", "LDT", _cake) {
        claimWait = 3600;
        minimumTokenBalanceForDividends = 100 * (10**18); //must hold 100 + tokens
    }

    function _transfer(address, address, uint256) internal pure override {
        require(false, "Lasm_Dividend_Tracker: No transfers allowed");
    }

    function withdrawDividend() public pure override {
        require(false, "Lasm_Dividend_Tracker: withdrawDividend disabled. Use the 'claim' function on the main LASM contract.");
    }

    function excludeFromDividends(address account) external onlyOwner {
        require(!excludedFromDividends[account]);
        excludedFromDividends[account] = true;

        _setBalance(account, 0);
        tokenHoldersMap.remove(account);

        emit ExcludeFromDividends(account);
    }

    function updateClaimWait(uint256 newClaimWait) external onlyOwner {
        require(newClaimWait >= 3600 && newClaimWait <= 86400, "Lasm_Dividend_Tracker: claimWait must be updated to between 1 and 24 hours");
        require(newClaimWait != claimWait, "Lasm_Dividend_Tracker: Cannot update claimWait to same value");
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function updateMinimumTokenBalanceForDividends(uint256 amount) external onlyOwner {
        minimumTokenBalanceForDividends = amount;
    }

    function getLastProcessedIndex() external view returns(uint256) {
        return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }

    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ?
                                                        tokenHoldersMap.keys.length.sub(lastProcessedIndex) :
                                                        0;


                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }


        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);

        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ?
                                    lastClaimTime.add(claimWait) :
                                    0;

        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ?
                                                    nextClaimTime.sub(block.timestamp) :
                                                    0;
    }

    function getAccountAtIndex(uint256 index)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
        if(lastClaimTime > block.timestamp)  {
            return false;
        }

        return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address payable account, uint256 newBalance) external onlyOwner {
        if(excludedFromDividends[account]) {
            return;
        }

        if(newBalance >= minimumTokenBalanceForDividends) {
            _setBalance(account, newBalance);
            tokenHoldersMap.set(account, newBalance);
        }
        else {
            _setBalance(account, 0);
            tokenHoldersMap.remove(account);
        }

        processAccount(account, true);
    }

    function process(uint256 gas) public returns (uint256, uint256, uint256) {
        uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

        if(numberOfTokenHolders == 0) {
            return (0, 0, lastProcessedIndex);
        }

        uint256 _lastProcessedIndex = lastProcessedIndex;

        uint256 gasUsed = 0;

        uint256 gasLeft = gasleft();

        uint256 iterations = 0;
        uint256 claims = 0;

        while(gasUsed < gas && iterations < numberOfTokenHolders) {
            _lastProcessedIndex++;

            if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
                _lastProcessedIndex = 0;
            }

            address account = tokenHoldersMap.keys[_lastProcessedIndex];

            if(canAutoClaim(lastClaimTimes[account])) {
                if(processAccount(payable(account), true)) {
                    claims++;
                }
            }

            iterations++;

            uint256 newGasLeft = gasleft();

            if(gasLeft > newGasLeft) {
                gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
            }

            gasLeft = newGasLeft;
        }

        lastProcessedIndex = _lastProcessedIndex;

        return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic) public onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account);

        if(amount > 0) {
            lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
            return true;
        }

        return false;
    }
}
