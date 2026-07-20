// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {DataTypes} from '../../../contracts/protocol/libraries/types/DataTypes.sol';
import {UserConfiguration} from '../../../contracts/protocol/libraries/configuration/UserConfiguration.sol';
import {ValidationLogic} from '../../../contracts/protocol/libraries/logic/ValidationLogic.sol';
import {IScaledBalanceToken} from '../../../contracts/interfaces/IScaledBalanceToken.sol';
import {OneInchDebtTransferValidation} from './OneInchDebtTransferValidation.sol';

/**
 * @title OneInchDebtTransferLogic
 * @author 1inch
 * @notice Externally-linked logic library for `OneInchPoolInstance.finalizeDebtTransfer`.
 * @dev Deployed as a standalone library (like Aave's Borrow/Supply/LiquidationLogic) and
 * delegatecalled by the pool. This keeps the heavy health-factor machinery
 * (`ValidationLogic.validateHFAndLtv` -> `GenericLogic.calculateUserAccountData`) OUT of the
 * `OneInchPoolInstance` runtime bytecode, which would otherwise exceed the EIP-170 24,576-byte
 * deployment limit on a real network (caught by the anvil integration test; in-memory forge
 * tests do not enforce the limit).
 */
library OneInchDebtTransferLogic {
  using UserConfiguration for DataTypes.UserConfigurationMap;

  /**
   * @notice Validates a debt transfer, updates both users' borrowing flags and health-checks
   * the receiver. Mirrors the aToken `finalizeTransfer` flow but for variable debt.
   * @dev The debt token has already moved the scaled balance, so balances read here are
   * post-move.
   */
  function executeFinalizeDebtTransfer(
    mapping(address => DataTypes.ReserveData) storage reservesData,
    mapping(uint256 => address) storage reservesList,
    mapping(uint8 => DataTypes.EModeCategory) storage eModeCategories,
    mapping(address => DataTypes.UserConfigurationMap) storage usersConfig,
    address asset,
    address from,
    address to,
    uint8 toEModeCategory,
    address priceOracle
  ) external {
    DataTypes.ReserveData storage reserve = reservesData[asset];

    OneInchDebtTransferValidation.validateDebtTransfer(reserve, eModeCategories, toEModeCategory);

    uint256 reserveId = reserve.id;
    usersConfig[to].setBorrowing(reserveId, true);
    if (IScaledBalanceToken(reserve.variableDebtTokenAddress).scaledBalanceOf(from) == 0) {
      usersConfig[from].setBorrowing(reserveId, false);
    }

    // Only the receiver (who just assumed the debt) can become unhealthy.
    ValidationLogic.validateHFAndLtv(
      reservesData,
      reservesList,
      eModeCategories,
      usersConfig[to],
      to,
      toEModeCategory,
      priceOracle
    );
  }
}
