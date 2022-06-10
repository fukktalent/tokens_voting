import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Voting, ERC20Token, ERC20Token__factory, Voting__factory } from "../typechain-types";

describe("Voting", function () {
    const PERIOD_DURATION = 24 * 60 * 60;
    const MINIMUM_QUORUM = 1_000_000;

    let owner: SignerWithAddress;
    let acc1: SignerWithAddress;
    let acc2: SignerWithAddress;
    let acc3: SignerWithAddress;

    let erc20: ERC20Token;
    let voting: Voting;

    function getExampleProposal (isInvalid = false) {
        const iface = new ethers.utils.Interface([
            "function transferFrom(address from, address to, uint256 amount)"
        ]);

        const callData = iface.encodeFunctionData(
            "transferFrom", 
            [isInvalid ? acc3.address : acc1.address, acc2.address, 123]
        );
        const recipient = erc20.address;
        const description = "transfer from acc1 to acc2";

        return { callData, recipient, description };
    }

    before(async function() {
        [owner, acc1, acc2, acc3] = await ethers.getSigners();

        erc20 = await new ERC20Token__factory(owner).deploy("test", "TST");
        await erc20.deployed();

        voting = await new Voting__factory(owner).deploy(erc20.address, PERIOD_DURATION, MINIMUM_QUORUM);
        await voting.deployed();

        erc20.mint(owner.address, MINIMUM_QUORUM);
        erc20.mint(acc1.address, MINIMUM_QUORUM);
        erc20.mint(acc2.address, MINIMUM_QUORUM);

        await erc20.approve(voting.address, ethers.constants.MaxUint256);
        await erc20.connect(acc1).approve(voting.address, ethers.constants.MaxUint256);
        await erc20.connect(acc2).approve(voting.address, ethers.constants.MaxUint256);
    });

    it("Should correct deployed", async function() {
        expect(await voting.debatingPeriodDuration()).to.be.equal(PERIOD_DURATION);
        expect(await voting.minimumQuorum()).to.be.equal(MINIMUM_QUORUM);
        expect(await voting.proposalsCount()).to.be.equal(0);
    });

    it("Should deposit balances", async function() {
        const tx = await voting.deposit(MINIMUM_QUORUM / 2 + 1);
        voting.connect(acc1).deposit(MINIMUM_QUORUM / 2);
        voting.connect(acc2).deposit(MINIMUM_QUORUM / 2 - 1);

        expect(() => tx).to.changeTokenBalance(erc20, owner, MINIMUM_QUORUM / 2);

        const userData = await voting.user(owner.address);
        expect(userData.balance).to.be.equal(MINIMUM_QUORUM / 2 + 1);
        expect(userData.lastFinishDate).to.be.equal(0);
    });

    describe("addProposal", function() {
        it("Should add proposal", async function() {
            const { callData, recipient, description } = getExampleProposal();
            const tx = await voting.addProposal(callData, recipient, description);
            await expect(tx).to.emit(
                voting,
                "ProposalVotingStarted"
            ).withArgs(
                0,
                callData,
                recipient,
                description
            );

            const proposal = await voting.proposal(0);
            expect(proposal.callData).to.be.equal(callData);
            expect(proposal.recipient).to.be.equal(recipient);
            expect(proposal.description).to.be.equal(description);
            expect(proposal.votesFor).to.be.equal(0);
            expect(proposal.votesAgainst).to.be.equal(0);
            expect(await voting.proposalsCount()).to.be.equal(1);
        });

        it("Should revert with Ownable: not owner", async function() {
            const { callData, recipient, description } = getExampleProposal();
            const tx = voting.connect(acc1).addProposal(callData, recipient, description);
            await expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    describe("vote", function() {
        it("Should revert with InvalidProposal", async function() {
            const tx = voting.vote(1, true);
            await expect(tx).to.be.revertedWith("InvalidProposal()");
        });

        it("Should add votes for proposal", async function() {
            await voting.vote(0, true);
            const proposal = await voting.proposal(0);
            expect(proposal.votesFor).to.be.equal(MINIMUM_QUORUM / 2 + 1);
            expect(proposal.votesAgainst).to.be.equal(0);
        });

        it("Should add votes against proposal", async function() {
            await voting.connect(acc1).vote(0, false);
            const proposal = await voting.proposal(0);
            expect(proposal.votesFor).to.be.equal(MINIMUM_QUORUM / 2 + 1);
            expect(proposal.votesAgainst).to.be.equal(MINIMUM_QUORUM / 2);
        });

        it("Should revert with InvalidProposal", async function() {
            const tx = voting.vote(0, true);
            await expect(tx).to.be.revertedWith("AlreadyVoted()");
        });

        it("Should revert with NotActiveProposalTime", async function() {
            const { callData, recipient, description } = getExampleProposal();
            await voting.addProposal(callData, recipient, description);

            await ethers.provider.send("evm_increaseTime", [PERIOD_DURATION]);
            await ethers.provider.send("evm_mine", []);

            const tx = voting.vote(0, true);
            await expect(tx).to.be.revertedWith("NotActiveProposalTime()");
        });
    });

    describe("finishProposal", function() {
        before(async function() {
            const { callData, recipient, description } = getExampleProposal();
            await voting.addProposal(callData, recipient, description);

            await voting.vote(2, false);
            await voting.connect(acc1).vote(2, true);
        });

        it("Should revert with InvalidProposal", async function() {
            const tx = voting.finishProposal(99);
            await expect(tx).to.be.revertedWith("InvalidProposal()");
        });

        it("Should revert with StillActiveProposalTime", async function() {
            const tx = voting.finishProposal(2);
            await expect(tx).to.be.revertedWith("StillActiveProposalTime()");
        });

        it("Should finish voting and do accepted proposal", async function() {
            const tx = voting.finishProposal(0);

            await expect(tx).to.emit(
                voting,
                "ProposalAccepted"
            ).withArgs(
                0,
                MINIMUM_QUORUM / 2 + 1,
                MINIMUM_QUORUM / 2,
                ethers.utils.hexZeroPad(ethers.utils.hexlify(1), 32)
            )
            .and.to.emit(
                erc20,
                "Transfer"
            ).withArgs(
                acc1.address,
                acc2.address,
                123
            );
        });

        it("Should finish voting and decline proposal", async function() {
            await ethers.provider.send("evm_increaseTime", [PERIOD_DURATION]);
            await ethers.provider.send("evm_mine", []);

            const tx1 = voting.finishProposal(1);
            await expect(tx1).to.emit(
                voting,
                "ProposalDeclined"
            ).withArgs(
                1,
                0,
                0
            );

            const tx2 = voting.finishProposal(2);
            await expect(tx2).to.emit(
                voting,
                "ProposalDeclined"
            ).withArgs(
                2,
                MINIMUM_QUORUM / 2,
                MINIMUM_QUORUM / 2 + 1
            );
        });

        it("Should finish voting and decline proposal then invalid proposal", async function() {
            const { callData, recipient, description } = getExampleProposal(true);
            await voting.addProposal(callData, recipient, description);

            await voting.vote(3, true);
            await voting.connect(acc1).vote(3, false);

            await ethers.provider.send("evm_increaseTime", [PERIOD_DURATION]);
            await ethers.provider.send("evm_mine", []);

            const tx = voting.finishProposal(3);
            await expect(tx).to.emit(
                voting,
                "ProposalFailed"
            ).withArgs(3);
        });
    });

    describe("withdraw", function() {
        it("Should revert with ActiveBalance", async function() {
            const { callData, recipient, description } = getExampleProposal();
            await voting.addProposal(callData, recipient, description);
            await voting.vote(4, true);

            const tx = voting.withdraw(100);
            await expect(tx).to.be.revertedWith("ActiveBalance()");
        });

        it("Should revert with InvalidAmount", async function() {
            await ethers.provider.send("evm_increaseTime", [PERIOD_DURATION]);
            await ethers.provider.send("evm_mine", []);

            const tx = voting.withdraw(MINIMUM_QUORUM);
            await expect(tx).to.be.revertedWith("InvalidAmount()");
        });

        it("Should transfer tokens", async function() {
            const tx = voting.withdraw(100);
            await expect(() => tx).to.changeTokenBalances(
                erc20, 
                [owner, voting], 
                [100, -100]
            );
        });
    });
});
