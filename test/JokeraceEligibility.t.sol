// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import { Test, console2 } from "forge-std/Test.sol";
import { JokeraceEligibility } from "../src/JokeraceEligibility.sol";
import { DeployImplementation } from "../script/JokeraceEligibility.s.sol";
import {
  IHats,
  HatsModuleFactory,
  deployModuleFactory,
  deployModuleInstance
} from "lib/hats-module/src/utils/DeployFunctions.sol";

contract JokeraceEligibilityTest is DeployImplementation, Test {
  // variables inherited from DeployImplementation script
  // JokeraceEligibility public implementation;
  // bytes32 public SALT;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 16_947_805; // the block number where v1.hatsprotocol.eth was deployed;

  IHats public constant HATS = IHats(0x9D2dfd6066d5935267291718E8AA16C8Ab729E9d); // v1.hatsprotocol.eth
  string public FACTORY_VERSION = "factory test version";
  string public JOKERACE_ELIGIBILITY_VERSION = "test version";

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("mainnet"), BLOCK_NUMBER);

    // deploy via the script
    DeployImplementation.prepare(JOKERACE_ELIGIBILITY_VERSION, false); // set last arg to true to log deployment
    DeployImplementation.run();
  }

  function test_deploy_implementation() public {
    assertEq(implementation.version_(), JOKERACE_ELIGIBILITY_VERSION, "implementation version");
  }
}
