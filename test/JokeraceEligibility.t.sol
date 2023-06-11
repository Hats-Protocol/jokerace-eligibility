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
import { GovernorCountingSimple } from "jokerace/governance/extensions/GovernorCountingSimple.sol";
import { GenericVotesTimestampToken } from "jokerace/GenericVotesTimestampToken.sol";
import { Contest } from "jokerace/Contest.sol";
import { IVotesTimestamp } from "jokerace/governance/utils/IVotesTimestamp.sol";

contract DeployImplementationTest is DeployImplementation, Test {
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
}

contract TestSetup is DeployImplementationTest {
  error JokeraceEligibility_ContestNotCompleted();
  error JokeraceEligibility_TermNotCompleted();
  error JokeraceEligibility_NoTies();
  error JokeraceEligibility_NotAdmin();

  HatsModuleFactory public factory;
  JokeraceEligibility public instance;
  bytes public otherImmutableArgs;
  bytes public initData;

  uint256 public tophat;
  uint256 public winnersHat;
  address public eligibility = makeAddr("eligibility");
  address public toggle = makeAddr("toggle");
  address public dao = makeAddr("dao");
  address public wearer1 = makeAddr("wearer1");
  address public wearer2 = makeAddr("wearer2");
  address public nonWearer = makeAddr("nonWearer");

  address public minter = makeAddr("minter");
  address public candidate1 = makeAddr("candidate1");
  address public candidate2 = makeAddr("candidate2");
  address public candidate3 = makeAddr("candidate3");

  Contest contest;
  GenericVotesTimestampToken token;
  uint256[] args;
  uint256 contestStart;
  uint256 constant voteDelay = 3600;
  uint256 constant votePeriod = 3600;
  uint256 constant termPeriod = 86_400;

  enum ContestState {
    NotStarted,
    Active,
    Canceled,
    Queued,
    Completed
  }

  function deployInstance(uint256 _winnersHat, uint256 _adminHat, address _contest, uint256 _termEnd, uint256 _topK)
    public
    returns (JokeraceEligibility)
  {
    // encode the other immutable args as packed bytes
    otherImmutableArgs = abi.encodePacked(_adminHat);
    // encoded the initData as unpacked bytes
    initData = abi.encode(_contest, _termEnd, _topK);
    // deploy the instance
    return JokeraceEligibility(
      deployModuleInstance(factory, address(implementation), _winnersHat, otherImmutableArgs, initData)
    );
  }

  function setUp() public virtual override {
    super.setUp();
    contestStart = block.timestamp;
    // deploy the hats module factory
    factory = deployModuleFactory(HATS, SALT, FACTORY_VERSION);

    // set up a contest
    token = new GenericVotesTimestampToken("test", "test", minter, 3 ether, true);
    vm.startPrank(minter);
    token.transfer(candidate1, 1 ether);
    token.transfer(candidate2, 1 ether);
    token.transfer(candidate3, 1 ether);
    // each candidate delegates to itself
    vm.startPrank(candidate1);
    token.delegate(candidate1);
    vm.stopPrank();

    vm.startPrank(candidate2);
    token.delegate(candidate2);
    vm.stopPrank();

    vm.startPrank(candidate3);
    token.delegate(candidate3);
    vm.stopPrank();

    args.push(contestStart);
    args.push(voteDelay);
    args.push(votePeriod);
    args.push(contestStart);
    args.push(0);
    args.push(50);
    args.push(50);
    args.push(1);
    args.push(1);
    contest = new Contest("test contest", "contest", token, token, args);

    //address predictedInstanceAddress = factory.getHatsModuleAddress(address(implementation), )

    // set up hats
    tophat = HATS.mintTopHat(dao, "tophat", "dao.eth/tophat");
    vm.startPrank(dao);
    winnersHat = HATS.createHat(tophat, "winnersHat", 50, eligibility, toggle, true, "dao.eth/winnersHat");
    HATS.mintHat(winnersHat, wearer1);
    HATS.mintHat(winnersHat, wearer2);
    vm.stopPrank();

    // deploy the eligibility instance
    instance =
      deployInstance(winnersHat, tophat, address(contest), contestStart + voteDelay + votePeriod + termPeriod, 2);

    // update winners hat eligibilty to instance
    vm.startPrank(dao);
    HATS.changeHatEligibility(winnersHat, address(instance));
    vm.stopPrank();
  }
}

contract TestDeployment is TestSetup {
  function test_deployImplementation() public {
    assertEq(implementation.version_(), JOKERACE_ELIGIBILITY_VERSION, "implementation version");
  }

  function test_instanceAdminHat() public {
    assertEq(instance.ADMIN_HAT(), tophat);
  }

  function test_instanceContest() public {
    assertEq(address(instance.underlyingContest()), address(contest));
  }

  function test_instanceTermEnd() public {
    assertEq(instance.termEnd(), contest.contestDeadline() + 86_400);
  }

  function test_instanceTopK() public {
    assertEq(instance.topK(), 2);
  }

  function test_hatEligibility() public {
    assertEq(HATS.getHatEligibilityModule(winnersHat), address(instance), "eligibility module of winners hat");
  }

  function test_candidatesTokenBalance() public {
    assertEq(token.balanceOf(candidate1), 1 ether, "candidate 1 token balance");
    assertEq(token.balanceOf(candidate2), 1 ether, "candidate 2 token balance");
    assertEq(token.balanceOf(candidate3), 1 ether, "candidate 3 token balance");
  }
}

contract Proposing1Scenario is TestSetup {
  uint256[] proposalIds;

  function setUp() public virtual override {
    super.setUp();
    // set time to  proposing period
    vm.warp(contestStart + voteDelay - 1);

    // each candidate proposes and delegates to itself
    vm.startPrank(candidate1);
    contest.propose("candidate 1 proposal");
    vm.stopPrank();

    vm.startPrank(candidate2);
    contest.propose("candidate 2 proposal");
    vm.stopPrank();

    vm.startPrank(candidate3);
    contest.propose("candidate 3 proposal");
    vm.stopPrank();

    proposalIds = contest.getAllProposalIds();
  }
}

contract TestProposing1Scenario is Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();
  }

  function test_contestState() public {
    assertEq(uint256(contest.state()), uint256(ContestState.Queued), "contest proposing state");
  }

  function test_proposals() public {
    assertEq(proposalIds.length, 3, "number of proposals");
  }

  function test_pullContestResults_reverts() public {
    vm.expectRevert(JokeraceEligibility_ContestNotCompleted.selector);
    instance.pullElectionResults();
  }

  function test_setReelection_reverts() public {
    vm.expectRevert(JokeraceEligibility_TermNotCompleted.selector);
    instance.reelection(contest, contestStart + voteDelay + votePeriod + termPeriod, 2);
  }
}

contract Voting1Proposing1Scenario is Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();

    // set time to voting period
    vm.warp(contestStart + voteDelay + 1);

    // candidates vote
    vm.startPrank(candidate1);
    contest.castVote(proposalIds[0], 0, 1 ether);
    vm.stopPrank();
    vm.startPrank(candidate2);
    contest.castVote(proposalIds[1], 0, 0.5 ether);
    vm.stopPrank();
    vm.startPrank(candidate3);
    contest.castVote(proposalIds[2], 0, 0.1 ether);
    vm.stopPrank();
  }
}

contract TestVoting1Proposing1Scenario is Voting1Proposing1Scenario {
  function test_candidateVotes() public {
    (uint256 forVotes1, uint256 againstVotes1) = contest.proposalVotes(proposalIds[0]);
    assertEq(int256(forVotes1) - int256(againstVotes1), 1 ether, "candidate 1 votes");

    (uint256 forVotes2, uint256 againstVotes2) = contest.proposalVotes(proposalIds[1]);
    assertEq(int256(forVotes2) - int256(againstVotes2), 0.5 ether, "candidate 2 votes");

    (uint256 forVotes3, uint256 againstVotes3) = contest.proposalVotes(proposalIds[2]);
    assertEq(int256(forVotes3) - int256(againstVotes3), 0.1 ether, "candidate 3 votes");
  }

  function test_pullContestResults_reverts() public {
    vm.expectRevert(JokeraceEligibility_ContestNotCompleted.selector);
    instance.pullElectionResults();
  }

  function test_setReelection_reverts() public {
    vm.expectRevert(JokeraceEligibility_TermNotCompleted.selector);
    instance.reelection(contest, contestStart + voteDelay + votePeriod + termPeriod, 2);
  }
}

contract ContestCompletedVoting1Proposing1Scenario is Voting1Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();
    // set time to contest completion
    vm.warp(contestStart + voteDelay + votePeriod + 1);
    instance.pullElectionResults();
  }
}

contract TestContestCompletedVoting1Proposing1Scenario is ContestCompletedVoting1Proposing1Scenario {
  function test_eligibilityInstance() public {
    (bool eligible1,) = instance.getWearerStatus(candidate1, winnersHat);
    assertEq(eligible1, true, "candidate 1 eligibility");
    (bool eligible2,) = instance.getWearerStatus(candidate2, winnersHat);
    assertEq(eligible2, true, "candidate 2 eligibility");
    (bool eligible3,) = instance.getWearerStatus(candidate3, winnersHat);
    assertEq(eligible3, false, "candidate 3 eligibility");
  }

  function test_eligibilityHats() public {
    assertEq(HATS.isEligible(candidate1, winnersHat), true, "candidate 1 eligibility");
    assertEq(HATS.isEligible(candidate2, winnersHat), true, "candidate 2 eligibility");
    assertEq(HATS.isEligible(candidate3, winnersHat), false, "candidate 3 eligibility");
  }

  function test_setReelection_reverts() public {
    vm.expectRevert(JokeraceEligibility_TermNotCompleted.selector);
    instance.reelection(contest, contestStart + voteDelay + votePeriod + termPeriod, 2);
  }
}

contract TermEndedVoting1Proposing1Scenario is ContestCompletedVoting1Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();
    // set time to contest completion
    vm.warp(contestStart + voteDelay + votePeriod + termPeriod + 1);
  }
}

contract TestTermEndedVoting1Proposing1Scenario is TermEndedVoting1Proposing1Scenario {
  function test_setReelectionNotAdmin_reverts() public {
    vm.startPrank(candidate1);
    vm.expectRevert(JokeraceEligibility_NotAdmin.selector);
    instance.reelection(contest, contestStart + voteDelay + votePeriod + termPeriod, 2);
    vm.stopPrank();
  }

  function test_eligibilityInstance() public {
    (bool eligible1,) = instance.getWearerStatus(candidate1, winnersHat);
    assertEq(eligible1, false, "candidate 1 eligibility");
    (bool eligible2,) = instance.getWearerStatus(candidate2, winnersHat);
    assertEq(eligible2, false, "candidate 2 eligibility");
    (bool eligible3,) = instance.getWearerStatus(candidate3, winnersHat);
    assertEq(eligible3, false, "candidate 3 eligibility");
  }

  function test_eligibilityHats() public {
    assertEq(HATS.isEligible(candidate1, winnersHat), false, "candidate 1 eligibility");
    assertEq(HATS.isEligible(candidate2, winnersHat), false, "candidate 2 eligibility");
    assertEq(HATS.isEligible(candidate3, winnersHat), false, "candidate 3 eligibility");
  }
}

contract TestReelectionVoting1Proposing1Scenario is TermEndedVoting1Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();

    // deploy a new contest
    contestStart = block.timestamp;
    args.push(contestStart);
    args.push(voteDelay);
    args.push(votePeriod);
    args.push(contestStart);
    args.push(0);
    args.push(50);
    args.push(50);
    args.push(1);
    args.push(1);
    contest = new Contest("test contest reelection", "contest reelection", token, token, args);
  }

  function test_reelection() public {
    vm.startPrank(dao);
    instance.reelection(contest, contestStart + voteDelay + votePeriod + termPeriod, 2);
    vm.stopPrank();
  }
}
