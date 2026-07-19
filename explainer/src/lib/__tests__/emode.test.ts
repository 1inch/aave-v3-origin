import { describe, it, expect } from 'vitest';
import { getUserReserveLtv, isEModeEntryBlocked } from '../emode';
import type { EModeAsset } from '../emode';

const WETH: EModeAsset = { inCollateralBitmap: true, baseLtv: 80.5, emodeLtv: 93 };
const LINK: EModeAsset = { inCollateralBitmap: false, baseLtv: 66, emodeLtv: 66 };
const FROZEN_LST: EModeAsset = {
  inCollateralBitmap: true,
  inLtvzeroBitmap: true,
  baseLtv: 78.5,
  emodeLtv: 93,
};

describe('getUserReserveLtv (ValidationLogic v3.7)', () => {
  it('branch 1: bitmap assets get the eMode LTV', () => {
    const r = getUserReserveLtv(WETH, true, true);
    expect(r.branch).toBe(1);
    expect(r.ltv).toBe(93);
  });

  it('branch 1 precedence: ltvzeroBitmap zeroes a bitmap asset even in an isolated category', () => {
    const r = getUserReserveLtv(FROZEN_LST, true, false);
    expect(r.branch).toBe(1);
    expect(r.ltv).toBe(0);
  });

  it('branch 2 (NEW in v3.7): outside-bitmap assets get LTV 0 in an isolated eMode', () => {
    const r = getUserReserveLtv(LINK, true, true);
    expect(r.branch).toBe(2);
    expect(r.ltv).toBe(0);
  });

  it('branch 3: outside-bitmap assets keep their base LTV in a non-isolated eMode', () => {
    const r = getUserReserveLtv(LINK, true, false);
    expect(r.branch).toBe(3);
    expect(r.ltv).toBe(66);
  });

  it('branch 3: everything uses base LTV outside eMode (category 0)', () => {
    expect(getUserReserveLtv(WETH, false, true).ltv).toBe(80.5);
    expect(getUserReserveLtv(LINK, false, true).ltv).toBe(66);
  });
});

describe('isEModeEntryBlocked (validateSetUserEMode)', () => {
  it('blocks entry into an isolated eMode with outside-bitmap collateral enabled', () => {
    const blocked = isEModeEntryBlocked(
      [
        { asset: WETH, enabledAsCollateral: true },
        { asset: LINK, enabledAsCollateral: true },
      ],
      true,
    );
    expect(blocked).toBe(true);
  });

  it('allows entry once the offending collateral is disabled', () => {
    const blocked = isEModeEntryBlocked(
      [
        { asset: WETH, enabledAsCollateral: true },
        { asset: LINK, enabledAsCollateral: false },
      ],
      true,
    );
    expect(blocked).toBe(false);
  });

  it('does not block entry into a NON-isolated eMode', () => {
    const blocked = isEModeEntryBlocked(
      [
        { asset: WETH, enabledAsCollateral: true },
        { asset: LINK, enabledAsCollateral: true },
      ],
      false,
    );
    expect(blocked).toBe(false);
  });
});
