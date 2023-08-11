from hexbytes import HexBytes
from sha3 import keccak_256


def to_bytes32(string):
    return HexBytes(keccak_256((string).encode("utf-8")).hexdigest())
