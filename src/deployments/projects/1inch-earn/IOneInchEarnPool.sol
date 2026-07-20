// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @title IOneInchEarnPool
 * @author 1inch
 * @notice Extension surface added by `OneInchPoolInstance` on top of the audited Aave v3.7
 * `IPool`, exposing the callback the transferable debt token uses after moving balances.
 */
interface IOneInchEarnPool {
  /**
   * @notice Finalizes a debt-token transfer: updates the borrowing flags of both accounts and
   * validates that the receiver (which just assumed the debt) remains solvent.
   * @dev Callable only by the reserve's variable debt token, and only AFTER the token has moved
   * the scaled balance. The sender is never health-checked (losing debt only improves them).
   * @param asset The underlying asset of the reserve whose debt was moved
   * @param from The account the debt was moved from
   * @param to The account that assumed the debt (health-checked here)
   */
  function finalizeDebtTransfer(address asset, address from, address to) external;
}
