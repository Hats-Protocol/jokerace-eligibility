# JokeraceEligibility

JokeraceEligibility is an eligibility module for [Hats Protocol](https://github.com/hats-protocol/hats-protocol).
In general, the module defines eligibility for wearers according to a Jokerace contest results. More specifically, the module supports multiple terms, each defined by:

- A Jokerace contest.
- The number of winners in the contest (top K with highest score).
- The term duration, starting from the contest completion.

Each module instance has its admin/s which can set a reelection (new term), once the current term has ended.

## JokeraceEligibility Details

JokeraceEligibility inherits from the [HatsEligibilityModule](https://github.com/Hats-Protocol/hats-module#hatseligibilitymodule) base contract, from which it receives two major properties:

- It can be cheaply deployed via the [HatsModuleFactory](https://github.com/Hats-Protocol/hats-module#hatsmodulefactory) minimal proxy factory, and
- It implements the [IHatsEligibility](https://github.com/Hats-Protocol/hats-protocol/blob/main/src/Interfaces/IHatsEligibility.sol) interface

### Setup

A JokeraceEligibility instance requires several parameters to be set at deployment, passed to the `HatsModuleFactory.createHatsModule()` function in various ways.

#### Immutable values

- `hatId`: The id of the hat to which this instance will be attached as an eligibility module, passed as itself
- `ADMIN_HAT`: The id of the admin hat which can set reelections (new terms). If set to zero, then the default admins are hatsId's admins in Hats. The parameter is abi-encoded (packed) and passed as `_otherImmutableArgs`

The following immutable values will also automatically be set within the instance at deployment:

- `IMPLEMENTATION`: The address of the JokeraceEligibility implementation contract
- `HATS`: The address of the Hats Protocol contract

#### Initial state values

The following are abi-encoded (unpacked) and then passed to the `HatsModuleFactory.createHatsModule()` function as `_initData`. These values can be changed at each reelection:

- `underlyingContest`: The Jokerace contest of the current term.
- `termEnd`: The timestamp of the term ending time (first second in which the term is considered as ended).
- `topK`: The top K candidates with the highest scores will be eligible wearers for the corresponding term.

### Contest Results

Each term starts at the current contest completion and ends according to `termEnd`. After contest completion, anyone can call the `pullElectionResults` function in order to pull its results and update the eligible wearers for the current term. The eligible wearers are the authors of the `topK` proposals with the highest scores.

**NOTE**: Negative or zero scores are also counted as valid.

**NOTE**: In case there are no definite K winners, meaning that there is a tie between place K and K+1, then the term is considered invalid and no candidate will be eligible.

### Reelection

After the current term has ended, or in case the contest in the current term has been canceled, a reelection can be set by an admin of the module. The reelection is defined with a new Jokerace contest, term ending timestamp and a top K parameter.

## Development

This repo uses Foundry for development and testing. To get started:

1. Fork the project
2. Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
3. To compile the contracts, run `forge build`
4. To test, run `forge test`
