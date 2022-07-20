// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./CrowdSale.sol";

interface ILASM {
    function excludeFromDividends(address account) external;
    function excludeFromFees(address account, bool excluded) external;
}

contract Manager is Context, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ILASM token;
    address public ico_addr;
    address[] public rounds;
    uint256[] public roundAmount;

    event CreateTokenSale(uint256 locktime, uint256 amount, uint256 noRounds);
    event WithdrawToken(address recipient, uint256 amountToken);

    constructor(address token_) {
        token = ILASM(token_);
    }

    receive() external payable {}

    function noRounds() public view returns (uint256) {
        return rounds.length;
    }

    function setToken(address token_) public onlyOwner {
        token = ILASM(token_);
    }

    function getToken() public view returns (address) {
        return address(token);
    }

    function transfer(address recipient, uint256 amount)
        public
        payable
        virtual
        onlyOwner
        returns (bool) {
        require(amount <= IERC20(address(token)).balanceOf(address(this)), "not enough amount");
        IERC20(address(token)).safeTransfer(recipient, amount);
        return true;
    }

    function create_TokenSale(
        uint256 buyTime,
        uint256 lockTime,
        uint256 claimTime,
        uint256 amount
    ) public onlyOwner {
        require(getToken() != address(0), "set Token for Sale");

        if (rounds.length > 0) {
            bool status = isSaleFinalized();
            require(status == true, "Sale in progress");
        }

        require(amount <= IERC20(address(token)).balanceOf(address(this)), "not enough amount");

        Crowdsale ico;
        ico = new Crowdsale(
            buyTime,
            lockTime,
            claimTime,
            payable(owner()),
            IERC20(address(token)),
            payable(owner())
        );
        ico_addr = address(ico);

        token.excludeFromDividends(ico_addr);
        token.excludeFromFees(ico_addr, true);

        require(transfer(ico_addr, amount));

        rounds.push(ico_addr);
        roundAmount.push(amount);

        emit CreateTokenSale(lockTime, amount, rounds.length);
    }

    function totalRoundSaleInfo() public view returns (uint256, uint256, uint256) {
        uint256 length = rounds.length;
        uint256 totalAmountToken;
        uint256 totalAmountPurchased;
        uint256 totalAmountFunds;
        for (uint8 i=0; i<length; i++) {
            (uint256 amountToken, uint256 amountPurchased, uint256 amountFunds) = roundSaleInfo(i);
            totalAmountToken += amountToken;
            totalAmountPurchased += amountPurchased;
            totalAmountFunds += amountFunds;
        }

        return (totalAmountToken, totalAmountPurchased, totalAmountFunds);
    }

    function roundSaleInfo(uint8 index) public view returns (uint256, uint256, uint256) {
        require(index < rounds.length, "Wrong Round Index.");
        uint256 amountToken;
        uint256 amountPurchased;
        uint256 amountFunds;

        amountToken += roundAmount[index];

        address sale_addr = rounds[index];
        Crowdsale sale = Crowdsale(payable(sale_addr));
        amountPurchased += sale._tokenPurchased();
        amountFunds += sale._weiRaised();

        return (amountToken, amountPurchased, amountFunds);
    }

    function isSaleFinalized() public view returns (bool) {
        require(rounds.length > 0, "No round");

        address sale_addr = rounds[rounds.length - 1];
        Crowdsale sale = Crowdsale(payable(sale_addr));

        return sale.finalized();
    }

    function withdrawToken() public onlyOwner {
        uint256 remainingTokensInTheContract = IERC20(address(token)).balanceOf(address(this));
        IERC20(address(token)).safeTransfer(msg.sender, remainingTokensInTheContract);

        emit WithdrawToken(msg.sender, remainingTokensInTheContract);
    }
}
