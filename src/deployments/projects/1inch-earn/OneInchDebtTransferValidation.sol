// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {DataTypes} from '../../../contracts/protocol/libraries/types/DataTypes.sol';
import {ReserveConfiguration} from '../../../contracts/protocol/libraries/configuration/ReserveConfiguration.sol';
import {EModeConfiguration} from '../../../contracts/protocol/libraries/configuration/EModeConfiguration.sol';

/**
 * @title OneInchDebtTransferValidation
 * @author 1inch
 * @notice Reserve-state and eMode validation for a debt-token transfer on the 1inch Earn market.
 * @dev Mirrors the borrow-side checks of `ValidationLogic` for the receiver assuming the debt.
 * Note: Aave v3.7 removed isolation mode, debt ceilings and siloed borrowing (no references in
 * `ValidationLogic`/`ReserveConfiguration`), so those checks do not apply here. The receiver's
 * health-factor check is done separately by `ValidationLogic.validateHFAndLtv`.
 */
library OneInchDebtTransferValidation {
  using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

  error ReserveInactive();
  error ReserveFrozen();
  error ReservePaused();
  error BorrowingNotEnabled();
  error DebtNotBorrowableInEMode();

  /**
   * @param reserve The reserve whose debt is being moved
   * @param eModeCategories The configuration of all the efficiency mode categories
   * @param toEModeCategory The receiver's active eMode category (0 if none)
   */
  function validateDebtTransfer(
    DataTypes.ReserveData storage reserve,
    mapping(uint8 => DataTypes.EModeCategory) storage eModeCategories,
    uint8 toEModeCategory
  ) internal view {
    DataTypes.ReserveConfigurationMap memory configuration = reserve.configuration;

    (bool isActive, bool isFrozen, bool borrowingEnabled, bool isPaused) = configuration.getFlags();

    require(isActive, ReserveInactive());
    require(!isPaused, ReservePaused());
    require(!isFrozen, ReserveFrozen());
    // Receiving debt is borrow-like: only allowed for reserves where borrowing is enabled.
    // This also structurally blocks the red-row assets (1INCH/AQUA borrowing disabled).
    require(borrowingEnabled, BorrowingNotEnabled());

    // If the receiver is in an eMode category, the debt asset must be borrowable in it,
    // matching ValidationLogic.validateBorrow's eMode borrowable rule.
    if (toEModeCategory != 0) {
      require(
        EModeConfiguration.isReserveEnabledOnBitmap(
          eModeCategories[toEModeCategory].borrowableBitmap,
          reserve.id
        ),
        DebtNotBorrowableInEMode()
      );
    }
  }
}
