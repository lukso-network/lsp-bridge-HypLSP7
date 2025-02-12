// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

/**
 * @title TokenMessage library for LSP7 calldatas
 * @author CJ42
 *
 * @dev Adjusted version of the TokenMessage library from Hyperlane to extract parameters from
 * the calldata of an LSP7 transfer according to the `transfer(address,address,uint256,bool,bytes)` function signature.
 *
 * Example 1: for the following LSP7 `transfer(address,address,uint256,bool,bytes)` function call:
 * ======================================================================================================================
 * | Parameter  | Value in calldata                           | Description                                             |
 * |------------|---------------------------------------------|---------------------------------------------------------|
 * | from       | 0xCAfEcAfeCAfECaFeCaFecaFecaFECafECafeCaFe  | sender address bridging tokens from LUKSO.              |
 * | to         | 0xBEeFbeefbEefbeEFbeEfbEEfBEeFbeEfBeEfBeef  | recipient address receiving bridged tokens on Ethereum. |
 * | amount     | 100000000000000000000                       | represents 100 tokens with 18 decimals (in wei)         |
 * | force      | true                                        | indicates whether the transfer should be forced.        |
 * | data       | 0x                                          | additional data (empty in this case).                   |
 * ======================================================================================================================
 *
 * The calldata will look as follow:
 * 0x760d9bba000000000000000000000000cafecafecafecafecafecafecafecafecafecafe000000000000000000000000beefbeefbeefbeefbeefbeefbeefbeefbeefbeef0000000000000000000000000000000000000000000000056bc75e2d63100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000
 *
 *      0x760d9bba                                                         -> bytes4 selector
 * (0)    000000000000000000000000cafecafecafecafecafecafecafecafecafecafe -> address `from`
 * (32)   000000000000000000000000beefbeefbeefbeefbeefbeefbeefbeefbeefbeef -> address `to`
 * (64)   0000000000000000000000000000000000000000000000056bc75e2d63100000 -> uint256 `amount` (`100` written in hex)
 * (96)   0000000000000000000000000000000000000000000000000000000000000000 -> bool `force`
 * (128)  00000000000000000000000000000000000000000000000000000000000000a0 -> offset of bytes `data`
 * (160)  0000000000000000000000000000000000000000000000000000000000000000 -> `data.length` = 0
 *
 * ---
 *
 * Example 2: for the following LSP8 `transfer(address,address,bytes32,bool,bytes)` function call:
 * ======================================================================================================================
 * | Parameter  | Value in calldata                           | Description                                             |
 * |------------|---------------------------------------------|---------------------------------------------------------|
 * | from       | 0xCAfEcAfeCAfECaFeCaFecaFecaFECafECafeCaFe  | sender address bridging tokens from LUKSO.              |
 * | to         | 0xBEeFbeefbEefbeEFbeEfbEEfBEeFbeEfBeEfBeef  | recipient address receiving bridged tokens on Ethereum. |
 * | tokenId    | 123                                         | tokenId nb 123                                          |
 * | force      | true                                        | indicates whether the transfer should be forced.        |
 * | data       | 0x                                          | additional data (empty in this case).                   |
 * ======================================================================================================================
 *
 * The calldata will look as follow:
 * 0x511b6952000000000000000000000000cafecafecafecafecafecafecafecafecafecafe000000000000000000000000beefbeefbeefbeefbeefbeefbeefbeefbeefbeef7b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000
 *
 *      0x511b6952                                                         -> bytes4 selector
 * (0)    000000000000000000000000cafecafecafecafecafecafecafecafecafecafe -> address `from`
 * (32)   000000000000000000000000beefbeefbeefbeefbeefbeefbeefbeefbeefbeef -> address `to`
 * (64)   7b00000000000000000000000000000000000000000000000000000000000000 -> bytes32 `tokenId` (`123` written in hex)
 * (96)   0000000000000000000000000000000000000000000000000000000000000000 -> bool `force`
 * (128)  00000000000000000000000000000000000000000000000000000000000000a0 -> offset of bytes `data`
 * (160)  0000000000000000000000000000000000000000000000000000000000000000 -> `data.length` = 0
 *
 * Notes:
 *
 * The offset is the index in the calldata bytes string where each parameter.
 * It is a number in the calldata bytes that starts at 0 "just after the bytes4 selector". For example:
 *
 * 1. `data[offset]` = index 0
 * 2. `data[length + value]` = index 160
 *
 * Note also that the `to` address (recipient of the bridged tokens on the destination chain)
 * could be either the same `from` address, or a different one.
 */
library TokenMessageForLSP {
    function format(bytes32 _recipient, uint256 _amount, bytes memory _metadata) internal view returns (bytes memory) {
        return abi.encodePacked(
            abi.encode(msg.sender),
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

    function tokenId(bytes calldata message) internal pure returns (bytes32) {
        return bytes32(message[64:96]);
    }

    function metadata(bytes calldata message) internal pure returns (bytes calldata) {
        return message[128:];
    }
}
