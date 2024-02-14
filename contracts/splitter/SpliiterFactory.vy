# @version 0.3.7

interface ISplitter:
    def initialize(
        name: String[64], 
        manager: address,
        manager_recipient: address,
        splitee: address,
        original_split: uint256
    ): nonpayable

event NewSplitter:
    splitter: indexed(address)
    manager: indexed(address)
    manager_recipient: indexed(address)
    splitee: address

# The address that all newly deployed vaults are based from.
ORIGINAL: immutable(address)

@external
def __init__(original: address):
    ORIGINAL = original


@external
def newSplitter(
    name: String[64], 
    manager: address,
    manager_recipient: address,
    splitee: address,
    original_split: uint256
) -> address:

    # Clone a new version of the vault using create2.
    new_splitter: address = create_minimal_proxy_to(
            ORIGINAL, 
            value=0
        )

    ISplitter(new_splitter).initialize(
        name,
        manager,
        manager_recipient,
        splitee,
        original_split
    )
        
    log NewSplitter(new_splitter, manager, manager_recipient, splitee)
    return new_splitter