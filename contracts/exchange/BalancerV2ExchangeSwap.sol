// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "../interfaces/balancerV2/vault/IVault.sol";
import "../interfaces/IExchangeSwapWithOutQuote.sol";
import "../libraries/VaultErrors.sol";

/**
 * @title BalancerV2ExchangeSwap
 * @author Souq.Finance
 * @notice The Balancer Swap Exchange connector
 * @notice License: https://souq-peripherals.s3.amazonaws.com/LICENSE.md
 */
contract BalancerV2ExchangeSwap is IExchangeSwapWithOutQuote {
    IVault public immutable vault;
    address owner;

    struct ExchangePool {
        address token1;
        address token2;
        bytes32 poolId;
    }

    mapping(bytes32 => ExchangePool) public tokenPairs;

    event WithdrawDust(address tokenAddress, uint256 amount);

    constructor(IVault _vault) {
        vault = _vault;
        owner = msg.sender;
    }

    /**
     * @dev Adds a new token pair for swapping.
     * @param token1 The first token address.
     * @param token2 The second token address.
     * @param poolId The pool ID associated with the token pair.
     */

    function addTokenPair(address token1, address token2, bytes32 poolId) external {
        require(token1 != address(0), VaultErrors.ADDRESS_IS_ZERO);
        require(token2 != address(0), VaultErrors.ADDRESS_IS_ZERO);
        bytes32 pairHash = getPairHash(token1, token2);
        bytes32 pairHash2 = getPairHash(token2, token1);

        tokenPairs[pairHash] = ExchangePool(token1, token2, poolId);
        tokenPairs[pairHash2] = ExchangePool(token2, token1, poolId);
    }

    /**
     * @dev Gets the pool ID for a given token pair.
     * @param tokenA The first token address.
     * @param tokenB The second token address.
     * @return The pool ID associated with the token pair.
     */

    function getPool(address tokenA, address tokenB) public view returns (bytes32) {
        bytes32 pairHash = getPairHash(tokenA, tokenB);
        return tokenPairs[pairHash].poolId;
    }

    /**
     * @dev Gets the hash of a token pair.
     * @param token1 The first token address.
     * @param token2 The second token address.
     * @return The hash of the token pair.
     */

    function getPairHash(address token1, address token2) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(token1, token2));
    }

    /**
     * @dev Swaps tokens using Balancer V2.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _amountTokenInMax The maximum amount of input tokens.
     * @param _exactAmountTokenOut The exact amount of output tokens.
     * @return The amount of output tokens received.
     */

    //Balancer don't let contracts swap on behalf of users (unless the contract is part of the relayer DAO list. So we have to transfer the funds to this contract, perform the swap, then transfer the funds back...)
    function swap(address _tokenIn, address _tokenOut, uint256 _amountTokenInMax, uint256 _exactAmountTokenOut) external returns (uint256) {
        require(_tokenIn != address(0), VaultErrors.ADDRESS_IS_ZERO);
        require(_tokenOut != address(0), VaultErrors.ADDRESS_IS_ZERO);
        uint256 initialTokenInBalance = IERC20(_tokenIn).balanceOf(address(this));

        uint256 tokenOutBefore = IERC20(_tokenOut).balanceOf(address(this));
        bytes32 poolId = getPool(_tokenIn, _tokenOut);

        IERC20(_tokenIn).approve(address(this), _amountTokenInMax);
        IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountTokenInMax);

        IVault.SingleSwap memory singleSwap = IVault.SingleSwap(
            poolId,
            IVault.SwapKind.GIVEN_OUT,
            IAsset(_tokenIn),
            IAsset(_tokenOut),
            _exactAmountTokenOut,
            bytes("")
        );
        IVault.FundManagement memory funds = IVault.FundManagement(address(this), false, payable(address(this)), false);
        uint256 limit = _amountTokenInMax;
        uint256 deadline = block.timestamp + 500;

        IERC20(_tokenIn).approve(address(vault), _amountTokenInMax);
        uint256 amountOut = vault.swap(singleSwap, funds, limit, deadline);

        require(
            IERC20(_tokenOut).balanceOf(address(this)) >= tokenOutBefore + _exactAmountTokenOut,
            "Balancer swap failed, not enough tokens received"
        );
        IERC20(_tokenOut).transfer(msg.sender, _exactAmountTokenOut);

        uint256 remainingTokenInBalance = IERC20(_tokenIn).balanceOf(address(this)) - initialTokenInBalance;
        if (remainingTokenInBalance > 0) {
            IERC20(_tokenIn).transfer(msg.sender, remainingTokenInBalance);
        }

        return amountOut;
    }

    /**
     * @dev Calculates the quote for a given swap from _tokenIn to _tokenOut with a specified _amountOut.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _amountOut The desired amount of output tokens.
     * @return The estimated amount of input tokens needed.
     */

    function getQuoteOut(address _tokenIn, address _tokenOut, uint256 _amountOut) external returns (uint256) {
        bytes32 poolId = getPool(_tokenIn, _tokenOut);
        IVault.BatchSwapStep memory batchSwapStep = IVault.BatchSwapStep(poolId, 0, 1, _amountOut, bytes(""));

        IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](1);
        swaps[0] = batchSwapStep;

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(_tokenIn);
        assets[1] = IAsset(_tokenOut);

        int256[] memory results = vault.queryBatchSwap(
            IVault.SwapKind.GIVEN_OUT,
            swaps,
            assets,
            IVault.FundManagement(address(this), false, payable(address(this)), false)
        );

        return uint256(results[0]); //this should never be a negative value so it's safe to cast to uint
    }

    /**
     * @dev Calculates the quote for a given swap from _tokenIn to _tokenOut with a specified _amountIn.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _amountIn The amount of input tokens.
     * @return The estimated amount of output tokens.
     */

    function getQuoteIn(address _tokenIn, address _tokenOut, uint256 _amountIn) external returns (uint256) {
        bytes32 poolId = getPool(_tokenIn, _tokenOut);
        IVault.BatchSwapStep memory batchSwapStep = IVault.BatchSwapStep(poolId, 0, 1, _amountIn, bytes(""));

        IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](1);
        swaps[0] = batchSwapStep;

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(_tokenIn);
        assets[1] = IAsset(_tokenOut);

        int256[] memory results = vault.queryBatchSwap(
            IVault.SwapKind.GIVEN_IN,
            swaps,
            assets,
            IVault.FundManagement(address(this), false, payable(address(this)), false)
        );

        return uint256(abs(results[results.length - 1])); //this should never be a negative value so it's safe to cast to uint
    }

    /**
     * @dev Allows the contract owner to withdraw dust (small amounts) of a specific token.
     * @param tokenAddress The address of the token to withdraw.
     * @param amount The amount of tokens to withdraw.
     */

    function withdrawDust(address tokenAddress, uint256 amount) external {
        require(msg.sender == owner, VaultErrors.ONLY_OWNER_CAN_WITHDRAW_DUST);
        require(tokenAddress != address(0), VaultErrors.ADDRESS_IS_ZERO);
        IERC20 token = IERC20(tokenAddress);
        token.transfer(owner, amount);

        emit WithdrawDust(tokenAddress, amount);
    }

    /**
     * @dev Returns the absolute value of an int256.
     * @param x The input value.
     * @return The absolute value of x as a uint256.
     */

    function abs(int256 x) public pure returns (uint256) {
        if (x < 0) {
            return uint256(-x);
        }
        return uint256(x);
    }
}
