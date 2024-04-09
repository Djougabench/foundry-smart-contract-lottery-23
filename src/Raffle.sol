// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 *@title  A sample Raffle Contract
 *@author Lionel Djouhan
 *@notice This is a sample Raffle Contract
 *@dev Implement Chainlink VRFv2
 */

contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    /**Type declarations */

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /** States Variables*/
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1; // 1 random word for atant

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    uint256 private S_lastTimeStamp;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] public s_players;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /**Events */
    event EnteredRaffle(address indexed player);
    event winnerPicked(address indexed winner);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_callbackGasLimit = callbackGasLimit;
        i_subscriptionId = subscriptionId;
        s_raffleState = RaffleState.OPEN;
        S_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        //1.Makes migration easier
        //2.Makes front end "indexing" easier

        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev this is the function that the Chailink Automation node call
     * to see if it's time to perform an upKeep.
     * the following should be true for this to return true:
     * 1. the time  interval has passed beetween raffles runs
     * 2. The raffle is in the OPEN state
     * 3. the contract has ETH (aka,palyers)
     * 4. (Implicit) The subscription is funded with LINK
     *
     */
    function checkUpkeep(
        bytes memory /*chekData*/
    ) public view returns (bool upkeepNeeded, bytes memory /*performData*/) {
        bool timeHasPassed = (block.timestamp - S_lastTimeStamp) >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    //1.Get a random number
    //2.Use the random number to pick a player
    //3.Be automatically called
    function performUpkeep(bytes calldata /**performData */) external {
        //check to see if enough time has passed
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;

        i_vrfCoordinator.requestRandomWords(
            i_gasLane, //gas lane
            i_subscriptionId, // subscription ID funded with LINK
            REQUEST_CONFIRMATIONS, // number of confirmations
            i_callbackGasLimit, // gas limit for callback
            NUM_WORDS // number of random words
        );
    }

    //to have a random number back
    //1.Check, 2.effects, 3.Interactions
    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        //Checks
        //Effects( in our own contract)

        uint256 indexOfWInner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWInner];
        s_recentWinner = winner;

        s_raffleState = RaffleState.OPEN;

        //reseting players array for a new raffle
        s_players = new address payable[](0);

        //start the clock over for  a new lotterie
        S_lastTimeStamp = block.timestamp;

        emit winnerPicked(winner);
        //Interactions
        (bool succes, ) = winner.call{value: address(this).balance}("");

        if (!succes) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Function */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPLayer) external view returns (address) {
        return s_players[indexOfPLayer];
    }
}
