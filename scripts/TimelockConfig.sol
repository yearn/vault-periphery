// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/// @title Timelock Deployment Configuration
/// @notice Chain-specific configuration for timelock deployment
library TimelockConfig {
    struct ChainConfig {
        // TimelockController settings
        uint256 minDelay;
        // YearnRoleManager position holders
        address daddy;
        address brain;
        address security;
        address keeper;
        // Existing role manager (address(0) if needs deployment)
        address existingRoleManager;
    }

    /// @notice Registry address - same on all chains
    address public constant REGISTRY =
        0xd40ecF29e001c76Dcc4cC0D9cd50520CE845B038;

    /// @notice Get configuration for the current chain
    function getConfig() internal view returns (ChainConfig memory config) {
        uint256 chainId = block.chainid;

        if (chainId == 1) {
            // Ethereum Mainnet
            config = ChainConfig({
                minDelay: 1 days,
                daddy: 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52,
                brain: 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7,
                security: 0xe5e2Baf96198c56380dDD5E992D7d1ADa0e989c0,
                keeper: 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E,
                existingRoleManager: 0xb3bd6B2E61753C311EFbCF0111f75D29706D9a41 // Set to address if already deployed
            });
        } else if (chainId == 137) {
            // Polygon
            config = ChainConfig({
                minDelay: 1 days,
                daddy: address(0xC4ad0000E223E398DC329235e6C497Db5470B626), // TODO: Set Polygon addresses
                brain: address(0x16388000546eDed4D476bd2A4A374B5a16125Bc1),
                security: address(0),
                keeper: address(0x3A95F75f0Ea2FD60b31E7c6180C7B5fC9865492F),
                existingRoleManager: address(0)
            });
        } else if (chainId == 42161) {
            // Arbitrum One
            config = ChainConfig({
                minDelay: 1 days,
                daddy: address(0xb6bc033D34733329971B938fEf32faD7e98E56aD), // TODO: Set Arbitrum addresses
                brain: address(0x6346282DB8323A54E840c6C772B4399C9c655C0d),
                security: address(0xfd99a19Fcf577Be92fDAB4ef162c1644BB056885),
                keeper: address(0xE0D19f6b240659da8E87ABbB73446E7B4346Baee),
                existingRoleManager: address(
                    0x3BF72024420bdc4D7cA6a8b6211829476D6685b1
                )
            });
        } else if (chainId == 10) {
            // Optimism
            config = ChainConfig({
                minDelay: 1 days,
                daddy: address(0xF5d9D6133b698cE29567a90Ab35CfB874204B3A7), // TODO: Set Optimism addresses
                brain: address(0xea3a15df68fCdBE44Fdb0DB675B2b3A14a148b26),
                security: address(0),
                keeper: address(0x21BB199ab3be9E65B1E60b51ea9b0FE9a96a480a),
                existingRoleManager: address(0)
            });
        } else if (chainId == 8453) {
            // Base
            config = ChainConfig({
                minDelay: 1 days,
                daddy: address(0xbfAABa9F56A39B814281D68d2Ad949e88D06b02E), // TODO: Set Base addresses
                brain: address(0x01fE3347316b2223961B20689C65eaeA71348e93),
                security: address(0xFEaE2F855250c36A77b8C68dB07C4dD9711fE36F),
                keeper: address(0x46679Ba8ce6473a9E0867c52b5A50ff97579740E),
                existingRoleManager: address(
                    0xea3481244024E2321cc13AcAa80df1050f1fD456
                )
            });
        } else if (chainId == 100) {
            // Gnosis Chain
            config = ChainConfig({
                minDelay: 1 days,
                daddy: address(0), // TODO: Set Gnosis addresses
                brain: address(0xFB4464a18d18f3FF439680BBbCE659dB2806A187),
                security: address(0),
                keeper: address(0),
                existingRoleManager: address(0)
            });
        } else if (chainId == 747474) {
            // Katana
            config = ChainConfig({
                minDelay: 1 days,
                daddy: address(0xe6ad5A88f5da0F276C903d9Ac2647A937c917162), // TODO: Set Katana addresses
                brain: address(0xBe7c7efc1ef3245d37E3157F76A512108D6D7aE6),
                security: address(0x518C21DC88D9780c0A1Be566433c571461A70149),
                keeper: address(0xC29cbdcf5843f8550530cc5d627e1dd3007EF231),
                existingRoleManager: address(0)
            });
        } else {
            revert("TimelockConfig: unsupported chain");
        }
    }

    /// @notice Check if the chain is supported
    function isSupported() internal view returns (bool) {
        uint256 chainId = block.chainid;
        return
            chainId == 1 ||
            chainId == 137 ||
            chainId == 42161 ||
            chainId == 10 ||
            chainId == 8453 ||
            chainId == 100 ||
            chainId == 747474;
    }
}
