// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IExchangeSwapWithOutQuote.sol";
import "../interfaces/IMMESVS.sol";
import "../interfaces/ILPTokenSVS.sol";
import "../interfaces/IAccessManager.sol";
import "../interfaces/IAddressesRegistry.sol";
import "../libraries/VaultErrors.sol";


/**
 * @title SouqExchangeSwap
 * @author Souq.Finance
 * @notice The Souq Swap Exchange connector
 * @notice License: https://souq-peripherals.s3.amazonaws.com/LICENSE.md
 */
contract SouqExchangeSwap is IExchangeSwapWithOutQuote {
    IMMESVS public amm;
    address public immutable addressesRegistry;
    address owner;

    event WithdrawDust(address tokenAddress, uint256 amount);

    constructor(address _registry) {
        require(_registry != address(0), VaultErrors.ADDRESS_IS_ZERO);
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
     * @dev Set the Automated Market Maker (AMM) contract.
     * @param _amm The address of the AMM contract.
     */

    function setAMM(IMMESVS _amm) external onlyVaultAdminOrOperations {
        amm = _amm;
    }

    /**
     * @dev Swap tokens using the Souq Exchange Swap.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _amountInMaximum The maximum amount of input tokens to swap.
     * @param _amountOut The desired amount of output tokens.
     * @return The actual amount of output tokens received.
     */

    function swap(address _tokenIn, address _tokenOut, uint256 _amountInMaximum, uint256 _amountOut) external returns (uint256) {
        require(_tokenIn != address(0), VaultErrors.ADDRESS_IS_ZERO);
        require(_tokenOut != address(0), VaultErrors.ADDRESS_IS_ZERO);
        uint256 beforeLPBalance = IERC20(_tokenOut).balanceOf(address(this));
        IMMESVS(amm).addLiquidityStable(_amountOut, _amountInMaximum);

        require(
            IERC20(_tokenOut).balanceOf(address(this)) >= beforeLPBalance + _amountOut,
            "SouqExchangeSwap: Not enough LP tokens received"
        );
        return _amountOut;
    }

    /**
     * @dev Get the estimated amount of input tokens required to receive a specific amount of output tokens.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _amountOut The desired amount of output tokens.
     * @return The estimated amount of input tokens required.
     */

    /// @notice Returns the amount in required to receive the given exact output amount but for a swap. Function signature is in the same format as other exchange swap contracts
    function getQuoteOut(address _tokenIn, address _tokenOut, uint256 _amountOut) external returns (uint256) {
        uint256 LPPrice = IMMESVS(amm).getLPPrice();
        return ((_amountOut * LPPrice) / 10 ** 18) + 1; // 1e6 is to convert back from the 6 decimal places, round up so quote is always enough
    }

    /**
     * @dev Function to get the Quote specifying the amount in
     * @param _tokenIn the input token (VIT)
     * @param _tokenOut the output token (stablecoin)
     * @param _amountIn the amount of VIT to get the received stablecoin
     * @return uint256 the amount of stablecoin to receive
     */
    function getQuoteIn(address _tokenIn, address _tokenOut, uint256 _amountIn) external returns (uint256) {
        uint256 LPPrice = IMMESVS(amm).getLPPrice();
        return ((_amountIn * (10 ** 18)) / LPPrice);
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
