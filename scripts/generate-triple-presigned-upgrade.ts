import { encodeFunctionData, Hex, parseGwei, keccak256, getCreate2Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import fs from "fs";
import {
  SAFE_SINGLETON_FACTORY,
  IMPLEMENTATION_SALTS,
  getAddresses,
  getNetworkType,
} from "./addresses";
import { artifactAbi, artifactBytecode, getScriptClients, normalizePrivateKey } from "./foundry";

/**
 * Generate 3 pre-signed upgrade transactions
 * Simple approach: one transaction per upgrade, sequential nonces
 */
async function main() {
  const { publicClient, chainId } = await getScriptClients();

  // Get network-specific config
  const networkType = getNetworkType(chainId);
  const PROXIES = getAddresses(chainId);

  console.log("=".repeat(80));
  console.log("Generating 3 Pre-Signed Upgrade Transactions");
  console.log("=".repeat(80));
  console.log("Network type:", networkType);
  console.log("Chain ID:", chainId);
  console.log("");

  // Calculate implementation addresses via CREATE2
  const identityImplAbi = artifactAbi("IdentityRegistryUpgradeable");
  const reputationImplAbi = artifactAbi("ReputationRegistryUpgradeable");
  const validationImplAbi = artifactAbi("ValidationRegistryUpgradeable");
  const identityImplBytecode = artifactBytecode("IdentityRegistryUpgradeable");
  const reputationImplBytecode = artifactBytecode("ReputationRegistryUpgradeable");
  const validationImplBytecode = artifactBytecode("ValidationRegistryUpgradeable");

  const IMPLEMENTATIONS = {
    identityRegistry: getCreate2Address({
      from: SAFE_SINGLETON_FACTORY,
      salt: IMPLEMENTATION_SALTS.identityRegistry,
      bytecodeHash: keccak256(identityImplBytecode),
    }),
    reputationRegistry: getCreate2Address({
      from: SAFE_SINGLETON_FACTORY,
      salt: IMPLEMENTATION_SALTS.reputationRegistry,
      bytecodeHash: keccak256(reputationImplBytecode),
    }),
    validationRegistry: getCreate2Address({
      from: SAFE_SINGLETON_FACTORY,
      salt: IMPLEMENTATION_SALTS.validationRegistry,
      bytecodeHash: keccak256(validationImplBytecode),
    }),
  };

  console.log("Implementation addresses (calculated via CREATE2):");
  console.log("  IdentityRegistry:  ", IMPLEMENTATIONS.identityRegistry);
  console.log("  ReputationRegistry:", IMPLEMENTATIONS.reputationRegistry);
  console.log("  ValidationRegistry:", IMPLEMENTATIONS.validationRegistry);
  console.log("");

  // Get owner private key
  let ownerPrivateKey = process.env.OWNER_PRIVATE_KEY;
  if (!ownerPrivateKey) {
    throw new Error("OWNER_PRIVATE_KEY not found in environment variables");
  }

  const ownerAccount = privateKeyToAccount(normalizePrivateKey(ownerPrivateKey));
  console.log("Owner address:", ownerAccount.address);
  console.log("");

  // Always use nonces 0, 1, 2 for production package
  // This assumes owner address is fresh (never used before)
  const startingNonce = 0;

  console.log("Generating transactions with nonces: 0, 1, 2");
  console.log("⚠️  Owner address must be fresh (never used) for these to work!");
  console.log("");

  // Get MinimalUUPS artifact for upgradeToAndCall
  const minimalUUPSAbi = artifactAbi("MinimalUUPS");

  // Gas settings
  const gasPrice = parseGwei("20"); // 20 gwei

  // Encode initialize() calls for each implementation
  const identityInitData = encodeFunctionData({
    abi: identityImplAbi,
    functionName: "initialize",
    args: []
  });
  const reputationInitData = encodeFunctionData({
    abi: reputationImplAbi,
    functionName: "initialize",
    args: [PROXIES.identityRegistry]
  });
  const validationInitData = encodeFunctionData({
    abi: validationImplAbi,
    functionName: "initialize",
    args: [PROXIES.identityRegistry]
  });

  // Prepare all three transactions
  const transactions = [
    {
      name: "IdentityRegistry",
      proxy: PROXIES.identityRegistry,
      implementation: IMPLEMENTATIONS.identityRegistry,
      initData: identityInitData,
      nonce: startingNonce,
    },
    {
      name: "ReputationRegistry",
      proxy: PROXIES.reputationRegistry,
      implementation: IMPLEMENTATIONS.reputationRegistry,
      initData: reputationInitData,
      nonce: startingNonce + 1,
    },
    {
      name: "ValidationRegistry",
      proxy: PROXIES.validationRegistry,
      implementation: IMPLEMENTATIONS.validationRegistry,
      initData: validationInitData,
      nonce: startingNonce + 2,
    },
  ];

  const signedTransactions = [];

  for (const tx of transactions) {
    console.log(`Preparing ${tx.name} upgrade (nonce ${tx.nonce})...`);

    // Encode upgradeToAndCall with initialize() data
    const upgradeData = encodeFunctionData({
      abi: minimalUUPSAbi,
      functionName: "upgradeToAndCall",
      args: [tx.implementation, tx.initData],
    });

    // Estimate gas
    const gasEstimate = await publicClient.estimateGas({
      account: ownerAccount.address,
      to: tx.proxy as `0x${string}`,
      data: upgradeData,
    });

    // Add 30% buffer
    const gasLimit = (gasEstimate * 130n) / 100n;

    console.log(`  Gas estimate: ${gasEstimate.toString()}`);
    console.log(`  Gas limit (with 30% buffer): ${gasLimit.toString()}`);

    // Create and sign transaction
    const transaction = {
      to: tx.proxy as `0x${string}`,
      value: 0n,
      data: upgradeData,
      gas: gasLimit,
      gasPrice,
      nonce: tx.nonce,
      chainId,
    };

    const signature = await ownerAccount.signTransaction(transaction);

    const requiredFunding = gasLimit * gasPrice;

    signedTransactions.push({
      name: tx.name,
      proxy: tx.proxy,
      implementation: tx.implementation,
      nonce: tx.nonce,
      gasLimit: gasLimit.toString(),
      gasPrice: gasPrice.toString(),
      requiredFunding: requiredFunding.toString(),
      requiredFundingEth: (Number(requiredFunding) / 1e18).toFixed(6),
      signedTransaction: signature,
    });

    console.log(`  ✅ Signed`);
    console.log("");
  }

  // Calculate total funding needed
  const totalFunding = signedTransactions.reduce(
    (sum, tx) => sum + BigInt(tx.requiredFunding),
    0n
  );

  // Prepare output
  const output = {
    chainId,
    ownerAddress: ownerAccount.address,
    startingNonce,
    gasPrice: gasPrice.toString(),
    gasPriceGwei: Number(gasPrice) / 1e9,
    transactions: signedTransactions,
    totalFunding: totalFunding.toString(),
    totalFundingEth: (Number(totalFunding) / 1e18).toFixed(6),
    timestamp: new Date().toISOString(),
  };

  // Save to JSON
  const outputPath = `triple-presigned-upgrade-chain-${chainId}.json`;
  fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));

  console.log("=".repeat(80));
  console.log("✅ All 3 Transactions Signed");
  console.log("=".repeat(80));
  console.log("");
  console.log("Output saved to:", outputPath);
  console.log("");
  console.log("📦 PACKAGE:");
  console.log("  Transaction 1 (nonce", startingNonce + "):", "IdentityRegistry upgrade");
  console.log("  Transaction 2 (nonce", startingNonce + 1 + "):", "ReputationRegistry upgrade");
  console.log("  Transaction 3 (nonce", startingNonce + 2 + "):", "ValidationRegistry upgrade");
  console.log("");
  console.log("  Total funding needed:", output.totalFundingEth, "ETH");
  console.log("  Owner address:", ownerAccount.address);
  console.log("");
  console.log("📋 TO BROADCAST:");
  console.log("  tsx scripts/upgrade-vanity-presigned.ts --network <network>");
  console.log("");
  console.log("=".repeat(80));

  return output;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
