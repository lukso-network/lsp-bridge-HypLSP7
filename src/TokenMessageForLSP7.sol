// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

/// @dev Adjusted version of the TokenMessage library from Hyperlane
/// to extract parameters from the calldata of an LSP7 transfer
/// according to the `transfer(address,address,uint256,bool,bytes)` signature.
/**
 * @title TokenMessage library for LSP7 calldatas
 * @author CJ42
 * @dev
 *
 * Example: for the following `transfer(...)` function call:
 *
 * from:    0x927aad446e3bf6eeb776387b3d7a89d8016fa54d (cj42)
 * to:      0x345b918b9e06faa7b0e56bd71ba418f31f47fed4 (yamen)
 * amount:  100000000000000000000 (= 100 tokens with 18 decimals)
 * force:   false
 * data:    0x
 *
 * The calldata will look as follow:
 * 0x760d9bba000000000000000000000000927aad446e3bf6eeb776387b3d7a89d8016fa54d000000000000000000000000345b918b9e06faa7b0e56bd71ba418f31f47fed40000000000000000000000000000000000000000000000056bc75e2d63100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000
 *
 * 0x760d9bba                                                         -> bytes4 selector
 *   000000000000000000000000927aad446e3bf6eeb776387b3d7a89d8016fa54d -> address `from`
 *   000000000000000000000000345b918b9e06faa7b0e56bd71ba418f31f47fed4 -> address `to`
 *   0000000000000000000000000000000000000000000000056bc75e2d63100000 -> uint256 `amount`
 *   0000000000000000000000000000000000000000000000000000000000000000 -> bool `force`
 *   00000000000000000000000000000000000000000000000000000000000000a0 -> offset of bytes `data`
 *   0000000000000000000000000000000000000000000000000000000000000000 -> `data.length` = 0
 *
 * Note: the offset of data is index starting from just after the bytes4 selector, where the data [length + value] is
 * located in the calldata (0xa0 = 160).
 */
library TokenMessageForLSP7 {
    function format(bytes32 _recipient, uint256 _amount, bytes memory _metadata) internal view returns (bytes memory) {
        return abi.encodePacked(
            abi.encode(msg.sender), // TODO: which sender should be specified here? Should we add an
                // extra parameter?
            _recipient,
            _amount,
            abi.encode(true), // force param set to `true` by default
            _metadata
        );
    }

    function recipient(bytes calldata message) internal pure returns (bytes32) {
        return bytes32(message[32:64]);
    }

    function amount(bytes calldata message) internal pure returns (uint256) {
        return uint256(bytes32(message[64:96]));
    }

    function metadata(bytes calldata message) internal pure returns (bytes calldata) {
        return message[128:];
    }
}

// 0x44c028fe
//   0000000000000000000000000000000000000000000000000000000000000000
//   0000000000000000000000005b8b0e44d4719f8a328470dccd3746bfc73d6b14
//   0000000000000000000000000000000000000000000000000000000000000000
//   0000000000000000000000000000000000000000000000000000000000000080
//   00000000000000000000000000000000000000000000000000000000000000c4
//   760d9bba000000000000000000000000927aad446e3bf6eeb776387b3d7a89d8016fa54d000000000000000000000000345b918b9e06faa7b0e56bd71ba418f31f47fed40000000000000000000000000000000000000000000000056bc75e2d63100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
