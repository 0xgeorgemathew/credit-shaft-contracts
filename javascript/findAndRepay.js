// Filename: scripts/findAndRepay.js

const { ethers } = require("ethers");
require("@chainlink/env-enc").config();

const aavePoolAbi = require("../abis/AavePool.json");
const erc20Abi = require("../abis/ERC20.json");

// --- Configuration ---
const AAVE_POOL_ADDRESS = "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951";
const USDC_ADDRESS = "0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8";
const USDC_VARIABLE_DEBT_TOKEN_ADDRESS =
  "0x36b5de936ef1710e1d22eabe5231b28581a92ecc";

// NEW: Add a safety cap to prevent spending too much in one go.
const MAX_REPAY_AMOUNT = ethers.utils.parseUnits("1000000.0", 6); // Cap repayment at 100 USDC

// --- Chunking Configuration ---
const CHUNK_SIZE = 499;
const TOTAL_BLOCKS_TO_SEARCH = 200000;

const findAndRepay = async () => {
  // --- 1. Initialize Ethers Signer & Provider ---
  const rpcUrl = process.env.SEPOLIA_RPC_URL;
  const privateKey = process.env.PRIVATE_KEY;
  if (!rpcUrl || !privateKey) {
    throw new Error(
      "SEPOLIA_RPC_URL and PRIVATE_KEY must be set in your .env.enc file."
    );
  }
  const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
  const signer = new ethers.Wallet(privateKey, provider);
  const aavePoolContract = new ethers.Contract(
    AAVE_POOL_ADDRESS,
    aavePoolAbi,
    signer
  );
  const usdcContract = new ethers.Contract(USDC_ADDRESS, erc20Abi, signer);
  const debtTokenContract = new ethers.Contract(
    USDC_VARIABLE_DEBT_TOKEN_ADDRESS,
    erc20Abi,
    provider
  );

  console.log("\n=============================================");
  console.log("  🤖 Aave Auto-Repayment Bot (JS Version) 🤖");
  console.log(`   - Running as: ${signer.address}`);
  console.log("=============================================");

  // --- 2. Find a Recent Debtor ---
  console.log(`📡 Searching for a recent debtor...`);
  const debtor = await findRecentDebtorInChunks(provider, debtTokenContract);

  if (!debtor) {
    console.log("❌ No active debtors found in the searched range. Exiting.");
    return;
  }

  console.log(`✅ Target Acquired!`);
  console.log(`   - Debtor Address: ${debtor.address}`);
  console.log(
    `   - Current Debt:   ${ethers.utils.formatUnits(debtor.debt, 6)} USDC`
  );

  // --- 3. Execute Repayment ---

  // NEW: Determine the amount to repay dynamically.
  // We'll repay the smaller of the user's full debt, or our safety cap.
  let amountToRepay = debtor.debt;
  if (amountToRepay.gt(MAX_REPAY_AMOUNT)) {
    console.log(
      `   - Debt exceeds safety cap. Repaying max amount of ${ethers.utils.formatUnits(
        MAX_REPAY_AMOUNT,
        6
      )} USDC.`
    );
    amountToRepay = MAX_REPAY_AMOUNT;
  }

  const ourBalance = await usdcContract.balanceOf(signer.address);
  console.log(
    `\nYour USDC Balance: ${ethers.utils.formatUnits(ourBalance, 6)} USDC`
  );
  if (ourBalance.lt(amountToRepay)) {
    // throw new Error(
    //   `You have insufficient USDC to repay ${ethers.utils.formatUnits(
    //     amountToRepay,
    //     6
    //   )} USDC.`
    // );
    amountToRepay = ourBalance;
  }

  console.log("\n⚙️  Executing Repayment...");

  const repayTx = await aavePoolContract.repay(
    USDC_ADDRESS,
    amountToRepay,
    2,
    debtor.address
  );
  await repayTx.wait();
  console.log(`   - Repayment successful! Tx: ${repayTx.hash}`);

  // --- 4. Verification ---
  const finalDebt = await debtTokenContract.balanceOf(debtor.address);
  console.log("\n📊 Verification:");
  console.log(
    `   - Debtor's final debt: ${ethers.utils.formatUnits(finalDebt, 6)} USDC`
  );
  console.log("\n🎉 Mission Accomplished! 🎉");
};

// The findRecentDebtorInChunks function remains the same as it's working perfectly.
async function findRecentDebtorInChunks(provider, debtTokenContract) {
  //   const latestBlock = await provider.getBlockNumber();
  const latestBlock = 8194978;
  const totalChunks = Math.ceil(TOTAL_BLOCKS_TO_SEARCH / CHUNK_SIZE);
  for (let i = 0; i < totalChunks; i++) {
    const toBlock = latestBlock - i * CHUNK_SIZE;
    const fromBlock = Math.max(0, toBlock - CHUNK_SIZE + 1);
    console.log(
      `   - Searching chunk #${i + 1}: blocks ${fromBlock} to ${toBlock}...`
    );
    const filter = {
      address: USDC_VARIABLE_DEBT_TOKEN_ADDRESS,
      topics: [
        ethers.utils.id("Transfer(address,address,uint256)"),
        ethers.utils.hexZeroPad(ethers.constants.AddressZero, 32),
      ],
      fromBlock: fromBlock,
      toBlock: toBlock,
    };
    const logs = await provider.getLogs(filter);
    if (logs.length === 0) continue;
    for (let j = logs.length - 1; j >= 0; j--) {
      const log = logs[j];
      const potentialDebtorAddress = ethers.utils.defaultAbiCoder.decode(
        ["address"],
        log.topics[2]
      )[0];
      const currentDebt = await debtTokenContract.balanceOf(
        potentialDebtorAddress
      );
      if (currentDebt.gt(100000000)) {
        return { address: potentialDebtorAddress, debt: currentDebt };
      }
    }
  }
  return null;
}

findAndRepay().catch((e) => {
  console.error("\n❌ An error occurred:");
  console.error(e.reason || e.message || e);
  process.exit(1);
});
