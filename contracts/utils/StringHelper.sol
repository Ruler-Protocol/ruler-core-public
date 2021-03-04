// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title Ruler contract interface. See {Ruler}.
 * @author crypto-pumpkin
 * Help convert other types to string
 */
library StringHelper {
  function stringToBytes32(string calldata str) internal pure returns (bytes32 result) {
    bytes memory strBytes = abi.encodePacked(str);
    assembly {
      result := mload(add(strBytes, 32))
    }
  }

  function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
    uint8 i = 0;
    while(i < 32 && _bytes32[i] != 0) {
        i++;
    }
    bytes memory bytesArray = new bytes(i);
    for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
        bytesArray[i] = _bytes32[i];
    }
    return string(bytesArray);
  }

  // TODO optimized this func, changes were made for solidity 0.8.0
  function uintToString(uint256 _i) internal pure returns (string memory _uintAsString) {
    if (_i == 0) {
      return '0';
    } else {
      bytes32 ret;
      while (_i > 0) {
        ret = bytes32(uint(ret) / (2 ** 8));
        ret |= bytes32(((_i % 10) + 48) * 2 ** (8 * 31));
        _i /= 10;
      }
      _uintAsString = bytes32ToString(ret);
    }
  }

  // function uintToString(uint256 _i) internal pure returns (string memory _uintAsString) {
  //   if (_i == 0) {
  //     return "0";
  //   }
  //   uint256 j = _i;
  //   uint256 len;
  //   while (j != 0) {
  //     len++;
  //     j /= 10;
  //   }
  //   bytes memory bstr = new bytes(len);
  //   uint256 k = len - 1;
  //   while (_i != 0) {
  //     bstr[k--] = bytes1(bytes32(48 + _i % 10));
  //     _i /= 10;
  //   }
  //   return string(bstr);
  // }
}