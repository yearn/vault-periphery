from ape import project, accounts, Contract, chain, networks
from ape.utils import ZERO_ADDRESS
from web3 import Web3, HTTPProvider
from hexbytes import HexBytes
import os
import hashlib
from copy import deepcopy


def deploy_address_provider():
    print("Deploying Address Provider on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    address_provider = project.AddressProvider
    deployer = accounts.load("")
    deployer_contract = project.Deployer.at(
        "0x8D85e7c9A4e369E53Acc8d5426aE1568198b0112"
    )

    salt_string = "v3.0.0"

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

    # generate and deploy
    constructor = address_provider.constructor.encode_input("GOV")

    deploy_bytecode = HexBytes(
        HexBytes(address_provider.contract_type.deployment_bytecode.bytecode)
        + constructor
    )

    print(f"Deploying Address Provider...")

    tx = deployer_contract.deploy(deploy_bytecode, salt, sender=deployer)

    event = list(tx.decode_logs(deployer_contract.Deployed))

    address = event[0].addr

    print(f"Deployed the address provider to {address}")


def main():
    deploy_address_provider()
