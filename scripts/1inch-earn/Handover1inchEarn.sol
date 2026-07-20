// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {console} from 'forge-std/console.sol';
import {OneInchEarnReportReader} from './utils/OneInchEarnReportReader.sol';
import {MarketReport} from '../../src/deployments/interfaces/IMarketReportTypes.sol';
import {OneInchEarnHandover} from '../../src/deployments/projects/1inch-earn/OneInchEarnHandover.sol';

/**
 * @title Handover1inchEarn
 * @author 1inch
 * @notice Final step: transfer every privileged role and ownership from the bootstrap
 * deployer to the 1inch DAO executor, guardian and risk provider, and revoke all deployer
 * permissions. Run ONLY after listing + seeding + the independent config audit have passed.
 *
 * Env (all required):
 * - `DAO_EXECUTOR`  : marketOwner, POOL_ADMIN, DEFAULT_ADMIN, treasury & proxy admins.
 * - `GUARDIAN`      : EMERGENCY_ADMIN (SafeSnap guardian multisig).
 * - `RISK_PROVIDER` : RISK_ADMIN (Chaos Labs / Gauntlet-class).
 *
 * Usage (mainnet, Ledger):
 *   REPORT_PATH=reports/<ts>-market-deployment.json DAO_EXECUTOR=0x.. GUARDIAN=0x.. RISK_PROVIDER=0x.. \
 *   forge script scripts/1inch-earn/Handover1inchEarn.sol:Handover1inchEarn \
 *     --rpc-url mainnet --ledger --sender <LEDGER_SENDER> --broadcast --slow
 */
contract Handover1inchEarn is OneInchEarnReportReader {
  function run() external {
    MarketReport memory report = _readReport();

    OneInchEarnHandover.HandoverTargets memory targets = OneInchEarnHandover.HandoverTargets({
      daoExecutor: vm.envAddress('DAO_EXECUTOR'),
      guardian: vm.envAddress('GUARDIAN'),
      riskProvider: vm.envAddress('RISK_PROVIDER')
    });

    vm.startBroadcast();
    OneInchEarnHandover.execute(report, targets, msg.sender);
    vm.stopBroadcast();

    console.log('1inch Earn handover complete. DAO executor:', targets.daoExecutor);
  }
}
