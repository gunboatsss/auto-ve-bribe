// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {AutoVeBribeFactory} from "src/AutoVeBribeFactory.sol";
import {ProtocolTimeLibrary} from "src/libraries/ProtocolTimeLibrary.sol";
import {AutoVeBribe} from "src/AutoVeBribe.sol";

contract AutoVeBribeFactoryTest is Test {
    AutoVeBribeFactory factory;
    address owner = address(666666666666666);
    address gauge = 0x4F09bAb2f0E15e2A078A227FE1537665F55b8360; // AERO/USDC gauge

    function setUp() public {
        _setup();
    }

    function _setup() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));
        factory = new AutoVeBribeFactory(0x16613524e02ad97eDfeF371bC883F2F5d6C480A5);
        vm.warp(ProtocolTimeLibrary.epochVoteStart(block.timestamp) + 1);
    }

    function test_sanity() view public {
        assert(factory.implementation() != address(0));
        assertEq(factory.getLength(), 0);
    }

    function test_createNewBribe() public {
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
}
