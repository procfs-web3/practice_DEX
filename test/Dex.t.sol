// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "src/Dex.sol";

contract MintableToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {

    }

    function mint(address receiver, uint256 value) public {
        super._mint(receiver, value);
    }
}

contract DexTest is Test {

    Dex dex;
    MintableToken tokenX;
    MintableToken tokenY;
    IERC20 lpToken;

    function setUp() public {
        tokenX = new MintableToken("token X", "TX");
        tokenY = new MintableToken("token Y", "TY");
        tokenX.mint(address(this), 100 ether);
        tokenY.mint(address(this), 100 ether);
        dex = new Dex(address(tokenX), address(tokenY));
        (address _tokX, address _tokY, address lpTokenAddress) = dex.getTokenAddresses();
        lpToken = IERC20(lpTokenAddress);

        // provide initial liquidity
        tokenX.approve(address(dex), 10 ether);
        tokenY.approve(address(dex), 10 ether);
        dex.addLiquidity(10 ether, 10 ether, 0);
    }

    function testAddLiquidityBasic() public {
        tokenX.approve(address(dex), 10 ether);
        tokenY.approve(address(dex), 10 ether);
        uint lpTokenAmount1 = dex.addLiquidity(5 ether, 5 ether, 0);
        tokenX.approve(address(dex), 20 ether);
        tokenY.approve(address(dex), 20 ether);
        uint256 lpTokenAmount2 = dex.addLiquidity(20 ether, 20 ether, 0);
        require(lpTokenAmount2 > lpTokenAmount1);
    }

    function testRemoveLiquidityBasic() public {
        address provider = address(0x11223344);
        tokenX.transfer(provider, 10 ether);
        tokenY.transfer(provider, 10 ether);

        vm.startPrank(provider);
        tokenX.approve(address(dex), 10 ether);
        tokenY.approve(address(dex), 10 ether);
        uint lpTokenAmount = dex.addLiquidity(10 ether, 10 ether, 0);
        uint256 lpBalance = lpToken.balanceOf(provider);
        uint256 balBefore = tokenX.balanceOf(provider);
        lpToken.approve(address(dex), lpBalance);
        dex.removeLiquidity(lpTokenAmount, 0, 0);
        uint256 balAfter = tokenX.balanceOf(provider);
        assertEq(balAfter, balBefore + 10 ether);
    }

    function testSwapBasic() public {
        address actor1 = address(0xaa);
        address actor2 = address(0xbb);
        tokenX.approve(address(dex), 10 ether);
        tokenY.approve(address(dex), 10 ether);
        uint256 lpTokenAmount = dex.addLiquidity(10 ether, 10 ether, 0);
        tokenX.transfer(actor1, 1 ether);
        vm.startPrank(actor1);
        tokenX.approve(address(dex), 1 ether);
        uint256 tokenYAmountFirst = dex.swap(0.1 ether, 0, 0);
        uint256 tokenYAmountSecond = dex.swap(0.1 ether, 0, 0);
        assert(tokenYAmountFirst > tokenYAmountSecond);
    }

    function testFeeBasic() public {
        address actor1 = address(0xaa);
        tokenX.approve(address(dex), 10 ether);
        tokenY.approve(address(dex), 10 ether);
        uint256 lpTokenAmount = dex.addLiquidity(10 ether, 10 ether, 0);
        tokenX.transfer(actor1, 1 ether);
        vm.startPrank(actor1);
        tokenX.approve(address(dex), 1 ether);
        uint256 balBefore = tokenX.balanceOf(actor1);
        uint256 tokenYAmountFirst = dex.swap(0.1 ether, 0, 0);
        uint256 balAfter = tokenX.balanceOf(actor1);
        assertEq(balAfter, balBefore - 0.1001 ether);
        assertEq(dex.tokenXFees(), 0.0001 ether);
    }

    function testFeeRedeem() public {
        address actor1 = address(0xaa);
        address actor2 = address(0xbb);
        address actor3 = address(0xcc);
        tokenX.transfer(actor1, 1 ether);
        tokenY.transfer(actor1, 1 ether);
        tokenX.transfer(actor2, 1 ether);
        tokenY.transfer(actor2, 1 ether);
        tokenX.transfer(actor3, 1 ether);
        tokenY.transfer(actor3, 1 ether);
        
        // provide liquidity
        vm.startPrank(actor1);
        tokenX.approve(address(dex), 1 ether);
        tokenY.approve(address(dex), 1 ether);
        uint lpAmount1 = dex.addLiquidity(1 ether, 1 ether, 0);
        vm.stopPrank();

        vm.startPrank(actor2);
        tokenX.approve(address(dex), 1 ether);
        tokenY.approve(address(dex), 1 ether);
        uint lpAmount2 = dex.addLiquidity(1 ether, 1 ether, 0);
        vm.stopPrank();

        assertEq(lpAmount1, lpAmount2);

        // swap
        vm.startPrank(actor3);
        tokenX.approve(address(dex), 1 ether);
        dex.swap(0.1 ether, 0, 0);
        vm.stopPrank();
        assertEq(dex.tokenXFees(), 0.0001 ether);
        
        // redeem for actor1
        vm.startPrank(actor1);
        lpToken.approve(address(dex), lpAmount1);
        uint actor1XBefore = tokenX.balanceOf(actor1);
        dex.removeLiquidity(lpAmount1, 0, 0);
        uint actor1XAfter = tokenX.balanceOf(actor1);
        assertEq(lpToken.balanceOf(actor1), 0);
        vm.stopPrank();

        // redeem for actor2
        vm.startPrank(actor2);
        lpToken.approve(address(dex), lpAmount2);
        uint actor2XBefore = tokenX.balanceOf(actor2);
        dex.removeLiquidity(lpAmount2, 0, 0);
        uint actor2XAfter = tokenX.balanceOf(actor2);
        assertEq(lpToken.balanceOf(actor2), 0);
        vm.stopPrank();
        // the two must redeem the same amount of tokens
        assertEq(actor2XAfter - actor2XBefore, actor1XAfter - actor1XBefore);
    }

    function testTokenY() public {
        address actor1 = address(0xaa);
        address actor2 = address(0xbb);
        address actor3 = address(0xcc);
        tokenX.transfer(actor1, 1 ether);
        tokenY.transfer(actor1, 1 ether);
        tokenX.transfer(actor2, 1 ether);
        tokenY.transfer(actor2, 1 ether);
        tokenX.transfer(actor3, 1 ether);
        tokenY.transfer(actor3, 1 ether);
        
        // provide liquidity
        vm.startPrank(actor1);
        tokenX.approve(address(dex), 1 ether);
        tokenY.approve(address(dex), 1 ether);
        uint lpAmount1 = dex.addLiquidity(1 ether, 1 ether, 0);
        vm.stopPrank();

        vm.startPrank(actor2);
        tokenX.approve(address(dex), 1 ether);
        tokenY.approve(address(dex), 1 ether);
        uint lpAmount2 = dex.addLiquidity(1 ether, 1 ether, 0);
        vm.stopPrank();

        assertEq(lpAmount1, lpAmount2);

        // swap
        vm.startPrank(actor3);
        tokenY.approve(address(dex), 1 ether);
        dex.swap(0, 0.1 ether, 0);
        vm.stopPrank();
        assertEq(dex.tokenYFees(), 0.0001 ether);
        
        // redeem for actor1
        vm.startPrank(actor1);
        lpToken.approve(address(dex), lpAmount1);
        uint actor1YBefore = tokenY.balanceOf(actor1);
        dex.removeLiquidity(lpAmount1, 0, 0);
        uint actor1YAfter = tokenY.balanceOf(actor1);
        assertEq(lpToken.balanceOf(actor1), 0);
        vm.stopPrank();

        // redeem for actor2
        vm.startPrank(actor2);
        lpToken.approve(address(dex), lpAmount2);
        uint actor2YBefore = tokenY.balanceOf(actor2);
        dex.removeLiquidity(lpAmount2, 0, 0);
        uint actor2YAfter = tokenY.balanceOf(actor2);
        assertEq(lpToken.balanceOf(actor2), 0);
        vm.stopPrank();
        // the two must redeem the same amount of tokens
        assertEq(actor2YAfter - actor2YBefore, actor1YAfter - actor1YBefore);
    }
}