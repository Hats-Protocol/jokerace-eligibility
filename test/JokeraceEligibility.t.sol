// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

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
import { Contest } from "jokerace/Contest.sol";
import { Governor } from "jokerace/governance/Governor.sol";

contract DeployImplementationTest is DeployImplementation, Test {
  // variables inherited from DeployImplementation script
  // JokeraceEligibility public implementation;
  // bytes32 public SALT;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 6_488_268; // the block number where hats module factory was deployed on Sepolia;

  IHats public constant HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137); // v1.hatsprotocol.eth
  string public FACTORY_VERSION = "factory test version";
  string public JOKERACE_ELIGIBILITY_VERSION = "test version";

  function setUp() public virtual {
    // create and activate a fork, at BLOCK_NUMBER
    fork = vm.createSelectFork(vm.rpcUrl("sepolia"), BLOCK_NUMBER);
    // deploy via the script
    DeployImplementation.prepare(JOKERACE_ELIGIBILITY_VERSION, false); // set last arg to true to log deployment
    DeployImplementation.run();
  }
}

contract TestSetup is DeployImplementationTest {
  error JokeraceEligibility_ContestNotCompleted();
  error JokeraceEligibility_ContestTie();
  error JokeraceEligibility_TermNotCompleted();
  error JokeraceEligibility_NotAdmin();
  error JokeraceEligibility_MustHaveDownvotingDisabled();
  error JokeraceEligibility_MustHaveSortingEnabled();

  event NextTermSet(address NewContest, uint256 newTopK, uint256 newTermEnd, uint256 newTransitionPeriod);
  event TermStarted(address contest, uint256 topK, uint256 termEnd, uint256 transitionPeriod);

  HatsModuleFactory constant FACTORY = HatsModuleFactory(0xfE661c01891172046feE16D3a57c3Cf456729efA);
  JokeraceEligibility public instanceDefaultAdmin;
  JokeraceEligibility public instanceHatAdmin;
  JokeraceEligibility public instanceWithDownVoting;
  JokeraceEligibility public instancewithSortingDisabled;
  bytes public otherImmutableArgs;
  bytes public initData;
  uint256 public tophat;
  uint256 public winnersHat;
  uint256 public optionalAdminHat;
  address public eligibility = makeAddr("eligibility");
  address public toggle = makeAddr("toggle");
  address public dao = makeAddr("dao");
  address public minter = makeAddr("minter");
  address public optionalAdmin = makeAddr("optionalAdmin");
  address public candidate1 = makeAddr("candidate1");
  address public candidate2 = makeAddr("candidate2");
  address public candidate3 = makeAddr("candidate3");
  bytes32 leaf1;
  bytes32 leaf2;
  bytes32 leaf3;
  bytes32[] proof1;
  bytes32[] proof2;
  bytes32[] proof3;
  bytes32 votingMerkleRoot;
  address[] signers1 = [candidate1];
  address[] signers2 = [candidate2];
  address[] signers3 = [candidate3];
  Contest contest;
  Contest contestWithDownVoting;
  Contest contestWithSortingDisabled;
  Contest contestCanceled;
  //GenericVotesTimestampToken token;
  uint256[] args;
  uint256 contestStart;
  uint256 constant voteDelay = 3600;
  uint256 constant votePeriod = 3600;
  uint256 constant termPeriod = 86_400;
  uint256 constant transitionPeriod = 604_800;
  uint256 constant transitionPeriod2 = 1_209_600;
  uint256 termEnd1;

  enum ContestState {
    NotStarted,
    Active,
    Canceled,
    Queued,
    Completed
  }

  struct TermDetails {
    address contest;
    uint96 topK;
    uint256 termEnd;
    uint256 transitionPeriod;
  }

  function deployInstance(
    uint256 _winnersHat,
    uint256 _adminHat,
    address _contest,
    uint256 _termEnd,
    uint256 _topK,
    uint256 _transitionPeriod
  ) public returns (JokeraceEligibility) {
    // encode the other immutable args as packed bytes
    otherImmutableArgs = abi.encodePacked(_adminHat);
    // encoded the initData as unpacked bytes
    initData = abi.encode(_contest, _termEnd, _transitionPeriod, _topK);
    // deploy the instance
    return JokeraceEligibility(
      deployModuleInstance(FACTORY, address(implementation), _winnersHat, otherImmutableArgs, initData)
    );
  }

  function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
    /// @solidity memory-safe-assembly
    assembly {
      mstore(0x00, a)
      mstore(0x20, b)
      value := keccak256(0x00, 0x40)
    }
  }

  function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
    return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
  }

  function setUp() public virtual override {
    super.setUp();
    contestStart = block.timestamp;
    termEnd1 = contestStart + voteDelay + votePeriod + termPeriod;
    // set up a contest with sorting enabled and without down voting
    leaf1 = keccak256(abi.encodePacked(candidate1, uint256(100)));
    leaf2 = keccak256(abi.encodePacked(candidate2, uint256(100)));
    leaf3 = keccak256(abi.encodePacked(candidate3, uint256(100)));
    proof1 = [leaf2, leaf3];
    proof2 = [leaf1, leaf3];
    proof3 = [_hashPair(leaf1, leaf2)];
    votingMerkleRoot = _hashPair(_hashPair(leaf1, leaf2), leaf3);
    args.push(contestStart);
    args.push(voteDelay);
    args.push(votePeriod);
    args.push(50);
    args.push(50);
    args.push(0);
    args.push(0);
    args.push(0);
    args.push(1);
    args.push(250);
    contest = new Contest("test contest", "contest", bytes32(0), votingMerkleRoot, args);

    // set up a contest and cancel it
    contestCanceled = new Contest("test contest", "contest", bytes32(0), votingMerkleRoot, args);
    contestCanceled.cancel();

    // set up a contest with sorting enabled and with down voting
    args[5] = 1;
    contestWithDownVoting = new Contest("test contest", "contest", bytes32(0), votingMerkleRoot, args);

    // set up a contest with sorting disabled and without down voting
    args[5] = 0;
    args[8] = 0;
    contestWithSortingDisabled = new Contest("test contest", "contest", bytes32(0), votingMerkleRoot, args);

    // set up hats
    tophat = HATS.mintTopHat(dao, "tophat", "dao.eth/tophat");
    vm.startPrank(dao);
    winnersHat = HATS.createHat(tophat, "winnersHat", 50, eligibility, toggle, true, "dao.eth/winnersHat");
    optionalAdminHat =
      HATS.createHat(tophat, "optionalAdminHat", 50, eligibility, toggle, true, "dao.eth/optionalAdminHat");
    HATS.mintHat(optionalAdminHat, optionalAdmin);
    vm.stopPrank();
    // deploy the eligibility instance with a default admin
    instanceDefaultAdmin = deployInstance(winnersHat, uint256(0), address(contest), termEnd1, 2, transitionPeriod);
    // deploy the eligibility instance with a specific hat admin. This instance is used only to check correct admin
    // rights
    instanceHatAdmin = deployInstance(winnersHat, optionalAdminHat, address(contest), termEnd1, 2, transitionPeriod);

    // update winners hat eligibilty to instance
    vm.prank(dao);
    HATS.changeHatEligibility(winnersHat, address(instanceDefaultAdmin));
  }
}

contract TestDeployment is TestSetup {
  function test_deployImplementation() public {
    assertEq(implementation.version_(), JOKERACE_ELIGIBILITY_VERSION, "implementation version");
  }

  function test_instanceDefaultAdmin() public {
    assertEq(instanceDefaultAdmin.ADMIN_HAT(), uint256(0));
  }

  function test_instanceAdminHat() public {
    assertEq(instanceHatAdmin.ADMIN_HAT(), optionalAdminHat);
  }

  function test_instanceNextTerm() public {
    uint256 currentTermIndex = instanceDefaultAdmin.currentTermIndex();
    TermDetails memory nextTerm;
    (nextTerm.contest, nextTerm.topK, nextTerm.termEnd, nextTerm.transitionPeriod) =
      instanceDefaultAdmin.terms(currentTermIndex + 1);
    assertEq(address(nextTerm.contest), address(contest));
    assertEq(nextTerm.termEnd, termEnd1);
    assertEq(nextTerm.topK, 2);
    assertEq(nextTerm.transitionPeriod, transitionPeriod);
  }

  function test_instanceCurrentTerm() public {
    uint256 currentTermIndex = instanceDefaultAdmin.currentTermIndex();
    TermDetails memory currentTerm;
    (currentTerm.contest, currentTerm.topK, currentTerm.termEnd, currentTerm.transitionPeriod) =
      instanceDefaultAdmin.terms(currentTermIndex);
    assertEq(currentTerm.contest, address(0));
    assertEq(currentTerm.termEnd, 0);
    assertEq(currentTerm.topK, 0);
    assertEq(currentTerm.transitionPeriod, 0);
  }

  function test_hatEligibility() public {
    assertEq(
      HATS.getHatEligibilityModule(winnersHat), address(instanceDefaultAdmin), "eligibility module of winners hat"
    );
  }

  function test_canStartNextTerm() public {
    bool canStart = instanceDefaultAdmin.canStartNextTerm();
    assertEq(canStart, false);
  }
}

// Three candidates propose
contract Proposing1Scenario is TestSetup {
  uint256[] proposalIds;

  function setUp() public virtual override {
    super.setUp();
    // set time to  proposing period
    vm.warp(contestStart + voteDelay - 1);
    // each candidate proposes and delegates to itself
    vm.prank(candidate1);
    Governor.ProposalCore memory proposal1 = Governor.ProposalCore({
      author: candidate1,
      description: "candidate 1 proposal",
      exists: true,
      targetMetadata: Governor.TargetMetadata({ targetAddress: candidate1 }),
      safeMetadata: Governor.SafeMetadata({ signers: signers1, threshold: 1 })
    });
    contest.proposeWithoutProof(proposal1);
    vm.prank(candidate2);
    Governor.ProposalCore memory proposal2 = Governor.ProposalCore({
      author: candidate2,
      description: "candidate 2 proposal",
      exists: true,
      targetMetadata: Governor.TargetMetadata({ targetAddress: candidate2 }),
      safeMetadata: Governor.SafeMetadata({ signers: signers2, threshold: 1 })
    });
    contest.proposeWithoutProof(proposal2);
    vm.prank(candidate3);
    Governor.ProposalCore memory proposal3 = Governor.ProposalCore({
      author: candidate3,
      description: "candidate 3 proposal",
      exists: true,
      targetMetadata: Governor.TargetMetadata({ targetAddress: candidate3 }),
      safeMetadata: Governor.SafeMetadata({ signers: signers3, threshold: 1 })
    });
    contest.proposeWithoutProof(proposal3);
    proposalIds = contest.getAllProposalIds();
  }
}

// Only one candidate proposes
contract Proposing2Scenario is TestSetup {
  uint256[] proposalIds;

  function setUp() public virtual override {
    super.setUp();
    // set time to  proposing period
    vm.warp(contestStart + voteDelay - 1);
    // only one proposal
    vm.prank(candidate1);
    Governor.ProposalCore memory proposal1 = Governor.ProposalCore({
      author: candidate1,
      description: "candidate 1 proposal",
      exists: true,
      targetMetadata: Governor.TargetMetadata({ targetAddress: candidate1 }),
      safeMetadata: Governor.SafeMetadata({ signers: signers1, threshold: 1 })
    });
    contest.proposeWithoutProof(proposal1);
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

  function test_startNextTerm_reverts() public {
    vm.expectRevert(JokeraceEligibility_ContestNotCompleted.selector);
    instanceDefaultAdmin.startNextTerm();
  }
}

// Candidates scoring: candidate 1 > candidate 2 > candidate 3
contract Voting1Proposing1Scenario is Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();
    // set time to voting period
    vm.warp(contestStart + voteDelay + 1);
    // candidates vote
    vm.prank(candidate1);
    contest.castVote(proposalIds[0], 0, 100, 100, proof1);
    vm.prank(candidate2);
    contest.castVote(proposalIds[1], 0, 100, 50, proof2);
    vm.prank(candidate3);
    contest.castVote(proposalIds[2], 0, 100, 100, proof3);
  }
}

// Candidates scoring (tie between second and third place): candidate 1 > candidate 2 = candidate 3
contract Voting2Proposing1Scenario is Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();
    // set time to voting period
    vm.warp(contestStart + voteDelay + 1);
    // candidates vote
    vm.prank(candidate1);
    contest.castVote(proposalIds[0], 0, 100, 100, proof1);
    vm.prank(candidate2);
    contest.castVote(proposalIds[1], 0, 100, 100, proof2);
    vm.prank(candidate3);
    contest.castVote(proposalIds[2], 0, 100, 100, proof3);
  }
}

contract TestVoting1Proposing1Scenario is Voting1Proposing1Scenario {
  function test_candidateVotes() public {
    (uint256 forVotes1, uint256 againstVotes1) = contest.proposalVotes(proposalIds[0]);
    assertEq(int256(forVotes1) - int256(againstVotes1), 100, "candidate 1 votes");
    (uint256 forVotes2, uint256 againstVotes2) = contest.proposalVotes(proposalIds[1]);
    assertEq(int256(forVotes2) - int256(againstVotes2), 50, "candidate 2 votes");
    (uint256 forVotes3, uint256 againstVotes3) = contest.proposalVotes(proposalIds[2]);
    assertEq(int256(forVotes3) - int256(againstVotes3), 100, "candidate 3 votes");
  }

  function test_startNextTerm_reverts() public {
    vm.expectRevert(JokeraceEligibility_ContestNotCompleted.selector);
    instanceDefaultAdmin.startNextTerm();
  }
}

// Contest completed with candidates 1 & 2 as winners
contract ContestCompletedVoting1Proposing1Scenario is Voting1Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();
    // set time to contest completion
    vm.warp(contestStart + voteDelay + votePeriod + 1);
    uint256 currentTermIndex = instanceDefaultAdmin.currentTermIndex();
    TermDetails memory nextTerm;
    (nextTerm.contest, nextTerm.topK, nextTerm.termEnd, nextTerm.transitionPeriod) =
      instanceDefaultAdmin.terms(currentTermIndex + 1);
    vm.expectEmit();
    emit TermStarted(nextTerm.contest, nextTerm.topK, nextTerm.termEnd, nextTerm.transitionPeriod);
    instanceDefaultAdmin.startNextTerm();
  }
}

// Contest completed with a tie (should not accept ties)
contract ContestCompletedVoting2Proposing1Scenario is Voting2Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();
    // set time to contest completion
    vm.warp(contestStart + voteDelay + votePeriod + 1);
  }
}

// Contest completed with only one candidate, which is less than topK (2)
contract ContestCompletedProposing2Scenario is Proposing2Scenario {
  function setUp() public virtual override {
    super.setUp();
    // set time to contest completion
    vm.warp(contestStart + voteDelay + votePeriod + 1);
    bool canStart = instanceDefaultAdmin.canStartNextTerm();
    assertEq(canStart, true);
    uint256 currentTermIndex = instanceDefaultAdmin.currentTermIndex();
    TermDetails memory nextTerm;
    (nextTerm.contest, nextTerm.topK, nextTerm.termEnd, nextTerm.transitionPeriod) =
      instanceDefaultAdmin.terms(currentTermIndex + 1);
    vm.expectEmit();
    emit TermStarted(address(nextTerm.contest), nextTerm.topK, nextTerm.termEnd, nextTerm.transitionPeriod);
    instanceDefaultAdmin.startNextTerm();
  }
}

contract TestContestCompletedProposing2Scenario is ContestCompletedProposing2Scenario {
  function test_eligibilityInstance() public {
    (bool eligible1,) = instanceDefaultAdmin.getWearerStatus(candidate1, winnersHat);
    assertEq(eligible1, false, "candidate 1 eligibility");
    (bool eligible2,) = instanceDefaultAdmin.getWearerStatus(candidate2, winnersHat);
    assertEq(eligible2, false, "candidate 2 eligibility");
    (bool eligible3,) = instanceDefaultAdmin.getWearerStatus(candidate3, winnersHat);
    assertEq(eligible3, false, "candidate 3 eligibility");
  }

  function test_eligibilityHats() public {
    assertEq(HATS.isEligible(candidate1, winnersHat), false, "candidate 1 eligibility");
    assertEq(HATS.isEligible(candidate2, winnersHat), false, "candidate 2 eligibility");
    assertEq(HATS.isEligible(candidate3, winnersHat), false, "candidate 3 eligibility");
  }

  function test_canStartNextTerm() public {
    bool canStart = instanceDefaultAdmin.canStartNextTerm();
    assertEq(canStart, false);
  }
}

contract TestContestCompletedVoting2Proposing1Scenario is ContestCompletedVoting2Proposing1Scenario {
  function test_startNextTerm() public {
    vm.expectRevert(JokeraceEligibility_ContestTie.selector);
    instanceDefaultAdmin.startNextTerm();
    uint256 currentTermIndex = instanceDefaultAdmin.currentTermIndex();
    assertEq(currentTermIndex, 0);
    TermDetails memory currentTerm;
    (currentTerm.contest, currentTerm.topK, currentTerm.termEnd, currentTerm.transitionPeriod) =
      instanceDefaultAdmin.terms(currentTermIndex);
    assertEq(currentTerm.contest, address(0));
    assertEq(currentTerm.topK, 0);
    assertEq(currentTerm.termEnd, 0);
    assertEq(currentTerm.transitionPeriod, 0);
    TermDetails memory nextTerm;
    (nextTerm.contest, nextTerm.topK, nextTerm.termEnd, nextTerm.transitionPeriod) =
      instanceDefaultAdmin.terms(currentTermIndex + 1);
    assertEq(nextTerm.contest, address(contest));
    assertEq(nextTerm.topK, 2);
    assertEq(nextTerm.termEnd, termEnd1);
    assertEq(nextTerm.transitionPeriod, transitionPeriod);
  }
}

contract TestContestCompletedVoting1Proposing1Scenario is ContestCompletedVoting1Proposing1Scenario {
  function test_startNextTermResult() public {
    uint256 currentTermIndex = instanceDefaultAdmin.currentTermIndex();
    assertEq(currentTermIndex, 1);
    TermDetails memory currentTerm;
    (currentTerm.contest, currentTerm.topK, currentTerm.termEnd, currentTerm.transitionPeriod) =
      instanceDefaultAdmin.terms(currentTermIndex);
    assertEq(currentTerm.contest, address(contest));
    assertEq(currentTerm.topK, 2);
    assertEq(currentTerm.termEnd, termEnd1);
    assertEq(currentTerm.transitionPeriod, transitionPeriod);
    TermDetails memory nextTerm;
    (nextTerm.contest, nextTerm.topK, nextTerm.termEnd, nextTerm.transitionPeriod) =
      instanceDefaultAdmin.terms(currentTermIndex + 1);
    assertEq(nextTerm.contest, address(0));
    assertEq(nextTerm.topK, 0);
    assertEq(nextTerm.termEnd, 0);
    assertEq(nextTerm.transitionPeriod, 0);
  }

  function test_eligibilityInstance() public {
    (bool eligible1,) = instanceDefaultAdmin.getWearerStatus(candidate1, winnersHat);
    assertEq(eligible1, true, "candidate 1 eligibility");
    (bool eligible2,) = instanceDefaultAdmin.getWearerStatus(candidate2, winnersHat);
    assertEq(eligible2, false, "candidate 2 eligibility");
    (bool eligible3,) = instanceDefaultAdmin.getWearerStatus(candidate3, winnersHat);
    assertEq(eligible3, true, "candidate 3 eligibility");
  }

  function test_eligibilityHats() public {
    assertEq(HATS.isEligible(candidate1, winnersHat), true, "candidate 1 eligibility");
    assertEq(HATS.isEligible(candidate2, winnersHat), false, "candidate 2 eligibility");
    assertEq(HATS.isEligible(candidate3, winnersHat), true, "candidate 3 eligibility");
  }
}

contract TestTermNotCompleted is ContestCompletedVoting1Proposing1Scenario {
  function test_canStartNextTerm() public {
    bool canStart = instanceDefaultAdmin.canStartNextTerm();
    assertEq(canStart, false);
  }

  function test_startNextTerm_reverts() public {
    vm.prank(dao);
    instanceDefaultAdmin.setNextTerm(address(contest), termEnd1 + 86_400, transitionPeriod, 3);
    vm.expectRevert(JokeraceEligibility_TermNotCompleted.selector);
    instanceDefaultAdmin.startNextTerm();
  }
}

// Current term ended, ready for reelection
contract TermEndedVoting1Proposing1Scenario is ContestCompletedVoting1Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();
    // set time to contest completion
    vm.warp(contestStart + voteDelay + votePeriod + termPeriod + 1);
  }
}

contract TestStartEmptyTerm is TermEndedVoting1Proposing1Scenario {
  function test_canStartNextTerm() public {
    vm.expectRevert();
    instanceDefaultAdmin.canStartNextTerm();
  }

  function test_startNextTerm_reverts() public {
    vm.expectRevert();
    instanceDefaultAdmin.startNextTerm();
  }
}

contract TestTermEndedVoting1Proposing1Scenario is TermEndedVoting1Proposing1Scenario {
  function test_setNextTermnNotAdmin_reverts() public {
    vm.startPrank(candidate1);
    vm.expectRevert(JokeraceEligibility_NotAdmin.selector);
    instanceDefaultAdmin.setNextTerm(address(contest), termEnd1, transitionPeriod, 2);
    vm.stopPrank();
  }

  function test_eligibilityInstance() public {
    (bool eligible1,) = instanceDefaultAdmin.getWearerStatus(candidate1, winnersHat);
    assertEq(eligible1, true, "candidate 1 eligibility");
    (bool eligible2,) = instanceDefaultAdmin.getWearerStatus(candidate2, winnersHat);
    assertEq(eligible2, false, "candidate 2 eligibility");
    (bool eligible3,) = instanceDefaultAdmin.getWearerStatus(candidate3, winnersHat);
    assertEq(eligible3, true, "candidate 3 eligibility");
  }

  function test_eligibilityHats() public {
    assertEq(HATS.isEligible(candidate1, winnersHat), true, "candidate 1 eligibility");
    assertEq(HATS.isEligible(candidate2, winnersHat), false, "candidate 2 eligibility");
    assertEq(HATS.isEligible(candidate3, winnersHat), true, "candidate 3 eligibility");
  }
}

// Transition period ended, no reelection, previous elected should not be eligible anymore
contract TransitionPeriodEndedVoting1Proposing1Scenario is TermEndedVoting1Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();
    // set time to contest completion
    vm.warp(termEnd1 + transitionPeriod + 1);
  }
}

contract TestTransitionPeriodEndedVoting1Proposing1Scenario is TransitionPeriodEndedVoting1Proposing1Scenario {
  function test_eligibilityInstance() public {
    (bool eligible1,) = instanceDefaultAdmin.getWearerStatus(candidate1, winnersHat);
    assertEq(eligible1, false, "candidate 1 eligibility");
    (bool eligible2,) = instanceDefaultAdmin.getWearerStatus(candidate2, winnersHat);
    assertEq(eligible2, false, "candidate 2 eligibility");
    (bool eligible3,) = instanceDefaultAdmin.getWearerStatus(candidate3, winnersHat);
    assertEq(eligible3, false, "candidate 3 eligibility");
  }

  function test_eligibilityHats() public {
    assertEq(HATS.isEligible(candidate1, winnersHat), false, "candidate 1 eligibility");
    assertEq(HATS.isEligible(candidate2, winnersHat), false, "candidate 2 eligibility");
    assertEq(HATS.isEligible(candidate3, winnersHat), false, "candidate 3 eligibility");
  }
}

// Transition period ended, no reelection, previous elected should not be eligible anymore
contract NextContestCanceledVoting1Proposing1Scenario is TermEndedVoting1Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();
    uint256 newTermEnd = block.timestamp + voteDelay + votePeriod;
    uint96 newTopK = 5;
    vm.prank(dao);
    vm.expectEmit();
    emit NextTermSet(address(contestCanceled), newTopK, newTermEnd, transitionPeriod);
    instanceDefaultAdmin.setNextTerm(address(contestCanceled), newTermEnd, transitionPeriod, newTopK);
  }
}

contract TestNextContestCanceledVoting1Proposing1Scenario is NextContestCanceledVoting1Proposing1Scenario {
  function test_canStartNextTerm() public {
    bool canStart = instanceDefaultAdmin.canStartNextTerm();
    assertEq(canStart, false);
  }

  function test_startNextTerm_reverts() public {
    vm.expectRevert(JokeraceEligibility_ContestNotCompleted.selector);
    instanceDefaultAdmin.startNextTerm();
  }

  function test_canSetNewElection() public {
    vm.prank(dao);
    uint256 newTermEnd = block.timestamp + voteDelay + votePeriod;
    uint96 newTopK = 5;
    vm.expectEmit();
    emit NextTermSet(address(contest), newTopK, newTermEnd, transitionPeriod2);
    instanceDefaultAdmin.setNextTerm(address(contest), newTermEnd, transitionPeriod2, newTopK);
    bool canStart = instanceDefaultAdmin.canStartNextTerm();
    assertEq(canStart, true);
  }
}

contract TestSetNextTermVoting1Proposing1Scenario is TermEndedVoting1Proposing1Scenario {
  address public newContest;

  function setUp() public virtual override {
    super.setUp();
    // deploy a new contest
    contestStart = block.timestamp;
    uint256[] memory newContestArgs = new uint256[](10);
    newContestArgs[0] = contestStart;
    newContestArgs[1] = voteDelay;
    newContestArgs[2] = votePeriod;
    newContestArgs[3] = 50;
    newContestArgs[4] = 50;
    newContestArgs[5] = 0;
    newContestArgs[6] = 0;
    newContestArgs[7] = 0;
    newContestArgs[8] = 1;
    newContestArgs[9] = 250;
    newContest = address(
      new Contest("test contest reelection", "contest reelection", bytes32(0), votingMerkleRoot, newContestArgs)
    );
  }

  function test_reelection() public {
    vm.prank(dao);
    uint256 newTermEnd = block.timestamp + voteDelay + votePeriod;
    uint96 newTopK = 5;
    vm.expectEmit();
    emit NextTermSet(address(newContest), newTopK, newTermEnd, transitionPeriod2);
    instanceDefaultAdmin.setNextTerm(newContest, newTermEnd, transitionPeriod2, newTopK);
  }
}

contract TestSetNextTermHatAdmin is TestSetup {
  function setUp() public virtual override {
    super.setUp();
    // set time to contest completion
    vm.warp(termEnd1 + 1);
  }

  function test_setNextTermByTopHat_reverts() public {
    vm.startPrank(dao);
    vm.expectRevert(JokeraceEligibility_NotAdmin.selector);
    instanceHatAdmin.setNextTerm(
      address(contest), contestStart + voteDelay + votePeriod + termPeriod, transitionPeriod, 2
    );
    vm.stopPrank();
  }
}

contract TestSetNextTermDefaultAdmin is TestSetup {
  address newContest;
  uint256 newTermEnd;
  uint96 newTopK;

  function setUp() public virtual override {
    super.setUp();
    newContest = address(contest);
    newTermEnd = termEnd1 + 86_000;
    newTopK = 5;
    vm.prank(optionalAdmin);
    vm.expectEmit();
    emit NextTermSet(address(newContest), newTopK, newTermEnd, transitionPeriod);
    instanceHatAdmin.setNextTerm(newContest, newTermEnd, transitionPeriod, newTopK);
  }

  function test_setNextTermDefaultAdmin() public {
    assertEq(instanceHatAdmin.currentTermIndex(), 0);
    TermDetails memory nextTerm;
    (nextTerm.contest, nextTerm.topK, nextTerm.termEnd, nextTerm.transitionPeriod) = instanceHatAdmin.terms(1);
    assertEq(address(nextTerm.contest), address(newContest));
    assertEq(nextTerm.termEnd, newTermEnd);
    assertEq(nextTerm.topK, newTopK);
    assertEq(nextTerm.transitionPeriod, transitionPeriod);
  }
}

contract TestSetupContestWithDownVoting is TestSetup {
  function test_setUp_reverts() public {
    vm.expectRevert(JokeraceEligibility_MustHaveDownvotingDisabled.selector);
    deployInstance(
      winnersHat,
      uint256(1),
      address(contestWithDownVoting),
      contestStart + voteDelay + votePeriod + termPeriod,
      2,
      transitionPeriod
    );
  }
}

contract TestSetupContestWithSortingDisabled is TestSetup {
  function test_setUp_reverts() public {
    vm.expectRevert(JokeraceEligibility_MustHaveSortingEnabled.selector);
    deployInstance(
      winnersHat,
      uint256(1),
      address(contestWithSortingDisabled),
      contestStart + voteDelay + votePeriod + termPeriod,
      2,
      transitionPeriod
    );
  }
}

contract TestSetNextTermContestWithDownVoting is TestSetup {
  function test_reelection_reverts() public {
    vm.startPrank(dao);
    vm.expectRevert(JokeraceEligibility_MustHaveDownvotingDisabled.selector);
    instanceDefaultAdmin.setNextTerm(address(contestWithDownVoting), block.timestamp + 86_400, transitionPeriod, 5);
    vm.stopPrank();
  }
}

contract TestSetNextTermContestWithSortingDisabled is TestSetup {
  function test_reelection_reverts() public {
    vm.startPrank(dao);
    vm.expectRevert(JokeraceEligibility_MustHaveSortingEnabled.selector);
    instanceDefaultAdmin.setNextTerm(address(contestWithSortingDisabled), block.timestamp + 86_400, transitionPeriod, 5);
    vm.stopPrank();
  }
}
