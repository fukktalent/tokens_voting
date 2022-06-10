import { task } from 'hardhat/config'
import { Voting } from '../typechain-types';

task("addProposal", "add proposal")
    .addParam("contract", "address of voting")
    .addParam("calldata", "calldata bytes array")
    .addParam("recipient", "recipient address")
    .addParam("description", "description of proposal")
    .setAction(async (args, { ethers }) => {
        const { contract, calldata, recipient, description } = args;
        const [signer] = await ethers.getSigners();

        const voting: Voting = <Voting>(await ethers.getContractAt("Voting", contract, signer));
        const tx = await voting.addProposal(calldata, recipient, description);

        console.log(tx);
    });

task("vote", "add proposal")
    .addParam("contract", "address of voting")
    .addParam("id", "proposal id")
    .addParam("isfor", "true - for, false - against")
    .setAction(async (args, { ethers }) => {
        const { contract, id, isfor } = args;
        const [signer] = await ethers.getSigners();

        const voting: Voting = <Voting>(await ethers.getContractAt("Voting", contract, signer));
        const tx = await voting.vote(id, isfor === "true");

        console.log(tx);
    });


task("finishProposal", "finish proposal")
    .addParam("contract", "address of voting")
    .addParam("id", "proposal id")
    .setAction(async (args, { ethers }) => {
        const { contract, id } = args;
        const [signer] = await ethers.getSigners();

        const voting: Voting = <Voting>(await ethers.getContractAt("Voting", contract, signer));
        const tx = await voting.finishProposal(id);

        console.log(tx);
    });

task("deposit", "deposit tokens to voting contract")
    .addParam("contract", "address of voting")
    .addParam("amount", "amount to deposit")
    .setAction(async (args, { ethers }) => {
        const { contract, amount } = args;
        const [signer] = await ethers.getSigners();

        const voting: Voting = <Voting>(await ethers.getContractAt("Voting", contract, signer));
        const tx = await voting.deposit(amount);

        console.log(tx);
    });

task("withdraw", "withdraw tokens from voting contract")
    .addParam("contract", "address of voting")
    .addParam("amount", "amount to withdraw")
    .setAction(async (args, { ethers }) => {
        const { contract, amount } = args;
        const [signer] = await ethers.getSigners();

        const voting: Voting = <Voting>(await ethers.getContractAt("Voting", contract, signer));
        const tx = await voting.withdraw(amount);

        console.log(tx);
    });