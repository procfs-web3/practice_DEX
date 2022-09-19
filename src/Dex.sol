// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

uint256 constant MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

contract LPToken is ERC20, Ownable {
    constructor() ERC20("LP Token", "LPT") {
        super._mint(msg.sender, MAX_INT);
    }
}

contract Dex {
    IERC20 tokenX;
    IERC20 tokenY;
    LPToken lpToken;

    uint256 public tokenXBalance;
    uint256 public tokenYBalance;
    uint256 public tokenXFees;
    uint256 public tokenYFees;

    constructor(address tokenXAddress, address tokenYAddress) {
        tokenX = IERC20(tokenXAddress);
        tokenY = IERC20(tokenYAddress);
        lpToken = new LPToken();
    }

    function calculateExchangeRate(uint256 srcTokenAmount, uint256 srcTokenBalance, uint256 dstTokenBalance) internal pure returns (uint256) {
        return srcTokenAmount * dstTokenBalance / srcTokenBalance;
    }

    function calculateSwapFee(uint256 amount) internal pure returns (uint256) {
        return amount * 1 / 10;
    }

    function swap(uint256 tokenXAmount, uint256 tokenYAmount, uint256 tokenMinimumOutputAmount) public returns (uint256 outputAmount) {
        uint256 srcTokenAmount;
        uint256 dstTokenAmount;
        uint256 srcTokenBalance;
        uint256 dstTokenBalance;
        uint256 fee;
        IERC20 srcToken;
        IERC20 dstToken;
        require((tokenXAmount == 0 && tokenYAmount > 0) || (tokenYAmount == 0 && tokenXAmount > 0), "swap: ambiguous arguments");
        if (tokenXAmount == 0) {
            srcToken = tokenY;
            dstToken = tokenX;
            srcTokenAmount = tokenYAmount;
            srcTokenBalance = tokenYBalance;
            dstTokenBalance = tokenXBalance;
        }
        else {
            srcToken = tokenX;
            dstToken = tokenY;
            srcTokenAmount = tokenXAmount;
            srcTokenBalance = tokenXBalance;
            dstTokenBalance = tokenYBalance;
        }
        fee = calculateSwapFee(srcTokenAmount);
        require(fee > 0, "swap: swap amount is too small to incur fees");
        dstTokenAmount = calculateExchangeRate(srcTokenAmount, srcTokenBalance, dstTokenBalance);
        require(dstTokenAmount >= tokenMinimumOutputAmount, "swap: minimum output amount not fulfilled");
        require(fee + srcTokenAmount <= srcToken.balanceOf(msg.sender), "swap: insufficient funds");
        srcToken.transferFrom(msg.sender, address(this), srcTokenAmount + fee);
        srcTokenBalance += srcTokenAmount;
        dstToken.transfer(msg.sender, dstTokenAmount);
        dstTokenBalance -= dstTokenAmount;
        if (tokenXAmount == 0) {
            tokenYBalance = srcTokenBalance;
            tokenXBalance = dstTokenBalance;
            tokenYFees += fee;
        }
        else {
            tokenXBalance = srcTokenBalance;
            tokenYBalance = dstTokenBalance;
            tokenXFees += fee;
        }
        return dstTokenAmount;
    }

    function addLiquidity(uint256 tokenXAmount, uint256 tokenYAmount, uint256 minimumLPTokenAmount) public returns (uint256 LPTokenAmount) {
        // TODO: check that adding liquidity does not alter exchange rate
        uint256 exchangeRatePrev;
        uint256 exchangeRateAfter;
        uint256 LPTokenAmount;
        // is this safe?
        exchangeRatePrev = calculateExchangeRate(1 ether, tokenXBalance, tokenYBalance);
        exchangeRateAfter = calculateExchangeRate(1 ether, tokenXBalance + tokenXAmount, tokenYBalance + tokenYAmount);
        require(exchangeRatePrev == exchangeRateAfter, "addLiquidity: cannot add liquidity in a manner that changes the exchange rate");
        // Not a good idea, but 'works'
        LPTokenAmount = tokenXAmount;
        require(LPTokenAmount >= minimumLPTokenAmount, "addLiquidity: minimum LP token amount is not fulfilled");
        tokenX.transferFrom(msg.sender, address(this), tokenXAmount);
        tokenXBalance += tokenXAmount;
        tokenY.transferFrom(msg.sender, address(this), tokenYAmount);
        tokenYBalance += tokenYAmount;
        lpToken.transfer(msg.sender, LPTokenAmount);
    }

    function removeLiquidity(uint256 LPTokenAmount, uint256 minimumTokenXAmount, uint256 minimumTokenYAmount) public {
        uint256 tokenXAmount;
        uint256 tokenYAmount;
        uint256 exchangeRatePrev;
        uint256 exchangeRateAfter;
        require(lpToken.balanceOf(msg.sender) >= LPTokenAmount, "removeLiquidity: insufficient LP token");
        tokenXAmount = LPTokenAmount;
        tokenYAmount = calculateExchangeRate(tokenXAmount, tokenXBalance, tokenYBalance);
        require(tokenXAmount >= minimumTokenXAmount, "removeLiquidity: minimum X token amount is not fulfilled");
        require(tokenYAmount >= minimumTokenYAmount, "removeLiquidity: minimum Y token amount is not fulfilled");
        tokenX.transferFrom(address(this), msg.sender, tokenXAmount);
        tokenXBalance -= tokenXAmount;
        tokenY.transferFrom(address(this), msg.sender, tokenYAmount);
        tokenYBalance -= tokenYAmount;
        lpToken.transferFrom(msg.sender, address(this), LPTokenAmount);
    }

    function transfer(address to, uint256 lpAmount) public returns (bool) {
        if (lpToken.allowance(msg.sender, to) >= lpAmount) {
            lpToken.transferFrom(msg.sender, to, lpAmount);
            return true;
        }
        else {
            return false;
        }
    }

}