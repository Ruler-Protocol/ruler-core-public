// SPDX-License-Identifier: NONE

pragma solidity ^0.8.0;

/**
 * @title Ruler Protocol Bonus Token Rewards Interface
 * @author crypto-pumpkin
 */
interface IBonusRewards {
  event Deposit(address indexed user, address indexed lpToken, uint256 amount);
  event Withdraw(address indexed user, address indexed lpToken, uint256 amount);
  event PausedStatusUpdated(address user, bool old, bool _new);

  struct Bonus {
    address bonusTokenAddr; // the external bonus token, like CRV
    uint48 startTime;
    uint48 endTime;
    uint256 weeklyRewards; // total amount to be distributed from start to end
    uint256 accRewardsPerToken; // accumulated bonus to the lastUpdated Time
    uint256 remBonus; // remaining bonus in contract
  }

  struct Pool {
    Bonus[] bonuses;
    uint256 lastUpdatedAt; // last accumulated bonus update timestamp
  }

  struct User {
    uint256 amount;
    uint256[] rewardsWriteoffs; // the amount of bonus tokens to write off when calculate rewards from last update
  }

  function getPoolList() external view returns (address[] memory);
  function getResponders() external view returns (address[] memory);
  function getPool(address _lpToken) external view returns (Pool memory);
  function getUser(address _lpToken, address _account) external view returns (User memory _user, uint256[] memory _rewards);
  function getAuthorizers(address _lpToken, address _bonusTokenAddr) external view returns (address[] memory);
  function viewRewards(address _lpToken, address _user) external view  returns (uint256[] memory);

  function claimRewardsForPools(address[] calldata _lpTokens) external;
  function deposit(address _lpToken, uint256 _amount) external;
  function withdraw(address _lpToken, uint256 _amount) external;
  function emergencyWithdraw(address[] calldata _lpTokens) external;
  function addBonus(
    address _lpToken,
    address _bonusTokenAddr,
    uint48 _startTime,
    uint256 _weeklyRewards,
    uint256 _transferAmount
  ) external;
  function extendBonus(
    address _lpToken,
    uint256 _poolBonusId,
    address _bonusTokenAddr,
    uint256 _transferAmount
  ) external;
  function updateBonus(
    address _lpToken,
    address _bonusTokenAddr,
    uint256 _weeklyRewards,
    uint48 _startTime
  ) external;

  // only owner
  function setResponders(address[] calldata _responders) external;
  function setPaused(bool _paused) external;
  function collectDust(address _token, address _lpToken, uint256 _poolBonusId) external;
  function addPoolsAndAllowBonus(
    address[] calldata _lpTokens,
    address[] calldata _bonusTokenAddrs,
    address[] calldata _authorizers
  ) external;
}
