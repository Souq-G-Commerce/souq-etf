// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IExchangeSwapWithOutQuote.sol";
import "../interfaces/IAccessManager.sol";
import "../interfaces/IAddressesRegistry.sol";
import "../libraries/VaultErrors.sol";

/**
 * @title UniV3ExchangeSwap
 * @author Souq.Finance
 * @notice The uniswapv3 Swap Exchange connector
 * @notice License: https://souq-peripherals.s3.amazonaws.com/LICENSE.md
 */
contract UniV3ExchangeSwap is IExchangeSwapWithOutQuote {
    ISwapRouter public immutable swapRouter;
    IQuoter public immutable quoter;
    address public immutable addressesRegistry;
    address owner;

    mapping(address => mapping(address => uint24)) public fee;

    event WithdrawDust(address tokenAddress, uint256 amount);

    constructor(ISwapRouter _swapRouter, IQuoter _quoter, address _registry) {
        require(_registry != address(0), VaultErrors.ADDRESS_IS_ZERO);
        swapRouter = _swapRouter;
        quoter = _quoter;
        addressesRegistry = _registry;
        owner = msg.sender;
    }

    modifier onlyVaultAdminOrOperations() {
        require(
            IAccessManager(IAddressesRegistry(addressesRegistry).getAccessManager()).isPoolAdmin(msg.sender) ||
                IAccessManager(IAddressesRegistry(addressesRegistry).getAccessManager()).isPoolOperations(msg.sender),
            VaultErrors.CALLER_IS_NOT_VAULT_ADMIN_OR_OPERATIONS
        );
        _;
    }

    /**
     * @dev Swap tokens using the UniV3ExchangeSwap.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _amountInMaximum The maximum amount of input tokens to swap.
     * @param _amountOut The desired amount of output tokens.
     * @return amountIn The actual amount of input tokens swapped.
     */

    function swap(address _tokenIn, address _tokenOut, uint256 _amountInMaximum, uint256 _amountOut) external returns (uint256 amountIn) {
        require(_tokenIn != address(0), VaultErrors.ADDRESS_IS_ZERO);
        require(_tokenOut != address(0), VaultErrors.ADDRESS_IS_ZERO);
        uint256 initialTokenInBalance = IERC20(_tokenIn).balanceOf(address(this));

        IERC20(_tokenIn).approve(address(this), _amountInMaximum);
        TransferHelper.safeTransferFrom(_tokenIn, msg.sender, address(this), _amountInMaximum);
        TransferHelper.safeApprove(_tokenIn, address(swapRouter), _amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: fee[_tokenIn][_tokenOut],
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: _amountOut,
            amountInMaximum: _amountInMaximum,
            sqrtPriceLimitX96: 0
        });

        amountIn = swapRouter.exactOutputSingle(params);

        uint256 remainingTokenInBalance = IERC20(_tokenIn).balanceOf(address(this)) - initialTokenInBalance;
        if (remainingTokenInBalance > 0) {
            TransferHelper.safeTransfer(_tokenIn, msg.sender, remainingTokenInBalance);
        }
    }

    /**
     * @dev Get the estimated amount of input tokens required to receive a specific amount of output tokens.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _amountOut The desired amount of output tokens.
     * @return The estimated amount of input tokens required.
     */

    /// @notice Returns the amount in required to receive the given exact output amount but for a swap of a single pool
    function getQuoteOut(address _tokenIn, address _tokenOut, uint256 _amountOut) external returns (uint256) {
        return quoter.quoteExactOutputSingle(_tokenIn, _tokenOut, fee[_tokenIn][_tokenOut], _amountOut, 0);
    }

    /**
     * @dev Get the estimated amount of output tokens to receive a specific amount of input tokens.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _amountIn The amount of input tokens.
     * @return The estimated amount of output tokens.
     */

    /// @notice Returns the amount out to be received given exact input amount but for a swap of a single pool
    function getQuoteIn(address _tokenIn, address _tokenOut, uint256 _amountIn) external returns (uint256) {
        return quoter.quoteExactInputSingle(_tokenIn, _tokenOut, fee[_tokenIn][_tokenOut], _amountIn, 0);
    }

    /**
     * @dev Set the fee for a token pair.
     * @param _tokenIn The first token in the pair.
     * @param _tokenOut The second token in the pair.
     * @param _fee The fee to set.
     */

    function setFee(address _tokenIn, address _tokenOut, uint24 _fee) external {
        require(_tokenIn != address(0), VaultErrors.ADDRESS_IS_ZERO);
        require(_tokenOut != address(0), VaultErrors.ADDRESS_IS_ZERO);
        //bidirectional fee
        fee[_tokenIn][_tokenOut] = _fee;
        fee[_tokenOut][_tokenIn] = _fee;
    }

    /**
     * @dev Allows the contract owner to withdraw small amounts of tokens (dust).
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
}
