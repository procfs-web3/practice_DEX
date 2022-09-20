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
    
    struct Provision {
        address provider;
        uint256 amount;
    }

    Provision[] liquidityProvisions;
    uint256 initialLpTokenIssueAmount;

    constructor(address tokenXAddress, address tokenYAddress) {
        tokenX = IERC20(tokenXAddress);
        tokenY = IERC20(tokenYAddress);
        tokenXBalance = 0;
        tokenYBalance = 0;
        tokenXFees = 0;
        tokenYFees = 0;
        lpToken = new LPToken();
    }    

    function getTokenAddresses() public view returns (address, address, address) {
        return (address(tokenX), address(tokenY), address(lpToken));
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

    function addLiquidity(uint256 tokenXAmount, uint256 tokenYAmount, uint256 minimumLPTokenAmount) public returns (uint256) {
        // TODO: check that adding liquidity does not alter exchange rate
        uint256 appropriateTokenXAmount;
        uint256 appropriateTokenYAmount;
        uint256 tokenXActualTransferAmount;
        uint256 tokenYActualTransferAmount;
        uint256 lpTokenAmount;
        bool firstTime;

        require(tokenXAmount > 0 && tokenYAmount > 0, "addLiquidity: must deposit nonzero number of tokens");
        if (tokenXBalance == 0 && tokenYBalance == 0) {
            // only at the first call
            tokenXActualTransferAmount = tokenXAmount;
            tokenYActualTransferAmount = tokenYAmount;
            firstTime = true;
        }   

        else {
            require(tokenXBalance > 0 && tokenYBalance > 0, "addLiquidity: balance of all tokens must be nonzero");
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
            firstTime = false;
        }

        tokenX.transferFrom(msg.sender, address(this), tokenXActualTransferAmount);
        tokenXBalance += tokenXActualTransferAmount;
        tokenY.transferFrom(msg.sender, address(this), tokenYActualTransferAmount);
        tokenYBalance += tokenYActualTransferAmount;
        
        if (!firstTime) {
            uint256 lpSum = initialLpTokenIssueAmount;
            for (uint i = 0; i < liquidityProvisions.length; i++) {
                Provision storage p = liquidityProvisions[i];
                lpSum += p.amount;
            }
            lpTokenAmount = tokenXActualTransferAmount * lpSum / (tokenXBalance - tokenXActualTransferAmount);
            require(lpTokenAmount >= minimumLPTokenAmount, "addLiquidity: minimum LP token amount is not fulfilled");
            lpToken.transfer(msg.sender, lpTokenAmount);

            for (uint i = 0; i < liquidityProvisions.length; i++) {
                Provision storage p = liquidityProvisions[i];
                if (p.provider == msg.sender) {
                    p.amount += lpTokenAmount;
                    return lpTokenAmount;
                }
            }
            Provision memory p;
            p.provider = msg.sender;
            p.amount = lpTokenAmount;
            liquidityProvisions.push(p);
            return lpTokenAmount;
        }
        else {
            initialLpTokenIssueAmount = sqrt(tokenXActualTransferAmount * tokenYActualTransferAmount);
            return initialLpTokenIssueAmount;
        }
    }

    function removeLiquidity(uint256 lpTokenAmount, uint256 minimumTokenXAmount, uint256 minimumTokenYAmount) public {
        uint256 tokenXAmount;
        uint256 tokenYAmount;
        uint256 feeRedemptionAmountX;
        uint256 feeRedemptionAmountY;
        uint256 lpSum;
        uint256 senderLpTokenAmount;
        require(lpToken.balanceOf(msg.sender) >= lpTokenAmount, "removeLiquidity: insufficient LP token");
        lpSum = initialLpTokenIssueAmount;
        for (uint i = 0; i < liquidityProvisions.length; i++) {
            Provision storage p = liquidityProvisions[i];
            lpSum += p.amount;
        }
        tokenXAmount = tokenXBalance * lpTokenAmount / lpSum;
        tokenYAmount = calculateExchangeRate(tokenXAmount, tokenXBalance, tokenYBalance);
        require(tokenXAmount >= minimumTokenXAmount, "removeLiquidity: minimum X token amount is not fulfilled");
        require(tokenYAmount >= minimumTokenYAmount, "removeLiquidity: minimum Y token amount is not fulfilled");
        tokenX.transfer(msg.sender, tokenXAmount);
        tokenXBalance -= tokenXAmount;
        tokenY.transfer(msg.sender, tokenYAmount);
        tokenYBalance -= tokenYAmount;
        lpToken.transferFrom(msg.sender, address(this), lpTokenAmount);

        // now, redeem fees. In this case, don't include initial lp token issue amount to lpSum
        lpSum = 0;
        senderLpTokenAmount = 0;
        for (uint i = 0; i < liquidityProvisions.length; i++) {
            Provision storage p = liquidityProvisions[i];
            lpSum += p.amount;
            if (p.provider == msg.sender) { 
                // vulnerable to gas exhuastion, should remove entry instead of zeroing it out
                senderLpTokenAmount = p.amount;
                p.amount = 0;
            }
        }
        assert(senderLpTokenAmount > 0);
        feeRedemptionAmountX = tokenXFees * senderLpTokenAmount / lpSum;
        feeRedemptionAmountY = tokenYFees * senderLpTokenAmount / lpSum;
        tokenX.transfer(msg.sender, feeRedemptionAmountX);
        tokenXFees -= feeRedemptionAmountX;
        tokenY.transfer(msg.sender, feeRedemptionAmountY);
        tokenYFees -= feeRedemptionAmountY;
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