// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, ISplitter, ISplitterFactory, IVault, Accountant, MockTokenized} from "../utils/Setup.sol";

import {Dumper} from "../../splitter/Dumper.sol";

interface IAuction {
    function kick(address token) external;
    function enable(address token) external;
}

contract TestSplitter is Setup {
    event UpdateManagerRecipient(address indexed newManagerRecipient);
    event UpdateSplitee(address indexed newSplitee);
    event UpdateSplit(uint256 newSplit);
    event UpdateMaxLoss(uint256 newMaxLoss);
    event UpdateAuction(address indexed newAuction);

    IVault public vault;
    MockTokenized public mockTokenized;

    ISplitter public protocolFeeRecipient = ISplitter(0x8E8EE92Dc7A146982003Abad26e4bC4e98776F69);

    Dumper public dumper;

    address public splitToken = 0x182863131F9a4630fF9E27830d945B1413e347E8;

    address public managementRecipient;

    address public three = 0x33333333D5eFb92f19a5F94a43456b3cec2797AE;

    IAuction public auction = IAuction(0x42AeF4830b763fD8d10CD67f03D63e7250A1ea58);

    function setUp() public override {
        super.setUp();
        (splitterFactory, splitter) = setupSplitter();
        vault = createVault(address(asset), daddy, MAX_INT, WEEK, "", "VV3");
        mockTokenized = deployMockTokenized("MockTokenized", 1000);
    }

    function test_dumper() public {
        dumper = new Dumper(management, address(protocolFeeRecipient), splitToken);

        daddy = protocolFeeRecipient.manager();
        managementRecipient = protocolFeeRecipient.managerRecipient();

        vm.prank(daddy);
        protocolFeeRecipient.setMangerRecipient(managementRecipient);

        vm.prank(protocolFeeRecipient.splitee());
        protocolFeeRecipient.setSplitee(address(dumper));

        vm.prank(daddy);
        protocolFeeRecipient.setSplit(10_000);

        vm.prank(daddy);
        protocolFeeRecipient.setAuction(address(auction));

        vm.prank(management);
        dumper.setAllowed(user, true);

        vm.prank(three);
        auction.enable(0x028eC7330ff87667b6dfb0D94b954c820195336c);

        vm.prank(user);
        dumper.dumpToken(0x028eC7330ff87667b6dfb0D94b954c820195336c);

        address[] memory tokens = new address[](2);
        tokens[0] = 0xF0825750791A4444c5E70743270DcfA8Bb38f959;
        tokens[1] = 0x6acEDA98725505737c0F00a3dA0d047304052948;

        vm.startPrank(three);
        auction.enable(tokens[0]);
        auction.enable(tokens[1]);
        vm.stopPrank();

        vm.prank(user);
        dumper.dumpTokens(tokens);

        vm.prank(user);
        dumper.unwrapVault(0x23eE3D14F09946A084350CC6A7153fc6eb918817);

        address[] memory vaults = new address[](3);
        vaults[0] = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;
        vaults[1] = 0x4cE9c93513DfF543Bc392870d57dF8C04e89Ba0a;
        vaults[2] = 0x206db0A0Af10Bec57784045e089A418771D20227;

        vm.prank(user);
        dumper.unwrapVaults(vaults);

        vm.prank(user);
        dumper.distribute();

        assertTrue(false);
    }

    function test_split_setup() public {
        assertNotEq(address(splitterFactory.ORIGINAL()), address(0));
        assertNotEq(address(splitter), address(0));
        assertEq(splitter.manager(), daddy);
        assertEq(splitter.managerRecipient(), management);
        assertEq(splitter.splitee(), brain);
        assertEq(splitter.split(), 5000);
        assertEq(splitter.maxLoss(), 1);
        assertEq(splitter.auction(), address(0));
    }

    function test_unwrap(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        asset.mint(user, _amount);

        uint256 amount = _amount / 3;

        MockTokenized secondStrategy = deployMockTokenized(
            "MockTokenized",
            1000
        );

        vm.startPrank(user);
        asset.approve(address(vault), amount);
        asset.approve(address(mockTokenized), amount);
        asset.approve(address(secondStrategy), amount);

        vault.deposit(amount, address(splitter));
        mockTokenized.deposit(amount, address(splitter));
        secondStrategy.deposit(amount, address(splitter));
        vm.stopPrank();

        assertEq(vault.balanceOf(address(splitter)), amount);
        assertEq(mockTokenized.balanceOf(address(splitter)), amount);
        assertEq(secondStrategy.balanceOf(address(splitter)), amount);
        assertEq(asset.balanceOf(address(splitter)), 0);

        vm.prank(user);
        vm.expectRevert("!allowed");
        splitter.unwrapVault(address(secondStrategy));

        vm.prank(daddy);
        splitter.unwrapVault(address(secondStrategy));

        assertEq(vault.balanceOf(address(splitter)), amount);
        assertEq(mockTokenized.balanceOf(address(splitter)), amount);
        assertEq(secondStrategy.balanceOf(address(splitter)), 0);
        assertEq(asset.balanceOf(address(splitter)), amount);

        address[] memory vaults = new address[](2);
        vaults[0] = address(vault);
        vaults[1] = address(mockTokenized);

        vm.prank(user);
        vm.expectRevert("!allowed");
        splitter.unwrapVaults(vaults);

        vm.prank(daddy);
        splitter.unwrapVaults(vaults);

        assertEq(vault.balanceOf(address(splitter)), 0);
        assertEq(mockTokenized.balanceOf(address(splitter)), 0);
        assertEq(secondStrategy.balanceOf(address(splitter)), 0);
        assertEq(asset.balanceOf(address(splitter)), amount * 3);
    }

    function test_distribute(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        asset.mint(user, _amount);

        uint256 amount = _amount / 4;

        MockTokenized secondStrategy = deployMockTokenized(
            "MockTokenized",
            1000
        );

        vm.startPrank(user);
        asset.approve(address(vault), amount);
        asset.approve(address(mockTokenized), amount);
        asset.approve(address(secondStrategy), amount);

        vault.deposit(amount, address(splitter));
        mockTokenized.deposit(amount, address(splitter));
        secondStrategy.deposit(amount, address(splitter));
        vm.stopPrank();

        assertEq(vault.balanceOf(address(splitter)), amount);
        assertEq(vault.balanceOf(management), 0);
        assertEq(vault.balanceOf(brain), 0);

        assertEq(mockTokenized.balanceOf(address(splitter)), amount);
        assertEq(mockTokenized.balanceOf(management), 0);
        assertEq(mockTokenized.balanceOf(brain), 0);

        assertEq(secondStrategy.balanceOf(address(splitter)), amount);
        assertEq(secondStrategy.balanceOf(management), 0);
        assertEq(secondStrategy.balanceOf(brain), 0);

        vm.prank(user);
        vm.expectRevert("!allowed");
        splitter.distributeToken(address(secondStrategy));

        vm.prank(daddy);
        splitter.distributeToken(address(secondStrategy));

        uint256 managerShare = amount / 2;
        uint256 spliteeShare = amount - managerShare;

        assertEq(secondStrategy.balanceOf(address(splitter)), 0);
        assertEq(secondStrategy.balanceOf(management), managerShare);
        assertEq(secondStrategy.balanceOf(brain), spliteeShare);

        address[] memory vaults = new address[](2);
        vaults[0] = address(vault);
        vaults[1] = address(mockTokenized);

        vm.prank(user);
        vm.expectRevert("!allowed");
        splitter.distributeTokens(vaults);

        vm.prank(daddy);
        splitter.distributeTokens(vaults);

        assertEq(vault.balanceOf(address(splitter)), 0);
        assertEq(vault.balanceOf(management), managerShare);
        assertEq(vault.balanceOf(brain), spliteeShare);

        assertEq(mockTokenized.balanceOf(address(splitter)), 0);
        assertEq(mockTokenized.balanceOf(management), managerShare);
        assertEq(mockTokenized.balanceOf(brain), spliteeShare);
    }

    function test_auction(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        asset.mint(user, _amount);

        uint256 amount = _amount / 4;

        MockTokenized secondStrategy = deployMockTokenized(
            "MockTokenized",
            1000
        );

        vm.startPrank(user);
        asset.approve(address(vault), amount);
        asset.approve(address(mockTokenized), amount);
        asset.approve(address(secondStrategy), amount);

        vault.deposit(amount, address(splitter));
        mockTokenized.deposit(amount, address(splitter));
        secondStrategy.deposit(amount, address(splitter));
        vm.stopPrank();

        assertEq(vault.balanceOf(address(splitter)), amount);
        assertEq(vault.balanceOf(user), 0);

        assertEq(mockTokenized.balanceOf(address(splitter)), amount);
        assertEq(mockTokenized.balanceOf(user), 0);

        assertEq(secondStrategy.balanceOf(address(splitter)), amount);
        assertEq(secondStrategy.balanceOf(user), 0);

        vm.prank(user);
        vm.expectRevert("!allowed");
        splitter.fundAuction(address(secondStrategy));

        vm.prank(daddy);
        vm.expectRevert();
        splitter.fundAuction(address(secondStrategy));

        vm.prank(daddy);
        splitter.setAuction(user);

        vm.prank(daddy);
        splitter.fundAuction(address(secondStrategy));

        assertEq(secondStrategy.balanceOf(address(splitter)), 0);
        assertEq(secondStrategy.balanceOf(user), amount);

        address[] memory vaults = new address[](2);
        vaults[0] = address(vault);
        vaults[1] = address(mockTokenized);

        vm.prank(user);
        vm.expectRevert("!allowed");
        splitter.fundAuctions(vaults);

        vm.prank(daddy);
        splitter.fundAuctions(vaults);

        assertEq(vault.balanceOf(address(splitter)), 0);
        assertEq(vault.balanceOf(user), amount);

        assertEq(mockTokenized.balanceOf(address(splitter)), 0);
        assertEq(mockTokenized.balanceOf(user), amount);
    }

    function test_setters() public {
        address newRecipient = user;

        assertEq(splitter.managerRecipient(), management);

        vm.prank(brain);
        vm.expectRevert("!manager");
        splitter.setManagerRecipient(newRecipient);

        assertEq(splitter.managerRecipient(), management);

        vm.prank(daddy);
        vm.expectEmit(true, false, false, true);
        emit UpdateManagerRecipient(newRecipient);
        splitter.setManagerRecipient(newRecipient);

        assertEq(splitter.managerRecipient(), newRecipient);

        address newSplitee = user;

        assertEq(splitter.splitee(), brain);

        vm.prank(daddy);
        vm.expectRevert("!splitee");
        splitter.setSplitee(newSplitee);

        assertEq(splitter.splitee(), brain);

        vm.prank(brain);
        vm.expectEmit(true, false, false, true);
        emit UpdateSplitee(newSplitee);
        splitter.setSplitee(newSplitee);

        assertEq(splitter.splitee(), newSplitee);

        uint256 newSplit = 123;

        assertEq(splitter.split(), 5000);

        vm.prank(brain);
        vm.expectRevert("!manager");
        splitter.setSplit(newSplit);

        assertEq(splitter.split(), 5000);

        vm.prank(daddy);
        vm.expectEmit(false, false, false, true);
        emit UpdateSplit(newSplit);
        splitter.setSplit(newSplit);

        assertEq(splitter.split(), newSplit);

        uint256 newMaxLoss = 123;

        assertEq(splitter.maxLoss(), 1);

        vm.prank(brain);
        vm.expectRevert("!manager");
        splitter.setMaxLoss(newMaxLoss);

        assertEq(splitter.maxLoss(), 1);

        vm.prank(daddy);
        vm.expectEmit(false, false, false, true);
        emit UpdateMaxLoss(newMaxLoss);
        splitter.setMaxLoss(newMaxLoss);

        assertEq(splitter.maxLoss(), newMaxLoss);

        address newAuction = user;

        assertEq(splitter.auction(), address(0));

        vm.prank(brain);
        vm.expectRevert("!manager");
        splitter.setAuction(newAuction);

        assertEq(splitter.auction(), address(0));

        vm.prank(daddy);
        vm.expectEmit(true, false, false, true);
        emit UpdateAuction(newAuction);
        splitter.setAuction(newAuction);

        assertEq(splitter.auction(), newAuction);
    }
}
