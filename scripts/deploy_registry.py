from ape import project, accounts, Contract, chain, networks
from hexbytes import HexBytes
from scripts.deployments import getSalt, deploy_contract


def deploy_release_and_factory():
    print("Deploying Vault Registry on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    release_registry = project.ReleaseRegistry
    factory = project.RegistryFactory

    deployer = input("Name of account to use? ")
    deployer = accounts.load(deployer)

    salt = getSalt("registry")

    print(f"Salt we are using {salt}")
    print("Init balance:", deployer.balance / 1e18)
    release_address = "0x990089173D5d5287c344092Be0bB37950A67d17B"

    if input("Do you want to deploy a new Release Registry? ") == "y":

        # generate and deploy release registry
        release_constructor = release_registry.constructor.encode_input(
            "0x33333333D5eFb92f19a5F94a43456b3cec2797AE"
        )

        release_deploy_bytecode = HexBytes(
            HexBytes(release_registry.contract_type.deployment_bytecode.bytecode)
            + release_constructor
        )

        print(f"Deploying Release Registry...")

        # Use old deployer contract to get the same address.
        deployer_contract = project.Deployer.at(
            "0x8D85e7c9A4e369E53Acc8d5426aE1568198b0112"
        )

        release_tx = deployer_contract.deploy(
            release_deploy_bytecode, salt, sender=deployer
        )

        release_event = list(release_tx.decode_logs(deployer_contract.Deployed))

        release_address = release_event[0].addr

        print(f"Deployed the vault release to {release_address}")
        print("------------------")
        print(f"Encoded Constructor to use for verifaction {release_constructor.hex()}")

    # Deploy factory
    print(f"Deploying factory...")

    factory_constructor = factory.constructor.encode_input(release_address)

    factory_deploy_bytecode = HexBytes(
        HexBytes(factory.contract_type.deployment_bytecode.bytecode)
        + factory_constructor
    )

    deploy_contract(factory_deploy_bytecode, salt, deployer)

    print("------------------")
    print(f"Encoded Constructor to use for verifaction {factory_constructor.hex()[2:]}")


def main():
    deploy_release_and_factory()
