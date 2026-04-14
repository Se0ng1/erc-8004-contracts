// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../contracts/ERC1967Proxy.sol";
import "../contracts/IdentityRegistryUpgradeable.sol";
import "../contracts/ReputationRegistryUpgradeable.sol";
import "../contracts/TestMinimalUUPS.sol";
import "../contracts/ValidationRegistryUpgradeable.sol";

abstract contract ERC8004TestBase is Test {
    bytes32 internal constant AGENT_WALLET_SET_TYPEHASH =
        keccak256("AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)");
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant ZERO_HASH = bytes32(0);

    address internal agentOwner = address(0xA11CE);
    address internal client = address(0xB0B);
    address internal client2 = address(0xCAFE);
    address internal client3 = address(0xC0FFEE);
    address internal responder = address(0xD00D);
    address internal responder2 = address(0xD00E);
    address internal validator = address(0xF00D);
    address internal validator2 = address(0xF00E);
    address internal attacker = address(0xBAD);

    uint256 internal newWalletPk = 0xBEEF;
    uint256 internal wrongWalletPk = 0xBADF00D;
    address internal newWallet;
    address internal wrongWallet;

    function setUp() public virtual {
        newWallet = vm.addr(newWalletPk);
        wrongWallet = vm.addr(wrongWalletPk);

        vm.deal(agentOwner, 100 ether);
        vm.deal(client, 100 ether);
        vm.deal(client2, 100 ether);
        vm.deal(client3, 100 ether);
        vm.deal(responder, 100 ether);
        vm.deal(responder2, 100 ether);
        vm.deal(validator, 100 ether);
        vm.deal(validator2, 100 ether);
        vm.deal(attacker, 100 ether);
        vm.deal(newWallet, 100 ether);
        vm.deal(wrongWallet, 100 ether);
    }

    function deployProxy(address implementation, bytes memory initCalldata) internal returns (ERC1967Proxy) {
        return new ERC1967Proxy(implementation, initCalldata);
    }

    function deployIdentityRegistryProxy() internal returns (IdentityRegistryUpgradeable) {
        TestMinimalUUPS minimalImpl = new TestMinimalUUPS();
        ERC1967Proxy proxy =
            deployProxy(address(minimalImpl), abi.encodeCall(TestMinimalUUPS.initialize, (address(0))));

        IdentityRegistryUpgradeable realImpl = new IdentityRegistryUpgradeable();
        TestMinimalUUPS(address(proxy)).upgradeToAndCall(
            address(realImpl),
            abi.encodeCall(IdentityRegistryUpgradeable.initialize, ())
        );

        return IdentityRegistryUpgradeable(address(proxy));
    }

    function deployReputationRegistryProxy(address identityRegistry)
        internal
        returns (ReputationRegistryUpgradeable)
    {
        TestMinimalUUPS minimalImpl = new TestMinimalUUPS();
        ERC1967Proxy proxy =
            deployProxy(address(minimalImpl), abi.encodeCall(TestMinimalUUPS.initialize, (identityRegistry)));

        ReputationRegistryUpgradeable realImpl = new ReputationRegistryUpgradeable();
        TestMinimalUUPS(address(proxy)).upgradeToAndCall(
            address(realImpl),
            abi.encodeCall(ReputationRegistryUpgradeable.initialize, (identityRegistry))
        );

        return ReputationRegistryUpgradeable(address(proxy));
    }

    function deployValidationRegistryProxy(address identityRegistry)
        internal
        returns (ValidationRegistryUpgradeable)
    {
        TestMinimalUUPS minimalImpl = new TestMinimalUUPS();
        ERC1967Proxy proxy =
            deployProxy(address(minimalImpl), abi.encodeCall(TestMinimalUUPS.initialize, (identityRegistry)));

        ValidationRegistryUpgradeable realImpl = new ValidationRegistryUpgradeable();
        TestMinimalUUPS(address(proxy)).upgradeToAndCall(
            address(realImpl),
            abi.encodeCall(ValidationRegistryUpgradeable.initialize, (identityRegistry))
        );

        return ValidationRegistryUpgradeable(address(proxy));
    }

    function deployAll()
        internal
        returns (
            IdentityRegistryUpgradeable identityRegistry,
            ReputationRegistryUpgradeable reputationRegistry,
            ValidationRegistryUpgradeable validationRegistry
        )
    {
        identityRegistry = deployIdentityRegistryProxy();
        reputationRegistry = deployReputationRegistryProxy(address(identityRegistry));
        validationRegistry = deployValidationRegistryProxy(address(identityRegistry));
    }

    function registerAgent(IdentityRegistryUpgradeable identityRegistry, address owner, string memory tokenURI)
        internal
        returns (uint256)
    {
        vm.prank(owner);
        return identityRegistry.register(tokenURI);
    }

    function signAgentWallet(
        IdentityRegistryUpgradeable identityRegistry,
        uint256 agentId,
        address newWalletAddress,
        address owner,
        uint256 deadline,
        uint256 signingKey
    ) internal view returns (bytes memory) {
        bytes32 structHash =
            keccak256(abi.encode(AGENT_WALLET_SET_TYPEHASH, agentId, newWalletAddress, owner, deadline));
        bytes32 domainSeparator = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("ERC8004IdentityRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                address(identityRegistry)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function giveFeedback(
        ReputationRegistryUpgradeable reputationRegistry,
        uint256 agentId,
        address feedbackClient,
        int128 value,
        string memory tag1,
        string memory tag2
    ) internal {
        vm.prank(feedbackClient);
        reputationRegistry.giveFeedback(agentId, value, 0, tag1, tag2, "", "", ZERO_HASH);
    }

    function appendResponse(
        ReputationRegistryUpgradeable reputationRegistry,
        uint256 agentId,
        address feedbackClient,
        uint64 feedbackIndex,
        address responseSender
    ) internal {
        vm.prank(responseSender);
        reputationRegistry.appendResponse(agentId, feedbackClient, feedbackIndex, "ipfs://response", ZERO_HASH);
    }

    function singleAddress(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }

    function twoAddresses(address first, address second) internal pure returns (address[] memory values) {
        values = new address[](2);
        values[0] = first;
        values[1] = second;
    }

    function threeAddresses(address first, address second, address third)
        internal
        pure
        returns (address[] memory values)
    {
        values = new address[](3);
        values[0] = first;
        values[1] = second;
        values[2] = third;
    }

    function emptyAddressArray() internal pure returns (address[] memory values) {
        values = new address[](0);
    }
}
