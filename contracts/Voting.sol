//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Voting is Ownable {
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

    IERC20 private _token;
    uint32 private _debatingPeriodDuration;
    uint256 private _minimumQuorum;

    mapping(address => UserData) private _users;

    mapping(uint64 => Proposal) private _proposals;
    uint64 private _proposalCount;

    // user => (proposal id => is voted)
    mapping(address => mapping(uint64 => bool)) private _isVoted;

    event ProposalAccepted(
        uint64 proposalId,
        uint256 votesFor,
        uint256 votesAgainst,
        bytes funcResult
    );

    // when votes < _minimumQuorum or votes against > votes for
    event ProposalDeclined(
        uint64 proposalId,
        uint256 votesFor,
        uint256 votesAgainst
    );

    // wnen call proposal signature failed
    event ProposalFailed(uint64 proposalId);

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

    modifier onlyActive(uint64 proposalId) {
        if (_proposals[proposalId].finishDate == 0) revert InvalidProposal();
        _;
    }

    constructor(
        IERC20 token,
        uint32 debatingPeriodDuration_,
        uint256 minimumQuorum_
    ) {
        _token = token;
        _debatingPeriodDuration = debatingPeriodDuration_;
        _minimumQuorum = minimumQuorum_;
    }

    function deposit(uint256 amount) external {
        _token.transferFrom(msg.sender, address(this), amount);
        _users[msg.sender].balance += amount;
    }

    function addProposal(
        bytes memory callData,
        address recipient,
        string memory description
    ) external onlyOwner {
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

    function vote(
        uint64 proposalId, 
        bool isFor
    )
        external
        onlyActive(proposalId)
    {
        if (_proposals[proposalId].finishDate <= block.timestamp) revert NotActiveProposalTime();
        if (_isVoted[msg.sender][proposalId]) revert AlreadyVoted();

        _isVoted[msg.sender][proposalId] = true;
        _users[msg.sender].lastFinishDate = _proposals[proposalId].finishDate;
        if (isFor) {
            _proposals[proposalId].votesFor += _users[msg.sender].balance;
        } else {
            _proposals[proposalId].votesAgainst += _users[msg.sender].balance;
        }
    }

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

    function withdraw(uint256 amount) external {
        if (_users[msg.sender].lastFinishDate > block.timestamp)
            revert ActiveBalance();
        if (_users[msg.sender].balance < amount) revert InvalidAmount();

        _token.transfer(msg.sender, amount);
        _users[msg.sender].balance -= amount;
    }

    function debatingPeriodDuration() external view returns (uint32) {
        return _debatingPeriodDuration;
    }

    function minimumQuorum() external view returns (uint256) {
        return _minimumQuorum;
    }

    function user(address addr) external view returns (UserData memory) {
        return _users[addr];
    }

    function proposal(uint64 proposalId)
        external
        view
        returns (Proposal memory)
    {
        return _proposals[proposalId];
    }

    function proposalsCount() external view returns (uint64) {
        return _proposalCount;
    }
}
