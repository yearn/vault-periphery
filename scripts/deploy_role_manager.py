from ape import project, accounts, Contract, chain, networks, managers, compilers
from ape.utils import ZERO_ADDRESS
from hexbytes import HexBytes
import hashlib

deployer = accounts.load("v3_deployer")


def deploy_role_manager():

    print("Deploying Role Manager on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    role_manager = project.RoleManager
    deployer_contract = project.Deployer.at(
        "0x8D85e7c9A4e369E53Acc8d5426aE1568198b0112"
    )

    salt_string = "Role Manager"

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

    print(f"Deploying the Role Manager...")
    print("Enter the addresses to use on deployment.")

    gov = input("Governance? ")
    daddy = input("Daddy? ")
    brain = input("Brain? ")
    security = input("Security? ")
    keeper = input("Keeper? ")
    strategy_manager = input("Strategy manager? ")

    constructor = role_manager.constructor.encode_input(
        gov, daddy, brain, security, keeper, strategy_manager
    )

    deploy_bytecode = HexBytes(
        HexBytes(role_manager.contract_type.deployment_bytecode.bytecode) + constructor
    )

    tx = deployer_contract.deploy(deploy_bytecode, salt, sender=deployer)

    event = list(tx.decode_logs(deployer_contract.Deployed))

    address = event[0].addr

    print("------------------")
    print(f"Deployed the Role Manager to {address}")
    print("------------------")
    print(f"Encoded Constructor to use for verifaction {constructor.hex()[2:]}")


def main():
    deploy_role_manager()
