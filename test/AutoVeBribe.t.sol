// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.27;
import {AutoVeBribeFactory} from "src/AutoVeBribeFactory.sol";
import {AutoVeBribe} from "src/AutoVeBribe.sol";

import {IVoter} from "src/interfaces/IVoter.sol";

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

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

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));
        factory = new AutoVeBribeFactory(0x16613524e02ad97eDfeF371bC883F2F5d6C480A5);
        console.log("current", block.timestamp);
        console.log("start time", ProtocolTimeLibrary.epochVoteStart(block.timestamp));
        console.log("end time", ProtocolTimeLibrary.epochVoteEnd(block.timestamp));
        vm.warp(ProtocolTimeLibrary.epochVoteStart(block.timestamp) + 1);
        autoBribe = AutoVeBribe(factory.deployAutoVeBribe(gauge, owner));
        console.log("voter address", address(autoBribe.voter()));
        console.log("bribe address", IVoter(0x16613524e02ad97eDfeF371bC883F2F5d6C480A5).gaugeToBribe(gauge));
        console.log("owner address", autoBribe.owner());
        console.log("gauge address", autoBribe.gauge());
        console.log("bribe in contract", address(autoBribe.bribeVotingReward()));
    }

    function test_bribe() public {
        deal(token, address(autoBribe), 1e18);
        autoBribe.distribute(token);
        assertEq(SafeTransferLib.balanceOf(token, address(autoBribe)), 0);
    }
    function test_setAmount() public {
        vm.expectRevert();
        autoBribe.setTokenAmountPerEpoch(token, 0.5e18);
        vm.prank(owner);
        autoBribe.setTokenAmountPerEpoch(token, 0.5e18);
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
        vm.expectRevert(AutoVeBribe.GaugeAlreadySet.selector);
        autoBribe.initialize(gauge, owner);
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
}