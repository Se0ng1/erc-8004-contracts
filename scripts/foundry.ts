import fs from "node:fs";
import path from "node:path";

import dotenv from "dotenv";
import {
  createPublicClient,
  createWalletClient,
  defineChain,
  http,
  type Chain,
  type Hex,
  type PublicClient,
  type Transport,
  type WalletClient,
} from "viem";
import { privateKeyToAccount, type Account } from "viem/accounts";

dotenv.config();

const DEFAULT_ANVIL_PRIVATE_KEY =
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

type NetworkConfig = {
  name: string;
  rpcUrl: string;
  privateKeyEnv?: string;
};

const NETWORKS: Record<string, NetworkConfig> = {
  localhost: {
    name: "Localhost",
    rpcUrl: process.env.LOCALHOST_RPC_URL || "http://127.0.0.1:8545",
    privateKeyEnv: "PRIVATE_KEY",
  },
  sepolia: { name: "Sepolia", rpcUrl: process.env.SEPOLIA_RPC_URL || "", privateKeyEnv: "SEPOLIA_PRIVATE_KEY" },
  mainnet: { name: "Ethereum Mainnet", rpcUrl: process.env.MAINNET_RPC_URL || "", privateKeyEnv: "MAINNET_PRIVATE_KEY" },
  baseSepolia: { name: "Base Sepolia", rpcUrl: process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org", privateKeyEnv: "BASE_SEPOLIA_PRIVATE_KEY" },
  base: { name: "Base", rpcUrl: process.env.BASE_RPC_URL || "https://mainnet.base.org", privateKeyEnv: "BASE_PRIVATE_KEY" },
  polygonAmoy: { name: "Polygon Amoy", rpcUrl: process.env.POLYGON_AMOY_RPC_URL || "https://rpc-amoy.polygon.technology", privateKeyEnv: "POLYGON_AMOY_PRIVATE_KEY" },
  polygon: { name: "Polygon", rpcUrl: process.env.POLYGON_RPC_URL || "https://polygon-rpc.com", privateKeyEnv: "POLYGON_PRIVATE_KEY" },
  bnbTestnet: { name: "BNB Testnet", rpcUrl: process.env.BNB_TESTNET_RPC_URL || "https://bsc-testnet-rpc.publicnode.com", privateKeyEnv: "BNB_TESTNET_PRIVATE_KEY" },
  bnb: { name: "BNB", rpcUrl: process.env.BNB_RPC_URL || "https://bsc-dataseed.binance.org", privateKeyEnv: "BNB_PRIVATE_KEY" },
  monadTestnet: { name: "Monad Testnet", rpcUrl: process.env.MONAD_TESTNET_RPC_URL || "https://testnet-rpc.monad.xyz", privateKeyEnv: "MONAD_TESTNET_PRIVATE_KEY" },
  monad: { name: "Monad", rpcUrl: process.env.MONAD_RPC_URL || "https://rpc.monad.xyz", privateKeyEnv: "MONAD_PRIVATE_KEY" },
  scrollSepolia: { name: "Scroll Sepolia", rpcUrl: process.env.SCROLL_SEPOLIA_RPC_URL || "https://sepolia-rpc.scroll.io", privateKeyEnv: "SCROLL_SEPOLIA_PRIVATE_KEY" },
  scroll: { name: "Scroll", rpcUrl: process.env.SCROLL_RPC_URL || "https://rpc.scroll.io", privateKeyEnv: "SCROLL_PRIVATE_KEY" },
  gnosisChiado: { name: "Gnosis Chiado", rpcUrl: process.env.GNOSIS_CHIADO_RPC_URL || "https://rpc.chiadochain.net", privateKeyEnv: "GNOSIS_CHIADO_PRIVATE_KEY" },
  gnosis: { name: "Gnosis", rpcUrl: process.env.GNOSIS_RPC_URL || "https://rpc.gnosischain.com", privateKeyEnv: "GNOSIS_PRIVATE_KEY" },
  arbitrumSepolia: { name: "Arbitrum Sepolia", rpcUrl: process.env.ARBITRUM_SEPOLIA_RPC_URL || "https://sepolia-rollup.arbitrum.io/rpc", privateKeyEnv: "ARBITRUM_SEPOLIA_PRIVATE_KEY" },
  arbitrum: { name: "Arbitrum One", rpcUrl: process.env.ARBITRUM_RPC_URL || "https://arb1.arbitrum.io/rpc", privateKeyEnv: "ARBITRUM_PRIVATE_KEY" },
  celoSepolia: { name: "Celo Sepolia", rpcUrl: process.env.CELO_SEPOLIA_RPC_URL || "https://forno.celo-sepolia.celo-testnet.org", privateKeyEnv: "CELO_SEPOLIA_PRIVATE_KEY" },
  celo: { name: "Celo", rpcUrl: process.env.CELO_RPC_URL || "https://forno.celo.org", privateKeyEnv: "CELO_PRIVATE_KEY" },
  taikoHoodi: { name: "Taiko Hoodi", rpcUrl: process.env.TAIKO_HOODI_RPC_URL || "https://rpc.hoodi.taiko.xyz", privateKeyEnv: "TAIKO_HOODI_PRIVATE_KEY" },
  taiko: { name: "Taiko", rpcUrl: process.env.TAIKO_RPC_URL || "https://rpc.mainnet.taiko.xyz", privateKeyEnv: "TAIKO_PRIVATE_KEY" },
  megaeth: { name: "MegaETH", rpcUrl: process.env.MEGAETH_RPC_URL || "https://alpha.megaeth.com/rpc", privateKeyEnv: "MEGAETH_PRIVATE_KEY" },
  megaethTestnet: { name: "MegaETH Testnet", rpcUrl: process.env.MEGAETH_TESTNET_RPC_URL || "https://timothy.megaeth.com/rpc", privateKeyEnv: "MEGAETH_TESTNET_PRIVATE_KEY" },
  lineaSepolia: { name: "Linea Sepolia", rpcUrl: process.env.LINEA_SEPOLIA_RPC_URL || "https://rpc.sepolia.linea.build", privateKeyEnv: "LINEA_SEPOLIA_PRIVATE_KEY" },
  linea: { name: "Linea", rpcUrl: process.env.LINEA_RPC_URL || "https://rpc.linea.build", privateKeyEnv: "LINEA_PRIVATE_KEY" },
  avalancheFuji: { name: "Avalanche Fuji", rpcUrl: process.env.AVALANCHE_FUJI_RPC_URL || "https://api.avax-test.network/ext/bc/C/rpc", privateKeyEnv: "AVALANCHE_FUJI_PRIVATE_KEY" },
  avalanche: { name: "Avalanche", rpcUrl: process.env.AVALANCHE_RPC_URL || "https://api.avax.network/ext/bc/C/rpc", privateKeyEnv: "AVALANCHE_PRIVATE_KEY" },
  opSepolia: { name: "Optimism Sepolia", rpcUrl: process.env.OP_SEPOLIA_RPC_URL || "https://sepolia.optimism.io", privateKeyEnv: "OP_SEPOLIA_PRIVATE_KEY" },
  op: { name: "Optimism", rpcUrl: process.env.OP_MAINNET_RPC_URL || "https://mainnet.optimism.io", privateKeyEnv: "OP_MAINNET_PRIVATE_KEY" },
  xlayer: { name: "XLayer", rpcUrl: process.env.XLAYER_RPC_URL || "https://rpc.xlayer.tech", privateKeyEnv: "XLAYER_PRIVATE_KEY" },
  xlayerTestnet: { name: "XLayer Testnet", rpcUrl: process.env.XLAYER_TESTNET_RPC_URL || "https://testrpc.xlayer.tech", privateKeyEnv: "XLAYER_TESTNET_PRIVATE_KEY" },
  abstract: { name: "Abstract", rpcUrl: process.env.ABSTRACT_RPC_URL || "https://api.mainnet.abs.xyz", privateKeyEnv: "ABSTRACT_PRIVATE_KEY" },
  abstractSepolia: { name: "Abstract Sepolia", rpcUrl: process.env.ABSTRACT_SEPOLIA_RPC_URL || "https://api.testnet.abs.xyz", privateKeyEnv: "ABSTRACT_SEPOLIA_PRIVATE_KEY" },
  mantleSepolia: { name: "Mantle Sepolia", rpcUrl: process.env.MANTLE_SEPOLIA_RPC_URL || "https://rpc.sepolia.mantle.xyz", privateKeyEnv: "MANTLE_SEPOLIA_PRIVATE_KEY" },
  mantle: { name: "Mantle", rpcUrl: process.env.MANTLE_RPC_URL || "https://rpc.mantle.xyz", privateKeyEnv: "MANTLE_PRIVATE_KEY" },
  soneiumMinato: { name: "Soneium Minato", rpcUrl: process.env.SONEIUM_MINATO_RPC_URL || "https://rpc.minato.soneium.org", privateKeyEnv: "SONEIUM_MINATO_PRIVATE_KEY" },
  soneium: { name: "Soneium", rpcUrl: process.env.SONEIUM_RPC_URL || "https://rpc.soneium.org", privateKeyEnv: "SONEIUM_PRIVATE_KEY" },
  goatTestnet: { name: "GOAT Testnet3", rpcUrl: process.env.GOAT_TESTNET_RPC_URL || "https://rpc.testnet3.goat.network", privateKeyEnv: "GOAT_TESTNET_PRIVATE_KEY" },
  goat: { name: "GOAT", rpcUrl: process.env.GOAT_RPC_URL || "https://rpc.goat.network", privateKeyEnv: "GOAT_PRIVATE_KEY" },
  metis: { name: "Metis", rpcUrl: process.env.METIS_RPC_URL || "https://andromeda.metis.io/?owner=1088", privateKeyEnv: "METIS_PRIVATE_KEY" },
  metisSepolia: { name: "Metis Sepolia", rpcUrl: process.env.METIS_SEPOLIA_RPC_URL || "https://sepolia.metisdevops.link", privateKeyEnv: "METIS_SEPOLIA_PRIVATE_KEY" },
  hedera: { name: "Hedera", rpcUrl: process.env.HEDERA_RPC_URL || "https://mainnet.hashio.io/api", privateKeyEnv: "HEDERA_PRIVATE_KEY" },
  hederaTestnet: { name: "Hedera Testnet", rpcUrl: process.env.HEDERA_TESTNET_RPC_URL || "https://testnet.hashio.io/api", privateKeyEnv: "HEDERA_TESTNET_PRIVATE_KEY" },
  skaleBaseSepolia: { name: "SKALE Base Sepolia", rpcUrl: process.env.SKALE_BASE_SEPOLIA_RPC_URL || "https://base-sepolia-testnet.skalenodes.com/v1/jubilant-horrible-ancha", privateKeyEnv: "SKALE_BASE_SEPOLIA_PRIVATE_KEY" },
  skaleBase: { name: "SKALE Base", rpcUrl: process.env.SKALE_BASE_RPC_URL || "https://skale-base.skalenodes.com/v1/base", privateKeyEnv: "SKALE_BASE_PRIVATE_KEY" },
  shape: { name: "Shape", rpcUrl: process.env.SHAPE_RPC_URL || "https://mainnet.shape.network", privateKeyEnv: "SHAPE_PRIVATE_KEY" },
  shapeSepolia: { name: "Shape Sepolia", rpcUrl: process.env.SHAPE_SEPOLIA_RPC_URL || "https://sepolia.shape.network", privateKeyEnv: "SHAPE_SEPOLIA_PRIVATE_KEY" },
  arcTestnet: { name: "Arc Testnet", rpcUrl: process.env.ARC_TESTNET_RPC_URL || "https://rpc.testnet.arc.network", privateKeyEnv: "ARC_TESTNET_PRIVATE_KEY" },
};

export type ScriptClients = {
  networkName: string;
  rpcUrl: string;
  chainId: number;
  chain: Chain;
  publicClient: PublicClient;
  walletClient?: WalletClient<Transport, Chain, Account>;
};

export function argValue(name: string): string | undefined {
  const idx = process.argv.indexOf(name);
  return idx === -1 ? undefined : process.argv[idx + 1];
}

export function normalizePrivateKey(privateKey: string): Hex {
  const normalized = privateKey.startsWith("0x") ? privateKey : `0x${privateKey}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(normalized)) {
    throw new Error("Invalid private key format. Expected 32-byte hex string.");
  }
  return normalized as Hex;
}

export async function getScriptClients(options: { requireWallet?: boolean } = {}): Promise<ScriptClients> {
  const networkName = argValue("--network") || "localhost";
  const network = NETWORKS[networkName];
  const rpcUrl = argValue("--rpc-url") || network?.rpcUrl || process.env.RPC_URL;
  if (!rpcUrl) {
    throw new Error(`Missing RPC URL. Pass --rpc-url or configure ${networkName.toUpperCase()}_RPC_URL.`);
  }

  const publicClientWithoutChain = createPublicClient({ transport: http(rpcUrl) });
  const chainId = await publicClientWithoutChain.getChainId();
  const chain = defineChain({
    id: chainId,
    name: network?.name || networkName,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [rpcUrl] } },
  });

  const publicClient = createPublicClient({ chain, transport: http(rpcUrl) });

  let walletClient: WalletClient<Transport, Chain, Account> | undefined;
  const privateKeyArg = argValue("--private-key");
  const privateKeyFromEnv =
    privateKeyArg ||
    (network?.privateKeyEnv ? process.env[network.privateKeyEnv] : undefined) ||
    process.env.PRIVATE_KEY ||
    (networkName === "localhost" ? DEFAULT_ANVIL_PRIVATE_KEY : undefined);

  if (privateKeyFromEnv) {
    const account = privateKeyToAccount(normalizePrivateKey(privateKeyFromEnv));
    walletClient = createWalletClient({ account, chain, transport: http(rpcUrl) });
  } else if (options.requireWallet) {
    throw new Error("Missing private key. Pass --private-key or set the network PRIVATE_KEY env var.");
  }

  return { networkName, rpcUrl, chainId, chain, publicClient, walletClient };
}

export function readFoundryArtifact(contractName: string) {
  const artifactPath = path.join(process.cwd(), "out", `${contractName}.sol`, `${contractName}.json`);
  if (!fs.existsSync(artifactPath)) {
    throw new Error(`Missing Foundry artifact for ${contractName}. Run "forge build" first.`);
  }
  return JSON.parse(fs.readFileSync(artifactPath, "utf8"));
}

export function artifactBytecode(contractName: string): Hex {
  const artifact = readFoundryArtifact(contractName);
  const bytecode = artifact.bytecode?.object || artifact.bytecode;
  if (!bytecode || bytecode === "0x") {
    throw new Error(`Artifact for ${contractName} does not include deploy bytecode.`);
  }
  return (bytecode.startsWith("0x") ? bytecode : `0x${bytecode}`) as Hex;
}

export function artifactAbi(contractName: string) {
  return readFoundryArtifact(contractName).abi;
}
