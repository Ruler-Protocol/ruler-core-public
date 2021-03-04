// SPDX-License-Identifier: No License

pragma solidity ^0.8.0;

import "./ERC20/IERC20.sol";
import "./ERC20/IERC20Permit.sol";
import "./ERC20/SafeERC20.sol";
import "./interfaces/IERC3156FlashBorrower.sol";
import "./interfaces/IERC3156FlashLender.sol";
import "./interfaces/IRERC20.sol";
import "./interfaces/IRTokenProxy.sol";
import "./interfaces/IRulerCore.sol";
import "./interfaces/IOracle.sol";
import "./utils/Clones.sol";
import "./utils/Create2.sol";
import "./utils/Initializable.sol";
import "./utils/Ownable.sol";
import "./utils/ReentrancyGuard.sol";

/**
 * @title RulerCore contract
 * @author crypto-pumpkin
 * Ruler Pair: collateral, paired token, expiry, mintRatio
 *  - ! Paired Token cannot be a deflationary token !
 *  - rTokens have same decimals of each paired token
 *  - all Ratios are 1e18
 *  - rTokens have same decimals as Paired Token
 *  - Collateral can be deflationary token, but not rebasing token
 */
contract RulerCore is Ownable, IRulerCore, IERC3156FlashLender, ReentrancyGuard {
  using SafeERC20 for IERC20;

  // following ERC3156 https://eips.ethereum.org/EIPS/eip-3156
  bytes32 public constant FLASHLOAN_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

  bool public override paused;
  IOracle public override oracle;
  address public override responder;
  address public override feeReceiver;
  address public override rERC20Impl;
  uint256 public override flashLoanRate;

  address[] public override collaterals;
  /// @notice collateral => minimum collateralization ratio, paired token default to 1e18
  mapping(address => uint256) public override minColRatioMap;
  /// @notice collateral => pairedToken => expiry => mintRatio => Pair
  mapping(address => mapping(address => mapping(uint48 => mapping(uint256 => Pair)))) public override pairs;
  mapping(address => Pair[]) private pairList;
  mapping(address => uint256) public override feesMap;

  modifier onlyNotPaused() {
    require(!paused, "Ruler: paused");
    _;
  }

  function initialize(address _rERC20Impl, address _feeReceiver) external initializer {
    require(_rERC20Impl != address(0), "Ruler: _rERC20Impl cannot be 0");
    require(_feeReceiver != address(0), "Ruler: _feeReceiver cannot be 0");
    rERC20Impl = _rERC20Impl;
    feeReceiver = _feeReceiver;
    flashLoanRate = 0.00085 ether;
    initializeOwner();
    initializeReentrancyGuard();
  }

  /// @notice market make deposit, deposit paired Token to received rcTokens, considered as an immediately repaid loan
  function mmDeposit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rcTokenAmt
  ) public override onlyNotPaused nonReentrant {
    Pair memory pair = pairs[_col][_paired][_expiry][_mintRatio];
    _validateDepositInputs(_col, pair);

    pair.rcToken.mint(msg.sender, _rcTokenAmt);
    feesMap[_paired] = feesMap[_paired] + _rcTokenAmt * pair.feeRate / 1e18;

    // record loan ammount to colTotal as it is equivalent to be an immediately repaid loan
    uint256 colAmount = _getColAmtFromRTokenAmt(_rcTokenAmt, _col, address(pair.rcToken), pair.mintRatio);
    pairs[_col][_paired][_expiry][_mintRatio].colTotal = pair.colTotal + colAmount;

    // receive paired tokens from sender, deflationary token is not allowed
    IERC20 pairedToken = IERC20(_paired);
    uint256 pairedBalBefore =  pairedToken.balanceOf(address(this));
    pairedToken.safeTransferFrom(msg.sender, address(this), _rcTokenAmt);
    require(pairedToken.balanceOf(address(this)) - pairedBalBefore >= _rcTokenAmt, "Ruler: transfer paired failed");
    emit MarketMakeDeposit(msg.sender, _col, _paired, _expiry, _mintRatio, _rcTokenAmt);
  }

  function mmDepositWithPermit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rcTokenAmt,
    Permit calldata _pairedPermit
  ) external override {
    _permit(_paired, _pairedPermit);
    mmDeposit(_col, _paired, _expiry, _mintRatio, _rcTokenAmt);
  }

  /// @notice deposit collateral to a Ruler Pair, sender receives rcTokens and rrTokens
  function deposit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _colAmt
  ) public override onlyNotPaused nonReentrant {
    Pair memory pair = pairs[_col][_paired][_expiry][_mintRatio];
    _validateDepositInputs(_col, pair);

    // receive collateral
    IERC20 collateral = IERC20(_col);
    uint256 colBalBefore =  collateral.balanceOf(address(this));
    collateral.safeTransferFrom(msg.sender, address(this), _colAmt);
    uint256 received = collateral.balanceOf(address(this)) - colBalBefore;
    require(received > 0, "Ruler: transfer failed");
    pairs[_col][_paired][_expiry][_mintRatio].colTotal = pair.colTotal + received;

    // mint rTokens for reveiced collateral
    uint256 mintAmount = _getRTokenAmtFromColAmt(received, _col, _paired, pair.mintRatio);
    pair.rcToken.mint(msg.sender, mintAmount);
    pair.rrToken.mint(msg.sender, mintAmount);
    emit Deposit(msg.sender, _col, _paired, _expiry, _mintRatio, received);
  }

  function depositWithPermit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _colAmt,
    Permit calldata _colPermit
  ) external override {
    _permit(_col, _colPermit);
    deposit(_col, _paired, _expiry, _mintRatio, _colAmt);
  }

  /// @notice redeem with rrTokens and rcTokens before expiry only, sender receives collateral, fees charged on collateral
  function redeem(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rTokenAmt
  ) external override onlyNotPaused nonReentrant {
    Pair memory pair = pairs[_col][_paired][_expiry][_mintRatio];
    require(pair.mintRatio != 0, "Ruler: pair does not exist");
    require(block.timestamp <= pair.expiry, "Ruler: expired, col forfeited");
    pair.rrToken.burnByRuler(msg.sender, _rTokenAmt);
    pair.rcToken.burnByRuler(msg.sender, _rTokenAmt);

    // send collateral to sender
    uint256 colAmountToPay = _getColAmtFromRTokenAmt(_rTokenAmt, _col, address(pair.rcToken), pair.mintRatio);
    // once redeemed, it won't be considered as a loan for the pair anymore
    pairs[_col][_paired][_expiry][_mintRatio].colTotal = pair.colTotal - colAmountToPay;
    // accrue fees on payment
    _sendAmtPostFeesOptionalAccrue(IERC20(_col), colAmountToPay, pair.feeRate, true /* accrue */);
    emit Redeem(msg.sender, _col, _paired, _expiry, _mintRatio, _rTokenAmt);
  }

  /// @notice repay with rrTokens and paired token amount, sender receives collateral, no fees charged on collateral
  function repay(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rrTokenAmt
  ) public override onlyNotPaused nonReentrant {
    Pair memory pair = pairs[_col][_paired][_expiry][_mintRatio];
    require(pair.mintRatio != 0, "Ruler: pair does not exist");
    require(block.timestamp <= pair.expiry, "Ruler: expired, col forfeited");
    pair.rrToken.burnByRuler(msg.sender, _rrTokenAmt);

    // receive paired tokens from sender, deflationary token is not allowed
    IERC20 pairedToken = IERC20(_paired);
    uint256 pairedBalBefore =  pairedToken.balanceOf(address(this));
    pairedToken.safeTransferFrom(msg.sender, address(this), _rrTokenAmt);
    require(pairedToken.balanceOf(address(this)) - pairedBalBefore >= _rrTokenAmt, "Ruler: transfer paired failed");
    feesMap[_paired] = feesMap[_paired] + _rrTokenAmt * pair.feeRate / 1e18;

    // send collateral back to sender
    uint256 colAmountToPay = _getColAmtFromRTokenAmt(_rrTokenAmt, _col, address(pair.rrToken), pair.mintRatio);
    _safeTransfer(IERC20(_col), msg.sender, colAmountToPay);
    emit Repay(msg.sender, _col, _paired, _expiry, _mintRatio, _rrTokenAmt);
  }

  function repayWithPermit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rrTokenAmt,
    Permit calldata _pairedPermit
  ) external override {
    _permit(_paired, _pairedPermit);
    repay(_col, _paired, _expiry, _mintRatio, _rrTokenAmt);
  }

  /// @notice sender collect paired tokens by returning same amount of rcTokens to Ruler
  function collect(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rcTokenAmt
  ) external override onlyNotPaused nonReentrant {
    Pair memory pair = pairs[_col][_paired][_expiry][_mintRatio];
    require(pair.mintRatio != 0, "Ruler: pair does not exist");
    require(block.timestamp > pair.expiry, "Ruler: not ready");
    pair.rcToken.burnByRuler(msg.sender, _rcTokenAmt);

    IERC20 pairedToken = IERC20(_paired);
    uint256 defaultedLoanAmt = pair.rrToken.totalSupply();
    if (defaultedLoanAmt == 0) { // no default, send paired Token to sender
      // no fees accrued as it is accrued on Borrower payment
      _sendAmtPostFeesOptionalAccrue(pairedToken, _rcTokenAmt, pair.feeRate, false /* accrue */);
    } else {
      // rcTokens eligible to collect at expiry (converted from total collateral received, redeemed collateral not counted) == total loan amount at the moment of expiry
      uint256 rcTokensEligibleAtExpiry = _getRTokenAmtFromColAmt(pair.colTotal, _col, _paired, pair.mintRatio);

      // paired token amount to pay = rcToken amount * (1 - default ratio)
      uint256 pairedTokenAmtToCollect = _rcTokenAmt * (rcTokensEligibleAtExpiry - defaultedLoanAmt) / rcTokensEligibleAtExpiry;
      // no fees accrued as it is accrued on Borrower payment
      _sendAmtPostFeesOptionalAccrue(pairedToken, pairedTokenAmtToCollect, pair.feeRate, false /* accrue */);

      // default collateral amount to pay = converted collateral amount (from rcTokenAmt) * default ratio
      uint256 colAmount = _getColAmtFromRTokenAmt(_rcTokenAmt, _col, address(pair.rcToken), pair.mintRatio);
      uint256 colAmountToCollect = colAmount * defaultedLoanAmt / rcTokensEligibleAtExpiry;
      // accrue fees on defaulted collateral since it was never accrued
      _sendAmtPostFeesOptionalAccrue(IERC20(_col), colAmountToCollect, pair.feeRate, true /* accrue */);
    }
    emit Collect(msg.sender, _col, _paired,_expiry,  _mintRatio, _rcTokenAmt);
  }

  /// @notice anyone can call if they pay, no reason to prevent that. This will enable future xRULER or other fee related features
  function collectFees(IERC20[] calldata _tokens) external override {
    for (uint256 i = 0; i < _tokens.length; i++) {
      IERC20 token = _tokens[i];
      uint256 fee = feesMap[address(token)];
      feesMap[address(token)] = 0;
      _safeTransfer(token, feeReceiver, fee);
    }
  }

  /**
   * @notice add a new Ruler Pair
   *  - Paired Token cannot be a deflationary token
   *  - minColRatio is not respected if collateral is alreay added
   *  - all Ratios are 1e18
   */
  function addPair(
    address _col,
    address _paired,
    uint48 _expiry,
    string calldata _expiryStr,
    uint256 _mintRatio,
    string calldata _mintRatioStr,
    uint256 _feeRate
  ) external override onlyOwner {
    require(pairs[_col][_paired][_expiry][_mintRatio].mintRatio == 0, "Ruler: pair exists");
    require(_mintRatio > 0, "Ruler: _mintRatio <= 0");
    require(_feeRate < 0.1 ether, "Ruler: fee rate must be < 10%");
    require(_expiry > block.timestamp, "Ruler: expiry in the past");
    require(minColRatioMap[_col] > 0, "Ruler: col not listed");
    minColRatioMap[_paired] = 1e18; // default paired token to 100% collateralization ratio as most of them are stablecoins, can be updated later.

    Pair memory pair = Pair({
      active: true,
      feeRate: _feeRate,
      mintRatio: _mintRatio,
      expiry: _expiry,
      pairedToken: _paired,
      rcToken: IRERC20(_createRToken(_col, _paired, _expiry, _expiryStr, _mintRatioStr, "RC_")),
      rrToken: IRERC20(_createRToken(_col, _paired, _expiry, _expiryStr, _mintRatioStr, "RR_")),
      colTotal: 0
    });
    pairs[_col][_paired][_expiry][_mintRatio] = pair;
    pairList[_col].push(pair);
    emit PairAdded(_col, _paired, _expiry, _mintRatio);
  }

  /**
   * @notice allow flash loan borrow allowed tokens up to all core contracts' holdings
   * _receiver will received the requested amount, and need to payback the loan amount + fees
   * _receiver must implement IERC3156FlashBorrower
   */
  function flashLoan(
    IERC3156FlashBorrower _receiver,
    address _token,
    uint256 _amount,
    bytes calldata _data
  ) public override onlyNotPaused nonReentrant returns (bool) {
    require(minColRatioMap[_token] > 0, "Ruler: token not allowed");
    IERC20 token = IERC20(_token);
    uint256 tokenBalBefore = token.balanceOf(address(this));
    token.safeTransfer(address(_receiver), _amount);
    uint256 fees = flashFee(_token, _amount);
    require(
      _receiver.onFlashLoan(msg.sender, _token, _amount, fees, _data) == FLASHLOAN_CALLBACK_SUCCESS,
      "IERC3156: Callback failed"
    );

    // receive loans and fees
    token.safeTransferFrom(address(_receiver), address(this), _amount + fees);
    uint256 receivedFees = token.balanceOf(address(this)) - tokenBalBefore;
    require(receivedFees >= fees, "Ruler: not enough fees");
    feesMap[_token] = feesMap[_token] + receivedFees;
    return true;
  }

  /// @notice flashloan rate can be anything
  function setFlashLoanRate(uint256 _newRate) external override onlyOwner {
    emit FlashLoanRateUpdated(flashLoanRate, _newRate);
    flashLoanRate = _newRate;
  }

  /// @notice add new or update existing collateral
  function updateCollateral(address _col, uint256 _minColRatio) external override onlyOwner {
    require(_minColRatio > 0, "Ruler: min colRatio < 0");
    emit CollateralUpdated(_col, minColRatioMap[_col], _minColRatio);
    if (minColRatioMap[_col] == 0) {
      collaterals.push(_col);
    }
    minColRatioMap[_col] = _minColRatio;
  }

  function setPairActive(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    bool _active
  ) external override onlyOwner {
    pairs[_col][_paired][_expiry][_mintRatio].active = _active;
  }

  function setFeeReceiver(address _address) external override onlyOwner {
    require(_address != address(0), "Ruler: address cannot be 0");
    emit AddressUpdated('feeReceiver', feeReceiver, _address);
    feeReceiver = _address;
  }

  /// @dev update this will only affect pools deployed after
  function setRERC20Impl(address _newImpl) external override onlyOwner {
    require(_newImpl != address(0), "Ruler: _newImpl cannot be 0");
    emit RERC20ImplUpdated(rERC20Impl, _newImpl);
    rERC20Impl = _newImpl;
  }

  function setPaused(bool _paused) external override {
    require(msg.sender == owner() || msg.sender == responder, "Ruler: not owner/responder");
    emit PausedStatusUpdated(paused, _paused);
    paused = _paused;
  }

  function setResponder(address _address) external override onlyOwner {
    require(_address != address(0), "Ruler: address cannot be 0");
    emit AddressUpdated('responder', responder, _address);
    responder = _address;
  }

  function setOracle(address _address) external override onlyOwner {
    require(_address != address(0), "Ruler: address cannot be 0");
    emit AddressUpdated('oracle', address(oracle), _address);
    oracle = IOracle(_address);
  }

  function getCollaterals() external view override returns (address[] memory) {
    return collaterals;
  }

  function getPairList(address _col) external view override returns (Pair[] memory) {
    Pair[] memory colPairList = pairList[_col];
    Pair[] memory _pairs = new Pair[](colPairList.length);
    for (uint256 i = 0; i < colPairList.length; i++) {
      Pair memory pair = colPairList[i];
      _pairs[i] = pairs[_col][pair.pairedToken][pair.expiry][pair.mintRatio];
    }
    return _pairs;
  }

  /// @notice amount that is eligible to collect
  function viewCollectible(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rcTokenAmt
  ) external view override returns (uint256 colAmtToCollect, uint256 pairedAmtToCollect) {
    Pair memory pair = pairs[_col][_paired][_expiry][_mintRatio];
    if (pair.mintRatio == 0 || block.timestamp < pair.expiry) return (colAmtToCollect, pairedAmtToCollect);

    uint256 defaultedLoanAmt = pair.rrToken.totalSupply();
    if (defaultedLoanAmt == 0) { // no default, transfer paired Token
      pairedAmtToCollect =  _rcTokenAmt;
    } else {
      // rcTokens eligible to collect at expiry (converted from total collateral received, redeemed collateral not counted) == total loan amount at the moment of expiry
      uint256 rcTokensEligibleAtExpiry = _getRTokenAmtFromColAmt(pair.colTotal, _col, _paired, pair.mintRatio);

      // paired token amount to pay = rcToken amount * (1 - default ratio)
      pairedAmtToCollect = _rcTokenAmt * (rcTokensEligibleAtExpiry - defaultedLoanAmt) * (1e18 - pair.feeRate) / 1e18 / rcTokensEligibleAtExpiry;

      // default collateral amount to pay = converted collateral amount (from rcTokenAmt) * default ratio
      uint256 colAmount = _getColAmtFromRTokenAmt(_rcTokenAmt, _col, address(pair.rcToken), pair.mintRatio);
      colAmtToCollect = colAmount * defaultedLoanAmt * (1e18 - pair.feeRate) / 1e18 / rcTokensEligibleAtExpiry;
    }
  }

  function maxFlashLoan(address _token) external view override returns (uint256) {
    return IERC20(_token).balanceOf(address(this));
  }

  /// @notice returns the amount of fees charges by for the loan amount. 0 means no fees charged, may not have the token
  function flashFee(address _token, uint256 _amount) public view override returns (uint256 _fees) {
    require(minColRatioMap[_token] > 0, "RulerCore: token not supported");
    _fees = _amount * flashLoanRate / 1e18;
  }

  /// @notice version of current Ruler Core hardcoded
  function version() external pure override returns (string memory) {
    return '1.0';
  }

  function _safeTransfer(IERC20 _token, address _account, uint256 _amount) private {
    uint256 bal = _token.balanceOf(address(this));
    if (bal < _amount) {
      _token.safeTransfer(_account, bal);
    } else {
      _token.safeTransfer(_account, _amount);
    }
  }

  function _sendAmtPostFeesOptionalAccrue(IERC20 _token, uint256 _amount, uint256 _feeRate, bool _accrue) private {
    uint256 fees = _amount * _feeRate / 1e18;
    _safeTransfer(_token, msg.sender, _amount - fees);
    if (_accrue) {
      feesMap[address(_token)] = feesMap[address(_token)] + fees;
    }
  }

  function _createRToken(
    address _col,
    address _paired,
    uint256 _expiry,
    string calldata _expiryStr,
    string calldata _mintRatioStr,
    string memory _prefix
  ) private returns (address proxyAddr) {
    uint8 decimals = uint8(IERC20(_paired).decimals());
    require(decimals > 0, "RulerCore: paired decimals is 0");

    string memory symbol = string(abi.encodePacked(
      _prefix,
      IERC20(_col).symbol(), "_",
      _mintRatioStr, "_",
      IERC20(_paired).symbol(), "_",
      _expiryStr
    ));

    bytes32 salt = keccak256(abi.encodePacked(_col, _paired, _expiry, _mintRatioStr, _prefix));
    proxyAddr = Clones.cloneDeterministic(rERC20Impl, salt);
    IRTokenProxy(proxyAddr).initialize("Ruler Protocol rToken", symbol, decimals);
    emit RTokenCreated(proxyAddr);
  }

  function _getRTokenAmtFromColAmt(uint256 _colAmt, address _col, address _paired, uint256 _mintRatio) private view returns (uint256) {
    uint8 colDecimals = IERC20(_col).decimals();
    // pairedDecimals is the same as rToken decimals
    uint8 pairedDecimals = IERC20(_paired).decimals();
    return _colAmt * _mintRatio * (10 ** pairedDecimals) / (10 ** colDecimals) / 1e18;
  }

  function _getColAmtFromRTokenAmt(uint256 _rTokenAmt, address _col, address _rToken, uint256 _mintRatio) private view returns (uint256) {
    uint8 colDecimals = IERC20(_col).decimals();
    // pairedDecimals == rToken decimals
    uint8 rTokenDecimals = IERC20(_rToken).decimals();
    return _rTokenAmt * (10 ** colDecimals) * 1e18 / _mintRatio / (10 ** rTokenDecimals);
  }

  function _permit(address _token, Permit calldata permit) private {
    IERC20Permit(_token).permit(
      permit.owner,
      permit.spender,
      permit.amount,
      permit.deadline,
      permit.v,
      permit.r,
      permit.s
    );
  }

  function _validateDepositInputs(address _col, Pair memory _pair) private view {
    require(_pair.mintRatio != 0, "Ruler: pair does not exist");
    require(_pair.active, "Ruler: pair inactive");
    require(_pair.expiry > block.timestamp, "Ruler: pair expired");

    // Oracle price is not required, the consequence is low since it will just allow users to deposit collateral (which can be collected thro repay before expiry. If default, early repayments will be diluted
    if (address(oracle) != address(0)) {
      uint256 colPrice = oracle.getPriceUSD(_col);
      if (colPrice != 0) {
        uint256 pairedPrice = oracle.getPriceUSD(_pair.pairedToken);
        if (pairedPrice != 0) {
          // colPrice / mintRatio (1e18) / pairedPrice > min collateralization ratio (1e18), if yes, revert deposit
          require(colPrice * 1e36 > minColRatioMap[_col] * _pair.mintRatio * pairedPrice, "Ruler: collateral price too low");
        }
      }
    }
  }
}