// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.20;

// constants
import { _INTERFACEID_LSP0 } from "@lukso/lsp0-contracts/contracts/LSP0Constants.sol";
import {
    _LSP4_TOKEN_TYPE_TOKEN,
    _LSP4_SUPPORTED_STANDARDS_KEY,
    _LSP4_TOKEN_NAME_KEY,
    _LSP4_TOKEN_SYMBOL_KEY,
    _LSP4_TOKEN_TYPE_KEY,
    _LSP4_CREATORS_ARRAY_KEY,
    _LSP4_CREATORS_MAP_KEY_PREFIX,
    _LSP4_METADATA_KEY
} from "@lukso/lsp4-contracts/contracts/LSP4Constants.sol";

bytes constant SAMPLE_METADATA_BYTES =
    hex"00006f357c6a0020820464ddfac1bec070cc14a8daf04129871d458f2ca94368aae8391311af6361696670733a2f2f516d597231564a4c776572673670456f73636468564775676f3339706136727963455a4c6a7452504466573834554178";

// setting data keys for the following:
// - 1 x creator in the creator array
// - creator's info under the map key
// - the token metadata
function generateLSP4DataKeysAndValues() view returns (bytes32[] memory dataKeys, bytes[] memory dataValues) {
    dataKeys = new bytes32[](4);
    dataKeys[0] = _LSP4_CREATORS_ARRAY_KEY;
    dataKeys[1] = bytes32(abi.encodePacked(bytes16(_LSP4_CREATORS_ARRAY_KEY), bytes16(uint128(0))));
    dataKeys[2] = bytes32(abi.encodePacked(_LSP4_CREATORS_MAP_KEY_PREFIX, bytes2(0), bytes20(msg.sender)));
    dataKeys[3] = _LSP4_METADATA_KEY;

    dataValues = new bytes[](4);
    dataValues[0] = abi.encodePacked(bytes16(uint128(1)));
    dataValues[1] = abi.encodePacked(bytes20(msg.sender));
    dataValues[2] = abi.encodePacked(_INTERFACEID_LSP0, bytes16(uint128(0)));
    dataValues[3] = SAMPLE_METADATA_BYTES;
}

// This is a work around for creating a message to Mailbox.process()
// because the `Message.formatMessage` library from Hyperlane requires
// the `bytes _messageBody` to be from calldata.
// This function enables to pass bytes from memory.
function formatHyperlaneMessage(
    uint8 _version,
    uint32 _nonce,
    uint32 _originDomain,
    bytes32 _sender,
    uint32 _destinationDomain,
    bytes32 _recipient,
    bytes memory _messageBody // uses memory instead of calldata
)
    pure
    returns (bytes memory)
{
    return abi.encodePacked(_version, _nonce, _originDomain, _sender, _destinationDomain, _recipient, _messageBody);
}
