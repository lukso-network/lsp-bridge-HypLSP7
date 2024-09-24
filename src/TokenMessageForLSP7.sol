// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

/// @dev Adjusted version of the TokenMessage library from Hyperlane
/// to extract parameters from the calldata of an LSP7 transfer
/// according to the `transfer(address,address,uint256,bool,bytes)` signature.
library TokenMessageForLSP7 {
    function format(bytes32 _recipient, uint256 _amount, bytes memory _metadata) internal view returns (bytes memory) {
        return abi.encodePacked(
            msg.sender, // TODO: which sender should be specified here? Should we add an extra parameter?
            _recipient,
            _amount,
            true, // force param set to `true` by default
            _metadata
        );
    }

    function recipient(bytes calldata message) internal pure returns (bytes32) {
        return bytes32(message[32:64]);
    }

    function amount(bytes calldata message) internal pure returns (uint256) {
        return uint256(bytes32(message[64:96]));
    }
}
