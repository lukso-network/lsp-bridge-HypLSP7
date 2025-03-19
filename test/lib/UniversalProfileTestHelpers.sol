// SPDX-License-Identifer: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/src/Test.sol";

// modules
import { UniversalProfile } from "@lukso/universalprofile-contracts/contracts/UniversalProfile.sol";
import { LSP6KeyManager } from "@lukso/lsp6-contracts/contracts/LSP6KeyManager.sol";
import { LSP1UniversalReceiverDelegateUP as LSP1DelegateUP } from
    "@lukso/lsp1delegate-contracts/contracts/LSP1UniversalReceiverDelegateUP.sol";

// libraries
import { LSP2Utils } from "@lukso/lsp2-contracts/contracts/LSP2Utils.sol";
import { LSP6Utils } from "@lukso/lsp6-contracts/contracts/LSP6Utils.sol";

// interfaces
import { ILSP1UniversalReceiverDelegate as ILSP1Delegate } from
    "@lukso/lsp1-contracts/contracts/ILSP1UniversalReceiverDelegate.sol";

// constants
import {
    _LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY,
    _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX
} from "@lukso/lsp1-contracts/contracts/LSP1Constants.sol";
import {
    _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX,
    _PERMISSION_REENTRANCY,
    _PERMISSION_SUPER_SETDATA,
    ALL_REGULAR_PERMISSIONS
} from "@lukso/lsp6-contracts/contracts/LSP6Constants.sol";
import {
    _TYPEID_LSP7_TOKENSSENDER, _TYPEID_LSP7_TOKENSRECIPIENT
} from "@lukso/lsp7-contracts/contracts/LSP7Constants.sol";

contract UniversalProfileTestHelpers is Test {
    LSP1DelegateUP mainLSP1DelegateImplementationForUPs;

    function setUp() public {
        mainLSP1DelegateImplementationForUPs = new LSP1DelegateUP();
    }

    function _setUpUniversalProfileLikeBrowserExtension(address mainController) internal returns (UniversalProfile) {
        UniversalProfile universalProfile = new UniversalProfile(mainController);

        LSP6KeyManager keyManager = new LSP6KeyManager(address(universalProfile));

        _setupMainControllerPermissions(universalProfile, mainController);
        _setUPMainLSP1DelegateWithPermissions(universalProfile, mainController, mainLSP1DelegateImplementationForUPs);

        _transferOwnershipToKeyManager(universalProfile, mainController, keyManager);

        return universalProfile;
    }

    function _setUpSpecificLSP1DelegateForTokensSent(
        UniversalProfile universalProfile,
        address mainController,
        ILSP1Delegate specificLSP1Delegate,
        bytes32[] memory lsp1DelegatePermissionsList
    )
        internal
    {
        vm.startPrank(mainController);

        bytes32 dataKeyLSP1DelegateForTokensSent =
            LSP2Utils.generateMappingKey(_LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX, bytes20(_TYPEID_LSP7_TOKENSSENDER));

        bytes32 dataKeyPermissionsOfLSP1Delegate = LSP2Utils.generateMappingWithGroupingKey(
            _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX, bytes20(abi.encodePacked(specificLSP1Delegate))
        );

        bytes32 lsp1DelegatePermissionsValue = LSP6Utils.combinePermissions(lsp1DelegatePermissionsList);

        // register the specific LSP1 delegate to react on tokens sent

        universalProfile.setData(dataKeyLSP1DelegateForTokensSent, abi.encodePacked(specificLSP1Delegate));

        // set the permissions for the specific LSP1 delegate
        universalProfile.setData(dataKeyPermissionsOfLSP1Delegate, abi.encodePacked(lsp1DelegatePermissionsValue));

        vm.stopPrank();
    }

    function _setUpSpecificLSP1DelegateForTokensReceived(
        UniversalProfile universalProfile,
        address mainController,
        ILSP1Delegate specificLSP1Delegate,
        bytes32[] memory lsp1DelegatePermissionsList
    )
        internal
    {
        vm.startPrank(mainController);

        bytes32 dataKeyLSP1DelegateForTokensReceived = LSP2Utils.generateMappingKey(
            _LSP1_UNIVERSAL_RECEIVER_DELEGATE_PREFIX, bytes20(_TYPEID_LSP7_TOKENSRECIPIENT)
        );

        bytes32 dataKeyPermissions = LSP2Utils.generateMappingWithGroupingKey(
            _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX, bytes20(abi.encodePacked(specificLSP1Delegate))
        );

        bytes32 lsp1DelegatePermissionsValue = LSP6Utils.combinePermissions(lsp1DelegatePermissionsList);

        // register the specific LSP1 delegate to react on tokens received
        universalProfile.setData(dataKeyLSP1DelegateForTokensReceived, abi.encodePacked(lsp1DelegatePermissionsValue));

        // set the permissions for the specific LSP1 delegate
        universalProfile.setData(dataKeyPermissions, abi.encodePacked(lsp1DelegatePermissionsValue));

        vm.stopPrank();
    }

    function _setUPMainLSP1DelegateWithPermissions(
        UniversalProfile universalProfile,
        address mainController,
        ILSP1Delegate mainLSP1DelegateImplementation
    )
        internal
    {
        vm.startPrank(mainController);
        universalProfile.setData(
            _LSP1_UNIVERSAL_RECEIVER_DELEGATE_KEY, abi.encodePacked(mainLSP1DelegateImplementation)
        );

        // give SUPER_SETDATA + REENTRANCY permissions to the main LSP1 Universal Receiver Delegate contract
        bytes32 permissionDataKeyForMainLSP1Delegate = LSP2Utils.generateMappingWithGroupingKey(
            _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX, bytes20(abi.encodePacked(mainLSP1DelegateImplementation))
        );

        // use Bitwise OR to set each permission bit individually
        // (just for simplicity here and avoid creating a `bytes32[] memory` array).
        // However, it is recommended to use the LSP6Utils.combinePermissions(...) function.
        universalProfile.setData(
            permissionDataKeyForMainLSP1Delegate, abi.encodePacked(_PERMISSION_REENTRANCY | _PERMISSION_SUPER_SETDATA)
        );

        vm.stopPrank();
    }

    function _setupMainControllerPermissions(UniversalProfile universalProfile, address mainController) internal {
        bytes32 dataKey = LSP2Utils.generateMappingWithGroupingKey(
            _LSP6KEY_ADDRESSPERMISSIONS_PERMISSIONS_PREFIX, bytes20(mainController)
        );

        bytes memory dataValue = abi.encodePacked(ALL_REGULAR_PERMISSIONS);

        vm.prank(mainController);
        universalProfile.setData(dataKey, dataValue);
    }

    function _transferOwnershipToKeyManager(
        UniversalProfile universalProfile,
        address oldOwner,
        LSP6KeyManager keyManager
    )
        internal
    {
        // transfer ownership to keyManager
        vm.prank(oldOwner);
        universalProfile.transferOwnership(address(keyManager));

        // accept ownership of UniversalProfile as keyManager
        vm.prank(address(keyManager));
        universalProfile.acceptOwnership();

        // check if keyManager is owner of UniversalProfile
        assertEq(universalProfile.owner(), address(keyManager));
    }
}
