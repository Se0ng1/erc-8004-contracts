import { execSync } from "child_process";
import { bytesToHex, encodeFunctionData, Hex, keccak256, serializeTransaction, getCreate2Address, createWalletClient, http } from "viem";
import { privateKeyToAccount, toAccount } from "viem/accounts";
import {
  SAFE_SINGLETON_FACTORY,
  IMPLEMENTATION_SALTS,
  getAddresses,
  getNetworkType,
} from "./addresses";
import { artifactAbi, artifactBytecode, getScriptClients, normalizePrivateKey } from "./foundry";

/**
 * Upgrade vanity proxies to final implementations
 * This script REQUIRES OWNER_PRIVATE_KEY in .env
 *
 * The owner performs 3 transactions:
 * 1. Upgrade IdentityRegistry proxy
 * 2. Upgrade ReputationRegistry proxy
 * 3. Upgrade ValidationRegistry proxy
 *
 * Each upgrade also initializes the new implementation
 */
async function main() {
  const { publicClient, chainId, chain, rpcUrl } = await getScriptClients();

  // Get chainId and network-specific config
  const networkType = getNetworkType(chainId);
  const EXPECTED_ADDRESSES = getAddresses(chainId);

  console.log("Upgrading ERC-8004 Vanity Proxies (Owner Phase)");
  console.log("================================================");
  console.log("Network type:", networkType);
  console.log("Chain ID:", chainId);
  console.log("");

  // Get owner account - prefer HSM, fall back to .env private key
  let ownerAccount;

  const ownerPrivateKey = process.env.OWNER_PRIVATE_KEY;
  if (ownerPrivateKey) {
    console.log("WARNING: Using OWNER_PRIVATE_KEY from .env - storing private keys in .env is unsafe. Consider using HSM instead.");
    console.log("");
    ownerAccount = privateKeyToAccount(normalizePrivateKey(ownerPrivateKey));
  } else {
    console.log("INFO: Signing using HSM (slot 1)");
    console.log("");

    function hsm(cmd: string): string {
      for (let i = 0; i < 3; i++) {
        try {
          return execSync(`hsm ${cmd}`, { timeout: 5000 }).toString().trim();
        } catch {
          if (i === 2) throw new Error(`hsm ${cmd} failed after 3 retries`);
          execSync("sleep 1");
        }
      }
      throw new Error("unreachable");
    }

    const info = JSON.parse(hsm("addr"));
    const hsmAddress = info.address as Hex;

    ownerAccount = toAccount({
      address: hsmAddress,
      async signMessage({ message }) {
        const rawMessage = typeof message === "string"
          ? new TextEncoder().encode(message)
          : "raw" in message
            ? message.raw
            : message;
        const msg = typeof rawMessage === "string" ? rawMessage as Hex : bytesToHex(rawMessage);
        const hash = keccak256(msg);
        const raw = hash.startsWith("0x") ? hash.slice(2) : hash;
        const result = JSON.parse(hsm(`sign ${raw}`));
        return `${result.r}${(result.s as string).slice(2)}${(result.v - 27).toString(16).padStart(2, "0")}` as Hex;
      },
      async signTransaction(tx, { serializer = serializeTransaction } = {}) {
        const serialized = await serializer(tx);
        const hash = keccak256(serialized);
        const raw = hash.startsWith("0x") ? hash.slice(2) : hash;
        const result = JSON.parse(hsm(`sign ${raw}`));
        return await serializer(tx, { r: result.r, s: result.s, v: BigInt(result.v) });
      },
      async signTypedData() {
        throw new Error("signTypedData not implemented");
      },
    });
  }
  const ownerWallet = createWalletClient({
    account: ownerAccount,
    chain,
    transport: http(rpcUrl),
  });

  console.log("Owner address:", ownerAccount.address);
  console.log("");

  // Calculate implementation addresses via CREATE2
  const identityImplAbi = artifactAbi("IdentityRegistryUpgradeable");
  const reputationImplAbi = artifactAbi("ReputationRegistryUpgradeable");
  const validationImplAbi = artifactAbi("ValidationRegistryUpgradeable");
  const identityImplBytecode = artifactBytecode("IdentityRegistryUpgradeable");
  const reputationImplBytecode = artifactBytecode("ReputationRegistryUpgradeable");
  const validationImplBytecode = artifactBytecode("ValidationRegistryUpgradeable");

  const identityImpl = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: IMPLEMENTATION_SALTS.identityRegistry,
    bytecodeHash: keccak256(identityImplBytecode),
  });
  const reputationImpl = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: IMPLEMENTATION_SALTS.reputationRegistry,
    bytecodeHash: keccak256(reputationImplBytecode),
  });
  const validationImpl = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: IMPLEMENTATION_SALTS.validationRegistry,
    bytecodeHash: keccak256(validationImplBytecode),
  });

  console.log("Implementation addresses (deterministic via CREATE2):");
  console.log("  IdentityRegistry:    ", identityImpl);
  console.log("  ReputationRegistry:  ", reputationImpl);
  console.log("  ValidationRegistry:  ", validationImpl);
  console.log("");

  const identityProxyAddress = EXPECTED_ADDRESSES.identityRegistry as `0x${string}`;
  const reputationProxyAddress = EXPECTED_ADDRESSES.reputationRegistry as `0x${string}`;
  const validationProxyAddress = EXPECTED_ADDRESSES.validationRegistry as `0x${string}`;

  console.log("Proxy addresses:");
  console.log("  IdentityRegistry:    ", identityProxyAddress);
  console.log("  ReputationRegistry:  ", reputationProxyAddress);
  console.log("  ValidationRegistry:  ", validationProxyAddress);
  console.log("");

  // Get MinimalUUPS ABI for upgradeToAndCall
  const minimalUUPSAbi = artifactAbi("MinimalUUPS");

  console.log("=".repeat(80));
  console.log("PERFORMING UPGRADES");
  console.log("=".repeat(80));
  console.log("");

  // Proxies are already initialized by MinimalUUPS
  // Just upgrade them to real implementations (no need to reinitialize)

  // Helper function to get current implementation
  const getImplementation = async (proxyAddress: `0x${string}`) => {
    const implSlot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
    return await publicClient.getStorageAt({
      address: proxyAddress,
      slot: implSlot as `0x${string}`,
    });
  };

  // Upgrade IdentityRegistry proxy
  console.log("1. Checking IdentityRegistry proxy...");
  const currentIdentityImpl = await getImplementation(identityProxyAddress);
  const currentIdentityImplAddress = currentIdentityImpl ? `0x${currentIdentityImpl.slice(-40)}` : null;

  if (currentIdentityImplAddress?.toLowerCase() === identityImpl.toLowerCase()) {
    console.log("   ⏭️  Already upgraded to IdentityRegistryUpgradeable");
    console.log(`   Current implementation: ${identityImpl}`);
    console.log("");
  } else {
    console.log("   Upgrading IdentityRegistry proxy...");
    // Encode initialize() call for the new implementation
    const identityInitData = encodeFunctionData({
      abi: identityImplAbi,
      functionName: "initialize",
      args: []
    });
    const identityUpgradeData = encodeFunctionData({
      abi: minimalUUPSAbi,
      functionName: "upgradeToAndCall",
      args: [identityImpl, identityInitData]
    });
    const identityUpgradeTxHash = await ownerWallet.sendTransaction({
      account: ownerAccount,
      to: identityProxyAddress,
      data: identityUpgradeData,
    });
    await publicClient.waitForTransactionReceipt({ hash: identityUpgradeTxHash });
    console.log("   ✅ Upgraded to IdentityRegistryUpgradeable");
    console.log(`   Transaction: ${identityUpgradeTxHash}`);
    console.log("");
  }

  // Upgrade ReputationRegistry proxy
  console.log("2. Checking ReputationRegistry proxy...");
  const currentReputationImpl = await getImplementation(reputationProxyAddress);
  const currentReputationImplAddress = currentReputationImpl ? `0x${currentReputationImpl.slice(-40)}` : null;

  if (currentReputationImplAddress?.toLowerCase() === reputationImpl.toLowerCase()) {
    console.log("   ⏭️  Already upgraded to ReputationRegistryUpgradeable");
    console.log(`   Current implementation: ${reputationImpl}`);
    console.log("");
  } else {
    console.log("   Upgrading ReputationRegistry proxy...");
    // Encode initialize(address) call for the new implementation
    const reputationInitData = encodeFunctionData({
      abi: reputationImplAbi,
      functionName: "initialize",
      args: [identityProxyAddress]
    });
    const reputationUpgradeData = encodeFunctionData({
      abi: minimalUUPSAbi,
      functionName: "upgradeToAndCall",
      args: [reputationImpl, reputationInitData]
    });
    const reputationUpgradeTxHash = await ownerWallet.sendTransaction({
      account: ownerAccount,
      to: reputationProxyAddress,
      data: reputationUpgradeData,
    });
    await publicClient.waitForTransactionReceipt({ hash: reputationUpgradeTxHash });
    console.log("   ✅ Upgraded to ReputationRegistryUpgradeable");
    console.log(`   Transaction: ${reputationUpgradeTxHash}`);
    console.log("");
  }

  // Upgrade ValidationRegistry proxy
  console.log("3. Checking ValidationRegistry proxy...");
  const currentValidationImpl = await getImplementation(validationProxyAddress);
  const currentValidationImplAddress = currentValidationImpl ? `0x${currentValidationImpl.slice(-40)}` : null;

  if (currentValidationImplAddress?.toLowerCase() === validationImpl.toLowerCase()) {
    console.log("   ⏭️  Already upgraded to ValidationRegistryUpgradeable");
    console.log(`   Current implementation: ${validationImpl}`);
    console.log("");
  } else {
    console.log("   Upgrading ValidationRegistry proxy...");
    // Encode initialize(address) call for the new implementation
    const validationInitData = encodeFunctionData({
      abi: validationImplAbi,
      functionName: "initialize",
      args: [identityProxyAddress]
    });
    const validationUpgradeData = encodeFunctionData({
      abi: minimalUUPSAbi,
      functionName: "upgradeToAndCall",
      args: [validationImpl, validationInitData]
    });
    const validationUpgradeTxHash = await ownerWallet.sendTransaction({
      account: ownerAccount,
      to: validationProxyAddress,
      data: validationUpgradeData,
    });
    await publicClient.waitForTransactionReceipt({ hash: validationUpgradeTxHash });
    console.log("   ✅ Upgraded to ValidationRegistryUpgradeable");
    console.log(`   Transaction: ${validationUpgradeTxHash}`);
    console.log("");
  }

  console.log("=".repeat(80));
  console.log("UPGRADES COMPLETE");
  console.log("=".repeat(80));
  console.log("");
  console.log("✅ All 3 proxies upgraded successfully!");
  console.log("");
  console.log("Next step: Verify deployment");
  console.log("  npm run verify:vanity -- --network <network>");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
