import ape
from ape import chain, project
from utils.constants import MAX_INT, ROLES
import itertools


def test_setup(debt_optimizer_applicator, debt_allocator_factory, brain):

    assert debt_optimizer_applicator.managers(brain) == False
    assert (
        debt_optimizer_applicator.debtAllocatorFactory()
        == debt_allocator_factory.address
    )


def test_set_managers(debt_optimizer_applicator, brain, user):
    assert debt_optimizer_applicator.managers(brain) == False
    assert debt_optimizer_applicator.managers(user) == False

    with ape.reverts("!governance"):
        debt_optimizer_applicator.setManager(user, True, sender=user)

    tx = debt_optimizer_applicator.setManager(user, True, sender=brain)

    event = list(tx.decode_logs(debt_optimizer_applicator.UpdateManager))[0]

    assert event.manager == user
    assert event.allowed == True
    assert debt_optimizer_applicator.managers(user) == True

    tx = debt_optimizer_applicator.setManager(user, False, sender=brain)

    event = list(tx.decode_logs(debt_optimizer_applicator.UpdateManager))[0]

    assert event.manager == user
    assert event.allowed == False
    assert debt_optimizer_applicator.managers(user) == False


def test_set_ratios(
    debt_optimizer_applicator,
    debt_allocator,
    brain,
    daddy,
    vault,
    strategy,
    create_strategy,
    user,
):
    max = int(6_000)
    target = int(5_000)
    strategy_debt_ratio = (strategy.address, target, max)

    debt_allocator.setManager(debt_optimizer_applicator, True, sender=brain)
    debt_allocator.setMinimumChange(1, sender=brain)

    with ape.reverts("!manager"):
        debt_optimizer_applicator.setStrategyDebtRatios(
            debt_allocator, [strategy_debt_ratio], sender=user
        )

    vault.add_strategy(strategy.address, sender=daddy)

    tx = debt_optimizer_applicator.setStrategyDebtRatios(
        debt_allocator, [strategy_debt_ratio], sender=brain
    )

    event = list(tx.decode_logs(debt_allocator.StrategyChanged))[0]

    assert event.strategy == strategy
    assert event.status == 1

    event = list(tx.decode_logs(debt_allocator.UpdateStrategyDebtRatio))[0]

    assert event.newTargetRatio == target
    assert event.newMaxRatio == max
    assert event.newTotalDebtRatio == target
    assert debt_allocator.totalDebtRatio() == target
    assert debt_allocator.getConfig(strategy) == (True, target, max, 0, 0)

    new_strategy = create_strategy()
    vault.add_strategy(new_strategy, sender=daddy)

    with ape.reverts("ratio too high"):
        debt_optimizer_applicator.setStrategyDebtRatios(
            debt_allocator,
            [(new_strategy.address, int(10_000), int(10_000))],
            sender=brain,
        )

    tx = debt_optimizer_applicator.setStrategyDebtRatios(
        debt_allocator,
        [
            (strategy.address, int(8_000), int(9_000)),
            (new_strategy.address, int(2_000), int(0)),
        ],
        sender=brain,
    )

    events = list(tx.decode_logs(debt_allocator.UpdateStrategyDebtRatio))

    assert len(events) == 2
    for event in events:
        assert event.strategy in [strategy, new_strategy]
        if event.strategy == strategy:
            assert event.newTargetRatio == 8_000
            assert event.newMaxRatio == 9_000
        else:
            assert event.newTargetRatio == 2_000
            assert event.newMaxRatio == 2_000 * 1.2

    assert debt_allocator.totalDebtRatio() == 10_000
    assert debt_allocator.getConfig(strategy) == (True, 8_000, 9_000, 0, 0)
    assert debt_allocator.getConfig(new_strategy) == (True, 2_000, 2_000 * 1.2, 0, 0)


def test_set_ratios_multicall(
    debt_optimizer_applicator,
    debt_allocator,
    brain,
    daddy,
    asset,
    create_vault,
    create_strategy,
    create_debt_allocator,
    user,
):
    debt_allocators: dict[str, list[str]] = {}
    for _ in range(2):
        vault = create_vault(asset)
        debt_allocator = create_debt_allocator(vault)
        debt_allocator.setManager(debt_optimizer_applicator, True, sender=brain)
        debt_allocator.setMinimumChange(1, sender=brain)
        debt_allocators[debt_allocator.address] = []
        for _ in range(2):
            debt_allocators[debt_allocator.address].append(create_strategy(asset))

    calldata = [
        debt_optimizer_applicator.setStrategyDebtRatios.encode_input(
            allocator, [(strategy, int(5_000), int(0)) for strategy in strategies]
        )
        for allocator, strategies in debt_allocators.items()
    ]

    with ape.reverts("!manager"):
        debt_optimizer_applicator.multicall(calldata, sender=user)

    tx = debt_optimizer_applicator.multicall(
        calldata,
        sender=brain,
    )

    events = list(tx.decode_logs(debt_allocator.UpdateStrategyDebtRatio))
    strategies = list(itertools.chain(*debt_allocators.values()))

    assert len(events) == 4
    for event in events:
        assert event.strategy in strategies
        assert event.newTargetRatio == 5_000
        assert event.newMaxRatio == int(5_000 * 1.2)

    for debt_allocator_addr, strategies in debt_allocators.items():
        debt_allocator = project.DebtAllocator.at(debt_allocator_addr)
        assert debt_allocator.totalDebtRatio() == 10_000
        for strategy in strategies:
            assert debt_allocator.getConfig(strategy) == (
                True,
                5_000,
                5_000 * 1.2,
                0,
                0,
            )
