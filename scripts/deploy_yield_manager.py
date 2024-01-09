from ape import project, accounts, Contract, chain, networks, managers, compilers
from ape.utils import ZERO_ADDRESS
from hexbytes import HexBytes
import hashlib

deployer = accounts.load("")


def deploy_yield_manager():

    print("Deploying Yield Manager on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    yield_manager = project.YieldManager
    deployer_contract = project.Deployer.at(
        "0x8D85e7c9A4e369E53Acc8d5426aE1568198b0112"
    )

    salt_string = "Yield Manager test"

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

    tx = deployer_contract.deploy(deploy_bytecode, salt, sender=deployer)

    event = list(tx.decode_logs(deployer_contract.Deployed))

    address = event[0].addr

    print("------------------")
    print(f"Deployed the Yield Manager to {address}")
    print("------------------")
    print(f"Encoded Constructor to use for verifaction {constructor.hex()[2:]}")


def main():
    deploy_yield_manager()
