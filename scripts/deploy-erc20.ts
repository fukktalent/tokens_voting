import * as dotenv from "dotenv";

import { ethers } from "hardhat";

dotenv.config();

async function main() {
    const ERC20Token = await ethers.getContractFactory("ERC20Token");
    const erc20Token = await ERC20Token.deploy(
        process.env.ERC20_NAME || "Token ERC20", 
        process.env.ERC20_SYMBOL || "ERC20"
    );

    await erc20Token.deployed();

    console.log("Token deployed to:", erc20Token.address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
