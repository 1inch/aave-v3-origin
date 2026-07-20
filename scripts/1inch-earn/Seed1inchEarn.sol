// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {console} from 'forge-std/console.sol';
import {OneInchEarnReportReader} from './utils/OneInchEarnReportReader.sol';
import {MarketReport} from '../../src/deployments/interfaces/IMarketReportTypes.sol';
import {IPool} from '../../src/contracts/interfaces/IPool.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {OneInchEarnConfig} from '../../src/deployments/projects/1inch-earn/OneInchEarnConfig.sol';

/**
 * @title Seed1inchEarn
 * @author 1inch
 * @notice Step 2b (post-listing): seeds a small "dust" deposit of every reserve into the market,
 * owned by the `dustBin` so it can never be withdrawn. This initializes each reserve's liquidity
 * and keeps listing dust separate from treasury income (the purpose of the v3.4 dustBin).
 *
 * Operator flow: transfer the intended seed amount of each reserve token to `LEDGER_SENDER`
 * before running; the script supplies the sender's FULL balance of each configured token to the
 * dustBin. Tokens with a zero sender balance are skipped, so you control exactly what gets seeded.
 *
 * Usage (mainnet, Ledger):
 *   REPORT_PATH=reports/<ts>-market-deployment.json \
 *   forge script scripts/1inch-earn/Seed1inchEarn.sol:Seed1inchEarn \
 *     --rpc-url mainnet --ledger --sender <LEDGER_SENDER> --broadcast --slow
 */
contract Seed1inchEarn is OneInchEarnReportReader {
  function run() external {
    MarketReport memory report = _readReport();
    OneInchEarnConfig.TokenAddresses memory t = OneInchEarnConfig.mainnetTokens();

    address[] memory assets = new address[](7);
    assets[0] = t.oneInch;
    assets[1] = t.weth;
    assets[2] = t.wstEth;
    assets[3] = t.wbtc;
    assets[4] = t.cbBtc;
    assets[5] = t.usdc;
    assets[6] = t.usdt;

    vm.startBroadcast();
    for (uint256 i = 0; i < assets.length; i++) {
      uint256 bal = IERC20(assets[i]).balanceOf(msg.sender);
      if (bal == 0) continue;
      IERC20(assets[i]).approve(report.poolProxy, bal);
      IPool(report.poolProxy).supply(assets[i], bal, report.dustBin, 0);
      console.log('Seeded reserve', assets[i], bal);
    }
    vm.stopBroadcast();

    console.log('1inch Earn dust seeding complete; aTokens locked in dustBin:', report.dustBin);
  }
}
