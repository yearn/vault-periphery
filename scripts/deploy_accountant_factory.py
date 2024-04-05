from ape import project, accounts, Contract, chain, networks
from hexbytes import HexBytes
from scripts.deployments import getSalt, deploy_contract


def deploy_accountant_factory():
    print("Deploying an Accountant Factory on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    deployer = input("Name of account to use? ")
    deployer = accounts.load(deployer)

    accountant_factory = project.AccountantFactory

    salt = getSalt(f"Accountant Factory")

    print(f"Salt we are using {salt}")
    print("Init balance:", deployer.balance / 1e18)

    # generate and deploy
    deploy_bytecode = HexBytes(
        accountant_factory.contract_type.deployment_bytecode.bytecode
    )

    print(f"Deploying Accountant actory...")

    deploy_contract(deploy_bytecode, salt, deployer)

    print("------------------")


def main():
    deploy_accountant_factory()
