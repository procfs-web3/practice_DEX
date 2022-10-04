// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Dex is ERC20("DreamSwap", "DEX") {
    IERC20 tokenX;
    IERC20 tokenY;
    bool initialLiquidityProvided;
    constructor(address tokenXAddress, address tokenYAddress) {
        tokenX = IERC20(tokenXAddress);
        tokenY = IERC20(tokenYAddress);
        initialLiquidityProvided = false;
    }    

    function getTokenAddresses() public view returns (address, address) {
        return (address(tokenX), address(tokenY));
    }

    function calculateExchangeRate(uint256 srcTokenAmount, uint256 srcTokenBalance, uint256 dstTokenBalance) internal pure returns (uint256) {
        return dstTokenBalance - srcTokenBalance * dstTokenBalance / (srcTokenBalance + srcTokenAmount);
    }

    function calculateSwapFee(uint256 amount) internal pure returns (uint256) {
        return amount * 1 / 1000;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function swap(uint256 tokenXAmount, uint256 tokenYAmount, uint256 tokenMinimumOutputAmount) public returns (uint256) {
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
            srcTokenBalance = tokenY.balanceOf(address(this));
            dstTokenBalance = tokenX.balanceOf(address(this));
        }
        else {
            srcToken = tokenX;
            dstToken = tokenY;
            srcTokenAmount = tokenXAmount;
            srcTokenBalance = tokenX.balanceOf(address(this));
            dstTokenBalance = tokenY.balanceOf(address(this));
        }
        fee = calculateSwapFee(srcTokenAmount);
        require(fee > 0, "swap: swap amount is too small to incur fees");
        dstTokenAmount = calculateExchangeRate(srcTokenAmount - fee, srcTokenBalance, dstTokenBalance);
        require(dstTokenAmount >= tokenMinimumOutputAmount, "swap: minimum output amount not fulfilled");
        require(srcTokenAmount <= srcToken.balanceOf(msg.sender), "swap: insufficient funds");
        srcToken.transferFrom(msg.sender, address(this), srcTokenAmount);
        dstToken.transfer(msg.sender, dstTokenAmount);
        return dstTokenAmount;
    }

    function addLiquidity(uint256 tokenXAmount, uint256 tokenYAmount, uint256 minimumLPTokenAmount) public returns (uint256) {
        // TODO: check that adding liquidity does not alter exchange rate
        uint256 appropriateTokenXAmount;
        uint256 appropriateTokenYAmount;
        uint256 tokenXActualTransferAmount;
        uint256 tokenYActualTransferAmount;
        uint256 lpTokenAmount;
        uint256 tokenXBalance = tokenX.balanceOf(address(this));
        uint256 tokenYBalance = tokenY.balanceOf(address(this));

        require(tokenXAmount > 0 && tokenYAmount > 0, "addLiquidity: must deposit nonzero number of tokens");
        if (!initialLiquidityProvided) {
            // only at the first call
            tokenXActualTransferAmount = tokenXAmount;
            tokenYActualTransferAmount = tokenYAmount;
        }   

        else {
            appropriateTokenXAmount = tokenXBalance * tokenYAmount / tokenYBalance;
            appropriateTokenYAmount = tokenYBalance * tokenXAmount / tokenXBalance;
            if (appropriateTokenXAmount >= tokenXAmount) {
                // too much Y given
                tokenYActualTransferAmount = appropriateTokenYAmount;
                tokenXActualTransferAmount = tokenXAmount;
            }
            else {
                // too much X given
                tokenXActualTransferAmount = appropriateTokenXAmount;
                tokenYActualTransferAmount = tokenYAmount;
            }
            // only issue LP tokens if the liquidity provider is not the initial provider
        }

        tokenX.transferFrom(msg.sender, address(this), tokenXActualTransferAmount);
        tokenY.transferFrom(msg.sender, address(this), tokenYActualTransferAmount);
        
        if (initialLiquidityProvided) {
            lpTokenAmount = tokenXActualTransferAmount * totalSupply() / tokenXBalance;
            require(lpTokenAmount >= minimumLPTokenAmount, "addLiquidity: minimum LP token amount is not fulfilled");
            _mint(msg.sender, lpTokenAmount);
            return lpTokenAmount;
        }
        else {
            initialLiquidityProvided = true;
            lpTokenAmount = sqrt(tokenXActualTransferAmount * tokenYActualTransferAmount);
            _mint(msg.sender, lpTokenAmount);
            return lpTokenAmount;
        }
    }

    function removeLiquidity(uint256 lpTokenAmount, uint256 minimumTokenXAmount, uint256 minimumTokenYAmount) public returns (uint256, uint256) {
        uint256 tokenXAmount;
        uint256 tokenYAmount;
        uint256 feeRedemptionAmountX;
        uint256 feeRedemptionAmountY;
        uint256 lpSum;
        tokenXAmount = tokenX.balanceOf(address(this)) * lpTokenAmount / totalSupply();
        tokenYAmount = tokenY.balanceOf(address(this)) * lpTokenAmount / totalSupply();
        require(tokenXAmount >= minimumTokenXAmount, "removeLiquidity: minimum X token amount is not fulfilled");
        require(tokenYAmount >= minimumTokenYAmount, "removeLiquidity: minimum Y token amount is not fulfilled");
        tokenX.transfer(msg.sender, tokenXAmount);
        tokenY.transfer(msg.sender, tokenYAmount);
        _burn(msg.sender, lpTokenAmount);
        return (tokenXAmount, tokenYAmount);
    }

    function transfer(address to, uint256 lpAmount) public override returns (bool) {
        _transfer(msg.sender, to, lpAmount);
    }

}