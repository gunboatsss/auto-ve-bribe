// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IReward} from "./interfaces/IReward.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {ProtocolTimeLibrary} from "./libraries/ProtocolTimeLibrary.sol";

import {AutomationCompatibleInterface} from "./interfaces/AutomationCompatibleInterface.sol";

import {IOpsProxy} from "./interfaces/IOpsProxy.sol";

import {IERC20} from "./interfaces/IERC20.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract AutoVeBribe is Ownable, AutomationCompatibleInterface {
    bool public inited;

    mapping(address _token => uint256 amountPerEpoch) public amountToBribeByTokenPerEpoch;
    mapping(address _token => uint256 lastBribeTime) public nextBribeTimeByToken;
    mapping(address _token => uint256 tokenBudget) public tokenBudget;
    mapping(address _token => bool) public isReward;

    address[] public rewardToken;

    event TokenAdded(address indexed _token);
    event SetNewAmountPerEpoch(address indexed token, uint256 indexed amount);
    event SetNewTokenBudget(address indexed token, uint256 indexed amount);

    error AlreadySentThisEpoch(address _token);
    error NotWhitelisted(address _token);
    error ZeroToken(address _token);
    error InvalidDistributionTime();

    error GaugeIsStillAlive();

    function initialize(address _owner) external {
        if (inited) revert AlreadyInitialized();
        _initializeOwner(_owner);
        inited = true;
    }

    function voter() public view returns (IVoter _voter) {
        bytes memory res = LibClone.argsOnClone(address(this), 0, 20);
        assembly {
            _voter := mload(add(res, 20))
        }
    }

    function gauge() public view returns (address _gauge) {
        bytes memory res = LibClone.argsOnClone(address(this), 20, 40);
        assembly {
            _gauge := mload(add(res, 20))
        }
    }

    function bribeVotingReward() public view returns (IReward _bribeVotingReward) {
        bytes memory res = LibClone.argsOnClone(address(this), 40, 60);
        assembly {
            _bribeVotingReward := mload(add(res, 20))
        }
    }

    function rewardTokenByIndex(uint256 index) public view returns (address _token) {
        _token = rewardToken[index];
    }

    function rewardTokenLength() public view returns (uint256 length) {
        length = rewardToken.length;
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
        if (_checkInvalidTime()) {
            return (Err.INVALID_TIME, tokenArr);
        }
        uint256 length = tokens.length;
        tokenArr = new address[](length);
        uint256 tokenCount;
        for (uint256 i = 0; i < length; i++) {
            address token = tokens[i];
            if (!(voter().isWhitelistedToken(token))) {
                continue;
            }
            if (block.timestamp < nextBribeTimeByToken[token]) {
                continue;
            }
            (uint256 amountToSend, uint256 amountToPull) = _checkTokenBalance(token);
            if (amountToSend + amountToPull > 0 && block.timestamp > nextBribeTimeByToken[token]) {
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
        _checkAndAddToken(_token);
        if (_checkInvalidTime()) {
            revert InvalidDistributionTime();
        }
        if (!(voter().isWhitelistedToken(_token))) {
            revert NotWhitelisted(_token);
        }
        // Check the last time bribe was distributed
        if (block.timestamp < nextBribeTimeByToken[_token]) {
            revert AlreadySentThisEpoch(_token);
        }

        (uint256 amountToSend, uint256 amountToPull) = _checkTokenBalance(_token);
        uint256 cumAmount = amountToSend + amountToPull;
        if (cumAmount == 0) {
            revert ZeroToken(_token);
        }
        tokenBudget[_token] -= amountToPull;

        SafeTransferLib.safeTransferFrom(_token, owner(), address(this), amountToPull);

        nextBribeTimeByToken[_token] = ProtocolTimeLibrary.epochVoteEnd(block.timestamp);

        SafeTransferLib.safeApprove(_token, address(bribeVotingReward()), cumAmount);
        bribeVotingReward().notifyRewardAmount(_token, cumAmount);
    }

    function distribute(address[] memory _token) public {
        for (uint256 i = 0; i < _token.length; i++) {
            distribute(_token[i]);
        }
    }

    function _checkInvalidTime() internal view returns (bool) {
        return (
            ProtocolTimeLibrary.epochVoteStart(block.timestamp) > block.timestamp
                || ProtocolTimeLibrary.epochVoteEnd(block.timestamp) < block.timestamp
        );
    }

    function _checkTokenBalance(address _token)
        internal
        view
        returns (uint256 _amountToSend, uint256 _amountToPullFromOwner)
    {
        uint256 balanceInContract = SafeTransferLib.balanceOf(_token, address(this));
        uint256 cap = amountToBribeByTokenPerEpoch[_token];
        // any whitelisted token that was sent without cap set
        if (cap == 0 && balanceInContract > 0) {
            return (balanceInContract, 0);
        }
        // whitelisted token that has balance in contract and has cap set
        if (balanceInContract >= cap) {
            return (cap, 0);
        }
        uint256 amountNeeded = cap - balanceInContract;
        uint256 budget = tokenBudget[_token];
        uint256 allowance = IERC20(_token).allowance(owner(), address(this));
        uint256 ownerBalance = SafeTransferLib.balanceOf(_token, owner());
        uint256 effectiveBalance = (ownerBalance < allowance) ? ownerBalance : allowance;
        if (effectiveBalance == 0 || budget == 0 || amountNeeded > budget || amountNeeded > effectiveBalance) {
            return (balanceInContract, 0);
        }
        _amountToSend = balanceInContract;
        _amountToPullFromOwner = amountNeeded;
    }

    // SETTOR

    function setTokenAmountPerEpoch(address _token, uint256 _amount) external onlyOwner {
        _checkAndAddToken(_token);
        amountToBribeByTokenPerEpoch[_token] = _amount;
        emit SetNewAmountPerEpoch(_token, _amount);
    }

    function setTokenBudget(address _token, uint256 _amount) external onlyOwner {
        _checkAndAddToken(_token);
        tokenBudget[_token] = _amount;
        emit SetNewTokenBudget(_token, _amount);
    }

    function _checkAndAddToken(address _token) internal {
        if (!isReward[_token]) {
            isReward[_token] = true;
            rewardToken.push(_token);
            emit TokenAdded(_token);
        }
    }

    // ADMIN FUNCTION

    function recoverERC20(address _token) external onlyOwner {
        if (voter().isWhitelistedToken(_token) && voter().isAlive(gauge())) {
            revert GaugeIsStillAlive();
        }
        SafeTransferLib.safeTransferAll(_token, msg.sender);
    }
}
