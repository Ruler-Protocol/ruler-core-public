// SPDX-License-Identifier: No License

pragma solidity ^0.8.0;

import "./IRERC20.sol";
import "./IOracle.sol";

/**
 * @title IRulerCore contract interface. See {RulerCore}.
 * @author crypto-pumpkin
 */
interface IRulerCore {
  event RTokenCreated(address);
  event CollateralUpdated(address col, uint256 old, uint256 _new);
  event PairAdded(address indexed collateral, address indexed paired, uint48 expiry, uint256 mintRatio);
  event MarketMakeDeposit(address indexed user, address indexed collateral, address indexed paired, uint48 expiry, uint256 mintRatio, uint256 amount);
  event Deposit(address indexed user, address indexed collateral, address indexed paired, uint48 expiry, uint256 mintRatio, uint256 amount);
  event Repay(address indexed user, address indexed collateral, address indexed paired, uint48 expiry, uint256 mintRatio, uint256 amount);
  event Redeem(address indexed user, address indexed collateral, address indexed paired, uint48 expiry, uint256 mintRatio, uint256 amount);
  event Collect(address indexed user, address indexed collateral, address indexed paired, uint48 expiry, uint256 mintRatio, uint256 amount);
  event AddressUpdated(string _type, address old, address _new);
  event PausedStatusUpdated(bool old, bool _new);
  event RERC20ImplUpdated(address rERC20Impl, address newImpl);
  event FlashLoanRateUpdated(uint256 old, uint256 _new);

  struct Pair {
    bool active;
    uint48 expiry;
    address pairedToken;
    IRERC20 rcToken; // ruler capitol token, e.g. RC_Dai_wBTC_2_2021
    IRERC20 rrToken; // ruler repayment token, e.g. RR_Dai_wBTC_2_2021
    uint256 mintRatio; // 1e18, price of collateral / collateralization ratio
    uint256 feeRate; // 1e18
    uint256 colTotal;
  }

  struct Permit {
    address owner;
    address spender;
    uint256 amount;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  // state vars
  function oracle() external view returns (IOracle);
  function version() external pure returns (string memory);
  function flashLoanRate() external view returns (uint256);
  function paused() external view returns (bool);
  function responder() external view returns (address);
  function feeReceiver() external view returns (address);
  function rERC20Impl() external view returns (address);
  function collaterals(uint256 _index) external view returns (address);
  function minColRatioMap(address _col) external view returns (uint256);
  function feesMap(address _token) external view returns (uint256);
  function pairs(address _col, address _paired, uint48 _expiry, uint256 _mintRatio) external view returns (
    bool active, 
    uint48 expiry, 
    address pairedToken, 
    IRERC20 rcToken, 
    IRERC20 rrToken, 
    uint256 mintRatio, 
    uint256 feeRate, 
    uint256 colTotal
  );

  // extra view
  function getCollaterals() external view returns (address[] memory);
  function getPairList(address _col) external view returns (Pair[] memory);
  function viewCollectible(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rcTokenAmt
  ) external view returns (uint256 colAmtToCollect, uint256 pairedAmtToCollect);

  // user action - only when not paused
  function mmDeposit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rcTokenAmt
  ) external;
  function mmDepositWithPermit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rcTokenAmt,
    Permit calldata _pairedPermit
  ) external;
  function deposit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _colAmt
  ) external;
  function depositWithPermit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _colAmt,
    Permit calldata _colPermit
  ) external;
  function redeem(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rTokenAmt
  ) external;
  function repay(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rrTokenAmt
  ) external;
  function repayWithPermit(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rrTokenAmt,
    Permit calldata _pairedPermit
  ) external;
  function collect(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    uint256 _rcTokenAmt
  ) external;
  function collectFees(IERC20[] calldata _tokens) external;

  // access restriction - owner (dev) & responder
  function setPaused(bool _paused) external;

  // access restriction - owner (dev)
  function addPair(
    address _col,
    address _paired,
    uint48 _expiry,
    string calldata _expiryStr,
    uint256 _mintRatio,
    string calldata _mintRatioStr,
    uint256 _feeRate
  ) external;
  function setPairActive(
    address _col,
    address _paired,
    uint48 _expiry,
    uint256 _mintRatio,
    bool _active
  ) external;
  function updateCollateral(address _col, uint256 _minColRatio) external;
  function setFeeReceiver(address _addr) external;
  function setResponder(address _addr) external;
  function setRERC20Impl(address _addr) external;
  function setOracle(address _addr) external;
  function setFlashLoanRate(uint256 _newRate) external;
}