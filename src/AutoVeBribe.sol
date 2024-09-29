// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {IReward} from "./interfaces/IReward.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {ProtocolTimeLibrary} from "./libraries/ProtocolTimeLibrary.sol";

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract AutoVeBribe is Ownable {
    IVoter public immutable voter;

    address public gauge;
    IReward public bribeVotingReward;

    mapping(address _token => uint256 amountPerEpoch) public amountToBribeByTokenPerEpoch;
    mapping(address _token => uint256 lastBribeTime) public lastBribeTimeByToken;

    error GaugeAlreadySet();
    error NotAGauge();
    error AlreadySentThisEpoch(address _token);
    error InvalidDistributionTime();

    constructor(address _voter) {
        voter = IVoter(_voter);
    }

    function initialize(address _gauge, address _owner) external {
        if (gauge != address(0)) {
            revert GaugeAlreadySet();
        }
        if (!voter.isGauge(_gauge)) {
            revert NotAGauge();
        }
        bribeVotingReward = IReward(voter.gaugeToBribe(_gauge));
        gauge = _gauge;
        _initializeOwner(_owner);
    }

    function distribute(address _token) public {
        // Check the last time bribe was distributed
        uint256 currentTime = block.timestamp;
        uint256 lastDistributed = lastBribeTimeByToken[_token];
        if (
            ProtocolTimeLibrary.epochVoteStart(currentTime) > lastDistributed
                || ProtocolTimeLibrary.epochVoteEnd(currentTime) < lastDistributed
        ) {
            revert InvalidDistributionTime();
        }
        if (currentTime - lastDistributed < ProtocolTimeLibrary.WEEK) {
            revert AlreadySentThisEpoch(_token);
        }

        uint256 cap = amountToBribeByTokenPerEpoch[_token];
        uint256 balance = SafeTransferLib.balanceOf(_token, address(this));
        uint256 amountToSend = (balance > cap) ? cap : balance;

        if (cap == 0) {
            amountToSend = balance;
        }

        lastBribeTimeByToken[_token] = currentTime;

        SafeTransferLib.safeApprove(_token, address(bribeVotingReward), amountToSend);
        bribeVotingReward.notifyRewardAmount(_token, balance);
    }

    function distribute(address[] calldata _token) public {
        for (uint256 i = 0; i < _token.length; i++) {
            distribute(_token[i]);
        }
    }
}
