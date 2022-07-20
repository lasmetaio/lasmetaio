// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Crowdsale is Context, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // The token being sold
    IERC20 private _token;
    IERC20 public USDT;

    // Address where funds are collected
    address payable private _wallet;
    address payable public _manager;

    uint256 public minBuy       = 150   ether;
    uint256 public maxBuy       = 750   ether;
    uint256 public sale_price   = 0.043 ether;

    // Amount of wei raised
    uint256 public _weiRaised;
    uint256 public _tokenPurchased;
    bool public success;
    bool public finalized;
    bool public _buyable;
    
    event TokensPurchased(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    
    mapping (address => uint256) public purchase;
    mapping (address => uint256) public claimed;
    mapping (address => uint256) public msgValue;

    uint256 current = block.timestamp * 1 seconds;

    uint256 public immutable buyTime;           //  60 days
    uint256 public immutable limitationtime ;   // 180 days
    uint256 public immutable claimeTime;        // 150 days
    
    constructor (uint256 buyTime_, uint256 lockTime, uint256 claimTime_, address payable manager_, 
        IERC20 token_, address payable wallet_) {
        require(address(token_) != address(0), "Crowdsale: token is the zero address");

        _manager = manager_;
        _token = token_;
        _wallet = wallet_;

        buyTime = block.timestamp + buyTime_ * 1 seconds;
        limitationtime = block.timestamp + (buyTime_ + lockTime) * 1 seconds;
        claimeTime = block.timestamp + (buyTime_ + lockTime + claimTime_) * 1 seconds;

        USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);   // USDT address on Ethereum mainnet
    }
    
    /**
     * @dev fallback function ***DO NOT OVERRIDE***
     * Note that other contracts will transfer funds with a base gas stipend
     * of 2300, which is not enough to call buyTokens. Consider calling
     * buyTokens directly when purchasing tokens from a contract.
     */

    receive () external payable {
    }

    /**
     * @return the token being sold.
     */
    function token() public view returns (IERC20) {
        return _token;
    }

    /**
     * @return the address where funds are collected.
     */
    function wallet() public view returns (address payable) {
        return _wallet;
    }

    function getPrice() public view returns(uint256){
        return (10**18) / sale_price;
    }

    /**
     * @return the amount of wei raised.
     */
    function weiRaised() public view returns (uint256) {
        return _weiRaised;
    }

    function buyable()public returns(bool) { 
        if(buyTime > block.timestamp){
            _buyable = true;
        }
        return _buyable;
    }

    function buyTokens(uint256 amount) public nonReentrant {
        require(buyTime > block.timestamp, "Buy Time expired");
        require(amount >= minBuy && amount <= maxBuy,"Wrong amount range.");

        uint256 one = 1 ether;
        uint256 tokens =  (one * amount) / sale_price;
        require(_token.balanceOf(address(this)) >= tokens, "buy amount exceeds not enough Tokens remaining");

        USDT.safeTransferFrom(_msgSender(), address(this), amount);

        _tokenPurchased = _tokenPurchased + tokens;
        _weiRaised = _weiRaised + amount;
        
        msgValue[_msgSender()] = msgValue[_msgSender()] + amount;
        purchase[_msgSender()] = purchase[_msgSender()] + tokens;
    }

    function pendingTokens(address account) public view returns (uint256) {
        uint value;
        if (block.timestamp < limitationtime)
            value = 0;
        else if (block.timestamp >= claimeTime) {
            value = purchase[account] - claimed[account];
        }
        else {
            uint initValue = purchase[account] / 5;
            uint remainValue = purchase[account] - initValue;

            value = initValue;
            value += remainValue * (block.timestamp - limitationtime) / (claimeTime - limitationtime);
            value -= claimed[account];
        }

        return value;
    }

    function claim() public nonReentrant {
        require (block.timestamp > limitationtime);
        require (finalized,"IDO not finalized yet");

        uint256 tokenAmount = pendingTokens(_msgSender());  
        require (tokenAmount > 0, "0 tokens to claim");
        require(_token.balanceOf(address(this)) >= tokenAmount, "claim amount exceeds not enough Tokens remaining");

        _token.safeTransfer(_msgSender(), tokenAmount);

        claimed[_msgSender()] += tokenAmount;
    }
    
    function balance() public view returns(uint){
        return _token.balanceOf(address(this));
    }

    function finalize() public nonReentrant {
        require( buyTime < block.timestamp, "the crowdSale is in progress");
        require(!finalized,"already finalized");
        require(_msgSender() == _manager,"you are not the owner");

         uint256 remainingTokensInTheContract = _token.balanceOf(address(this)) - _tokenPurchased;
        _token.safeTransfer(address(_wallet), remainingTokensInTheContract);

        _forwardFunds(_weiRaised);
        finalized = true;
    }

    /**
     * @dev Determines how ETH is stored/forwarded on purchases.
     */
    function _forwardFunds(uint256 amount) internal {
      USDT.safeTransfer(_wallet, amount);
    }
}