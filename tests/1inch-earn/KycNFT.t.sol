// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {KycNFT} from '../../src/deployments/projects/1inch-earn/KycNFT.sol';
import {IERC721Errors} from 'openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol';
import {Ownable} from 'openzeppelin-contracts/contracts/access/Ownable.sol';

/**
 * @title KycNFTTest
 * @notice Unit tests for the vendored KycNFT gate token: owner + signature mint/transfer,
 * one-NFT-per-address, owner-burns-any / holder-burns-own, and signature expiry/validity.
 */
contract KycNFTTest is Test {
  bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)');

  string internal constant NAME = 'KYC';
  string internal constant VERSION = '1';

  KycNFT internal kyc;
  address internal owner;
  uint256 internal ownerPk;
  address internal alice = makeAddr('alice');
  address internal bob = makeAddr('bob');

  function setUp() public {
    (owner, ownerPk) = makeAddrAndKey('kycOwner');
    kyc = new KycNFT(NAME, VERSION, VERSION, owner);
  }

  // --------------------------------- owner mint/burn/transfer ---------------------------------

  function test_ownerMint() public {
    vm.prank(owner);
    kyc.mint(alice, 1);
    assertEq(kyc.balanceOf(alice), 1);
    assertEq(kyc.ownerOf(1), alice);
  }

  function test_revert_nonOwnerMint() public {
    vm.prank(bob);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
    kyc.mint(alice, 1);
  }

  function test_revert_oneNftPerAddress() public {
    vm.startPrank(owner);
    kyc.mint(alice, 1);
    vm.expectRevert(KycNFT.OnlyOneNFTPerAddress.selector);
    kyc.mint(alice, 2);
    vm.stopPrank();
  }

  function test_ownerBurnsAnyToken() public {
    vm.prank(owner);
    kyc.mint(alice, 1);
    vm.prank(owner); // owner burns a token it does not hold
    kyc.burn(1);
    assertEq(kyc.balanceOf(alice), 0);
  }

  function test_holderBurnsOwnToken() public {
    vm.prank(owner);
    kyc.mint(alice, 1);
    vm.prank(alice); // holder burns their own token
    kyc.burn(1);
    assertEq(kyc.balanceOf(alice), 0);
  }

  function test_ownerOnlyTransfer() public {
    vm.prank(owner);
    kyc.mint(alice, 1);

    vm.prank(bob);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
    kyc.transferFrom(alice, bob, 1);

    vm.prank(owner);
    kyc.transferFrom(alice, bob, 1);
    assertEq(kyc.ownerOf(1), bob);
  }

  // --------------------------------- signature mint/transfer ----------------------------------

  function test_signatureMint() public {
    uint256 tokenId = 42;
    uint256 deadline = block.timestamp + 1 hours;
    bytes memory sig = _sign(kyc.MINT_TYPEHASH(), alice, tokenId, deadline);

    // Anyone can submit the owner-signed mint.
    vm.prank(bob);
    kyc.mint(alice, tokenId, deadline, sig);
    assertEq(kyc.ownerOf(tokenId), alice);
  }

  function test_revert_signatureMintExpired() public {
    uint256 tokenId = 42;
    uint256 deadline = block.timestamp + 1 hours;
    bytes memory sig = _sign(kyc.MINT_TYPEHASH(), alice, tokenId, deadline);
    vm.warp(deadline + 1);
    vm.expectRevert(KycNFT.SignatureExpired.selector);
    kyc.mint(alice, tokenId, deadline, sig);
  }

  function test_revert_signatureMintBadSigner() public {
    uint256 tokenId = 42;
    uint256 deadline = block.timestamp + 1 hours;
    // Sign with a non-owner key.
    (, uint256 strangerPk) = makeAddrAndKey('stranger');
    bytes32 digest = _digest(kyc.MINT_TYPEHASH(), alice, tokenId, deadline);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerPk, digest);
    vm.expectRevert(KycNFT.BadSignature.selector);
    kyc.mint(alice, tokenId, deadline, abi.encodePacked(r, s, v));
  }

  function test_signatureTransfer() public {
    uint256 tokenId = 7;
    vm.prank(owner);
    kyc.mint(alice, tokenId);

    uint256 deadline = block.timestamp + 1 hours;
    bytes memory sig = _sign(kyc.TRANSFER_FROM_TYPEHASH(), bob, tokenId, deadline);
    vm.prank(bob);
    kyc.transferFrom(alice, bob, tokenId, deadline, sig);
    assertEq(kyc.ownerOf(tokenId), bob);
  }

  // ------------------------------------- helpers ----------------------------------------------

  function _domainSeparator() internal view returns (bytes32) {
    return
      keccak256(
        abi.encode(
          EIP712_DOMAIN_TYPEHASH,
          keccak256(bytes(NAME)),
          keccak256(bytes(VERSION)),
          block.chainid,
          address(kyc)
        )
      );
  }

  function _digest(
    bytes32 typeHash,
    address to,
    uint256 tokenId,
    uint256 deadline
  ) internal view returns (bytes32) {
    bytes32 structHash = keccak256(
      abi.encode(typeHash, to, kyc.nonces(tokenId), tokenId, deadline)
    );
    return keccak256(abi.encodePacked('\x19\x01', _domainSeparator(), structHash));
  }

  function _sign(
    bytes32 typeHash,
    address to,
    uint256 tokenId,
    uint256 deadline
  ) internal view returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, _digest(typeHash, to, tokenId, deadline));
    return abi.encodePacked(r, s, v);
  }
}
