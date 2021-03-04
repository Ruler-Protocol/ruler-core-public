// SPDX-License-Identifier: No License

pragma solidity ^0.8.0;

import "./ERC20/ERC20Permit.sol";
import "./interfaces/IRERC20.sol";
import "./utils/Initializable.sol";
import "./utils/Ownable.sol";

/**
 * @title RERC20 implements {ERC20} standards with expended features for Ruler
 * @author crypto-pumpkin
 * Symbol example:
 *  RC_Dai_wBTC_2_2021
 *  RR_Dai_wBTC_2_2021
 */
contract RERC20 is IRERC20, ERC20Permit, Ownable {

  /// @notice Initialize, called once
  function initialize(string memory _name, string memory _symbol, uint8 _decimals) external initializer {
    initializeOwner();
    initializeERC20(_name, _symbol, _decimals);
    initializeERC20Permit(_name);
  }

  /// @notice Ruler specific function
  function mint(address _account, uint256 _amount) external override onlyOwner returns (bool) {
    _mint(_account, _amount);
    return true;
  }

  /// @notice Ruler specific function
  function burnByRuler(address _account, uint256 _amount) external override onlyOwner returns (bool) {
    _burn(_account, _amount);
    return true;
  }

  // to support permit
  function getChainId() external view returns (uint256 chainId) {
    this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
    // solhint-disable-next-line no-inline-assembly
    assembly {
      chainId := chainid()
    }
  }
}
