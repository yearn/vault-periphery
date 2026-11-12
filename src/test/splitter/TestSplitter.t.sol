// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup, ISplitter, ISplitterFactory, IVault, Accountant, MockTokenized} from "../utils/Setup.sol";


contract TestSplitter is Setup {
    event UpdateManagerRecipient(address indexed newManagerRecipient);
    event UpdateSplitee(address indexed newSplitee);
    event UpdateSplit(uint256 newSplit);
    event UpdateMaxLoss(uint256 newMaxLoss);
    event UpdateAuction(address indexed newAuction);

    IVault public vault;
    MockTokenized public mockTokenized;
    function setUp() public override {
        super.setUp();
        (splitterFactory, splitter) = setupSplitter();
        vault = createVault(address(asset), daddy, MAX_INT, WEEK, "", "VV3");
        mockTokenized = deployMockTokenized("MockTokenized", 1000);
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
