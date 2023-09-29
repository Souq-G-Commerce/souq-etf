// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "../interfaces/ICustomCamelotRouter.sol";
import "../interfaces/IExchangeSwapWithOutQuote.sol";
import "../interfaces/IAccessManager.sol";
import "../interfaces/IAddressesRegistry.sol";
import "../libraries/VaultErrors.sol";

/**
 * @title CamelotExchangeSwap
 * @author Souq.Finance
 * @notice The Camelot Swap Exchange connector
 * @notice License: https://souq-peripherals.s3.amazonaws.com/LICENSE.md
 */

contract CamelotExchangeSwap is IExchangeSwapWithOutQuote {
    ICustomCamelotRouter public immutable swapRouter;
    address public immutable addressesRegistry;
    address owner;

    mapping(address => mapping(address => address[])) public tokenPath;

    event WithdrawDust(address tokenAddress, uint256 amount);

    constructor(ICustomCamelotRouter _swapRouter, address _registry) {
        require(_registry != address(0), VaultErrors.ADDRESS_IS_ZERO);
        swapRouter = _swapRouter;
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
     * @dev Swap tokens using CamelotSwap.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _amountIn The amount of input tokens to swap.
     * @param _amountOutMin The minimum amount of output tokens expected.
     * @return The actual amount of output tokens received.
     */

    function swap(address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _amountOutMin) external returns (uint256) {
        require(_tokenIn != address(0), VaultErrors.ADDRESS_IS_ZERO);
        require(_tokenOut != address(0), VaultErrors.ADDRESS_IS_ZERO);
        IERC20(_tokenIn).approve(address(this), _amountIn);

        TransferHelper.safeTransferFrom(_tokenIn, msg.sender, address(this), _amountIn);
        TransferHelper.safeApprove(_tokenIn, address(swapRouter), _amountIn);

        swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn,
            _amountOutMin,
            tokenPath[_tokenIn][_tokenOut],
            msg.sender,
            address(0),
            block.timestamp
        );

        return _amountOutMin;
    }


    /**
     * @dev Get the estimated amount of input tokens needed to receive a specific amount of output tokens.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _amountOut The desired amount of output tokens.
     * @return The estimated amount of input tokens required.
     */

    function getQuoteOut(address _tokenIn, address _tokenOut, uint _amountOut) external view returns (uint256) {
        uint256[] memory amountIn = swapRouter.getAmountsIn(_amountOut, tokenPath[_tokenIn][_tokenOut]);
        return amountIn[0];
    }

    /**
     * @dev Get the estimated amount of output tokens to receive a specific amount of input tokens.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _amountIn The amount of input tokens.
     * @return The estimated amount of output tokens.
     */

    function getQuoteIn(address _tokenIn, address _tokenOut, uint _amountIn) external view returns (uint256) {
        uint256[] memory amountOut = swapRouter.getAmountsOut(_amountIn, tokenPath[_tokenIn][_tokenOut]);
        return amountOut[tokenPath[_tokenIn][_tokenOut].length - 1];
    }

    /**
     * @dev Add a custom token path for swapping between tokens.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _path The custom token path.
     */

    function addTokenPath(address _tokenIn, address _tokenOut, address[] calldata _path) external onlyVaultAdminOrOperations {
        require(_tokenIn != address(0), VaultErrors.ADDRESS_IS_ZERO);
        require(_tokenOut != address(0), VaultErrors.ADDRESS_IS_ZERO);
        tokenPath[_tokenIn][_tokenOut] = _path;
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

    /**
     * @dev Get the custom token path between two tokens.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @return The custom token path.
     */

    function getTokenPath(address _tokenIn, address _tokenOut) external view returns (address[] memory) {
        return tokenPath[_tokenIn][_tokenOut];
    }
}
