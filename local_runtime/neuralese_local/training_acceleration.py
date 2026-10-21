from __future__ import annotations

from dataclasses import dataclass
from math import ceil, isfinite
from typing import Any, Mapping, Sequence

import numpy as np


_GRU_PARAMETER_PREFIXES = (
    "gru_w_zr_",
    "gru_u_zr_",
    "gru_b_zr_",
    "gru_w_n_",
    "gru_u_n_",
    "gru_b_n_",
)


@dataclass(frozen=True)
class FreezeStage:
    name: str
    start_epoch: int
    trainable_params: tuple[str, ...]


def _parameter_owner(name: str) -> str:
    value = str(name)
    for prefix in _GRU_PARAMETER_PREFIXES:
        if value.startswith(prefix):
            return value[len(prefix) :]
    if value.startswith(("w_", "b_")):
        return value[2:]
    return value


def parameter_groups(model: Any, trainable_params: Sequence[str]) -> list[tuple[str, ...]]:
    """Return trainable parameters grouped by their forward graph layer."""
    params = {str(value) for value in trainable_params}
    positions: dict[str, tuple[int, int]] = {}
    for node_index, node in enumerate(model.graph.node):
        for input_index, input_name in enumerate(node.input):
            name = str(input_name)
            if name in params and name not in positions:
                positions[name] = (node_index, input_index)

    grouped: dict[str, list[str]] = {}
    for name in params:
        grouped.setdefault(_parameter_owner(name), []).append(name)

    missing_position = len(model.graph.node) + 1

    def parameter_key(name: str) -> tuple[int, int, str]:
        node_index, input_index = positions.get(name, (missing_position, 0))
        return node_index, input_index, name

    ordered_groups = sorted(
        grouped.values(),
        key=lambda values: min(parameter_key(value) for value in values),
    )
    return [tuple(sorted(values, key=parameter_key)) for values in ordered_groups]


def freeze_schedule(
    groups: Sequence[Sequence[str]],
    epochs: int,
    *,
    enabled: bool = True,
) -> tuple[FreezeStage, ...]:
    normalized = [tuple(str(value) for value in group) for group in groups if group]
    full = tuple(value for group in normalized for value in group)
    stages = [FreezeStage("full", 0, full)]
    epochs = max(1, int(epochs))
    if not enabled or len(normalized) < 2 or epochs < 4:
        return tuple(stages)

    if len(normalized) >= 3:
        stages.append(
            FreezeStage(
                "suffix2",
                int(ceil(epochs * 0.40)),
                tuple(value for group in normalized[-2:] for value in group),
            )
        )
    stages.append(
        FreezeStage(
            "head",
            int(ceil(epochs * (0.75 if len(normalized) >= 3 else 0.40))),
            normalized[-1],
        )
    )

    unique: list[FreezeStage] = []
    seen: set[tuple[str, ...]] = set()
    for stage in stages:
        if stage.trainable_params in seen:
            continue
        seen.add(stage.trainable_params)
        unique.append(stage)
    return tuple(unique)


def algorithmic_acceleration_eligible(
    groups: Sequence[Sequence[str]],
    *,
    epochs: int,
    samples: int,
    batch_size: int,
    minimum_batches: int = 8,
) -> bool:
    """Keep approximation out of short jobs where it cannot repay its quality cost."""
    available_batches = int(ceil(max(0, int(samples)) / max(1, int(batch_size))))
    return (
        any(group for group in groups)
        and int(epochs) >= 3
        and available_batches >= max(1, int(minimum_batches))
    )


@dataclass(frozen=True)
class SelectiveBlockPolicy:
    keep_fraction: float = 0.80
    exploration_fraction: float = 0.15
    warmup_epochs: int = 2
    refresh_interval: int = 5

    def select(
        self,
        epoch: int,
        epochs: int,
        losses: Mapping[int, float],
        rng: np.random.Generator,
    ) -> set[int]:
        available = sorted(int(block) for block in losses)
        all_blocks = set(available)
        if (
            not available
            or int(epoch) < max(0, int(self.warmup_epochs))
            or int(epoch) == max(1, int(epochs)) - 1
            or (
                int(self.refresh_interval) > 0
                and (int(epoch) + 1) % int(self.refresh_interval) == 0
            )
        ):
            return all_blocks

        keep_count = min(
            len(available),
            max(1, int(ceil(len(available) * float(self.keep_fraction)))),
        )
        exploration_count = min(
            keep_count,
            max(0, int(ceil(len(available) * float(self.exploration_fraction)))),
        )
        hard_count = max(0, keep_count - exploration_count)
        ranked = sorted(
            available,
            key=lambda block: (
                -(float(losses[block]) if isfinite(float(losses[block])) else float("-inf")),
                block,
            ),
        )
        selected = set(ranked[:hard_count])
        candidates = np.asarray(
            [block for block in available if block not in selected], dtype=np.int64
        )
        if exploration_count > 0 and len(candidates) > 0:
            count = min(exploration_count, len(candidates))
            selected.update(
                int(value)
                for value in rng.choice(candidates, size=count, replace=False).tolist()
            )
        return selected
