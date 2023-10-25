from ape import project, accounts, Contract, chain, networks
from ape.utils import ZERO_ADDRESS
from web3 import Web3, HTTPProvider
from hexbytes import HexBytes
import os
import hashlib
from copy import deepcopy

deployer = accounts.load("")


def deploy_release_and_factory():
    print("Deploying Vault Registry on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    release_registry = project.ReleaseRegistry
    factory = project.RegistryFactory
    deployer_contract = project.Deployer.at(
        "0x8D85e7c9A4e369E53Acc8d5426aE1568198b0112"
    )

    salt_string = "registry"

    # Create a SHA-256 hash object
    hash_object = hashlib.sha256()
    # Update the hash object with the string data
    hash_object.update(salt_string.encode("utf-8"))
    # Get the hexadecimal representation of the hash
    hex_hash = hash_object.hexdigest()
    # Convert the hexadecimal hash to an integer
    salt = int(hex_hash, 16)

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

    factory_tx = deployer_contract.deploy(
        factory_deploy_bytecode, salt, sender=deployer
    )

    factory_event = list(factory_tx.decode_logs(deployer_contract.Deployed))

    deployed_factory = factory.at(factory_event[0].addr)

    print(f"Deployed Registry Factory to {deployed_factory.address}")
    print("------------------")
    print(f"Encoded Constructor to use for verifaction {factory_constructor.hex()}")


def main():
    deploy_release_and_factory()
