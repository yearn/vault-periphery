from ape import project, accounts, Contract, chain, networks
from hexbytes import HexBytes
from scripts.deployments import getSalt, deploy_contract


def deploy_allocator_factory():
    print("Deploying Debt Allocator Factory on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    allocator_factory = project.DebtAllocatorFactory

    deployer = input("Name of account to use? ")
    deployer = accounts.load(deployer)

    salt = getSalt("Debt Allocator Factory")

    print(f"Salt we are using {salt}")
    print("Init balance:", deployer.balance / 1e18)

    gov = input("Governance? ")

    allocator_constructor = allocator_factory.constructor.encode_input(gov)

    # generate and deploy
    deploy_bytecode = HexBytes(
        HexBytes(allocator_factory.contract_type.deployment_bytecode.bytecode)
        + allocator_constructor
    )

    print(f"Deploying the Factory...")

    deploy_contract(deploy_bytecode, salt, deployer)

    print("------------------")
    print(
        f"Encoded Constructor to use for verifaction {allocator_constructor.hex()[2:]}"
    )


def main():
    deploy_allocator_factory()
