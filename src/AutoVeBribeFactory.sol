// SPDX-License-Identifier: MIT
pragma solidity >=0.8.27;

import {LibClone} from "solady/utils/LibClone.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {AutoVeBribe} from "./AutoVeBribe.sol";

contract AutoVeBribeFactory {
    address public implementation;

    address[] public autoBribes;

    event NewAutoBribeCreated(address indexed autoBribe, address indexed gauge);

    constructor(address _voter) {
        implementation = address(new AutoVeBribe(_voter));
    }

    function getLength() external view returns (uint256) {
        return autoBribes.length;
    }

    function getBribe(uint256 index) external view returns (address) {
        return autoBribes[index];
    }

    function deployAutoVeBribe(address _gauge, address _owner) external returns (address newAutoBribe) {
        AutoVeBribe newBribe = AutoVeBribe(LibClone.clone_PUSH0(implementation));
        newBribe.initialize(_gauge, _owner);
        autoBribes.push(address(newBribe));
        emit NewAutoBribeCreated(address(newBribe), _gauge);
        return address(newBribe);
    }

    function recoverERC20(address _token) external {
        SafeTransferLib.safeTransferAll(_token, msg.sender);
    }
}
