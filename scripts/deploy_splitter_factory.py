from ape import project, accounts, Contract, chain, networks
from hexbytes import HexBytes
from scripts.deployments import getSalt, deploy_contract


def deploy_splitter_factory():
    print("Deploying Splitter Factory on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    splitter = project.Splitter
    splitter_factory = project.SplitterFactory

    deployer = input("Name of account to use? ")
    deployer = accounts.load(deployer)

    salt = getSalt("Splitter Factory")

    print(f"Salt we are using {salt}")
    print("Init balance:", deployer.balance / 1e18)

    print(f"Deploying Original.")

    original_deploy_bytecode = HexBytes(
        HexBytes(splitter.contract_type.deployment_bytecode.bytecode)
    )

    original_address = deploy_contract(original_deploy_bytecode, salt, deployer)

    print(f"Original deployed to {original_address}")

    allocator_constructor = splitter_factory.constructor.encode_input(original_address)

    # generate and deploy
    deploy_bytecode = HexBytes(
        HexBytes(splitter_factory.contract_type.deployment_bytecode.bytecode)
        + allocator_constructor
    )

    print(f"Deploying the Factory...")

    deploy_contract(deploy_bytecode, salt, deployer)

    print("------------------")
    print(
        f"Encoded Constructor to use for verifaction {allocator_constructor.hex()[2:]}"
    )


def main():
    deploy_splitter_factory()
