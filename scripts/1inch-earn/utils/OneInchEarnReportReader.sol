// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Script} from 'forge-std/Script.sol';
import {MarketReport} from '../../../src/deployments/interfaces/IMarketReportTypes.sol';

/**
 * @title OneInchEarnReportReader
 * @author 1inch
 * @notice Base for the 1inch Earn ops scripts: loads the market address report written by
 * the deploy step (MetadataReporter JSON under /reports) so the listing / gate / handover
 * steps operate on the real, already-deployed addresses.
 * @dev Set the `REPORT_PATH` env var to the deployment JSON, e.g.
 *   REPORT_PATH=reports/1751000000-market-deployment.json
 */
abstract contract OneInchEarnReportReader is Script {
  function _readReport() internal view returns (MarketReport memory report) {
    string memory path = vm.envString('REPORT_PATH');
    string memory json = vm.readFile(path);

    report.poolAddressesProviderRegistry = vm.parseJsonAddress(
      json,
      '.poolAddressesProviderRegistry'
    );
    report.poolAddressesProvider = vm.parseJsonAddress(json, '.poolAddressesProvider');
    report.poolProxy = vm.parseJsonAddress(json, '.poolProxy');
    report.poolConfiguratorProxy = vm.parseJsonAddress(json, '.poolConfiguratorProxy');
    report.protocolDataProvider = vm.parseJsonAddress(json, '.protocolDataProvider');
    report.aaveOracle = vm.parseJsonAddress(json, '.aaveOracle');
    report.aclManager = vm.parseJsonAddress(json, '.aclManager');
    report.treasury = vm.parseJsonAddress(json, '.treasury');
    report.dustBin = vm.parseJsonAddress(json, '.dustBin');
    report.wrappedTokenGateway = vm.parseJsonAddress(json, '.wrappedTokenGateway');
    report.aToken = vm.parseJsonAddress(json, '.aToken');
    report.variableDebtToken = vm.parseJsonAddress(json, '.variableDebtToken');
    report.emissionManager = vm.parseJsonAddress(json, '.emissionManager');
    report.defaultInterestRateStrategy = vm.parseJsonAddress(json, '.defaultInterestRateStrategy');
    report.staticATokenFactoryProxy = vm.parseJsonAddress(json, '.staticATokenFactoryProxy');

    return report;
  }
}
