-include .env

# deps
update:; forge update
build  :; forge build
size  :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storage-layout --pretty

# if we want to run only matching tests, set that here
test := test_

# local tests without fork
test  :; forge test -vv --ffi
trace  :; forge test -vvv --ffi
gas  :; forge test --ffi --gas-report
test-contract  :; forge test -vv --match-contract $(contract) --ffi
test-contract-gas  :; forge test --gas-report --match-contract ${contract} --ffi
trace-contract  :; forge test -vvv --match-contract $(contract) --ffi
test-test  :; forge test -vv --match-test $(test) --ffi
test-test-trace  :; forge test -vvv --match-test $(test) --ffi
trace-test  :; forge test -vvvvv --match-test $(test) --ffi
snapshot :; forge snapshot -vv --ffi
snapshot-diff :; forge snapshot --diff -vv --ffi
trace-setup  :; forge test -vvvv --ffi
trace-max  :; forge test -vvvvv --ffi
coverage :; forge coverage --ffi
coverage-report :; forge coverage --report lcov --ffi
coverage-debug :; forge coverage --report debug --ffi


clean  :; forge clean