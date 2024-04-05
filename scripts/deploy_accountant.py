from ape import project, accounts, Contract, chain, networks
from hexbytes import HexBytes
from scripts.deployments import getSalt, deploy_contract


def deploy_accountant():
    print("Deploying an Accountant on ChainID", chain.chain_id)

    if input("Do you want to continue? ") == "n":
        return

    deployer = input("Name of account to use? ")
    deployer = accounts.load(deployer)

    accountant
    salt = getSalt(f"Accountant {chain.pending_timestamp}")

    print(f"Salt we are using {salt}")
    print("Init balance:", deployer.balance / 1e18)

    version = input(
        "Would you like to deploy a normal Accountant a Refund Accountant? g/r "
    ).lower()

    if version == "g":
        print("Deploying an Accountant.")
        accountant = project.Accountant

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
    assert int(max_gain) <= 2**16 - 1

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

    deploy_contract(deploy_bytecode, salt, deployer)

    print("------------------")
    print(f"Encoded Constructor to use for verifaction {constructor.hex()[2:]}")


def main():
    deploy_accountant()
