// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../contracts/IdentityRegistryUpgradeable.sol";
import "../contracts/ReputationRegistryUpgradeable.sol";
import "../contracts/ValidationRegistryUpgradeable.sol";

contract ERC8004LocalTest is Test {
    address internal constant IDENTITY_REGISTRY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address internal constant REPUTATION_REGISTRY = 0x8004B663056A597Dffe9eCcC1965A193B7388713;
    address internal constant VALIDATION_REGISTRY = 0x8004Cb1BF31DAf7788923b405b754f57acEB4272;

    function setUp() public {
        vm.skip(block.chainid != 31337 || IDENTITY_REGISTRY.code.length == 0);
    }

    function testLocalDeploymentWiring() public {
        assertGt(IDENTITY_REGISTRY.code.length, 0);
        assertGt(REPUTATION_REGISTRY.code.length, 0);
        assertGt(VALIDATION_REGISTRY.code.length, 0);
        assertEq(IdentityRegistryUpgradeable(IDENTITY_REGISTRY).getVersion(), "2.0.0");
        assertEq(ReputationRegistryUpgradeable(REPUTATION_REGISTRY).getIdentityRegistry(), IDENTITY_REGISTRY);
        assertEq(ValidationRegistryUpgradeable(VALIDATION_REGISTRY).getIdentityRegistry(), IDENTITY_REGISTRY);
    }
}
