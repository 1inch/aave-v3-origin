// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {OneInchEarnTestBase} from './OneInchEarnTestBase.sol';
import {IPoolAddressesProvider} from '../../src/contracts/interfaces/IPoolAddressesProvider.sol';
import {ACLManager} from '../../src/contracts/protocol/configuration/ACLManager.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {OneInchEarnHandover, IOwnableLike} from '../../src/deployments/projects/1inch-earn/OneInchEarnHandover.sol';

/**
 * @title OneInchEarnHandoverLocalTest
 * @notice Local (no-fork) verification of the governance handover: every role and ownership moves
 * to the DAO executor / guardian / risk provider, the Umbrella backstop is wired, and the
 * bootstrap deployer is left with nothing.
 */
contract OneInchEarnHandoverLocalTest is OneInchEarnTestBase {
  bytes32 internal constant ADMIN_SLOT =
    0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

  address internal dao = makeAddr('dao');
  address internal guardian = makeAddr('guardian');
  address internal risk = makeAddr('risk');
  address internal umbrella = makeAddr('umbrella');

  function setUp() public {
    _deployMarketAndList();
  }

  function test_handoverMovesEverythingAndStripsDeployer() public {
    OneInchEarnHandover.HandoverTargets memory targets = OneInchEarnHandover.HandoverTargets({
      daoExecutor: dao,
      guardian: guardian,
      riskProvider: risk,
      umbrella: umbrella
    });

    vm.startPrank(deployer);
    OneInchEarnHandover.execute(report, targets, deployer);
    vm.stopPrank();

    ACLManager acl = ACLManager(report.aclManager);
    IPoolAddressesProvider provider = IPoolAddressesProvider(report.poolAddressesProvider);

    // New operators.
    assertTrue(acl.isPoolAdmin(dao), 'dao pool admin');
    assertTrue(acl.hasRole(bytes32(0), dao), 'dao default admin');
    assertTrue(acl.isEmergencyAdmin(guardian), 'guardian emergency admin');
    assertTrue(acl.isRiskAdmin(risk), 'risk admin');

    // Deployer stripped.
    assertFalse(acl.isPoolAdmin(deployer), 'deployer not pool admin');
    assertFalse(acl.isEmergencyAdmin(deployer), 'deployer not emergency admin');
    assertFalse(acl.hasRole(bytes32(0), deployer), 'deployer not default admin');

    // Ownership + config.
    assertEq(IOwnableLike(report.poolAddressesProvider).owner(), dao, 'provider owner');
    assertEq(IOwnableLike(report.poolAddressesProviderRegistry).owner(), dao, 'registry owner');
    assertEq(IOwnableLike(report.emissionManager).owner(), dao, 'emissionManager owner');
    assertEq(IOwnableLike(report.wrappedTokenGateway).owner(), dao, 'gateway owner');
    assertEq(provider.getACLAdmin(), dao, 'acl admin slot');
    assertEq(provider.getAddress('UMBRELLA'), umbrella, 'umbrella wired');

    // Transparent-proxy admins moved.
    assertEq(_proxyAdminOwner(report.treasury), dao, 'treasury proxy admin');
    assertEq(_proxyAdminOwner(report.dustBin), dao, 'dustBin proxy admin');
    assertEq(_proxyAdminOwner(report.staticATokenFactoryProxy), dao, 'static factory proxy admin');
  }

  function test_revert_zeroTarget() public {
    OneInchEarnHandover.HandoverTargets memory targets = OneInchEarnHandover.HandoverTargets({
      daoExecutor: address(0),
      guardian: guardian,
      riskProvider: risk,
      umbrella: address(0)
    });
    // External wrapper so expectRevert catches the (otherwise inlined internal-library) revert.
    vm.expectRevert(bytes('HANDOVER_TARGET_ZERO'));
    this.externalHandover(targets);
  }

  function test_umbrellaOptional_skippedWhenZero() public {
    OneInchEarnHandover.HandoverTargets memory targets = OneInchEarnHandover.HandoverTargets({
      daoExecutor: dao,
      guardian: guardian,
      riskProvider: risk,
      umbrella: address(0)
    });
    vm.startPrank(deployer);
    OneInchEarnHandover.execute(report, targets, deployer);
    vm.stopPrank();
    assertEq(
      IPoolAddressesProvider(report.poolAddressesProvider).getAddress('UMBRELLA'),
      address(0),
      'umbrella left unset'
    );
  }

  /// @dev External entrypoint used only to test the zero-target revert (which triggers before any
  /// role op, so the caller need not hold admin roles).
  function externalHandover(OneInchEarnHandover.HandoverTargets memory targets) external {
    OneInchEarnHandover.execute(report, targets, deployer);
  }

  function _proxyAdminOwner(address proxy) internal view returns (address) {
    address proxyAdmin = address(uint160(uint256(vm.load(proxy, ADMIN_SLOT))));
    return IOwnableLike(proxyAdmin).owner();
  }
}
