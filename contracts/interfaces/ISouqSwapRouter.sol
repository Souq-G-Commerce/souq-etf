// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

interface ISouqSwapRouter {
    function setExchangeSwapContract(address _tokenIn, address _tokenOut, address _exchangeSwapContract) external;
    function getContract(address _tokenIn) external view returns (address);
}