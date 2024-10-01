// SPDX-License-Identifier: MIT
pragma solidity >=0.8.27;

import {IReward} from "./interfaces/IReward.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {ProtocolTimeLibrary} from "./libraries/ProtocolTimeLibrary.sol";

import {AutomationCompatibleInterface} from "./interfaces/AutomationCompatibleInterface.sol";

import {IOpsProxy} from "./interfaces/IOpsProxy.sol";

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract AutoVeBribe is Ownable, AutomationCompatibleInterface {
    IVoter public immutable voter;

    address public gauge;
    IReward public bribeVotingReward;

    mapping(address _token => uint256 amountPerEpoch) public amountToBribeByTokenPerEpoch;
    mapping(address _token => uint256 lastBribeTime) public nextBribeTimeByToken;

    error GaugeAlreadySet();
    error NotAGauge();

    error AlreadySentThisEpoch(address _token);
    error NotWhitelisted(address _token);
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

    enum Err {
        NO,
        INVALID_TIME,
        NO_TOKEN
    }
    // CHAINLINK AUTOMATION

    function checkUpkeep(bytes calldata checkData)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        address[] memory tokenToCheck = abi.decode(checkData, (address[]));
        (Err err, address[] memory tokenArr) = _checkUpkeep(tokenToCheck);
        if (err == Err.INVALID_TIME) {
            return (false, "Not in bribe window");
        }
        if (err == Err.NO_TOKEN) {
            return (false, "No token to distribute");
        }
        upkeepNeeded = true;
        performData = abi.encode(tokenArr);
    }

    function checkUpkeepGelato(address[] calldata tokenToCheck)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        (Err err, address[] memory tokenArr) = _checkUpkeep(tokenToCheck);
        if (err == Err.INVALID_TIME) {
            return (false, "Not in bribe window");
        }
        if (err == Err.NO_TOKEN) {
            return (false, "No token to distribute");
        }
        upkeepNeeded = true;
        performData = abi.encodeCall(
            IOpsProxy.executeCall, (address(this), abi.encodeWithSignature("distribute(address[])", (tokenArr)), 0)
        );
    }


    function _checkUpkeep(address[] memory tokens) internal view returns (Err err, address[] memory tokenArr) {
        if (
            ProtocolTimeLibrary.epochVoteStart(block.timestamp) > block.timestamp
                || ProtocolTimeLibrary.epochVoteEnd(block.timestamp) < block.timestamp
        ) {
            return (Err.INVALID_TIME, tokenArr);
        }
        uint256 length = tokens.length;
        tokenArr = new address[](length);
        uint256 tokenCount;
        for (uint256 i = 0; i < length; i++) {
            address token = tokens[i];
            if (!voter.isWhitelistedToken(token)) {
                continue;
            }
            if (SafeTransferLib.balanceOf(token, address(this)) > 0 && block.timestamp > nextBribeTimeByToken[token]) {
                tokenArr[tokenCount] = token;
                tokenCount += 1;
            }
        }
        if (tokenCount == 0) {
            return (Err.NO_TOKEN, tokenArr);
        }
        assembly {
            mstore(tokenArr, tokenCount)
        }
        err = Err.NO;
    }

    function performUpkeep(bytes calldata performData) external {
        address[] memory tokenArr = abi.decode(performData, (address[]));
        distribute(tokenArr);
    }
    // TOKEN DISTRIBUTION FUNCTION

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

        if (!voter.isWhitelistedToken(_token)) {
            revert NotWhitelisted(_token);
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

    function distribute(address[] memory _token) public {
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
