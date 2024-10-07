// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {LibClone} from "solady/utils/LibClone.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {IVoter} from "./interfaces/IVoter.sol";
import {AutoVeBribe} from "./AutoVeBribe.sol";

contract AutoVeBribeFactory {
    AutoVeBribe public immutable implementation;
    IVoter public immutable voter;

    address[] public autoBribes;

    event NewAutoBribeCreated(address indexed autoBribe, address indexed gauge);

    error NotAGauge();

    constructor(address _voter) {
        voter = IVoter(_voter);
        implementation = new AutoVeBribe();
        implementation.initialize(address(this));
    }

    function getLength() external view returns (uint256) {
        return autoBribes.length;
    }

    function getBribe(uint256 index) external view returns (address) {
        return autoBribes[index];
    }

    function deployAutoVeBribe(address _gauge, address _owner) external returns (address newAutoBribe) {
        if (!voter.isGauge(_gauge)) {
            revert NotAGauge();
        }
        address bribeVotingReward = voter.gaugeToBribe(_gauge);
        bytes memory args = abi.encodePacked(address(voter), _gauge, bribeVotingReward);
        AutoVeBribe newBribe = AutoVeBribe(LibClone.clone(address(implementation), args));
        newBribe.initialize(_owner);
        autoBribes.push(address(newBribe));
        emit NewAutoBribeCreated(address(newBribe), _gauge);
        return address(newBribe);
    }

    function recoverERC20(address _token) external {
        SafeTransferLib.safeTransferAll(_token, msg.sender);
    }
}
