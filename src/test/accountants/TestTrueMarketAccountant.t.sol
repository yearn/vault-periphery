pragma solidity ^0.8.18;

import {Setup, IVault, MockStrategy, MockERC20} from "../utils/Setup.sol";
import {TrueMarketAccountant} from "src/accountants/TrueMarketAccountant.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";

contract TestTrueMarketAccountant is Setup {
    IVault public vault;
    MockStrategy public strategy;
    TrueMarketAccountant public trueMarketAccountant;

    address public auction;
    address public trueMarketRecipient;
    address public yearnRecipient;

    function setUp() public virtual override {
        super.setUp();
        vault = createVault(
            address(asset),
            daddy,
            MAX_INT,
            WEEK,
            "Test Vault",
            "tvTEST"
        );
        strategy = createStrategy(address(asset));

        // Create test addresses for recipients
        auction = makeAddr("auction");
        trueMarketRecipient = makeAddr("trueMarketRecipient");
        yearnRecipient = makeAddr("yearnRecipient");

        // Deploy TrueMarketAccountant
        trueMarketAccountant = new TrueMarketAccountant(
            daddy,
            auction,
            trueMarketRecipient,
            yearnRecipient
        );
    }

    function test_setup() public {
        assertEq(trueMarketAccountant.governance(), daddy);

        // Check initial splits
        (
            address _auction,
            uint16 auctionSplit,
            address _trueMarketRecipient,
            uint16 trueMarketSplit,
            address _yearnRecipient,
            uint16 yearnSplit
        ) = trueMarketAccountant.tokenSplit();

        assertEq(_auction, auction);
        assertEq(auctionSplit, 8_000); // 80%
        assertEq(_trueMarketRecipient, trueMarketRecipient);
        assertEq(trueMarketSplit, 1_000); // 10%
        assertEq(_yearnRecipient, yearnRecipient);
        assertEq(yearnSplit, 1_000); // 10%
    }

    function test_distribute_tokens() public {
        uint256 amount = 1e18;
        deal(address(asset), address(trueMarketAccountant), amount);

        // Distribute tokens
        trueMarketAccountant.distribute(address(asset));

        amount -= 1;

        // Check balances after distribution
        assertEq(asset.balanceOf(auction), (amount * 8_000) / 10_000); // 80%
        assertEq(
            asset.balanceOf(trueMarketRecipient),
            (amount * 1_000) / 10_000
        ); // 10%
        assertEq(asset.balanceOf(yearnRecipient), (amount * 1_000) / 10_000); // 10%
    }

    function test_update_split() public {
        uint16 newAuctionSplit = 5_000; // 50%
        uint16 newTrueMarketSplit = 3_000; // 30%
        uint16 newYearnSplit = 2_000; // 20%

        vm.prank(daddy);
        trueMarketAccountant.updateSplit(
            newAuctionSplit,
            newTrueMarketSplit,
            newYearnSplit
        );

        (
            ,
            uint16 auctionSplit,
            ,
            uint16 trueMarketSplit,
            ,
            uint16 yearnSplit
        ) = trueMarketAccountant.tokenSplit();

        assertEq(auctionSplit, newAuctionSplit);
        assertEq(trueMarketSplit, newTrueMarketSplit);
        assertEq(yearnSplit, newYearnSplit);
    }

    function test_update_split_reverts_if_not_100_percent() public {
        uint16 newAuctionSplit = 5_000; // 50%
        uint16 newTrueMarketSplit = 3_000; // 30%
        uint16 newYearnSplit = 1_000; // 10% (total 90%)

        vm.prank(daddy);
        vm.expectRevert("Total split must be 100%");
        trueMarketAccountant.updateSplit(
            newAuctionSplit,
            newTrueMarketSplit,
            newYearnSplit
        );
    }

    function test_update_addresses() public {
        address newAuction = makeAddr("newAuction");
        address newTrueMarketRecipient = makeAddr("newTrueMarketRecipient");
        address newYearnRecipient = makeAddr("newYearnRecipient");

        vm.prank(daddy);
        trueMarketAccountant.setAuction(newAuction);

        vm.prank(daddy);
        trueMarketAccountant.setTrueMarketRecipient(newTrueMarketRecipient);

        vm.prank(daddy);
        trueMarketAccountant.setYearnRecipient(newYearnRecipient);

        (
            address _auction,
            ,
            address _trueMarketRecipient,
            ,
            address _yearnRecipient,

        ) = trueMarketAccountant.tokenSplit();

        assertEq(_auction, newAuction);
        assertEq(_trueMarketRecipient, newTrueMarketRecipient);
        assertEq(_yearnRecipient, newYearnRecipient);
    }

    function test_update_addresses_reverts_on_zero_address() public {
        vm.prank(daddy);
        vm.expectRevert("Invalid auction address");
        trueMarketAccountant.setAuction(address(0));

        vm.prank(daddy);
        vm.expectRevert("Invalid true market recipient address");
        trueMarketAccountant.setTrueMarketRecipient(address(0));

        vm.prank(daddy);
        vm.expectRevert("Invalid yearn recipient address");
        trueMarketAccountant.setYearnRecipient(address(0));
    }

    function test_distribute_with_small_amount() public {
        uint256 amount = 1; // Very small amount
        deal(address(asset), address(trueMarketAccountant), amount);

        // Distribute tokens
        trueMarketAccountant.distribute(address(asset));

        // Check balances after distribution
        assertEq(asset.balanceOf(auction), 0); // Should round down to 0
        assertEq(asset.balanceOf(trueMarketRecipient), 0); // Should round down to 0
        assertEq(asset.balanceOf(yearnRecipient), 0); // Should round down to 0
    }

    function test_distribute_and_kick() public {
        uint256 amount = 1e18;

        depositIntoVault(vault, address(trueMarketAccountant), amount);

        // Mock the auction contract
        auction = address(new Auction());
        MockERC20 want = new MockERC20();
        Auction(auction).initialize(
            address(want),
            address(user),
            address(this),
            1 days,
            100000
        );

        Auction(auction).enable(address(asset));

        vm.prank(daddy);
        trueMarketAccountant.setAuction(auction);

        skip(1 days);

        // Expect the kick call
        vm.expectCall(
            auction,
            abi.encodeWithSelector(Auction.kick.selector, address(asset))
        );

        // Call distributeAndKick
        trueMarketAccountant.distributeAndKick(address(vault));

        amount -= 1;
        assertEq(asset.balanceOf(auction), (amount * 8_000) / 10_000);
        assertEq(
            asset.balanceOf(trueMarketRecipient),
            (amount * 1_000) / 10_000
        );
        assertEq(asset.balanceOf(yearnRecipient), (amount * 1_000) / 10_000);
    }

    function test_distribute_and_kick_with_active_auction() public {
        uint256 amount = 1e18;

        depositIntoVault(vault, address(trueMarketAccountant), amount);

        // Mock the auction contract
        auction = address(new Auction());
        MockERC20 want = new MockERC20();
        Auction(auction).initialize(
            address(want),
            address(user),
            address(this),
            1 days,
            100000
        );
        Auction(auction).enable(address(asset));

        vm.prank(daddy);
        trueMarketAccountant.setAuction(auction);

        skip(1 days);

        vm.mockCall(
            auction,
            abi.encodeWithSelector(Auction.isActive.selector, address(asset)),
            abi.encode(true)
        );

        vm.mockCall(
            auction,
            abi.encodeWithSelector(Auction.available.selector, address(asset)),
            abi.encode(0)
        );

        vm.mockCall(
            auction,
            abi.encodeWithSelector(Auction.settle.selector, address(asset)),
            abi.encode()
        );

        // Expect the settle and kick calls
        vm.expectCall(
            auction,
            abi.encodeWithSelector(Auction.settle.selector, address(asset))
        );

        vm.expectCall(
            auction,
            abi.encodeWithSelector(Auction.kick.selector, address(asset))
        );

        // Call distributeAndKick
        trueMarketAccountant.distributeAndKick(address(vault));
    }

    function test_distribute_and_kick_reverts_with_available_auction() public {
        uint256 amount = 1e18;

        depositIntoVault(vault, address(trueMarketAccountant), amount);

        // Mock the auction contract
        auction = address(new Auction());
        MockERC20 want = new MockERC20();
        Auction(auction).initialize(
            address(want),
            address(user),
            address(this),
            1 days,
            100000
        );

        vm.prank(daddy);
        trueMarketAccountant.setAuction(auction);

        skip(1 days);

        Auction(auction).enable(address(asset));

        deal(address(asset), auction, amount);

        Auction(auction).kick(address(asset));

        // Call distributeAndKick should revert
        vm.expectRevert("Auction still available");
        trueMarketAccountant.distributeAndKick(address(vault));
    }
}
