// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.27;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {Test, console} from "forge-std/Test.sol";
import {AutoVeBribeFactory} from "src/AutoVeBribeFactory.sol";
import {ProtocolTimeLibrary} from "src/libraries/ProtocolTimeLibrary.sol";
import {AutoVeBribe} from "src/AutoVeBribe.sol";

contract AutoVeBribeFactoryTest is Test {
    AutoVeBribeFactory factory;
    address owner = address(666666666666666);
    address token = 0x940181a94A35A4569E4529A3CDfB74e38FD98631; // AERO
    address gauge = 0x4F09bAb2f0E15e2A078A227FE1537665F55b8360; // AERO/USDC gauge

    function setUp() public {
        _setup();
    }

    function _setup() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));
        factory = new AutoVeBribeFactory(0x16613524e02ad97eDfeF371bC883F2F5d6C480A5);
        vm.warp(ProtocolTimeLibrary.epochVoteStart(block.timestamp) + 1);
    }

    function test_sanity() public view {
        assert(factory.implementation() != address(0));
        assertEq(factory.getLength(), 0);
    }

    function test_createNewBribe() public {
        vm.expectEmit(true, true, true, false);
        emit AutoVeBribeFactory.NewAutoBribeCreated(
            vm.computeCreateAddress(address(factory), vm.getNonce(address(factory))), gauge
        );
        address newBribe = factory.deployAutoVeBribe(gauge, owner);
        assertEq(factory.getLength(), 1);
        assertEq(factory.getBribe(0), newBribe);
        // console.log("in test", address(AutoVeBribe(newBribe).bribeVotingReward()));
        address anotherBribe = factory.deployAutoVeBribe(gauge, owner);
        assertEq(factory.getLength(), 2);
        assertEq(factory.getBribe(1), anotherBribe);
    }

    function test_invalidGauge() public {
        vm.expectRevert();
        factory.deployAutoVeBribe(address(69), owner);
    }

    function test_recoverERC20() public {
        deal(token, address(factory), 1e18);
        factory.recoverERC20(token);
        assertEq(SafeTransferLib.balanceOf(token, address(factory)), 0);
    }
}
