/**
 * L2Pool calldata packing, mirroring CalldataLogic.decodeSupplyParams:
 *   bits 0-15    assetId (index into _reservesList)
 *   bits 16-143  amount (uint128)
 *   bits 144-159 referralCode
 *   bits 160-255 unused (supplyWithPermit packs deadline/v here)
 * Source: src/contracts/protocol/libraries/logic/CalldataLogic.sol
 */

export type SupplyArgs = {
  assetId: number;
  amount: bigint;
  referralCode: number;
};

const MASK_16 = (1n << 16n) - 1n;
const MASK_128 = (1n << 128n) - 1n;

export function encodeSupplyArgs(args: SupplyArgs): bigint {
  const assetId = BigInt(args.assetId) & MASK_16;
  const amount = args.amount & MASK_128;
  const referral = BigInt(args.referralCode) & MASK_16;
  return assetId | (amount << 16n) | (referral << 144n);
}

export function decodeSupplyArgs(word: bigint): SupplyArgs {
  return {
    assetId: Number(word & MASK_16),
    amount: (word >> 16n) & MASK_128,
    referralCode: Number((word >> 144n) & MASK_16),
  };
}

/** 0x-prefixed, 64-char bytes32 hex representation. */
export function toBytes32Hex(word: bigint): string {
  return `0x${word.toString(16).padStart(64, '0')}`;
}

/**
 * Hex-char segments of the bytes32 (big-endian string): index ranges
 * [0,24) unused · [24,28) referralCode · [28,60) amount · [60,64) assetId.
 */
export const SUPPLY_HEX_SEGMENTS = [
  { name: 'unused', from: 0, to: 24 },
  { name: 'referralCode', from: 24, to: 28 },
  { name: 'amount', from: 28, to: 60 },
  { name: 'assetId', from: 60, to: 64 },
] as const;
