## DEX 실습 결과
* 원래라면 patch 브랜치에 커밋하고 merge해야 하지만, 실수로 인해 main에 바로 커밋해 버렸습니다. 모든 패치는 하나의 [커밋](https://github.com/procfs-web3/practice_DEX/commit/e2b56e7967037c726b2e37933f144190387f76dd))에 담겨있습니다. 

### Dex컨트랙트가 ERC20을 상속받도록 수정
기존에는 Dex에 `ERC20 lpToken`이라는 멤버변수로 LP Token을 관리하였습니다. Dex 컨트랙트가 LP Token 그 자체가 되도록 하면 ERC20의 여러 internal method들을 사용할 수 있는 장점이 있어서 수정하였습니다.

### Provision구조체 및 Provisions 배열 사용 중단
멘토들의 피드백 및 다른 드리머들의 오딧 결과에서 제시된 제 컨트랙트의 주 취약점의 원천이 provision구조체였습니다. 가장 중대한 취약점은 아래의 코드에서 발생되었습니다.
```solidity
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
```

문제가 되는 부분은 `p.amount = 0`으로 해놓은 부분으로, remove liquidity로 일부의 LP Token만을 지불해서 LP Token전체가 지불된 것처럼 취급되는 버그입니다. 간단한 해결방안은 `p.amount -= lpTokenAmount`인데, 이러한 방식 역시 2가지 문제점이 있습니다.
* LP Token을 `ERC20::transfer`함수를 이용하여 이동시, `liquidityProvisions` 어레이가 이를 반영하지 못합니다.
* tokenX 또는 tokenY를 여러 객체에게 분산시켜서 `addLiquidity`를 하여 `liquidityProvisions`에 대한 out-of-gas 공격을 할 수 있습니다.
* 근본적으로, `liquidityProvisions`에 있는 모든 정보는 LP Token ERC20 컨트랙트에 (다른 형태로) 남아 있습니다. 중복된 정보를 담고 있는 불필요한 구조체입니다.

따라서, `liquidityProvisions` 구조체를 폐기하고, LP Token의 ERC20 API만을 사용하여 재구현 하였습니다.

### *Balance, *Fee 변수 사용 중단
기존에는 `tokenXBalance`, `tokenXFee`, `tokenYBalance`, `tokenYFee` 4개의 `uint256` 멤버 변수를 사용하였습니다. 이 정보들이 ERC20::balanceOf을 통해서 계산될 수 있음에도 불구하고 멤버 변수로 관리한 이유는, Dex에 토큰을 `addLiquidity`를 통하지 아니한 방법으로 예치하는 것이 보안 취약점이라고 생각했기 때문입니다. 그러나 현재는 멘토 및 다른 드리머들과의 토의를 통해 이것이 보안 취약점이 아님을 이해하였습니다.

따라서, `tokenXBalance`를 사용한 부분은 전부 `tokenX.balanceOf(address(this))`로 고쳐서 사용하였습니다. fee의 경우 별도로 계산하지 않고, `removeLiquidity`에서 반환 토큰양을 계산할 때 `tokenX.balanceOf(address(this))`를 사용하여 자연스럽게 반영하였습니다.

### removeLiquidity에서 tokenY 반환량 계산 로직 수정
기존에는 tokenY 반환량을 계산할 때, 먼저 tokenX 반환량을 계산하고, 현재 exchange rate에 곱하였습니다. 그러나 이렇게 할 필요 없이, tokenY 도 tokenX처럼 LP Token 지분율로 계산하도록 수정하였습니다.