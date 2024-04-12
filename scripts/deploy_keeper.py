from ape import project, accounts, Contract, chain, networks
from hexbytes import HexBytes
from scripts.deployments import getSalt, deploy_contract


def deploy_keeper():
    print("Deploying Keeper on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    keeper = project.Keeper

    deployer = input("Name of account to use? ")
    deployer = accounts.load(deployer)

    salt = getSalt("Keeper")

    print(f"Salt we are using {salt}")
    print("Init balance:", deployer.balance / 1e18)

    # generate and deploy
    deploy_bytecode = HexBytes(
        HexBytes(keeper.contract_type.deployment_bytecode.bytecode)
    )

    print(f"Deploying the Keeper...")

    deploy_contract(deploy_bytecode, salt, deployer)

    print("------------------")


def main():
    deploy_keeper()
