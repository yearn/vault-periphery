from ape import project, accounts, Contract, chain, networks
from hexbytes import HexBytes
from scripts.deployments import getSalt, deploy_contract


def deploy_role_manager():

    print("Deploying Role Manager on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    role_manager = project.RoleManager

    deployer = input("Name of account to use? ")
    deployer = accounts.load(deployer)

    salt = getSalt("Role Manager")

    print(f"Salt we are using {salt}")
    print("Init balance:", deployer.balance / 1e18)

    print(f"Deploying the Role Manager...")
    print("Enter the addresses to use on deployment.")

    gov = input("Governance? ")
    daddy = input("Daddy? ")
    brain = input("Brain? ")
    security = input("Security? ")
    keeper = input("Keeper? ")
    strategy_manager = input("Strategy manager? ")
    registry = input("Registry? ")

    constructor = role_manager.constructor.encode_input(
        gov, daddy, brain, security, keeper, strategy_manager, registry
    )

    deploy_bytecode = HexBytes(
        HexBytes(role_manager.contract_type.deployment_bytecode.bytecode) + constructor
    )

    deploy_contract(deploy_bytecode, salt, deployer)

    print("------------------")
    print(f"Encoded Constructor to use for verifaction {constructor.hex()[2:]}")


def main():
    deploy_role_manager()
