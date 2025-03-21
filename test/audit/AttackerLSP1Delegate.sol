pragma solidity ^0.8.13;

import { console } from "forge-std/src/console.sol";

import { LSP1UniversalReceiverDelegateUP as LSP1Delegate } from
    "@lukso/lsp1delegate-contracts/contracts/LSP1UniversalReceiverDelegateUP.sol";


contract AttackerLSP1Delegate is LSP1Delegate {

    function universalReceiverDelegate(
        address notifier,
        uint256 value,
        bytes32 typeId,
        bytes memory data 
    ) public virtual override returns (bytes memory) {
        console.log("notifier ", notifier);
        console.log("value ", value);
        console.log("typeid ");
        console.logBytes32(typeId);
        console.log("data");
        bytes32[] memory data32 = breakIntoBytes32(data);
        for(uint i=0; i<data32.length; i++) {
            console.logBytes32(data32[i]);
        }
        // super.universalReceiverDelegate(notifier,value,typeId,data);
    }

    function breakIntoBytes32(bytes memory data) public pure returns (bytes32[] memory) {
        // Calculate the number of bytes32 chunks needed
        uint256 length = data.length;
        uint256 numChunks = (length + 31) / 32; // Round up to the nearest multiple of 32

        // Initialize the output array
        bytes32[] memory chunks = new bytes32[](numChunks);

        // Iterate over the data and slice it into bytes32 chunks
        for (uint256 i = 0; i < numChunks; i++) {
            uint256 start = i * 32;
            uint256 end = start + 32;

            // Ensure we don't read past the end of the data
            if (end > length) {
                end = length;
            }

            // Extract the chunk
            bytes memory chunk = new bytes(32);
            for (uint256 j = start; j < end; j++) {
                chunk[j - start] = data[j];
            }

            // Convert the chunk to bytes32 and store it in the output array
            chunks[i] = bytes32(chunk);
        }

        return chunks;
    }
}