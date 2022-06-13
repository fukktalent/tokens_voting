//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title DAO Voting contract
/// @author fukktalent
/// @notice voting for purposes. one token is one vote
contract Voting is AccessControl {
    struct Proposal {
        bytes callData;
        address recipient;
        string description;
        uint32 finishDate;
        uint256 votesFor;
        uint256 votesAgainst;
    }

    struct UserData {
        uint256 balance;
        uint32 lastFinishDate;
    }

    bytes32 public constant CHAIRMAN_ROLE = keccak256("CHAIRMAN_ROLE");

    IERC20 private _token;
    uint32 private _debatingPeriodDuration;
    uint256 private _minimumQuorum;

    mapping(address => UserData) private _users;

    mapping(uint64 => Proposal) private _proposals;
    uint64 private _proposalCount;

    // user => (proposal id => is voted)
    mapping(address => mapping(uint64 => bool)) private _isVoted;

    /// @notice when proposal successfuly accepted
    /// @param proposalId id of proposal
    /// @param votesFor votes for proposal
    /// @param votesAgainst votes against proposal
    /// @param funcResult result of proposal func
    event ProposalAccepted(
        uint64 proposalId,
        uint256 votesFor,
        uint256 votesAgainst,
        bytes funcResult
    );

    /// @notice when votes < _minimumQuorum or votes against > votes for
    /// @param proposalId id of proposal
    /// @param votesFor votes for proposal
    /// @param votesAgainst votes against proposal
    event ProposalDeclined(
        uint64 proposalId,
        uint256 votesFor,
        uint256 votesAgainst
    );

    /// @notice when call proposal signature failed
    /// @param proposalId id of proposal
    event ProposalFailed(uint64 proposalId);

    /// @notice when proposal was create
    /// @param proposalId id of proposal
    /// @param callData encoded proposal function signature 
    /// @param recipient contract address on which will call proposal function
    /// @param description of proposal
    event ProposalVotingStarted(
        uint64 proposalId,
        bytes callData,
        address recipient,
        string description
    );

    error InvalidProposal();
    error NotActiveProposalTime();
    error StillActiveProposalTime();
    error ActiveBalance();
    error InvalidAmount();
    error AlreadyVoted();
    error ZeroBalance();

    modifier onlyActive(uint64 proposalId) {
        if (_proposals[proposalId].finishDate == 0) revert InvalidProposal();
        _;
    }

    /// @notice set init data and grand DEFAULT_ADMIN_ROLE to owner
    /// @param token erc20 tokens, use as votes
    /// @param debatingPeriodDuration_ voting duration in seconds
    /// @param minimumQuorum_ minimum number of votes at which voting will take place
    constructor(
        IERC20 token,
        uint32 debatingPeriodDuration_,
        uint256 minimumQuorum_,
        address chairman
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CHAIRMAN_ROLE, chairman);
        _token = token;
        _debatingPeriodDuration = debatingPeriodDuration_;
        _minimumQuorum = minimumQuorum_;
    }

    /// @notice add tokens to balance
    /// @param amount of tokens to deposit
    function deposit(uint256 amount) external {
        _token.transferFrom(msg.sender, address(this), amount);
        _users[msg.sender].balance += amount;
    }

    /// @notice creates porposal and init voting
    /// @param callData encoded proposal function signature 
    /// @param recipient contract address on which will call proposal function
    /// @param description of proposal
    function addProposal(
        bytes memory callData,
        address recipient,
        string memory description
    ) external onlyRole(CHAIRMAN_ROLE) {
        uint64 proposalId = _proposalCount;
        _proposalCount++;

        Proposal storage proposal_ = _proposals[proposalId];
        proposal_.callData = callData;
        proposal_.recipient = recipient;
        proposal_.description = description;
        proposal_.finishDate = uint32(block.timestamp) + _debatingPeriodDuration;

        emit ProposalVotingStarted(
            proposalId,
            callData,
            recipient,
            description
        );
    }

    /// @notice votes for proposal, use full token balance 
    /// @param proposalId id of proposal
    /// @param isFor true - for proposal, false - against proposal
    function vote(
        uint64 proposalId, 
        bool isFor
    )
        external
        onlyActive(proposalId)
    {
        if (_proposals[proposalId].finishDate <= block.timestamp) revert NotActiveProposalTime();
        if (_isVoted[msg.sender][proposalId]) revert AlreadyVoted();
        if (_users[msg.sender].balance == 0) revert ZeroBalance();

        _isVoted[msg.sender][proposalId] = true;

        if (
          _users[msg.sender].lastFinishDate < _proposals[proposalId].finishDate
        ) {
            _users[msg.sender].lastFinishDate = _proposals[proposalId].finishDate;
        }

        if (isFor) {
            _proposals[proposalId].votesFor += _users[msg.sender].balance;
        } else {
            _proposals[proposalId].votesAgainst += _users[msg.sender].balance;
        }
    }

    /// @notice finish voting, three cases: 
    ///         proposal accepted and function call completed successfully,
    ///         proposal accepted and function call failed,
    ///         proposal rejected
    /// @dev deletes proposal from mapping for gas optimisation, emit event to save info
    /// @param proposalId a parameter just like in doxygen (must be followed by parameter name)
    function finishProposal(uint64 proposalId) external onlyActive(proposalId) {
        Proposal storage proposal_ = _proposals[proposalId];
        if (proposal_.finishDate > block.timestamp)
            revert StillActiveProposalTime();

        if (
            proposal_.votesFor + proposal_.votesAgainst >= _minimumQuorum &&
            proposal_.votesFor > proposal_.votesAgainst
        ) {
            (bool success, bytes memory res) = proposal_.recipient.call(
                proposal_.callData
            );

            if (success) {
                emit ProposalAccepted(
                    proposalId,
                    proposal_.votesFor,
                    proposal_.votesAgainst,
                    res
                );
            } else {
                emit ProposalFailed(proposalId);
            }
        } else {
            emit ProposalDeclined(
                proposalId,
                proposal_.votesFor,
                proposal_.votesAgainst
            );
        }

        delete _proposals[proposalId];
    }

    /// @notice withdraw tokens from balance, if tokens dont frozen
    /// @param amount of tokens
    function withdraw(uint256 amount) external {
        if (_users[msg.sender].lastFinishDate > block.timestamp)
            revert ActiveBalance();
        if (_users[msg.sender].balance < amount) revert InvalidAmount();

        _token.transfer(msg.sender, amount);
        _users[msg.sender].balance -= amount;
    }

    /// @notice debatingPeriodDuration getter
    /// @return _debatingPeriodDuration voting duration in seconds
    function debatingPeriodDuration() external view returns (uint32) {
        return _debatingPeriodDuration;
    }

    /// @notice minimumQuorum getter
    /// @return _minimumQuorum minimum number of votes at which voting will take place
    function minimumQuorum() external view returns (uint256) {
        return _minimumQuorum;
    }

    /// @notice user data getter
    /// @param addr addres of user
    /// @return user user data: balance and defrost time
    function user(address addr) external view returns (UserData memory) {
        return _users[addr];
    }

    /// @notice proposal getter
    /// @param proposalId id of proposal
    /// @return proposal proposal data
    function proposal(uint64 proposalId)
        external
        view
        returns (Proposal memory)
    {
        return _proposals[proposalId];
    }

    /// @notice proposalsCount getter
    /// @return _proposalCount amount of proposals for all time
    function proposalsCount() external view returns (uint64) {
        return _proposalCount;
    }
}
