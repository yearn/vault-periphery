from ape import project, accounts, Contract, chain, networks
from hexbytes import HexBytes
from scripts.deployments import getSalt, deploy_contract


def deploy_yield_manager():

    print("Deploying Yield Manager on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    yield_manager = project.YieldManager

    deployer = input("Name of account to use? ")
    deployer = accounts.load(deployer)

    salt = getSalt("Yield Manager")

    print(f"Salt we are using {salt}")
    print("Init balance:", deployer.balance / 1e18)

    print(f"Deploying the Yield Manager...")
    print("Enter the addresses to use on deployment.")

    gov = input("Governance? ")
    keeper = input("Keeper? ")

    constructor = yield_manager.constructor.encode_input(
        gov,
        keeper,
    )

    deploy_bytecode = HexBytes(
        HexBytes(yield_manager.contract_type.deployment_bytecode.bytecode) + constructor
    )

    deploy_contract(deploy_bytecode, salt, deployer)

    print("------------------")
    print(f"Encoded Constructor to use for verifaction {constructor.hex()[2:]}")


def main():
    deploy_yield_manager()
