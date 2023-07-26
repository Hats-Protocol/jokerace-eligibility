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
//import { GovernorCountingSimple } from "jokerace/governance/extensions/GovernorCountingSimple.sol";
//import { GenericVotesTimestampToken } from "jokerace/GenericVotesTimestampToken.sol";
import { GovernorSorting } from "jokerace/governance/extensions/GovernorSorting.sol";
import { Contest } from "jokerace/Contest.sol";
import { IGovernor } from "jokerace/governance/IGovernor.sol";
//import { IVotesTimestamp } from "jokerace/governance/utils/IVotesTimestamp.sol";

contract DeployImplementationTest is DeployImplementation, Test {
  // variables inherited from DeployImplementation script
  // JokeraceEligibility public implementation;
  // bytes32 public SALT;

  uint256 public fork;
  uint256 public BLOCK_NUMBER = 17_671_864; // the block number where v1.hatsprotocol.eth was deployed;

  IHats public constant HATS = IHats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137); // v1.hatsprotocol.eth
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

  //struct TargetMetadata {
  //  address targetAddress;
  //}
  //
  //struct SafeMetadata {
  //  address[] signers;
  //  uint256 threshold;
  //}
  //
  //struct ProposalCore {
  //  address author;
  //  bool exists;
  //  string description;
  //  TargetMetadata targetMetadata;
  //  SafeMetadata safeMetadata;
  //}

  HatsModuleFactory public factory;
  JokeraceEligibility public instanceDefaultAdmin;
  JokeraceEligibility public instanceHatAdmin;
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
  //GenericVotesTimestampToken token;
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
    // deploy the hats module factory
    factory = deployModuleFactory(HATS, SALT, FACTORY_VERSION);

    // set up a contest
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
    args.push(1);
    contest = new Contest("test contest", "contest", bytes32(0), votingMerkleRoot, args);

    // set up hats
    tophat = HATS.mintTopHat(dao, "tophat", "dao.eth/tophat");
    vm.startPrank(dao);
    winnersHat = HATS.createHat(tophat, "winnersHat", 50, eligibility, toggle, true, "dao.eth/winnersHat");
    optionalAdminHat =
      HATS.createHat(tophat, "optionalAdminHat", 50, eligibility, toggle, true, "dao.eth/optionalAdminHat");
    HATS.mintHat(optionalAdminHat, optionalAdmin);
    vm.stopPrank();

    // deploy the eligibility instance with a default admin
    instanceDefaultAdmin =
      deployInstance(winnersHat, uint256(0), address(contest), contestStart + voteDelay + votePeriod + termPeriod, 2);

    // deploy the eligibility instance with a specific hat admin. This instance is used only to check correct admin
    // rights
    instanceHatAdmin = deployInstance(
      winnersHat, optionalAdminHat, address(contest), contestStart + voteDelay + votePeriod + termPeriod, 2
    );

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

  function test_instanceContest() public {
    assertEq(address(instanceDefaultAdmin.underlyingContest()), address(contest));
  }

  function test_instanceTermEnd() public {
    assertEq(instanceDefaultAdmin.termEnd(), contest.contestDeadline() + 86_400);
  }

  function test_instanceTopK() public {
    assertEq(instanceDefaultAdmin.topK(), 2);
  }

  function test_hatEligibility() public {
    assertEq(
      HATS.getHatEligibilityModule(winnersHat), address(instanceDefaultAdmin), "eligibility module of winners hat"
    );
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
    IGovernor.ProposalCore memory proposal1 = IGovernor.ProposalCore({
      author: candidate1,
      description: "candidate 1 proposal",
      exists: true,
      targetMetadata: IGovernor.TargetMetadata({ targetAddress: candidate1 }),
      safeMetadata: IGovernor.SafeMetadata({ signers: signers1, threshold: 1 })
    });
    contest.proposeWithoutProof(proposal1);

    vm.prank(candidate2);
    IGovernor.ProposalCore memory proposal2 = IGovernor.ProposalCore({
      author: candidate2,
      description: "candidate 2 proposal",
      exists: true,
      targetMetadata: IGovernor.TargetMetadata({ targetAddress: candidate2 }),
      safeMetadata: IGovernor.SafeMetadata({ signers: signers2, threshold: 1 })
    });
    contest.proposeWithoutProof(proposal2);

    vm.prank(candidate3);
    IGovernor.ProposalCore memory proposal3 = IGovernor.ProposalCore({
      author: candidate3,
      description: "candidate 3 proposal",
      exists: true,
      targetMetadata: IGovernor.TargetMetadata({ targetAddress: candidate3 }),
      safeMetadata: IGovernor.SafeMetadata({ signers: signers3, threshold: 1 })
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
    IGovernor.ProposalCore memory proposal1 = IGovernor.ProposalCore({
      author: candidate1,
      description: "candidate 1 proposal",
      exists: true,
      targetMetadata: IGovernor.TargetMetadata({ targetAddress: candidate1 }),
      safeMetadata: IGovernor.SafeMetadata({ signers: signers1, threshold: 1 })
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

  function test_pullContestResults_reverts() public {
    vm.expectRevert(JokeraceEligibility_ContestNotCompleted.selector);
    instanceDefaultAdmin.pullElectionResults();
  }

  function test_setReelection_reverts() public {
    vm.expectRevert(JokeraceEligibility_TermNotCompleted.selector);
    instanceDefaultAdmin.reelection(address(contest), contestStart + voteDelay + votePeriod + termPeriod, 2);
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

  function test_pullContestResults_reverts() public {
    vm.expectRevert(JokeraceEligibility_ContestNotCompleted.selector);
    instanceDefaultAdmin.pullElectionResults();
  }

  function test_setReelection_reverts() public {
    vm.expectRevert(JokeraceEligibility_TermNotCompleted.selector);
    instanceDefaultAdmin.reelection(address(contest), contestStart + voteDelay + votePeriod + termPeriod, 2);
  }
}

// Contest completed with candidates 1 & 2 as winners
contract ContestCompletedVoting1Proposing1Scenario is Voting1Proposing1Scenario {
  function setUp() public virtual override {
    super.setUp();
    // set time to contest completion
    vm.warp(contestStart + voteDelay + votePeriod + 1);
    instanceDefaultAdmin.pullElectionResults();
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
    instanceDefaultAdmin.pullElectionResults();
  }
}

contract TestContestCompletedProposing2Scenario is ContestCompletedProposing2Scenario {
  function test_eligibilityInstance() public {
    (bool eligible1,) = instanceDefaultAdmin.getWearerStatus(candidate1, winnersHat);
    assertEq(eligible1, true, "candidate 1 eligibility");
    (bool eligible2,) = instanceDefaultAdmin.getWearerStatus(candidate2, winnersHat);
    assertEq(eligible2, false, "candidate 2 eligibility");
    (bool eligible3,) = instanceDefaultAdmin.getWearerStatus(candidate3, winnersHat);
    assertEq(eligible3, false, "candidate 3 eligibility");
  }

  function test_eligibilityHats() public {
    assertEq(HATS.isEligible(candidate1, winnersHat), true, "candidate 1 eligibility");
    assertEq(HATS.isEligible(candidate2, winnersHat), false, "candidate 2 eligibility");
    assertEq(HATS.isEligible(candidate3, winnersHat), false, "candidate 3 eligibility");
  }
}

contract TestContestCompletedVoting2Proposing1Scenario is ContestCompletedVoting2Proposing1Scenario {
  function test_pullResults_reverts() public {
    vm.expectRevert(JokeraceEligibility_NoTies.selector);
    instanceDefaultAdmin.pullElectionResults();
  }
}

contract TestContestCompletedVoting1Proposing1Scenario is ContestCompletedVoting1Proposing1Scenario {
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

  function test_setReelection_reverts() public {
    vm.expectRevert(JokeraceEligibility_TermNotCompleted.selector);
    instanceDefaultAdmin.reelection(address(contest), contestStart + voteDelay + votePeriod + termPeriod, 2);
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

contract TestTermEndedVoting1Proposing1Scenario is TermEndedVoting1Proposing1Scenario {
  function test_setReelectionNotAdmin_reverts() public {
    vm.startPrank(candidate1);
    vm.expectRevert(JokeraceEligibility_NotAdmin.selector);
    instanceDefaultAdmin.reelection(address(contest), contestStart + voteDelay + votePeriod + termPeriod, 2);
    vm.stopPrank();
  }

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
    contest = new Contest("test contest reelection", "contest reelection", bytes32(0), votingMerkleRoot, args);
  }

  function test_reelection() public {
    vm.prank(dao);
    address newContest = makeAddr("newContest");
    uint256 newTermEnd = block.timestamp + voteDelay + votePeriod;
    uint256 newTopK = 5;
    instanceDefaultAdmin.reelection(newContest, newTermEnd, newTopK);
    assertEq(address(instanceDefaultAdmin.underlyingContest()), newContest);
    assertEq(instanceDefaultAdmin.topK(), newTopK);
    assertEq(instanceDefaultAdmin.termEnd(), newTermEnd);
  }
}

contract TestReelectionHatAdmin is TestSetup {
  function setUp() public virtual override {
    super.setUp();
    // set time to contest completion
    vm.warp(contestStart + voteDelay + votePeriod + termPeriod + 1);
  }

  function test_reelectionByTopHat_reverts() public {
    vm.startPrank(dao);
    vm.expectRevert(JokeraceEligibility_NotAdmin.selector);
    instanceHatAdmin.reelection(address(contest), contestStart + voteDelay + votePeriod + termPeriod, 2);
    vm.stopPrank();
  }

  function test_reelectionDefaultAdmin() public {
    vm.prank(optionalAdmin);
    instanceHatAdmin.reelection(address(contest), contestStart + voteDelay + votePeriod + termPeriod, 2);
  }
}
