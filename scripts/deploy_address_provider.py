from ape import project, accounts, Contract, chain, networks
from hexbytes import HexBytes
from scripts.deployments import getSalt, deploy_contract


def deploy_address_provider():
    print("Deploying Address Provider on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    address_provider = project.ProtocolAddressProvider

    deployer = input("Name of account to use? ")
    deployer = accounts.load(deployer)

    salt = getSalt("Protocol Address Provider")

    print(f"Salt we are using {salt}")
    print("Init balance:", deployer.balance / 1e18)

    # generate and deploy
    constructor = address_provider.constructor.encode_input(
        "0x33333333D5eFb92f19a5F94a43456b3cec2797AE"
    )

    deploy_bytecode = HexBytes(
        HexBytes(address_provider.contract_type.deployment_bytecode.bytecode)
        + constructor
    )

    print(f"Deploying Address Provider...")

    deploy_contract(deploy_bytecode, salt, deployer)

    print("------------------")
    print(f"Encoded Constructor to use for verifaction {constructor.hex()[2:]}")


def main():
    deploy_address_provider()
