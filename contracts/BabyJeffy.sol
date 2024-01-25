// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./BEP20/BEP20.sol";

interface IRouter {
    function WETH() external view returns (address);
    function factory() external view returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract BabyJeffy is BEP20 {
    using SafeMath for uint256;
    using Address for address payable;

    address private constant zeroAddr = 0x0000000000000000000000000000000000000000;

    IRouter private immutable router;
    IFactory private immutable factory;
    address private immutable weth;
    address private pair;

    bool private swapping;
    bool private tradingEnabled;

    address private taxer = 0x0748b2A6D1afbB04D004a8dbFcD1e365f9d1e836;

    uint256 private supply = 1 * (10**9) * (10**18);
    uint256 private swapThreshold = supply * 5 / 10000;
    uint256 private swapMax = supply * 5 / 10000;

    uint256 public fee = 5;
    bool private starting;

    mapping(address => bool) public isExcludedFromFee;

    constructor() BEP20("Baby Jeffy", "BABYJEFFY") {
        router = IRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        weth = router.WETH();
        factory = IFactory(router.factory());
        pair = factory.createPair(weth, address(this));

        excludeFromFee(taxer, true);
        excludeFromFee(owner(), true);
        excludeFromFee(address(this), true);

        _approve(address(this), address(router), ~uint256(0));

        _mint(owner(), supply);
    }

    receive() external payable {}

    function excludeFromFee(address account, bool isExcluded) public onlyOwner {
        isExcludedFromFee[account] = isExcluded;
    }

    function isSwapPair(address addr) private returns (bool) {
        if(pair == zeroAddr) {
            pair = factory.getPair(weth, address(this));
        }
        return pair != zeroAddr && pair == addr;
    }

    function enableTrading() external onlyOwner {
        tradingEnabled = true;
        starting = true;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != zeroAddr, "BEP20: transfer from the zero address");
        require(to != zeroAddr, "BEP20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        uint256 feeInContract = balanceOf(address(this));
        if (
            feeInContract > swapThreshold &&
            !isSwapPair(from) &&
            !swapping &&
            !isExcludedFromFee[from] &&
            !isExcludedFromFee[to]
        ) {
            swapping = true;
            _swapAndTransferFee(min(amount, min(feeInContract, swapMax)));
            swapping = false;
        }

        bool takeFee = !swapping;

        if (isExcludedFromFee[from] || isExcludedFromFee[to]) {
            takeFee = false;
        }

        if (takeFee) {
            uint256 feeAmount = 0;
            if(isSwapPair(from) || isSwapPair(to)) {
                require(tradingEnabled, "trading is not enabled");
                feeAmount = amount.mul(fee).div(100);
            }

            if (feeAmount > 0) {
                super._transfer(from, address(this), feeAmount);
                amount = amount.sub(feeAmount);
            }
        }

        super._transfer(from, to, amount);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? b : a;
    }

    function _swapAndTransferFee(uint256 amount) private {
        _swapForETH(amount);
        payable(taxer).sendValue(address(this).balance);
    }

    function _swapForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp);
    }
}