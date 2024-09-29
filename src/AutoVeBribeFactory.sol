// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {LibClone} from "solady/utils/LibClone.sol";
import {AutoVeBribe} from "./AutoVeBribe.sol";

contract AutoVeBribeFactory {
    address public implementation;

    address[] public autoBribes;

    constructor(address _voter) {
        implementation = address(new AutoVeBribe(_voter));
    }

    function deployAutoVeBribe(address _gauge, address _owner) external {
        AutoVeBribe newBribe = AutoVeBribe(LibClone.clone_PUSH0(implementation));
        newBribe.initialize(_gauge, _owner);
        autoBribes.push(address(newBribe));
    }
}
