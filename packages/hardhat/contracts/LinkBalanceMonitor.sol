// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title The LinkToken balance Monitor contract
 * @notice A contract compatible with Chainlink Automation Network that monitors and funds  smart contracts with link tokens
 */

contract LinkBalanceMonitor is ConfirmedOwner, Pausable, AutomationCompatibleInterface {
  LinkTokenInterface private immutable tokenLink;
  uint256 private constant MIN_GAS_FOR_TRANSFER = 55_000;

  event FundsAdded(uint256 amountAdded, uint256 newBalance, address sender);
  event FundsWithdrawn(uint256 amountWithdrawn, address payee);
  event TopUpSucceeded(address indexed recipient);
  event TopUpFailed(address indexed recipient);
  event KeeperRegistryAddressUpdated(address oldAddress, address newAddress);
  event MinWaitPeriodUpdated(uint256 oldMinWaitPeriod, uint256 newMinWaitPeriod);

  error InvalidWatchList();
  error OnlyKeeperRegistry();
  error DuplicateAddress(address duplicate);

  struct Target {
    bool isActive;
    uint96 minBalanceLink;
    uint96 topUpAmountLink;
    uint56 lastTopUpTimestamp;
  }

  address private s_keeperRegistryAddress;
  uint256 private s_minWaitPeriodSeconds;
  address[] private s_watchList;
  mapping(address => Target) internal s_targets;

  /**
   * @param _keeperRegistryAddress The address of the Chainlink Automation registry contract
   * @param _minWaitPeriodSeconds The minimum wait period for addresses between funding
   * @param _linkTokenAddress the address of the link token contract on this particular chain
   *
   *
   * Network: Sepolia
   * Keeper Registry Address:
   * Min Wait Period :
   * Link Token Address: 0x779877A7B0D9E8603169DdbD7836e478b4624789
   */

  constructor(
    address _keeperRegistryAddress,
    uint256 _minWaitPeriodSeconds,
    address _linkTokenAddress
  ) ConfirmedOwner(msg.sender) {
    setKeeperRegistryAddress(_keeperRegistryAddress);
    setMinWaitPeriodSeconds(_minWaitPeriodSeconds);
    tokenLink = LinkTokenInterface(_linkTokenAddress);
  }

  /**
   * @notice Sets the list of addresses to watch and their funding parameters
   * @param addresses the list of addresses to watch
   * @param minBalancesLink the minimum balances for each address
   * @param topUpAmountsLink the amount to top up each address
   */
  function setWatchList(
    address[] calldata addresses,
    uint96[] calldata minBalancesLink,
    uint96[] calldata topUpAmountsLink
  ) external onlyOwner {
    if (addresses.length != minBalancesLink.length || addresses.length != topUpAmountsLink.length) {
      revert InvalidWatchList();
    }
    address[] memory oldWatchList = s_watchList;
    for (uint256 idx = 0; idx < oldWatchList.length; idx++) {
      s_targets[oldWatchList[idx]].isActive = false;
    }
    for (uint256 idx = 0; idx < addresses.length; idx++) {
      if (s_targets[addresses[idx]].isActive) {
        revert DuplicateAddress(addresses[idx]);
      }
      if (addresses[idx] == address(0)) {
        revert InvalidWatchList();
      }
      if (topUpAmountsLink[idx] == 0) {
        revert InvalidWatchList();
      }
      s_targets[addresses[idx]] = Target({
        isActive: true,
        minBalanceLink: minBalancesLink[idx],
        topUpAmountLink: topUpAmountsLink[idx],
        lastTopUpTimestamp: 0
      });
    }
    s_watchList = addresses;
  }

  /**
   * @notice Gets a list of addresses that are under funded
   * @return list of addresses that are underfunded
   */
  function getUnderfundedAddresses() public view returns (address[] memory) {
    address[] memory watchList = s_watchList;
    address[] memory needsFunding = new address[](watchList.length);
    uint256 count = 0;
    uint256 minWaitPeriod = s_minWaitPeriodSeconds;
    //uint256 balance = address(this).balance;
    uint256 balance = tokenLink.balanceOf(address(this));
    Target memory target;

    for (uint256 idx = 0; idx < watchList.length; idx++) {
      target = s_targets[watchList[idx]];
      if (
        target.lastTopUpTimestamp + minWaitPeriod <= block.timestamp &&
        balance >= target.topUpAmountLink &&
        //watchList[idx].balance < target.minBalanceLink
        tokenLink.balanceOf(watchList[idx]) < target.minBalanceLink
      ) {
        needsFunding[count] = watchList[idx];
        count++;
        balance -= target.topUpAmountLink;
      }
    }
    if (count != watchList.length) {
      assembly {
        mstore(needsFunding, count)
      }
    }
    return needsFunding;
  }

  /**
   * @notice Send funds to the addresses provided
   * @param needsFunding the list of addresses to fund (addresses must be pre-approved)
   */
  function topUp(address[] memory needsFunding) public whenNotPaused {
    uint256 minWaitPeriodSeconds = s_minWaitPeriodSeconds;
    Target memory target;
    for (uint256 idx = 0; idx < needsFunding.length; idx++) {
      target = s_targets[needsFunding[idx]];
      if (
        target.isActive &&
        target.lastTopUpTimestamp + minWaitPeriodSeconds <= block.timestamp &&
        //needsFunding[idx].balance < target.minBalanceLink
        tokenLink.balanceOf(needsFunding[idx]) < target.minBalanceLink
      ) {
        //bool success = payable(needsFunding[idx]).send(
        //  target.topUpAmountLink
        //);
        bool success = tokenLink.transfer(needsFunding[idx], target.topUpAmountLink);
        if (success) {
          s_targets[needsFunding[idx]].lastTopUpTimestamp = uint56(block.timestamp);
          emit TopUpSucceeded(needsFunding[idx]);
        } else {
          emit TopUpFailed(needsFunding[idx]);
        }
      }
      if (gasleft() < MIN_GAS_FOR_TRANSFER) {
        return;
      }
    }
  }

  function transfer(address to, uint256 value) external returns (bool success) {
    // Perform the transfer using the tokenLink instance
    require(tokenLink.transfer(to, value), "unable to transfer");

    // Return true to indicate success
    return true;
  }

  /**
   * @notice Get list of addresses that are underfunded and return payload compatible with Chainlink Automation Network
   * @return upkeepNeeded signals if upkeep is needed, performData is an abi encoded list of addresses that need funds
   */
  function checkUpkeep(
    bytes calldata
  ) external view override whenNotPaused returns (bool upkeepNeeded, bytes memory performData) {
    address[] memory needsFunding = getUnderfundedAddresses();
    upkeepNeeded = needsFunding.length > 0;
    performData = abi.encode(needsFunding);
    return (upkeepNeeded, performData);
  }

  /**
   * @notice Called by Chainlink Automation Node to send funds to underfunded addresses
   * @param performData The abi encoded list of addresses to fund
   */
  function performUpkeep(bytes calldata performData) external override onlyKeeperRegistry whenNotPaused {
    address[] memory needsFunding = abi.decode(performData, (address[]));
    topUp(needsFunding);
  }

  /**
   * @notice Withdraws the contract balance
   * @param amount The amount of Link (in wei) to withdraw
   * @param payee The address to pay
   */

  function withdrawLink(uint256 amount, address payee) external onlyOwner {
    require(payee != address(0));
    require(tokenLink.balanceOf(address(this)) >= amount, "Not enough LINK to withdraw");

    emit FundsWithdrawn(amount, payee);

    bool success = tokenLink.transfer(payee, amount);
    require(success, "Failed to transfer LINK");
  }

  /**
   * @notice Receive funds
   */
  receive() external payable {
    emit FundsAdded(msg.value, address(this).balance, msg.sender);
  }

  /**
   * @notice Sets the Chainlink Automation registry address
   */
  function setKeeperRegistryAddress(address keeperRegistryAddress) public onlyOwner {
    require(keeperRegistryAddress != address(0));
    emit KeeperRegistryAddressUpdated(s_keeperRegistryAddress, keeperRegistryAddress);
    s_keeperRegistryAddress = keeperRegistryAddress;
  }

  /**
   * @notice Sets the minimum wait period (in seconds) for addresses between funding
   */
  function setMinWaitPeriodSeconds(uint256 period) public onlyOwner {
    emit MinWaitPeriodUpdated(s_minWaitPeriodSeconds, period);
    s_minWaitPeriodSeconds = period;
  }

  /**
   * @notice Gets the Chainlink Automation registry address
   */
  function getKeeperRegistryAddress() external view returns (address keeperRegistryAddress) {
    return s_keeperRegistryAddress;
  }

  /**
   * @notice Gets the minimum wait period
   */
  function getMinWaitPeriodSeconds() external view returns (uint256) {
    return s_minWaitPeriodSeconds;
  }

  /**
   * @notice Gets the list of addresses being watched
   */
  function getWatchList() external view returns (address[] memory) {
    return s_watchList;
  }

  /**
   * @notice Gets configuration information for an address on the watchlist
   */
  function getAccountInfo(
    address targetAddress
  ) external view returns (bool isActive, uint96 minBalanceLink, uint96 topUpAmountLink, uint56 lastTopUpTimestamp) {
    Target memory target = s_targets[targetAddress];
    return (target.isActive, target.minBalanceLink, target.topUpAmountLink, target.lastTopUpTimestamp);
  }

  /**
   * @notice Pauses the contract, which prevents executing performUpkeep
   */
  function pause() external onlyOwner {
    _pause();
  }

  /**
   * @notice Unpauses the contract
   */
  function unpause() external onlyOwner {
    _unpause();
  }

  modifier onlyKeeperRegistry() {
    if (msg.sender != s_keeperRegistryAddress) {
      revert OnlyKeeperRegistry();
    }
    _;
  }
}
