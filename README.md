## How to start

### Requirements

- First you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation).
NOTE: If you are on a windows machine it is recommended to use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)

### Fork this repository

```sh
git clone --recursive https://github.com/yearn/vault-periphery

cd vault-periphery

pip install vyper==0.3.7

make build

make test
```
### Deployment

Deployment of periphery contracts are done using a create2 factory in order to get a deterministic address that is the same on each EVM chain.

This can be done permissionlessly if the most recent contract has not yet been deployed on a chain you would like to use it on using this repo https://github.com/wavey0x/yearn-v3-deployer
