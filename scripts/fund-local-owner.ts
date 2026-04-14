import { getScriptClients } from "./foundry";

/**
 * Fund the owner address with ETH on localhost for testing
 * This script is ONLY for localhost - owner should already have funds on real networks
 */
async function main() {
  const { networkName, publicClient, walletClient } = await getScriptClients({ requireWallet: true });
  const deployer = walletClient!;
  const account = deployer.account!;

  // Owner address (hardcoded from MinimalUUPS.sol line 19)
  const ownerAddress = "0x547289319C3e6aedB179C0b8e8aF0B5ACd062603" as `0x${string}`;

  console.log("Funding Owner Address on Localhost");
  console.log("===================================");
  console.log("Network:", networkName);
  console.log("Deployer address:", account.address);
  console.log("Owner address:", ownerAddress);
  console.log("");

  // Check network (allow localhost only for local testing)
  if (networkName !== "localhost") {
    throw new Error("This script is only for localhost. Owner should already have funds on real networks.");
  }

  // Transfer ETH to owner
  console.log("Transferring ETH to owner for gas...");
  const transferAmount = 10000000000000000000n; // 10 ETH
  const transferTxHash = await deployer.sendTransaction({
    account,
    to: ownerAddress,
    value: transferAmount,
  });
  await publicClient.waitForTransactionReceipt({ hash: transferTxHash });
  console.log(`   ✅ Transferred ${transferAmount} wei (10 ETH) to owner`);
  console.log("");

  // Check balance
  const balance = await publicClient.getBalance({ address: ownerAddress });
  console.log(`Owner balance: ${balance} wei (${Number(balance) / 1e18} ETH)`);
  console.log("");
  console.log("✅ Owner funded successfully");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
