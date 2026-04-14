// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC8004TestBase.sol";

contract ERC8004UpgradeableTest is ERC8004TestBase {
    event Upgraded(address indexed implementation);

    function testIdentityDeploysThroughProxyAndInitializes() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();

        assertEq(identityRegistry.getVersion(), "2.0.0");
        assertEq(identityRegistry.owner(), address(this));
    }

    function testIdentityPreventsDoubleInitialization() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();

        vm.expectRevert();
        identityRegistry.initialize();
    }

    function testIdentityMaintainsFunctionalityThroughProxy() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();

        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://QmTest123");

        assertEq(identityRegistry.tokenURI(agentId), "ipfs://QmTest123");
        assertEq(identityRegistry.ownerOf(agentId), agentOwner);
    }

    function testIdentityUpgradesToNewImplementationAndPreservesData() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://v1-agent");
        IdentityRegistryUpgradeable implV2 = new IdentityRegistryUpgradeable();

        identityRegistry.upgradeToAndCall(address(implV2), "");

        assertEq(identityRegistry.tokenURI(agentId), "ipfs://v1-agent");
        assertEq(identityRegistry.ownerOf(agentId), agentOwner);

        uint256 nextAgentId = registerAgent(identityRegistry, agentOwner, "ipfs://post-upgrade-agent");
        assertGt(nextAgentId, agentId);
    }

    function testIdentityOnlyOwnerCanUpgrade() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        IdentityRegistryUpgradeable implV2 = new IdentityRegistryUpgradeable();

        vm.prank(attacker);
        vm.expectRevert();
        identityRegistry.upgradeToAndCall(address(implV2), "");

        identityRegistry.upgradeToAndCall(address(implV2), "");
    }

    function testReputationDeploysThroughProxyAndInitializes() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        ReputationRegistryUpgradeable reputationRegistry =
            deployReputationRegistryProxy(address(identityRegistry));

        assertEq(reputationRegistry.getVersion(), "2.0.0");
        assertEq(reputationRegistry.owner(), address(this));
        assertEq(reputationRegistry.getIdentityRegistry(), address(identityRegistry));
    }

    function testReputationUpgradeMaintainsStorage() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        ReputationRegistryUpgradeable reputationRegistry =
            deployReputationRegistryProxy(address(identityRegistry));
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        giveFeedback(reputationRegistry, agentId, client, 85, "quality", "service");

        ReputationRegistryUpgradeable implV2 = new ReputationRegistryUpgradeable();
        reputationRegistry.upgradeToAndCall(address(implV2), "");

        (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked) =
            reputationRegistry.readFeedback(agentId, client, 1);
        assertEq(value, 85);
        assertEq(valueDecimals, 0);
        assertEq(tag1, "quality");
        assertEq(tag2, "service");
        assertFalse(isRevoked);
        assertEq(reputationRegistry.getIdentityRegistry(), address(identityRegistry));
    }

    function testValidationDeploysThroughProxyAndInitializes() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        ValidationRegistryUpgradeable validationRegistry =
            deployValidationRegistryProxy(address(identityRegistry));

        assertEq(validationRegistry.getVersion(), "2.0.0");
        assertEq(validationRegistry.owner(), address(this));
        assertEq(validationRegistry.getIdentityRegistry(), address(identityRegistry));
    }

    function testValidationUpgradeMaintainsStorage() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        ValidationRegistryUpgradeable validationRegistry =
            deployValidationRegistryProxy(address(identityRegistry));
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        bytes32 requestHash = keccak256(bytes("request data"));

        vm.prank(agentOwner);
        validationRegistry.validationRequest(validator, agentId, "ipfs://request", requestHash);
        vm.prank(validator);
        validationRegistry.validationResponse(requestHash, 80, "ipfs://response", keccak256(bytes("r1")), "soft");

        ValidationRegistryUpgradeable implV2 = new ValidationRegistryUpgradeable();
        validationRegistry.upgradeToAndCall(address(implV2), "");

        (address validatorAddress, uint256 storedAgentId, uint8 response, bytes32 responseHash, string memory tag,) =
            validationRegistry.getValidationStatus(requestHash);
        assertEq(validatorAddress, validator);
        assertEq(storedAgentId, agentId);
        assertEq(response, 80);
        assertEq(responseHash, keccak256(bytes("r1")));
        assertEq(tag, "soft");
        assertEq(validationRegistry.getIdentityRegistry(), address(identityRegistry));
    }

    function testFullIntegrationSurvivesAllRegistryUpgrades() public {
        (
            IdentityRegistryUpgradeable identityRegistry,
            ReputationRegistryUpgradeable reputationRegistry,
            ValidationRegistryUpgradeable validationRegistry
        ) = deployAll();

        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        giveFeedback(reputationRegistry, agentId, client, 90, "quality", "fast");
        bytes32 requestHash = keccak256(bytes("request"));

        vm.prank(agentOwner);
        validationRegistry.validationRequest(validator, agentId, "ipfs://request", requestHash);
        vm.prank(validator);
        validationRegistry.validationResponse(requestHash, 100, "ipfs://response", keccak256(bytes("response")), "passed");

        identityRegistry.upgradeToAndCall(address(new IdentityRegistryUpgradeable()), "");
        reputationRegistry.upgradeToAndCall(address(new ReputationRegistryUpgradeable()), "");
        validationRegistry.upgradeToAndCall(address(new ValidationRegistryUpgradeable()), "");

        assertEq(identityRegistry.tokenURI(agentId), "ipfs://agent");
        (int128 value,,,,) = reputationRegistry.readFeedback(agentId, client, 1);
        assertEq(value, 90);
        (,, uint8 response,, string memory tag,) = validationRegistry.getValidationStatus(requestHash);
        assertEq(response, 100);
        assertEq(tag, "passed");
    }

    function testImplementationContractsCannotBeInitializedDirectly() public {
        IdentityRegistryUpgradeable identityImpl = new IdentityRegistryUpgradeable();
        vm.expectRevert();
        identityImpl.initialize();

        ReputationRegistryUpgradeable reputationImpl = new ReputationRegistryUpgradeable();
        vm.expectRevert();
        reputationImpl.initialize(address(0x1234));

        ValidationRegistryUpgradeable validationImpl = new ValidationRegistryUpgradeable();
        vm.expectRevert();
        validationImpl.initialize(address(0x1234));
    }

    function testRegistriesRejectZeroIdentityRegistryInitialization() public {
        TestMinimalUUPS minimalImpl = new TestMinimalUUPS();
        ERC1967Proxy reputationProxy =
            deployProxy(address(minimalImpl), abi.encodeCall(TestMinimalUUPS.initialize, (address(0))));
        ReputationRegistryUpgradeable reputationImpl = new ReputationRegistryUpgradeable();

        vm.expectRevert(bytes("bad identity"));
        TestMinimalUUPS(address(reputationProxy)).upgradeToAndCall(
            address(reputationImpl),
            abi.encodeCall(ReputationRegistryUpgradeable.initialize, (address(0)))
        );

        ERC1967Proxy validationProxy =
            deployProxy(address(minimalImpl), abi.encodeCall(TestMinimalUUPS.initialize, (address(0))));
        ValidationRegistryUpgradeable validationImpl = new ValidationRegistryUpgradeable();

        vm.expectRevert(bytes("bad identity"));
        TestMinimalUUPS(address(validationProxy)).upgradeToAndCall(
            address(validationImpl),
            abi.encodeCall(ValidationRegistryUpgradeable.initialize, (address(0)))
        );
    }

    function testRejectsUpgradeToZeroAddressAndEoa() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();

        vm.expectRevert();
        identityRegistry.upgradeToAndCall(address(0), "");

        vm.expectRevert();
        identityRegistry.upgradeToAndCall(attacker, "");
    }

    function testOwnershipTransferChangesUpgradeAuthority() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        address newOwner = address(0xACE);
        vm.deal(newOwner, 100 ether);

        identityRegistry.transferOwnership(newOwner);
        assertEq(identityRegistry.owner(), newOwner);

        IdentityRegistryUpgradeable implV2 = new IdentityRegistryUpgradeable();

        vm.expectRevert();
        identityRegistry.upgradeToAndCall(address(implV2), "");

        vm.prank(attacker);
        vm.expectRevert();
        identityRegistry.upgradeToAndCall(address(implV2), "");

        vm.prank(newOwner);
        identityRegistry.upgradeToAndCall(address(implV2), "");

        assertEq(identityRegistry.tokenURI(agentId), "ipfs://agent");
        assertEq(identityRegistry.owner(), newOwner);
    }

    function testIdentityComplexStoragePersistsAcrossUpgrade() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256[] memory agents = new uint256[](5);

        for (uint256 i; i < agents.length; i++) {
            agents[i] = registerAgent(identityRegistry, agentOwner, string.concat("ipfs://agent-", vm.toString(i)));
        }

        vm.startPrank(agentOwner);
        identityRegistry.setMetadata(agents[0], "key1", bytes("value1"));
        identityRegistry.setMetadata(agents[0], "key2", bytes("value2"));
        identityRegistry.setMetadata(agents[1], "key1", bytes("different-value"));
        identityRegistry.setMetadata(agents[2], "special", bytes("special-data"));
        vm.stopPrank();

        identityRegistry.upgradeToAndCall(address(new IdentityRegistryUpgradeable()), "");

        for (uint256 i; i < agents.length; i++) {
            assertEq(identityRegistry.tokenURI(agents[i]), string.concat("ipfs://agent-", vm.toString(i)));
        }
        assertEq(identityRegistry.getMetadata(agents[0], "key1"), bytes("value1"));
        assertEq(identityRegistry.getMetadata(agents[0], "key2"), bytes("value2"));
        assertEq(identityRegistry.getMetadata(agents[1], "key1"), bytes("different-value"));
        assertEq(identityRegistry.getMetadata(agents[2], "special"), bytes("special-data"));

        uint256 newAgentId = registerAgent(identityRegistry, agentOwner, "ipfs://post-upgrade");
        vm.prank(agentOwner);
        identityRegistry.setMetadata(newAgentId, "new-key", bytes("new-value"));
        assertEq(identityRegistry.getMetadata(newAgentId, "new-key"), bytes("new-value"));
    }

    function testReputationNestedMappingStoragePersistsAcrossUpgrade() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        ReputationRegistryUpgradeable reputationRegistry =
            deployReputationRegistryProxy(address(identityRegistry));

        uint256 firstAgent = registerAgent(identityRegistry, agentOwner, "ipfs://agent1");
        uint256 secondAgent = registerAgent(identityRegistry, agentOwner, "ipfs://agent2");

        giveFeedback(reputationRegistry, firstAgent, client, 85, "quality", "service");
        giveFeedback(reputationRegistry, firstAgent, client2, 90, "speed", "service");
        giveFeedback(reputationRegistry, secondAgent, client, 75, "quality", "service");
        giveFeedback(reputationRegistry, secondAgent, client2, 95, "reliability", "service");

        reputationRegistry.upgradeToAndCall(address(new ReputationRegistryUpgradeable()), "");

        (int128 feedback1,,,,) = reputationRegistry.readFeedback(firstAgent, client, 1);
        (int128 feedback2,,,,) = reputationRegistry.readFeedback(firstAgent, client2, 1);
        (int128 feedback3,,,,) = reputationRegistry.readFeedback(secondAgent, client, 1);
        (int128 feedback4,,,,) = reputationRegistry.readFeedback(secondAgent, client2, 1);
        assertEq(feedback1, 85);
        assertEq(feedback2, 90);
        assertEq(feedback3, 75);
        assertEq(feedback4, 95);
    }

    function testUpgradeEmitsEip1967UpgradedEvent() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        IdentityRegistryUpgradeable implV2 = new IdentityRegistryUpgradeable();

        vm.expectEmit(true, false, false, true, address(identityRegistry));
        emit Upgraded(address(implV2));
        identityRegistry.upgradeToAndCall(address(implV2), "");
    }
}
