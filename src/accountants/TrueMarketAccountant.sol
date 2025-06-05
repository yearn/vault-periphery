// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.18;

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Governance} from "@periphery/utils/Governance.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";

contract TrueMarketAccountant is Governance {
    using SafeERC20 for ERC20;

    event TokenDistributed(address token, uint256 amount);
    event MaxGainUpdated(uint256 maxGain);
    event MaxLossUpdated(uint256 maxLoss);
    event SplitUpdated(
        uint16 auctionSplit,
        uint16 trueMarketSplit,
        uint16 yearnSplit
    );
    event AddressUpdated(SplitType splitType, address newAddress);

    enum SplitType {
        AUCTION,
        TRUE_MARKET,
        YEARN
    }

    struct TokenSplit {
        address auction;
        uint16 auctionSplit;
        address trueMarketRecipient;
        uint16 trueMarketSplit;
        address yearnRecipient;
        uint16 yearnSplit;
    }

    // Basis points constants
    uint256 public constant MAX_BPS = 10_000;

    // Max gain on a specific report
    uint256 public maxGain;

    // Max loss on a specific report
    uint256 public maxLoss;

    TokenSplit public tokenSplit;

    /// @notice Mapping vault => strategy => flag for one time healthcheck skips.
    mapping(address => mapping(address => bool)) skipHealthCheck;

    constructor(
        address _governance,
        address _auction,
        address _trueMarketRecipient,
        address _yearnRecipient
    ) Governance(_governance) {
        maxGain = 10_000;
        emit MaxGainUpdated(maxGain);
        maxLoss = 0;
        emit MaxLossUpdated(maxLoss);

        tokenSplit = TokenSplit({
            auction: _auction,
            auctionSplit: 8_000,
            trueMarketRecipient: _trueMarketRecipient,
            trueMarketSplit: 1_000,
            yearnRecipient: _yearnRecipient,
            yearnSplit: 1_000
        });

        emit SplitUpdated(
            tokenSplit.auctionSplit,
            tokenSplit.trueMarketSplit,
            tokenSplit.yearnSplit
        );
    }

    function report(
        address strategy,
        uint256 gain,
        uint256 loss
    ) external returns (uint256 totalFees, uint256 refunds) {
        // Retrieve the strategy's params from the vault.
        IVault vault = IVault(msg.sender);
        IVault.StrategyParams memory strategyParams = vault.strategies(
            strategy
        );
        // Only charge performance fees if there is a gain.
        if (gain > 0) {
            // If we are skipping the healthcheck this report
            if (skipHealthCheck[msg.sender][strategy]) {
                // Make sure it is reset for the next one.
                skipHealthCheck[msg.sender][strategy] = false;

                // Setting `maxGain` to 0 will disable the healthcheck on profits.
            } else if (maxGain > 0) {
                require(
                    gain <= (strategyParams.current_debt * (maxGain)) / MAX_BPS,
                    "too much gain"
                );
            }

            // 100% performance fee
            totalFees = gain;

            // Only take fee if there's no loss.
            uint256 supply = vault.totalSupply();
            uint256 assets = vault.totalAssets();
            if (assets < supply) {
                uint256 needed = supply - assets;
                totalFees = gain < needed ? 0 : gain - needed;
            }
        } else {
            // If we are skipping the healthcheck this report
            if (skipHealthCheck[msg.sender][strategy]) {
                // Make sure it is reset for the next one.
                skipHealthCheck[msg.sender][strategy] = false;

                // Setting `maxLoss` to 10_000 will disable the healthcheck on losses.
            } else if (maxLoss < MAX_BPS) {
                require(
                    loss <= (strategyParams.current_debt * (maxLoss)) / MAX_BPS,
                    "too much loss"
                );
            }
        }

        return (totalFees, 0);
    }

    /**
     * @notice Set the max gain for a specific vault
     * @param _maxGain The new max gain
     */
    function setMaxGain(uint256 _maxGain) external onlyGovernance {
        maxGain = _maxGain;
        emit MaxGainUpdated(maxGain);
    }

    /**
     * @notice Set the max loss for a specific vault
     * @param _maxLoss The new max loss
     */
    function setMaxLoss(uint256 _maxLoss) external onlyGovernance {
        require(_maxLoss <= MAX_BPS, "max loss too high");
        maxLoss = _maxLoss;
        emit MaxLossUpdated(maxLoss);
    }

    /**
     * @notice Turn off the health check for a specific `vault` `strategy` combo.
     * @dev This will only last for one report and get automatically turned back on.
     * @param vault Address of the vault.
     * @param strategy Address of the strategy.
     */
    function turnOffHealthCheck(
        address vault,
        address strategy
    ) external virtual onlyGovernance {
        skipHealthCheck[vault][strategy] = true;
    }

    /**
     * @notice Update splits
     * @param _auctionSplit New split for auction
     * @param _trueMarketSplit New split for true market
     * @param _yearnSplit New split for yearn
     */
    function updateSplit(
        uint16 _auctionSplit,
        uint16 _trueMarketSplit,
        uint16 _yearnSplit
    ) external onlyGovernance {
        require(
            _auctionSplit + _trueMarketSplit + _yearnSplit == MAX_BPS,
            "Total split must be 100%"
        );

        tokenSplit.auctionSplit = _auctionSplit;
        tokenSplit.trueMarketSplit = _trueMarketSplit;
        tokenSplit.yearnSplit = _yearnSplit;

        emit SplitUpdated(_auctionSplit, _trueMarketSplit, _yearnSplit);
    }

    /**
     * @notice Set the auction address
     * @param _auction New auction address
     */
    function setAuction(address _auction) external onlyGovernance {
        require(_auction != address(0), "Invalid auction address");
        tokenSplit.auction = _auction;
        emit AddressUpdated(SplitType.AUCTION, _auction);
    }

    /**
     * @notice Set the true market recipient address
     * @param _trueMarketRecipient New true market recipient address
     */
    function setTrueMarketRecipient(
        address _trueMarketRecipient
    ) external onlyGovernance {
        require(
            _trueMarketRecipient != address(0),
            "Invalid true market recipient address"
        );
        tokenSplit.trueMarketRecipient = _trueMarketRecipient;
        emit AddressUpdated(SplitType.TRUE_MARKET, _trueMarketRecipient);
    }

    /**
     * @notice Set the yearn recipient address
     * @param _yearnRecipient New yearn recipient address
     */
    function setYearnRecipient(
        address _yearnRecipient
    ) external onlyGovernance {
        require(
            _yearnRecipient != address(0),
            "Invalid yearn recipient address"
        );
        tokenSplit.yearnRecipient = _yearnRecipient;
        emit AddressUpdated(SplitType.YEARN, _yearnRecipient);
    }

    /**
     * @notice Withdraw all accumulated tokens and kick the auction
     * @param _vault Address of the vault to withdraw from
     */
    function distributeAndKick(address _vault) public {
        address asset = IVault(_vault).asset();

        // If the auction is active, settle it
        Auction auction = Auction(tokenSplit.auction);
        if (auction.isActive(asset)) {
            require(auction.available(asset) == 0, "Auction still available");

            auction.settle(asset);
        }

        IVault(_vault).redeem(
            IVault(_vault).balanceOf(address(this)),
            address(this),
            address(this)
        );

        distribute(asset);

        auction.kick(asset);
    }

    /**
     * @notice Distribute tokens according to configured basis points
     * @param _token Address of the token to distribute
     */
    function distribute(address _token) public {
        TokenSplit memory split = tokenSplit;

        ERC20 token = ERC20(_token);
        uint256 balance = token.balanceOf(address(this)) - 1;

        uint256 amount;
        if (split.auctionSplit > 0) {
            amount = (balance * split.auctionSplit) / MAX_BPS;
            token.safeTransfer(split.auction, amount);
        }
        if (split.trueMarketSplit > 0) {
            amount = (balance * split.trueMarketSplit) / MAX_BPS;
            token.safeTransfer(split.trueMarketRecipient, amount);
        }
        if (split.yearnSplit > 0) {
            amount = (balance * split.yearnSplit) / MAX_BPS;
            token.safeTransfer(split.yearnRecipient, amount);
        }

        emit TokenDistributed(_token, balance);
    }

    function rescue(
        address _token,
        address _to
    ) external onlyGovernance returns (bool success) {
        uint256 balance = ERC20(_token).balanceOf(address(this));
        (success, ) = _token.call(
            abi.encodeCall(ERC20.transfer, (_to, balance))
        );
    }
}
