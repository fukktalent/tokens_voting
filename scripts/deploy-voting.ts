import * as dotenv from "dotenv";

import { ethers } from "hardhat";

dotenv.config();

async function main() {
    const Voting = await ethers.getContractFactory("Voting");
    const voting = await Voting.deploy(
        process.env.ERC20_ADDRESS || "0xfE3A443Ec77316b09d30bDbDB46ee3E27e739a33",
        process.env.PERIOD_DURATION || 24 * 60 * 60,
        process.env.MINIMUM_QUORUM || 1_000_000,
    );

    await voting.deployed();

    console.log("Voting contract deployed to:", voting.address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
