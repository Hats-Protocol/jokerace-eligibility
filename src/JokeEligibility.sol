// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import {IHatsEligibility} from "hats-protocol/Interfaces/IHatsEligibility.sol";
import {IHats} from "hats-protocol/Interfaces/IHats.sol";
import {HatsEligibilityModule, HatsModule} from "hats-module/HatsEligibilityModule.sol";
import {GovernorCountingSimple} from "jokerace/governance/extensions/GovernorCountingSimple.sol";
import {IGovernor} from "jokerace/governance/IGovernor.sol";

contract JokeraceEligibility is HatsEligibilityModule {
    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Indicates that the underlying contest has not completed yet
    error JokeraceEligibility_ContestNotCompleted();
    /// @notice Indicates that the current term is still on-going
    error JokeraceEligibility_TermNotCompleted();
    /// @notice Indicates that top K election winners cannot be deduced because of a tie
    error JokeraceEligibility_NoTies();
    /// @notice Indicates that the caller doesn't have admin permsissions
    error JokeraceEligibility_NotAdmin();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a reelection is set
    event NewTerm(address NewContest, address newAdmin, uint256 newTopK, uint256 newTermEnd);

    /*//////////////////////////////////////////////////////////////
                          PUBLIC  CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * This contract is a clone with immutable args, which means that it is deployed with a set of
     * immutable storage variables (ie constants). Accessing these constants is cheaper than accessing
     * regular storage variables (such as those set on initialization of a typical EIP-1167 clone),
     * but requires a slightly different approach since they are read from calldata instead of storage.
     *
     * Below is a table of constants and their locations. In this module, all are inherited from HatsModule.
     *
     * For more, see here: https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args
     *
     * --------------------------------------------------------------------+
     * CLONE IMMUTABLE "STORAGE"                                           |
     * --------------------------------------------------------------------|
     * Offset  | Constant        | Type    | Length  | Source Contract     |
     * --------------------------------------------------------------------|
     * 0       | IMPLEMENTATION  | address | 20      | HatsModule          |
     * 20      | HATS            | address | 20      | HatsModule          |
     * 40      | hatId           | uint256 | 32      | HatsModule          |
     * --------------------------------------------------------------------+
     */

    /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Current Jokerace contest (election)
    GovernorCountingSimple public underlyingContest;
    /// @notice Optional admin, granted a permission to create a new term (reelection). If not provided, then
    /// this permission is granted to the admins of hatId in Hats
    address public admin;
    /// @notice Final second of the current term (a unix timestamp), i.e. the point at which hats become inactive
    uint256 termEnd;
    /// @notice First K winners of the contest will be eligible
    uint256 topK;
    /// @notice wearer => contest address => eligible/not
    mapping(address => mapping(address => bool)) public eligibleWearersPerContest;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets up this instance with initial operational values
     * @dev Only callable by the hats-module factory. Since the factory only calls this function during a new deployment, this ensures
     * it can only be called once per instance, and that the implementation contract is never initialized.
     * @param _initData Packed initialization data with the following parameters:
     *  _underlyingContest - Jokerace contest
     *  _admin - Optional admin, granted a permission to create a new term (reelection). If not provided, then
     *           this permission is granted to the admins of hatId in Hats
     *  _termEnd - Final second of the current term (a unix timestamp), i.e. the point at which hats become inactive
     *  _topK - First K winners of the contest will be eligible
     */
    function setUp(bytes calldata _initData) public override initializer {
        (address payable _underlyingContest, address _admin, uint256 _termEnd, uint256 _topK) =
            abi.decode(_initData, (address, address, uint256, uint256));
        // initialize the mutable state vars
        underlyingContest = GovernorCountingSimple(_underlyingContest);
        admin = _admin;
        termEnd = _termEnd;
        topK = _topK;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy the JokeraceEligibility implementation contract and set its version
    /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
    constructor(string memory _version) HatsModule(_version) {}

    /*//////////////////////////////////////////////////////////////
                          HATS ELIGIBILITY FUNCTION
    //////////////////////////////////////////////////////////////*/

    function getWearerStatus(address _wearer, uint256 _hatId)
        public
        view
        override
        returns (bool eligible, bool standing)
    {
        standing = true;
        if (block.timestamp <= termEnd) {
            eligible = eligibleWearersPerContest[_wearer][address(underlyingContest)];
        }
    }

    /*//////////////////////////////////////////////////////////////
                           PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function pullElectionResults() public {
        if (underlyingContest.state() != IGovernor.ContestState.Completed) {
            revert JokeraceEligibility_ContestNotCompleted();
        }

        // sorted in ascending order
        uint256[] memory sortedProposalIds = underlyingContest.sortedProposals(true);
        uint256 numProposals = sortedProposalIds.length;
        GovernorCountingSimple currentContest = underlyingContest;

        // check if there's a tie between place k and k + 1. If so, election results are rejected
        if (sortedProposalIds.length > topK) {
            // get the score of candidate in place K
            (uint256 forVotesPlaceK, uint256 againstVotesPlaceK) =
                getVotes(currentContest, sortedProposalIds[numProposals - topK]);
            int256 totalVotesPlaceK = int256(forVotesPlaceK) - int256(againstVotesPlaceK);

            // get the score of candidate in place K + 1
            (uint256 forVotesPlaceKPlusOne, uint256 againstVotesPlaceKPlusOne) =
                getVotes(currentContest, sortedProposalIds[numProposals - topK - 1]);
            int256 totalVotesPlaceKPlusOne = int256(forVotesPlaceKPlusOne) - int256(againstVotesPlaceKPlusOne);

            if (totalVotesPlaceK == totalVotesPlaceKPlusOne) {
                revert JokeraceEligibility_NoTies();
            }
        }

        uint256 numEligibleWearers = topK < numProposals ? topK : numProposals;
        for (uint256 i = 0; i < numEligibleWearers;) {
            address candidate = getCandidate(currentContest, sortedProposalIds[numProposals - i - 1]);
            eligibleWearersPerContest[candidate][address(currentContest)] = true;

            // should not overflow based on < numEligibleWearers stopping condition
            unchecked {
                ++i;
            }
        }
    }

    function reelection(
        GovernorCountingSimple newUnderlyingContest,
        address newAdmin,
        uint256 newTermEnd,
        uint256 newTopK
    ) public {
        if (!reelectionAllowed()) {
            revert JokeraceEligibility_TermNotCompleted();
        }
        if (admin != address(0)) {
            if (msg.sender != admin) {
                revert JokeraceEligibility_NotAdmin();
            }
        } else {
            if (!HATS().isAdminOfHat(msg.sender, hatId())) {
                revert JokeraceEligibility_NotAdmin();
            }
        }

        underlyingContest = newUnderlyingContest;
        admin = newAdmin;
        termEnd = newTermEnd;
        topK = newTopK;

        emit NewTerm(address(newUnderlyingContest), newAdmin, newTopK, newTermEnd);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function reelectionAllowed() public view returns (bool allowed) {
        allowed = block.timestamp > termEnd || underlyingContest.state() == IGovernor.ContestState.Canceled;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getVotes(GovernorCountingSimple contest, uint256 proposalId)
        internal
        view
        returns (uint256 forVotes, uint256 againstVotes)
    {
        (forVotes, againstVotes) = contest.proposalVotes(proposalId);
    }

    function getCandidate(GovernorCountingSimple contest, uint256 proposalId)
        internal
        view
        returns (address candidate)
    {
        candidate = contest.getProposal(proposalId).author;
    }
}
