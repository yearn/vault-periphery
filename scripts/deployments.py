from ape import project, accounts, Contract, chain, networks
from hexbytes import HexBytes
import hashlib


def getSalt(salt_string):
    # Create a SHA-256 hash object
    hash_object = hashlib.sha256()
    # Update the hash object with the string data
    hash_object.update(salt_string.encode("utf-8"))
    # Get the hexadecimal representation of the hash
    hex_hash = hash_object.hexdigest()
    # Convert the hexadecimal hash to an integer
    return int(hex_hash, 16)


def deploy_contract(init_code, salt, deployer):
    deployer_contract = project.Deployer.at(
        "0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed"
    )

    tx = deployer_contract.deployCreate2(salt, init_code, sender=deployer)

    event = list(tx.decode_logs(deployer_contract.ContractCreation))

    address = event[0].newContract

    print("------------------")
    print(f"Deployed the contract to {address}")

    return address
