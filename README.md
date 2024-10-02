## How to start

### Requirements

- First you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation).
NOTE: If you are on a windows machine it is recommended to use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)
- Install [Node.js](https://nodejs.org/en/download/package-manager/)

### Fork this repository

    git clone https://github.com/yearn/vault-periphery

    cd vault-periphery

    
### Deployment

Deployment of periphery contracts such as the [Registry Factory](https://github.com/yearn/vault-periphery/blob/master/contracts/registry/RegistryFactory.sol) or [Address Provider](https://github.com/yearn/vault-periphery/blob/master/contracts/AddressProvider.vy) are done using a create2 factory in order to get a deterministic address that is the same on each EVM chain.

This can be done permissionlessly if the most recent contract has not yet been deployed on a chain you would like to use it on.

1. [Add an Ape account](https://docs.apeworx.io/ape/stable/commands/accounts.html) 
2. Run the deployment the contracts specific deployment script under `scripts/`
    ```sh
    ape run scripts/deploy_contract_name.py --network YOUR_RPC_URL
    ```
    - For chains that don't support 1559 tx's you may need to add a `type="0x0"` argument at the end of the deployment tx.
        - ie `tx = deployer_contract.deployCreate2(salt, init_code, sender=deployer, type="0x0")`
3. The address the contract was deployed at will print in the console and should match any other chain the same version has been deployed on.