// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MarketReport} from '../../interfaces/IMarketReportTypes.sol';
import {IPoolAddressesProvider} from '../../../contracts/interfaces/IPoolAddressesProvider.sol';
import {ACLManager} from '../../../contracts/protocol/configuration/ACLManager.sol';

interface IOwnableLike {
  function owner() external view returns (address);

  function transferOwnership(address newOwner) external;
}

interface IAccessControlLike {
  function grantRole(bytes32 role, address account) external;

  function renounceRole(bytes32 role, address account) external;

  function FUNDS_ADMIN_ROLE() external view returns (bytes32);
}

/**
 * @title OneInchEarnHandover
 * @author 1inch
 * @notice Moves every privileged role and ownership of a freshly deployed 1inch Earn
 * market from the bootstrap deployer to the 1inch DAO executor, guardian and risk
 * provider, and revokes all deployer permissions.
 *
 * @dev Executed from a forge script under `vm.startBroadcast()`, so `msg.sender` is the
 * bootstrap deployer that currently holds all roles (mirrors how AaveV3BatchOrchestration
 * runs). Run this ONLY after listing + seeding are complete and the fork dress rehearsal
 * + independent config audit have passed.
 *
 * Post-conditions (asserted by the fork test): the deployer keeps no POOL_ADMIN,
 * EMERGENCY_ADMIN, RISK_ADMIN or DEFAULT_ADMIN on the ACLManager, no FUNDS_ADMIN /
 * DEFAULT_ADMIN on the Collector, and owns none of the provider, registry, gateway,
 * emission manager, or any proxy admin.
 */
library OneInchEarnHandover {
  bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);

  struct HandoverTargets {
    address daoExecutor; // marketOwner, POOL_ADMIN, DEFAULT_ADMIN, treasury admin, proxy admins
    address guardian; // EMERGENCY_ADMIN (SafeSnap guardian multisig)
    address riskProvider; // RISK_ADMIN (Chaos Labs / Gauntlet-class)
  }

  function execute(
    MarketReport memory report,
    HandoverTargets memory targets,
    address deployer
  ) internal {
    require(
      targets.daoExecutor != address(0) &&
        targets.guardian != address(0) &&
        targets.riskProvider != address(0),
      'HANDOVER_TARGET_ZERO'
    );

    IPoolAddressesProvider provider = IPoolAddressesProvider(report.poolAddressesProvider);
    ACLManager acl = ACLManager(report.aclManager);

    // 1. Point the addresses-provider ACL_ADMIN slot at the DAO (seeds admin on any future
    // ACLManager redeploy). Must happen while the deployer still owns the provider.
    provider.setACLAdmin(targets.daoExecutor);

    // 2. Grant the new operators. DEFAULT_ADMIN to the DAO so it can manage every role.
    acl.grantRole(DEFAULT_ADMIN_ROLE, targets.daoExecutor);
    acl.addPoolAdmin(targets.daoExecutor);
    acl.addEmergencyAdmin(targets.guardian);
    acl.addRiskAdmin(targets.riskProvider);

    // 3. Revoke the deployer's ACL roles. DEFAULT_ADMIN is renounced LAST because the
    // preceding revokes require it.
    acl.removePoolAdmin(deployer);
    if (acl.isEmergencyAdmin(deployer)) {
      acl.removeEmergencyAdmin(deployer);
    }
    acl.renounceRole(DEFAULT_ADMIN_ROLE, deployer);

    // 4. Treasury (Collector): hand over AccessControl roles, then drop the deployer's.
    _handoverCollector(report.treasury, targets.daoExecutor, deployer);

    // 5. Ownable helpers.
    _transferOwnership(report.emissionManager, targets.daoExecutor, deployer);
    _transferOwnership(report.wrappedTokenGateway, targets.daoExecutor, deployer);

    // 6. Transparent-proxy admins (upgrade rights) for treasury, dustBin and the static
    // aToken factory proxy. Each proxy deploys its ProxyAdmin as its first CREATE (nonce 1).
    _transferProxyAdminOwnership(report.treasury, targets.daoExecutor, deployer);
    _transferProxyAdminOwnership(report.dustBin, targets.daoExecutor, deployer);
    _transferProxyAdminOwnership(report.staticATokenFactoryProxy, targets.daoExecutor, deployer);

    // 7. Finally, the provider + registry ownership.
    IOwnableLike(report.poolAddressesProvider).transferOwnership(targets.daoExecutor);
    if (
      report.poolAddressesProviderRegistry != address(0) &&
      IOwnableLike(report.poolAddressesProviderRegistry).owner() == deployer
    ) {
      IOwnableLike(report.poolAddressesProviderRegistry).transferOwnership(targets.daoExecutor);
    }
  }

  function _handoverCollector(address treasury, address dao, address deployer) private {
    IAccessControlLike collector = IAccessControlLike(treasury);
    bytes32 fundsAdmin = collector.FUNDS_ADMIN_ROLE();

    collector.grantRole(DEFAULT_ADMIN_ROLE, dao);
    collector.grantRole(fundsAdmin, dao);

    collector.renounceRole(fundsAdmin, deployer);
    // DEFAULT_ADMIN renounced last.
    collector.renounceRole(DEFAULT_ADMIN_ROLE, deployer);
  }

  function _transferOwnership(address target, address dao, address deployer) private {
    if (target == address(0)) return;
    if (IOwnableLike(target).owner() == deployer) {
      IOwnableLike(target).transferOwnership(dao);
    }
  }

  function _transferProxyAdminOwnership(address proxy, address dao, address deployer) private {
    if (proxy == address(0)) return;
    address proxyAdmin = _computeProxyAdmin(proxy);
    if (IOwnableLike(proxyAdmin).owner() == deployer) {
      IOwnableLike(proxyAdmin).transferOwnership(dao);
    }
  }

  /// @dev A TransparentUpgradeableProxy deploys its ProxyAdmin as its only contract (nonce 1),
  /// so the admin address is deterministic: keccak256(rlp([proxy, 0x01]))[12:].
  function _computeProxyAdmin(address proxy) private pure returns (address) {
    return
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(bytes1(0xd6), bytes1(0x94), proxy, bytes1(0x01))
            )
          )
        )
      );
  }
}
