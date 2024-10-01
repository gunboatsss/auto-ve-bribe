// SPDX-License-Identifier: MIT
pragma solidity >=0.8.27;

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
    mapping(address _token => uint256 lastBribeTime) public nextBribeTimeByToken;

    error GaugeAlreadySet();
    error NotAGauge();

    error AlreadySentThisEpoch(address _token);
    error ZeroToken(address _token);
    error InvalidDistributionTime();

    error GaugeIsStillAlive();

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
        // console.log("initalizing bribe with ", address(bribeVotingReward));
        gauge = _gauge;
        _initializeOwner(_owner);
    }

    function distribute(address _token) public {
        if (
            ProtocolTimeLibrary.epochVoteStart(block.timestamp) > block.timestamp
                || ProtocolTimeLibrary.epochVoteEnd(block.timestamp) < block.timestamp
        ) {
            revert InvalidDistributionTime();
        }

        // Check the last time bribe was distributed
        if (block.timestamp < nextBribeTimeByToken[_token]) {
            revert AlreadySentThisEpoch(_token);
        }

        uint256 cap = amountToBribeByTokenPerEpoch[_token];
        uint256 balance = SafeTransferLib.balanceOf(_token, address(this));
        uint256 amountToSend = (balance > cap) ? cap : balance;

        if (cap == 0) {
            amountToSend = balance;
        }
        if (amountToSend == 0) {
            revert ZeroToken(_token);
        }
        nextBribeTimeByToken[_token] = ProtocolTimeLibrary.epochVoteEnd(block.timestamp);

        SafeTransferLib.safeApprove(_token, address(bribeVotingReward), amountToSend);
        bribeVotingReward.notifyRewardAmount(_token, amountToSend);
    }

    function distribute(address[] calldata _token) public {
        for (uint256 i = 0; i < _token.length; i++) {
            distribute(_token[i]);
        }
    }

    // SETTOR

    function setTokenAmountPerEpoch(address _token, uint256 _amount) external onlyOwner {
        amountToBribeByTokenPerEpoch[_token] = _amount;
    }

    // ADMIN FUNCTION

    function recoverERC20(address _token) external onlyOwner {
        if (voter.isWhitelistedToken(_token) && voter.isAlive(gauge)) {
            revert GaugeIsStillAlive();
        }
        SafeTransferLib.safeTransferAll(_token, msg.sender);
    }
}
