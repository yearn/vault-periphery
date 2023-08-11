from hexbytes import HexBytes
import hashlib


def to_bytes32(string):
    return HexBytes(hashlib.sha3_256((string).encode("utf-8")).digest())
