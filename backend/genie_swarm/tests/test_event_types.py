"""Every event the code emits must be one the wire model accepts.

`SwarmEvent.type` is a closed `Literal`, so emitting a name that is not
in it raises a pydantic ValidationError from inside whatever stage
emitted it. That is a production-only failure: tests that pass a stub
event collector never touch the model, so a new event type can be added,
tested, reviewed and shipped while being incapable of ever firing.

That is exactly what happened to the packaging events. This scans the
source for emitted names instead of listing them by hand, so it also
covers the next one.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

from genie_swarm.models import SwarmEvent

_SRC = Path(__file__).resolve().parent.parent
_EMIT = re.compile(r"""\.emit\(\s*["']([a-z0-9_.]+)["']""")


def _valid_types() -> set[str]:
    annotation = SwarmEvent.model_fields["type"].annotation
    return set(getattr(annotation, "__args__", ()))


def _emitted_types() -> dict[str, set[str]]:
    found: dict[str, set[str]] = {}
    for path in sorted(_SRC.rglob("*.py")):
        if "tests" in path.parts:
            continue
        names = set(_EMIT.findall(path.read_text(encoding="utf-8")))
        if names:
            found[str(path.relative_to(_SRC))] = names
    return found


def test_every_emitted_event_type_is_accepted_by_the_model():
    valid = _valid_types()
    unknown: list[str] = []
    for source, names in _emitted_types().items():
        for name in sorted(names - valid):
            unknown.append(f"{source} emits '{name}'")
    assert not unknown, (
        "These would raise ValidationError the moment they fire. Add them "
        "to SwarmEvent.type:\n  " + "\n  ".join(unknown)
    )


def test_the_scan_actually_finds_something():
    """Guards against the regex silently matching nothing, which would
    make the test above pass for the wrong reason."""
    emitted = _emitted_types()
    assert emitted, "found no .emit(...) calls at all"
    everything = set().union(*emitted.values())
    assert "job.state" in everything
    assert "testflight.package" in everything


@pytest.mark.parametrize("name", sorted(_valid_types()))
def test_each_declared_type_can_be_constructed(name: str):
    event = SwarmEvent(type=name, job_id="job1", payload={})
    assert event.type == name
