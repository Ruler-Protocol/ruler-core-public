// SPDX-License-Identifier: No License

pragma solidity ^0.8.0;

import "./ERC20/IERC20.sol";
import "./ERC20/IERC20Permit.sol";
import "./ERC20/SafeERC20.sol";
import "./interfaces/IRERC20.sol";
import "./interfaces/IRulerCore.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IRulerZap.sol";
import "./utils/Ownable.sol";

/**
 * @title Ruler Protocol Zap
 * @author alan
 * Main logic is in _depositAndAddLiquidity & _depositAndSwapToPaired
 */
contract RulerZap is Ownable, IRulerZap {
    using SafeERC20 for IERC20;
    IRulerCore public override core;
    IRouter public override router;

    constructor (IRulerCore _core, IRouter _router) {
        require(address(_core) != address(0), "RulerZap: _core is 0");
        require(address(_router) != address(0), "RulerZap: _router is 0");
        core = _core;
        router = _router;
        initializeOwner();
    }

    /**
    * @notice Deposit collateral `_col` to receive paired token `_paired` and rrTokens
    *  - deposits collateral to receive rcTokens and rrTokens
    *  - rcTokens are swapped into paired token through router
    *  - paired token and rrTokens are sent to sender
    */
    function depositAndSwapToPaired(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _minPairedOut,
        address[] calldata _path,
        uint256 _deadline
    ) external override {
        _depositAndSwapToPaired(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _colAmt, 
            _minPairedOut, 
            _path, 
            _deadline
        );
    }

    function depositWithPermitAndSwapToPaired(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _minPairedOut,
        address[] calldata _path,
        uint256 _deadline,
        Permit calldata _colPermit
    ) external override {
        _permit(IERC20Permit(_col), _colPermit);
        _depositAndSwapToPaired(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _colAmt, 
            _minPairedOut, 
            _path, 
            _deadline
        );
    }

    /**
    * @notice Deposit collateral `_col` to receive LP tokens and rrTokens
    *  - deposits collateral to receive rcTokens and rrTokens
    *  - transfers paired token from sender
    *  - rcTokens and `_paired` tokens are added as liquidity to receive LP tokens
    *  - LP tokens and rrTokens are sent to sender
    */
    function depositAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _rcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _rcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline
    ) external override {
        _depositAndAddLiquidity(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _colAmt, 
            _rcTokenDepositAmt, 
            _pairedDepositAmt, 
            _rcTokenDepositMin, 
            _pairedDepositMin,
            _deadline
        );
    }

    function depositWithColPermitAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _rcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _rcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline,
        Permit calldata _colPermit
    ) external override {
        _permit(IERC20Permit(_col), _colPermit);
        _depositAndAddLiquidity(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _colAmt, 
            _rcTokenDepositAmt, 
            _pairedDepositAmt, 
            _rcTokenDepositMin, 
            _pairedDepositMin,
            _deadline
        );
    }

    function depositWithPairedPermitAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _rcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _rcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline,
        Permit calldata _pairedPermit
    ) external override {
        _permit(IERC20Permit(_paired), _pairedPermit);
        _depositAndAddLiquidity(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _colAmt, 
            _rcTokenDepositAmt, 
            _pairedDepositAmt, 
            _rcTokenDepositMin, 
            _pairedDepositMin,
            _deadline
        );
    }

    function depositWithBothPermitsAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _rcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _rcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline,
        Permit calldata _colPermit,
        Permit calldata _pairedPermit
    ) external override {
        _permit(IERC20Permit(_col), _colPermit);
        _permit(IERC20Permit(_paired), _pairedPermit);
        _depositAndAddLiquidity(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _colAmt, 
            _rcTokenDepositAmt, 
            _pairedDepositAmt, 
            _rcTokenDepositMin, 
            _pairedDepositMin,
            _deadline
        );
    }

    function mmDepositAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _rcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _rcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline
    ) external override {
        _mmDepositAndAddLiquidity(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _rcTokenDepositAmt, 
            _pairedDepositAmt, 
            _rcTokenDepositMin, 
            _pairedDepositMin,
            _deadline
        );
    }

    function mmDepositWithPermitAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _rcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _rcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline,
        Permit calldata _pairedPermit
    ) external override {
        _permit(IERC20Permit(_paired), _pairedPermit);
        _mmDepositAndAddLiquidity(
            _col, 
            _paired, 
            _expiry, 
            _mintRatio, 
            _rcTokenDepositAmt, 
            _pairedDepositAmt, 
            _rcTokenDepositMin, 
            _pairedDepositMin,
            _deadline
        );
    }

    /// @notice This contract should never hold any funds.
    /// Any tokens sent here by accident can be retreived.
    function collect(IERC20 _token) external override onlyOwner {
        uint256 balance = _token.balanceOf(address(this));
        require(balance > 0, "RulerZap: balance is 0");
        _token.safeTransfer(msg.sender, balance);
    }

    function updateCore(IRulerCore _core) external override onlyOwner {
        require(address(_core) != address(0), "RulerZap: _core is 0");
        core = _core;
    }

    function updateRouter(IRouter _router) external override onlyOwner {
        require(address(_router) != address(0), "RulerZap: _router is 0");
        router = _router;
    }

    /// @notice check received amount from swap, tokenOut is always the last in array
    function getAmountOut(
        uint256 _tokenInAmt, 
        address[] calldata _path
    ) external view override returns (uint256) {
        return router.getAmountsOut(_tokenInAmt, _path)[_path.length - 1];
    }

    function _depositAndSwapToPaired(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _minPairedOut,
        address[] calldata _path,
        uint256 _deadline
    ) private {
        require(_colAmt > 0, "RulerZap: _colAmt is 0");
        require(_path.length >= 2, "RulerZap: _path length < 2");
        require(_path[_path.length - 1] == _paired, "RulerZap: output != _paired");
        require(_deadline >= block.timestamp, "RulerZap: _deadline in past");
        (address _rcToken, uint256 _rcTokensReceived, ) = _deposit(_col, _paired, _expiry, _mintRatio, _colAmt);

        require(_path[0] == _rcToken, "RulerZap: input != rcToken");
        _approve(IERC20(_rcToken), address(router), _rcTokensReceived);
        router.swapExactTokensForTokens(_rcTokensReceived, _minPairedOut, _path, msg.sender, _deadline);
    }

    function _depositAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt,
        uint256 _rcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _rcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline
    ) private {
        require(_colAmt > 0, "RulerZap: _colAmt is 0");
        require(_deadline >= block.timestamp, "RulerZap: _deadline in past");
        require(_rcTokenDepositAmt > 0, "RulerZap: 0 rcTokenDepositAmt");
        require(_rcTokenDepositAmt >= _rcTokenDepositMin, "RulerZap: rcToken Amt < min");
        require(_pairedDepositAmt > 0, "RulerZap: 0 pairedDepositAmt");
        require(_pairedDepositAmt >= _pairedDepositMin, "RulerZap: paired Amt < min");

        // deposit collateral to Ruler
        IERC20 rcToken;
        uint256 rcTokensBalBefore;
        { // scope to avoid stack too deep errors
            (address _rcToken, uint256 _rcTokensReceived, uint256 _rcTokensBalBefore) = _deposit(_col, _paired, _expiry, _mintRatio, _colAmt);
            require(_rcTokenDepositAmt <= _rcTokensReceived, "RulerZap: rcToken Amt > minted");
            rcToken = IERC20(_rcToken);
            rcTokensBalBefore = _rcTokensBalBefore;
        }

        // received paired tokens from sender
        IERC20 paired = IERC20(_paired);
        uint256 pairedBalBefore = paired.balanceOf(address(this));
        paired.safeTransferFrom(msg.sender, address(this), _pairedDepositAmt);
        uint256 receivedPaired = paired.balanceOf(address(this)) - pairedBalBefore;
        require(receivedPaired > 0, "RulerZap: paired transfer failed");

        // add liquidity for sender
        _approve(rcToken, address(router), _rcTokenDepositAmt);
        _approve(paired, address(router), _pairedDepositAmt);
        router.addLiquidity(
            address(rcToken), 
            address(paired), 
            _rcTokenDepositAmt, 
            receivedPaired, 
            _rcTokenDepositMin,
            _pairedDepositMin,
            msg.sender,
            _deadline
        );

        // sending leftover tokens back to sender
        uint256 rcTokensLeftover = rcToken.balanceOf(address(this)) - rcTokensBalBefore;
        if (rcTokensLeftover > 0) {
            rcToken.safeTransfer(msg.sender, rcTokensLeftover);
        }
        uint256 pairedTokensLeftover = paired.balanceOf(address(this)) - pairedBalBefore;
        if (pairedTokensLeftover > 0) {
            paired.safeTransfer(msg.sender, pairedTokensLeftover);
        }
    }

    function _mmDepositAndAddLiquidity(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _rcTokenDepositAmt,
        uint256 _pairedDepositAmt,
        uint256 _rcTokenDepositMin,
        uint256 _pairedDepositMin,
        uint256 _deadline
    ) private {
        require(_deadline >= block.timestamp, "RulerZap: _deadline in past");
        require(_rcTokenDepositAmt > 0, "RulerZap: 0 rcTokenDepositAmt");
        require(_rcTokenDepositAmt >= _rcTokenDepositMin, "RulerZap: rcToken Amt < min");
        require(_pairedDepositAmt > 0, "RulerZap: 0 pairedDepositAmt");
        require(_pairedDepositAmt >= _pairedDepositMin, "RulerZap: paired Amt < min");

        // transfer all paired tokens from sender to this contract
        IERC20 paired = IERC20(_paired);
        uint256 pairedBalBefore = paired.balanceOf(address(this));
        paired.safeTransferFrom(msg.sender, address(this), _rcTokenDepositAmt + _pairedDepositAmt);
        require(paired.balanceOf(address(this)) - pairedBalBefore == _rcTokenDepositAmt + _pairedDepositAmt, "RulerZap: paired transfer failed");

        // mmDeposit paired to Ruler to receive rcTokens
        ( , , , IRERC20 rcToken, , , , ) = core.pairs(_col, _paired, _expiry, _mintRatio);
        require(address(rcToken) != address(0), "RulerZap: pair not exist");
        uint256 rcTokenBalBefore = rcToken.balanceOf(address(this));
        _approve(paired, address(core), _rcTokenDepositAmt);
        core.mmDeposit(_col, _paired, _expiry, _mintRatio, _rcTokenDepositAmt);
        uint256 rcTokenReceived = rcToken.balanceOf(address(this)) - rcTokenBalBefore;
        require(_rcTokenDepositAmt <= rcTokenReceived, "RulerZap: rcToken Amt > minted");

        // add liquidity for sender
        _approve(rcToken, address(router), _rcTokenDepositAmt);
        _approve(paired, address(router), _pairedDepositAmt);
        router.addLiquidity(
            address(rcToken),
            _paired,
            _rcTokenDepositAmt, 
            _pairedDepositAmt, 
            _rcTokenDepositMin,
            _pairedDepositMin,
            msg.sender,
            _deadline
        );

        // sending leftover tokens (since the beginning of user call) back to sender
        _transferRem(rcToken, rcTokenBalBefore);
        _transferRem(paired, pairedBalBefore);
    }

    function _deposit(
        address _col, 
        address _paired,
        uint48 _expiry,
        uint256 _mintRatio,
        uint256 _colAmt
    ) private returns (address rcTokenAddr, uint256 rcTokenReceived, uint256 rcTokenBalBefore) {
        ( , , , IRERC20 rcToken, IRERC20 rrToken, , , ) = core.pairs(_col, _paired, _expiry, _mintRatio);
        require(address(rcToken) != address(0) && address(rrToken) != address(0), "RulerZap: pair not exist");
        // receive collateral from sender
        IERC20 collateral = IERC20(_col);
        uint256 colBalBefore = collateral.balanceOf(address(this));
        collateral.safeTransferFrom(msg.sender, address(this), _colAmt);
        uint256 received = collateral.balanceOf(address(this)) - colBalBefore;
        require(received > 0, "RulerZap: col transfer failed");

        // deposit collateral to Ruler
        rcTokenBalBefore = rcToken.balanceOf(address(this));
        uint256 rrTokenBalBefore = rrToken.balanceOf(address(this));
        _approve(collateral, address(core), received);
        core.deposit(_col, _paired, _expiry, _mintRatio, received);

        // send rrToken back to sender, and record received rcTokens
        _transferRem(rrToken, rrTokenBalBefore);
        rcTokenReceived = rcToken.balanceOf(address(this)) - rcTokenBalBefore;
        rcTokenAddr = address(rcToken);
    }

    function _approve(IERC20 _token, address _spender, uint256 _amount) private {
        uint256 allowance = _token.allowance(address(this), _spender);
        if (allowance < _amount) {
            if (allowance != 0) {
                _token.safeApprove(_spender, 0);
            }
            _token.safeApprove(_spender, type(uint256).max);
        }
    }

    function _permit(IERC20Permit _token, Permit calldata permit) private {
        _token.permit(
            permit.owner,
            permit.spender,
            permit.amount,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );
    }

    // transfer remaining amount (since the beginnning of action) back to sender
    function _transferRem(IERC20 _token, uint256 _balBefore) private {
        uint256 tokensLeftover = _token.balanceOf(address(this)) - _balBefore;
        if (tokensLeftover > 0) {
            _token.safeTransfer(msg.sender, tokensLeftover);
        }
    }
}