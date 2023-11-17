from ape import project, accounts, Contract, chain, networks
from ape.utils import ZERO_ADDRESS
from web3 import Web3, HTTPProvider
from hexbytes import HexBytes
import os
import hashlib
from copy import deepcopy

deployer = accounts.load("")


def deploy_accountant():
    print("Deploying an Accountant on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    accountant = project.GenericAccountant
    deployer_contract = project.Deployer.at(
        "0x8D85e7c9A4e369E53Acc8d5426aE1568198b0112"
    )

    salt_string = f"Accountant {chain.pending_timestamp}"

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

    version = input(
        "Would you like to deploy a Generic Accountant, HealthCheck Accountant or a Refund Accountant? g/h/r "
    ).lower()

    if version == "g":
        print("Deploying a Generic accountant.")
        print("Enter the default amounts to use in Base Points. (100% == 10_000)")

        management_fee = input("Default management fee? ")
        assert int(management_fee) <= 200

        performance_fee = input("Default performance fee? ")
        assert int(performance_fee) <= 5_000

        refund_ratio = input("Default refund ratio? ")
        assert int(refund_ratio) <= 2**16 - 1

        max_fee = input("Default max fee? ")
        assert int(max_fee) <= 2**16 - 1

        constructor = accountant.constructor.encode_input(
            deployer.address,
            deployer.address,
            management_fee,
            performance_fee,
            refund_ratio,
            max_fee,
        )

    else:
        if version == "h":
            print("Deploying a HealthCheck accountant.")
            accountant = project.HealthCheckAccountant

        else:
            print("Deploying a Refund accountant.")
            accountant = project.RefundAccountant

        print("Enter the default amounts to use in Base Points. (100% == 10_000)")

        management_fee = input("Default management fee? ")
        assert int(management_fee) <= 200

        performance_fee = input("Default performance fee? ")
        assert int(performance_fee) <= 5_000

        refund_ratio = input("Default refund ratio? ")
        assert int(refund_ratio) <= 2**16 - 1

        max_fee = input("Default max fee? ")
        assert int(max_fee) <= 2**16 - 1

        max_gain = input("Default max gain? ")
        assert int(max_gain) <= 10_000

        max_loss = input("Default max loss? ")
        assert int(max_loss) <= 10_000

        constructor = accountant.constructor.encode_input(
            deployer.address,
            deployer.address,
            management_fee,
            performance_fee,
            refund_ratio,
            max_fee,
            max_gain,
            max_loss,
        )

    # generate and deploy
    deploy_bytecode = HexBytes(
        HexBytes(accountant.contract_type.deployment_bytecode.bytecode) + constructor
    )

    print(f"Deploying Accountant...")

    tx = deployer_contract.deploy(deploy_bytecode, salt, sender=deployer)

    event = list(tx.decode_logs(deployer_contract.Deployed))

    address = event[0].addr

    print("------------------")
    print(f"Deployed the Accountant to {address}")
    print("------------------")
    print(f"Encoded Constructor to use for verifaction {constructor.hex()[2:]}")


def main():
    deploy_accountant()
