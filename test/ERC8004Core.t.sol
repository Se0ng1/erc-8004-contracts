// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC8004TestBase.sol";

contract ERC8004CoreTest is ERC8004TestBase {
    function testIdentityRegistersAgentWithTokenURI() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();

        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://QmTest123");

        assertEq(identityRegistry.tokenURI(agentId), "ipfs://QmTest123");
        assertEq(identityRegistry.ownerOf(agentId), agentOwner);
    }

    function testIdentityAutoIncrementsAgentId() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();

        uint256 first = registerAgent(identityRegistry, agentOwner, "ipfs://agent1");
        uint256 second = registerAgent(identityRegistry, agentOwner, "ipfs://agent2");
        uint256 third = registerAgent(identityRegistry, agentOwner, "ipfs://agent3");

        assertEq(second, first + 1);
        assertEq(third, second + 1);
        assertEq(identityRegistry.tokenURI(first), "ipfs://agent1");
        assertEq(identityRegistry.tokenURI(second), "ipfs://agent2");
        assertEq(identityRegistry.tokenURI(third), "ipfs://agent3");
    }

    function testIdentityAllowsAuthorizedUriUpdate() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://initialURI");

        vm.prank(agentOwner);
        identityRegistry.setAgentURI(agentId, "https://example.com/updated-agent.json");

        assertEq(identityRegistry.tokenURI(agentId), "https://example.com/updated-agent.json");
    }

    function testIdentityRejectsUnauthorizedUriUpdate() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://initialURI");

        vm.prank(attacker);
        vm.expectRevert(bytes("Not authorized"));
        identityRegistry.setAgentURI(agentId, "https://example.com/attacker.json");
    }

    function testIdentitySupportsMetadata() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");

        vm.prank(agentOwner);
        identityRegistry.setMetadata(agentId, "name", bytes("TestAgent"));

        assertEq(identityRegistry.getMetadata(agentId, "name"), bytes("TestAgent"));
    }

    function testIdentityRegistersWithMetadataArray() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        IdentityRegistryUpgradeable.MetadataEntry[] memory metadata =
            new IdentityRegistryUpgradeable.MetadataEntry[](2);
        metadata[0] = IdentityRegistryUpgradeable.MetadataEntry("name", bytes("TestAgent"));
        metadata[1] = IdentityRegistryUpgradeable.MetadataEntry("version", bytes("1.0.0"));

        vm.prank(agentOwner);
        uint256 agentId = identityRegistry.register("ipfs://agent", metadata);

        assertEq(identityRegistry.getMetadata(agentId, "name"), bytes("TestAgent"));
        assertEq(identityRegistry.getMetadata(agentId, "version"), bytes("1.0.0"));
        assertEq(identityRegistry.getAgentWallet(agentId), agentOwner);
    }

    function testIdentityBlocksReservedAgentWalletMetadataKey() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");

        vm.prank(agentOwner);
        vm.expectRevert(bytes("reserved key"));
        identityRegistry.setMetadata(agentId, "agentWallet", bytes("0xdeadbeef"));

        IdentityRegistryUpgradeable.MetadataEntry[] memory metadata =
            new IdentityRegistryUpgradeable.MetadataEntry[](1);
        metadata[0] = IdentityRegistryUpgradeable.MetadataEntry("agentWallet", bytes("0xdeadbeef"));

        vm.prank(agentOwner);
        vm.expectRevert(bytes("reserved key"));
        identityRegistry.register("ipfs://agent", metadata);
    }

    function testIdentitySetsAgentWalletWithEoaSignature() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        uint256 deadline = block.timestamp + 240;
        bytes memory signature =
            signAgentWallet(identityRegistry, agentId, newWallet, agentOwner, deadline, newWalletPk);

        vm.prank(agentOwner);
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);

        assertEq(identityRegistry.getAgentWallet(agentId), newWallet);
        assertEq(identityRegistry.getMetadata(agentId, "agentWallet"), abi.encodePacked(newWallet));
    }

    function testIdentityRejectsInvalidAgentWalletSignature() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        uint256 deadline = block.timestamp + 240;
        bytes memory signature =
            signAgentWallet(identityRegistry, agentId, newWallet, agentOwner, deadline, wrongWalletPk);

        vm.prank(agentOwner);
        vm.expectRevert(bytes("invalid wallet sig"));
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);
    }

    function testIdentityRejectsExpiredAgentWalletDeadline() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        uint256 deadline = block.timestamp - 1;
        bytes memory signature =
            signAgentWallet(identityRegistry, agentId, newWallet, agentOwner, deadline, newWalletPk);

        vm.prank(agentOwner);
        vm.expectRevert(bytes("expired"));
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);
    }

    function testIdentityRejectsAgentWalletDeadlineTooFar() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        uint256 deadline = block.timestamp + 600;
        bytes memory signature =
            signAgentWallet(identityRegistry, agentId, newWallet, agentOwner, deadline, newWalletPk);

        vm.prank(agentOwner);
        vm.expectRevert(bytes("deadline too far"));
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);
    }

    function testIdentityRejectsAgentWalletUnauthorizedCaller() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        uint256 deadline = block.timestamp + 240;
        bytes memory signature =
            signAgentWallet(identityRegistry, agentId, newWallet, agentOwner, deadline, newWalletPk);

        vm.prank(attacker);
        vm.expectRevert(bytes("Not authorized"));
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);
    }

    function testIdentityDefaultsAndClearsAgentWalletOnTransfer() public {
        IdentityRegistryUpgradeable identityRegistry = deployIdentityRegistryProxy();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        assertEq(identityRegistry.getAgentWallet(agentId), agentOwner);

        uint256 deadline = block.timestamp + 240;
        bytes memory signature =
            signAgentWallet(identityRegistry, agentId, newWallet, agentOwner, deadline, newWalletPk);

        vm.prank(agentOwner);
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);
        assertEq(identityRegistry.getAgentWallet(agentId), newWallet);

        vm.prank(agentOwner);
        identityRegistry.transferFrom(agentOwner, client, agentId);

        assertEq(identityRegistry.ownerOf(agentId), client);
        assertEq(identityRegistry.getAgentWallet(agentId), address(0));
    }

    function testReputationReturnsIdentityRegistryAddress() public {
        (IdentityRegistryUpgradeable identityRegistry, ReputationRegistryUpgradeable reputationRegistry,) = deployAll();

        assertEq(reputationRegistry.getIdentityRegistry(), address(identityRegistry));
    }

    function testReputationGivesFeedbackAndReadsItBack() public {
        (IdentityRegistryUpgradeable identityRegistry, ReputationRegistryUpgradeable reputationRegistry,) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");

        vm.prank(client);
        reputationRegistry.giveFeedback(
            agentId,
            85,
            0,
            "quality",
            "speed",
            "https://agent.example.com",
            "ipfs://feedback1",
            keccak256(bytes("feedback content"))
        );

        (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked) =
            reputationRegistry.readFeedback(agentId, client, 1);
        assertEq(value, 85);
        assertEq(valueDecimals, 0);
        assertEq(tag1, "quality");
        assertEq(tag2, "speed");
        assertFalse(isRevoked);
    }

    function testReputationRevokesFeedback() public {
        (IdentityRegistryUpgradeable identityRegistry, ReputationRegistryUpgradeable reputationRegistry,) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        giveFeedback(reputationRegistry, agentId, client, 90, "tag1", "tag2");

        vm.prank(client);
        reputationRegistry.revokeFeedback(agentId, 1);

        (,,,, bool isRevoked) = reputationRegistry.readFeedback(agentId, client, 1);
        assertTrue(isRevoked);
    }

    function testReputationAppendsAndCountsResponses() public {
        (IdentityRegistryUpgradeable identityRegistry, ReputationRegistryUpgradeable reputationRegistry,) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        giveFeedback(reputationRegistry, agentId, client, 75, "tag1", "tag2");

        appendResponse(reputationRegistry, agentId, client, 1, responder);
        appendResponse(reputationRegistry, agentId, client, 1, responder2);
        appendResponse(reputationRegistry, agentId, client, 1, responder2);

        assertEq(reputationRegistry.getResponseCount(agentId, client, 1, emptyAddressArray()), 3);
        assertEq(reputationRegistry.getResponseCount(agentId, client, 1, singleAddress(responder)), 1);
        assertEq(reputationRegistry.getResponseCount(agentId, client, 1, singleAddress(responder2)), 2);
    }

    function testReputationTracksMultipleFeedbacksFromSameClient() public {
        (IdentityRegistryUpgradeable identityRegistry, ReputationRegistryUpgradeable reputationRegistry,) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");

        giveFeedback(reputationRegistry, agentId, client, 80, "tag", "one");
        giveFeedback(reputationRegistry, agentId, client, 81, "tag", "two");
        giveFeedback(reputationRegistry, agentId, client, 82, "tag", "three");

        assertEq(reputationRegistry.getLastIndex(agentId, client), 3);
        (int128 first,,,,) = reputationRegistry.readFeedback(agentId, client, 1);
        (int128 second,,,,) = reputationRegistry.readFeedback(agentId, client, 2);
        (int128 third,,,,) = reputationRegistry.readFeedback(agentId, client, 3);
        assertEq(first, 80);
        assertEq(second, 81);
        assertEq(third, 82);
    }

    function testReputationRejectsInvalidFeedbackInputs() public {
        (IdentityRegistryUpgradeable identityRegistry, ReputationRegistryUpgradeable reputationRegistry,) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");

        vm.prank(client);
        vm.expectRevert();
        reputationRegistry.giveFeedback(999, 85, 0, "tag1", "tag2", "", "ipfs://feedback", ZERO_HASH);

        vm.prank(agentOwner);
        vm.expectRevert(bytes("Self-feedback not allowed"));
        reputationRegistry.giveFeedback(agentId, 95, 0, "tag1", "tag2", "", "ipfs://feedback", ZERO_HASH);

        vm.prank(client);
        vm.expectRevert(bytes("too many decimals"));
        reputationRegistry.giveFeedback(agentId, 1, 19, "tag1", "tag2", "", "ipfs://feedback", ZERO_HASH);

        int128 tooLarge = 100000000000000000000000000000000000001;
        vm.prank(client);
        vm.expectRevert(bytes("value too large"));
        reputationRegistry.giveFeedback(agentId, tooLarge, 0, "tag1", "tag2", "", "ipfs://feedback", ZERO_HASH);
    }

    function testReputationCalculatesSummaryAndFiltersTags() public {
        (IdentityRegistryUpgradeable identityRegistry, ReputationRegistryUpgradeable reputationRegistry,) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");

        giveFeedback(reputationRegistry, agentId, client, 80, "service", "fast");
        giveFeedback(reputationRegistry, agentId, client, 90, "service", "fast");
        giveFeedback(reputationRegistry, agentId, client2, 100, "service", "fast");
        giveFeedback(reputationRegistry, agentId, client2, 70, "quality", "slow");

        (uint64 count, int128 summaryValue, uint8 summaryValueDecimals) =
            reputationRegistry.getSummary(agentId, twoAddresses(client, client2), "service", "fast");
        assertEq(count, 3);
        assertEq(summaryValue, 90);
        assertEq(summaryValueDecimals, 0);

        (count, summaryValue,) = reputationRegistry.getSummary(agentId, twoAddresses(client, client2), "", "");
        assertEq(count, 4);
        assertEq(summaryValue, 85);

        (count, summaryValue,) = reputationRegistry.getSummary(agentId, twoAddresses(client, client2), "quality", "");
        assertEq(count, 1);
        assertEq(summaryValue, 70);
    }

    function testReputationReadsAllFeedbackWithFiltersAndRevokedControl() public {
        (IdentityRegistryUpgradeable identityRegistry, ReputationRegistryUpgradeable reputationRegistry,) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");

        giveFeedback(reputationRegistry, agentId, client, 70, "quality", "fast");
        giveFeedback(reputationRegistry, agentId, client, 80, "speed", "slow");
        giveFeedback(reputationRegistry, agentId, client2, 90, "quality", "medium");

        vm.prank(client);
        reputationRegistry.revokeFeedback(agentId, 2);

        (
            address[] memory clients,
            uint64[] memory feedbackIndexes,
            int128[] memory values,
            ,
            string[] memory tag1s,
            ,
            bool[] memory revokedStatuses
        ) = reputationRegistry.readAllFeedback(agentId, twoAddresses(client, client2), "", "", false);

        assertEq(clients.length, 2);
        assertEq(feedbackIndexes[0], 1);
        assertEq(feedbackIndexes[1], 1);
        assertEq(values[0], 70);
        assertEq(values[1], 90);
        assertEq(tag1s[0], "quality");
        assertEq(tag1s[1], "quality");
        assertFalse(revokedStatuses[0]);
        assertFalse(revokedStatuses[1]);

        (,, values,,,, revokedStatuses) =
            reputationRegistry.readAllFeedback(agentId, singleAddress(client), "", "", true);
        assertEq(values.length, 2);
        assertTrue(revokedStatuses[1]);
    }

    function testReputationCountsResponsesAcrossScopes() public {
        (IdentityRegistryUpgradeable identityRegistry, ReputationRegistryUpgradeable reputationRegistry,) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");

        giveFeedback(reputationRegistry, agentId, client, 80, "", "");
        giveFeedback(reputationRegistry, agentId, client, 90, "", "");
        giveFeedback(reputationRegistry, agentId, client2, 95, "", "");

        appendResponse(reputationRegistry, agentId, client, 1, responder);
        appendResponse(reputationRegistry, agentId, client, 2, responder2);
        appendResponse(reputationRegistry, agentId, client2, 1, responder);

        assertEq(reputationRegistry.getResponseCount(agentId, address(0), 0, emptyAddressArray()), 3);
        assertEq(reputationRegistry.getResponseCount(agentId, client, 0, emptyAddressArray()), 2);
        assertEq(reputationRegistry.getResponseCount(agentId, client, 1, emptyAddressArray()), 1);
        assertEq(reputationRegistry.getResponseCount(agentId, address(0), 0, singleAddress(responder)), 2);
    }

    function testReputationTracksClientsAndRejectsOutOfBoundsReads() public {
        (IdentityRegistryUpgradeable identityRegistry, ReputationRegistryUpgradeable reputationRegistry,) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");

        giveFeedback(reputationRegistry, agentId, client, 80, "", "");
        giveFeedback(reputationRegistry, agentId, client2, 90, "", "");
        giveFeedback(reputationRegistry, agentId, client3, 95, "", "");

        address[] memory clients = reputationRegistry.getClients(agentId);
        assertEq(clients.length, 3);
        assertEq(clients[0], client);
        assertEq(clients[1], client2);
        assertEq(clients[2], client3);
        assertEq(reputationRegistry.getLastIndex(agentId, attacker), 0);

        vm.expectRevert(bytes("index out of bounds"));
        reputationRegistry.readFeedback(agentId, client, 2);
    }

    function testValidationReturnsIdentityRegistryAddress() public {
        (IdentityRegistryUpgradeable identityRegistry,, ValidationRegistryUpgradeable validationRegistry) = deployAll();

        assertEq(validationRegistry.getIdentityRegistry(), address(identityRegistry));
    }

    function testValidationCreatesRequestAndResponse() public {
        (IdentityRegistryUpgradeable identityRegistry,, ValidationRegistryUpgradeable validationRegistry) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        bytes32 requestHash = keccak256(bytes("request data"));

        vm.prank(agentOwner);
        validationRegistry.validationRequest(validator, agentId, "ipfs://validation-request", requestHash);

        (address validatorAddress, uint256 storedAgentId, uint8 response, bytes32 responseHash, string memory tag,) =
            validationRegistry.getValidationStatus(requestHash);
        assertEq(validatorAddress, validator);
        assertEq(storedAgentId, agentId);
        assertEq(response, 0);
        assertEq(responseHash, ZERO_HASH);
        assertEq(tag, "");

        vm.prank(validator);
        validationRegistry.validationResponse(
            requestHash,
            100,
            "ipfs://validation-response",
            keccak256(bytes("response data")),
            "passed"
        );

        (validatorAddress, storedAgentId, response, responseHash, tag,) =
            validationRegistry.getValidationStatus(requestHash);
        assertEq(validatorAddress, validator);
        assertEq(storedAgentId, agentId);
        assertEq(response, 100);
        assertEq(responseHash, keccak256(bytes("response data")));
        assertEq(tag, "passed");
    }

    function testValidationRejectsDuplicateUnauthorizedAndInvalidResponses() public {
        (IdentityRegistryUpgradeable identityRegistry,, ValidationRegistryUpgradeable validationRegistry) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        bytes32 requestHash = keccak256(bytes("request data"));

        vm.prank(agentOwner);
        validationRegistry.validationRequest(validator, agentId, "ipfs://request", requestHash);

        vm.prank(agentOwner);
        vm.expectRevert(bytes("exists"));
        validationRegistry.validationRequest(validator, agentId, "ipfs://request", requestHash);

        vm.prank(attacker);
        vm.expectRevert(bytes("not validator"));
        validationRegistry.validationResponse(requestHash, 100, "ipfs://fake", ZERO_HASH, "tag");

        vm.prank(validator);
        vm.expectRevert(bytes("resp>100"));
        validationRegistry.validationResponse(requestHash, 101, "ipfs://resp", ZERO_HASH, "tag");
    }

    function testValidationOnlyOwnerOrOperatorCanRequest() public {
        (IdentityRegistryUpgradeable identityRegistry,, ValidationRegistryUpgradeable validationRegistry) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");

        vm.prank(attacker);
        vm.expectRevert(bytes("Not authorized"));
        validationRegistry.validationRequest(validator, agentId, "ipfs://request", keccak256(bytes("request")));

        vm.prank(agentOwner);
        identityRegistry.setApprovalForAll(client, true);

        vm.prank(client);
        validationRegistry.validationRequest(validator, agentId, "ipfs://request", keccak256(bytes("request")));
    }

    function testValidationSummariesAndTracking() public {
        (IdentityRegistryUpgradeable identityRegistry,, ValidationRegistryUpgradeable validationRegistry) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        bytes32 firstRequest = keccak256(bytes("request1"));
        bytes32 secondRequest = keccak256(bytes("request2"));

        vm.prank(agentOwner);
        validationRegistry.validationRequest(validator, agentId, "ipfs://req1", firstRequest);
        vm.prank(agentOwner);
        validationRegistry.validationRequest(validator2, agentId, "ipfs://req2", secondRequest);

        vm.prank(validator);
        validationRegistry.validationResponse(firstRequest, 80, "ipfs://resp1", keccak256(bytes("r1")), "quality");
        vm.prank(validator2);
        validationRegistry.validationResponse(secondRequest, 100, "ipfs://resp2", keccak256(bytes("r2")), "quality");

        (uint64 count, uint8 avgResponse) =
            validationRegistry.getSummary(agentId, emptyAddressArray(), "quality");
        assertEq(count, 2);
        assertEq(avgResponse, 90);

        (count, avgResponse) = validationRegistry.getSummary(agentId, singleAddress(validator), "");
        assertEq(count, 1);
        assertEq(avgResponse, 80);

        bytes32[] memory agentValidations = validationRegistry.getAgentValidations(agentId);
        assertEq(agentValidations.length, 2);
        assertEq(agentValidations[0], firstRequest);
        assertEq(agentValidations[1], secondRequest);

        bytes32[] memory validatorRequests = validationRegistry.getValidatorRequests(validator);
        assertEq(validatorRequests.length, 1);
        assertEq(validatorRequests[0], firstRequest);
    }

    function testValidationAllowsResponseUpdatesAndBoundaryValues() public {
        (IdentityRegistryUpgradeable identityRegistry,, ValidationRegistryUpgradeable validationRegistry) = deployAll();
        uint256 agentId = registerAgent(identityRegistry, agentOwner, "ipfs://agent");
        bytes32 requestHash = keccak256(bytes("request data"));

        vm.prank(agentOwner);
        validationRegistry.validationRequest(validator, agentId, "ipfs://request", requestHash);

        vm.prank(validator);
        validationRegistry.validationResponse(requestHash, 0, "ipfs://failed", keccak256(bytes("fail")), "failed");
        (,, uint8 response,, string memory tag,) = validationRegistry.getValidationStatus(requestHash);
        assertEq(response, 0);
        assertEq(tag, "failed");

        vm.prank(validator);
        validationRegistry.validationResponse(requestHash, 67, "ipfs://partial", keccak256(bytes("partial")), "partial");
        (,, response,, tag,) = validationRegistry.getValidationStatus(requestHash);
        assertEq(response, 67);
        assertEq(tag, "partial");
    }
}
