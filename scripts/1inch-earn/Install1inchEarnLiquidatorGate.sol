// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {console} from 'forge-std/console.sol';
import {OneInchEarnReportReader} from './utils/OneInchEarnReportReader.sol';
import {MarketReport} from '../../src/deployments/interfaces/IMarketReportTypes.sol';
import {IPoolAddressesProvider} from '../../src/contracts/interfaces/IPoolAddressesProvider.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {KycNFT} from '../../src/deployments/projects/1inch-earn/KycNFT.sol';
import {OneInchEarnLiquidatorGate} from '../../src/deployments/projects/1inch-earn/OneInchEarnLiquidatorGate.sol';

/**
 * @title Install1inchEarnLiquidatorGate
 * @author 1inch
 * @notice Optional step: deploy the liquidator KYC NFT and install the NFT-gated pool
 * implementation (permissioned liquidations). Run by the current PoolAddressesProvider
 * owner (bootstrap deployer, or the DAO executor after handover).
 *
 * Env:
 * - `KYC_NFT` (optional): reuse an existing gate token; if unset, a new KycNFT is deployed
 *   owned by `KYC_OWNER`.
 * - `KYC_OWNER` (required when deploying a new gate): the Business Portal minting wallet /
 *   ops multisig that mints & revokes KYC tokens.
 *
 * To OPEN liquidations back up in an emergency, re-run with `KYC_NFT=0x0` (installs a
 * gate-disabled pool), or re-install vanilla PoolInstance.
 */
contract Install1inchEarnLiquidatorGate is OneInchEarnReportReader {
  function run() external {
    MarketReport memory report = _readReport();
    address existingGate = vm.envOr('KYC_NFT', address(0));

    vm.startBroadcast();

    IERC20 gate;
    if (existingGate == address(0) && !vm.envOr('DISABLE_GATE', false)) {
      KycNFT kyc = OneInchEarnLiquidatorGate.deployGate(vm.envAddress('KYC_OWNER'));
      gate = IERC20(address(kyc));
      console.log('Deployed liquidator KYC NFT:', address(kyc));
    } else {
      gate = IERC20(existingGate); // address(0) => permissionless pool
    }

    address newImpl = OneInchEarnLiquidatorGate.installGatedPool(
      IPoolAddressesProvider(report.poolAddressesProvider),
      report.defaultInterestRateStrategy,
      gate
    );

    vm.stopBroadcast();

    console.log('Installed gated pool implementation:', newImpl);
    console.log('Liquidator gate token:', address(gate));
  }
}
