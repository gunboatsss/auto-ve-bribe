// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.27;

import {AutoVeBribeFactory} from "src/AutoVeBribeFactory.sol";
import {AutoVeBribe} from "src/AutoVeBribe.sol";

import {IVoter} from "src/interfaces/IVoter.sol";

import {LibClone} from "solady/utils/LibClone.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {OpsProxyMock} from "./OpsProxyMock.sol";
import {IOpsProxy} from "src/interfaces/IOpsProxy.sol";

import {Test, console} from "forge-std/Test.sol";
import {AutoVeBribeFactory} from "src/AutoVeBribeFactory.sol";
import {ProtocolTimeLibrary} from "src/libraries/ProtocolTimeLibrary.sol";

contract AutoVeBribeTest is Test {
    AutoVeBribe autoBribe;
    AutoVeBribeFactory factory;
    address token = 0x940181a94A35A4569E4529A3CDfB74e38FD98631; // AERO
    address token2 = 0x4200000000000000000000000000000000000006; // WETH
    address owner = address(666666666666666);
    address gauge = 0x4F09bAb2f0E15e2A078A227FE1537665F55b8360; // AERO/USDC gauge
    IVoter voter = IVoter(0x16613524e02ad97eDfeF371bC883F2F5d6C480A5);

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));
        factory = new AutoVeBribeFactory(address(voter));
        console.log("current", block.timestamp);
        console.log("start time", ProtocolTimeLibrary.epochVoteStart(block.timestamp));
        console.log("end time", ProtocolTimeLibrary.epochVoteEnd(block.timestamp));
        vm.warp(ProtocolTimeLibrary.epochVoteStart(block.timestamp) + 1);
        autoBribe = AutoVeBribe(factory.deployAutoVeBribe(gauge, owner));
        deal(token, address(autoBribe.bribeVotingReward()), 0, true);
    }

    function test_view() public view {
        console.log(address(voter));
        console.log(gauge);
        console.logBytes(LibClone.argsOnClone(address(autoBribe)));
        console.log("voter address", address(autoBribe.voter()));
        console.log("bribe address", voter.gaugeToBribe(gauge));
        console.log("owner address", autoBribe.owner());
        console.log("gauge address", autoBribe.gauge());
        console.log("bribe in contract", address(autoBribe.bribeVotingReward()));
        assertEq(address(autoBribe.voter()), address(voter), "voter not match");
        assertEq(address(autoBribe.gauge()), gauge, "gauge not match");
        assertEq(address(autoBribe.bribeVotingReward()), voter.gaugeToBribe(gauge), "reward not match");
    }

    function test_bribe() public {
        deal(token, address(autoBribe), 1e18);
        autoBribe.distribute(token);
        assertEq(SafeTransferLib.balanceOf(token, address(autoBribe)), 0);
    }

    function test_multipleEpoch() public {
        deal(token, address(autoBribe), 0.9e18);
        vm.prank(owner);
        autoBribe.setTokenAmountPerEpoch(token, 0.5e18);
        autoBribe.distribute(token);
        skip(1 weeks + 1);
        autoBribe.distribute(token);
        assertEq(SafeTransferLib.balanceOf(token, address(autoBribe)), 0);
        deal(token, address(autoBribe), 0.9e18);
        skip(1 weeks + 1);
        autoBribe.distribute(token);
        assertEq(SafeTransferLib.balanceOf(token, address(autoBribe)), 0.4e18);
    }

    function test_setBudget() public {
        deal(token, address(autoBribe), 1e18);
        deal(token, owner, 1e18);
        vm.startPrank(owner);
        SafeTransferLib.safeApprove(token, address(autoBribe), 2e18);
        autoBribe.setTokenBudget(token, 2e18);
        autoBribe.setTokenAmountPerEpoch(token, 1e18);
        autoBribe.distribute(token);
        assertEq(SafeTransferLib.balanceOf(token, address(autoBribe)), 0);
        assertEq(SafeTransferLib.balanceOf(token, owner), 1e18);
        assertEq(autoBribe.tokenBudget(token), 2e18);
        skip(1 weeks + 1);
        autoBribe.distribute(token);
        assertEq(SafeTransferLib.balanceOf(token, owner), 0);
        assertEq(autoBribe.tokenBudget(token), 1e18);
        skip(1 weeks);
        deal(token, owner, 0.9e18);
        vm.expectRevert();
        autoBribe.distribute(token);
    }

    function test_setAmount() public {
        vm.expectRevert();
        autoBribe.setTokenAmountPerEpoch(token, 0.5e18);
        vm.prank(owner);
        autoBribe.setTokenAmountPerEpoch(token, 0.5e18);
        assertTrue(autoBribe.isReward(token), "token not in the list");
        assertEq(autoBribe.rewardToken(0), token, "token not in the array");
        deal(token, address(autoBribe), 1e18);
        autoBribe.distribute(token);
        assertEq(SafeTransferLib.balanceOf(token, address(autoBribe)), 0.5e18);
    }

    function test_cannotSendMultipleTimeInSingleEpoch() public {
        vm.prank(owner);
        autoBribe.setTokenAmountPerEpoch(token, 0.5e18);
        deal(token, address(autoBribe), 1e18);
        autoBribe.distribute(token);
        vm.expectRevert(abi.encodeWithSelector(AutoVeBribe.AlreadySentThisEpoch.selector, (token)));
        autoBribe.distribute(token);
    }

    function test_cannotReinit() public {
        vm.expectRevert();
        autoBribe.initialize(owner);
    }

    function test_cannotDistributeBeforeEpochStart() public {
        vm.warp(ProtocolTimeLibrary.epochVoteStart(block.timestamp) - 1);
        vm.expectRevert(AutoVeBribe.InvalidDistributionTime.selector);
        autoBribe.distribute(token);
    }

    function test_cannotDistributeAfterEpochEnd() public {
        vm.warp(ProtocolTimeLibrary.epochVoteEnd(block.timestamp) + 1);
        vm.expectRevert(AutoVeBribe.InvalidDistributionTime.selector);
        autoBribe.distribute(token);
    }

    function test_cannotDistributeZeroToken() public {
        vm.expectRevert(abi.encodeWithSelector(AutoVeBribe.ZeroToken.selector, (token)));
        autoBribe.distribute(token);
    }

    function test_distributeMultipleToken() public {
        deal(token, address(autoBribe), 100e18);
        deal(token2, address(autoBribe), 1e18);
        vm.prank(owner);
        autoBribe.setTokenAmountPerEpoch(token, 50e18);
        address[] memory tokens = new address[](2);
        tokens[0] = token;
        tokens[1] = token2;
        autoBribe.distribute(tokens);
        assertEq(SafeTransferLib.balanceOf(token, address(autoBribe)), 50e18);
        assertEq(SafeTransferLib.balanceOf(token2, address(autoBribe)), 0);
    }

    function test_cannotRugIfGaugeIsAlive() public {
        deal(token, address(autoBribe), 1e18);
        vm.prank(owner);
        vm.expectRevert(AutoVeBribe.GaugeIsStillAlive.selector);
        autoBribe.recoverERC20(token);
    }

    function test_recoverERC20IfGaugeIsKilled() public {
        deal(token, address(autoBribe), 1e18);
        vm.prank(voter.emergencyCouncil());
        voter.killGauge(gauge);
        vm.expectRevert();
        autoBribe.recoverERC20(token);
        vm.prank(owner);
        autoBribe.recoverERC20(token);
        assertEq(SafeTransferLib.balanceOf(token, address(autoBribe)), 0);
    }

    function test_recoverERC20IfTokenIsNotWhitelist() public {
        deal(token, address(autoBribe), 1e18);
        vm.prank(voter.governor());
        voter.whitelistToken(token, false);
        vm.expectRevert();
        autoBribe.recoverERC20(token);
        vm.prank(owner);
        autoBribe.recoverERC20(token);
        assertEq(SafeTransferLib.balanceOf(token, address(autoBribe)), 0);
    }

    function test_chainlinkAutomation() public {
        deal(token, address(autoBribe), 1e18);
        address[] memory tokenArr = new address[](2);
        address[] memory expectedArr = new address[](1);
        tokenArr[0] = token2;
        tokenArr[1] = token;
        expectedArr[0] = token;
        (bool performUpkeep, bytes memory data) = autoBribe.checkUpkeep(abi.encode(tokenArr));
        console.log(SafeTransferLib.balanceOf(token, address(autoBribe)));
        console.log(autoBribe.nextBribeTimeByToken(token));
        console.log(string(data));
        assertTrue(performUpkeep, "keeper checker failed");
        address[] memory result = abi.decode(data, (address[]));
        assertEq(expectedArr, result);
        autoBribe.performUpkeep(data);
        assertEq(SafeTransferLib.balanceOf(token, address(autoBribe)), 0);
    }

    function test_chainlinkAutomationNotHappy() public {
        address[] memory tokenArr = new address[](2);
        tokenArr[0] = token2;
        tokenArr[1] = token;
        bool performUpkeep;
        (performUpkeep,) = autoBribe.checkUpkeep(abi.encode(tokenArr));
        assertFalse(performUpkeep, "token balance is 0 but keeper is allowing it");
        deal(token, address(autoBribe), 1e18);
        vm.warp(ProtocolTimeLibrary.epochVoteEnd(block.timestamp) + 1);
        (performUpkeep,) = autoBribe.checkUpkeep(abi.encode(tokenArr));
        assertFalse(performUpkeep, "too late to bribe");
        vm.warp(ProtocolTimeLibrary.epochVoteStart(block.timestamp) - 1);
        (performUpkeep,) = autoBribe.checkUpkeep(abi.encode(tokenArr));
        assertFalse(performUpkeep, "too early to bribe");
    }

    function test_chainlinkWithBudget() public {
        address[] memory tokenArr = new address[](2);
        tokenArr[0] = token2;
        tokenArr[1] = token;
        vm.startPrank(owner);
        deal(token, owner, 1e18);
        SafeTransferLib.safeApprove(token, address(autoBribe), 1e18);
        autoBribe.setTokenAmountPerEpoch(token, 0.5e18);
        autoBribe.setTokenBudget(token, 1e18);
        bool performUpkeep;
        bytes memory data;
        (performUpkeep, data) = autoBribe.checkUpkeep(abi.encode(tokenArr));
        assertTrue(performUpkeep, "checker failed");
        autoBribe.performUpkeep(data);
        assertEq(SafeTransferLib.balanceOf(token, owner), 0.5e18);
        assertEq(SafeTransferLib.balanceOf(token, address(autoBribe)), 0);
        assertEq(SafeTransferLib.balanceOf(token, address(autoBribe.bribeVotingReward())), 0.5e18);
        skip(1 weeks);
        (performUpkeep, data) = autoBribe.checkUpkeep(abi.encode(tokenArr));
        assertTrue(performUpkeep, "checker failed");
        autoBribe.performUpkeep(data);
    }

    function test_GelatoAutomate() public {
        deal(token, address(autoBribe), 1e18);
        address[] memory tokenArr = new address[](2);
        address[] memory expectedArr = new address[](1);
        tokenArr[0] = token2;
        tokenArr[1] = token;
        expectedArr[0] = token;
        (bool performUpkeep, bytes memory data) = autoBribe.checkUpkeepGelato(tokenArr);
        OpsProxyMock ops = new OpsProxyMock();
        assertTrue(performUpkeep, "keeper checker failed");
        (bool succ,) = address(ops).call{value: 0}(data);
        assertTrue(succ, "Gelato Automate execution failed");
    }
}
