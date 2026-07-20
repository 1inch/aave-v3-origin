import { describe, it, expect } from 'vitest';
import { encodeSupplyArgs, decodeSupplyArgs, toBytes32Hex } from '../calldata';

describe('L2Pool supply-args packing (CalldataLogic layout)', () => {
  it('round-trips assetId / amount / referralCode', () => {
    const input = { assetId: 3, amount: 10n ** 18n, referralCode: 42 };
    expect(decodeSupplyArgs(encodeSupplyArgs(input))).toEqual(input);
  });

  it('places fields at the documented bit offsets', () => {
    const word = encodeSupplyArgs({ assetId: 0xabcd, amount: 0x1234n, referralCode: 0x99 });
    expect(word & 0xffffn).toBe(0xabcdn); // bits 0-15
    expect((word >> 16n) & ((1n << 128n) - 1n)).toBe(0x1234n); // bits 16-143
    expect((word >> 144n) & 0xffffn).toBe(0x99n); // bits 144-159
  });

  it('renders a 32-byte hex word', () => {
    const hex = toBytes32Hex(encodeSupplyArgs({ assetId: 1, amount: 1n, referralCode: 0 }));
    expect(hex).toMatch(/^0x[0-9a-f]{64}$/);
    // assetId 1 in the lowest 2 bytes, amount 1 just above it
    expect(hex.endsWith('10001')).toBe(true);
  });

  it('keeps the high permit bits (160+) zero for plain supply', () => {
    const word = encodeSupplyArgs({ assetId: 65535, amount: (1n << 128n) - 1n, referralCode: 65535 });
    expect(word >> 160n).toBe(0n);
  });
});
