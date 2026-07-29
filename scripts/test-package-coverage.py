#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

import yaml

DEFAULT_MANAGERS = {"apt", "brew", "dnf", "linuxbrew", "pacman"}
PACKAGE_GROUPS = {"core", "workstation", "development", "server", "gaming"}
REQUIRED_MANAGERS = {"apt", "brew", "dnf", "linuxbrew", "pacman"}


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    if not isinstance(data, dict):
        fail(f"expected mapping in {path}")
    return data


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        fail(f"expected object in {path}")
    return data


def profile_set(value: Any, scenario_name: str) -> set[str]:
    if not isinstance(value, str):
        fail(f"scenario {scenario_name} must use a comma-separated profiles string")
    profiles = {part for part in value.split(",") if part}
    if not profiles:
        fail(f"scenario {scenario_name} has no profiles")
    return profiles


def package_managers(package: dict[str, Any]) -> set[str]:
    raw = package.get("managers")
    if raw is None:
        return set(DEFAULT_MANAGERS)
    if not isinstance(raw, list) or not all(isinstance(item, str) for item in raw):
        fail(f"package {package.get('name', '<unknown>')} has invalid managers")
    return set(raw)


def package_group(package: dict[str, Any]) -> str:
    group = package.get("group", "core")
    if not isinstance(group, str) or group not in PACKAGE_GROUPS:
        fail(f"package {package.get('name', '<unknown>')} has unknown group {group!r}")
    return group


def selected_packages(
    catalog: list[dict[str, Any]],
    manager: str,
    profiles: set[str],
    *,
    explicit_only: bool = False,
) -> list[str]:
    selected: list[str] = []

    for package in catalog:
        name = package.get("name")
        if not isinstance(name, str) or not name:
            fail("catalog entry is missing a package name")

        managers = package_managers(package)
        if manager not in managers:
            continue
        if explicit_only and "managers" not in package:
            continue

        group = package_group(package)
        if group != "core" and group not in profiles:
            fail(
                f"scenario for {manager} does not select package {name} "
                f"from group {group}"
            )

        selected.append(name)

    return selected


def validate_scenario(
    scenario: dict[str, Any],
    catalog: list[dict[str, Any]],
    casks: list[dict[str, Any]],
) -> None:
    name = scenario.get("name")
    manager = scenario.get("manager")
    mode = scenario.get("package_mode")

    if not isinstance(name, str) or not name:
        fail("nightly scenario is missing a name")
    if manager not in REQUIRED_MANAGERS:
        fail(f"scenario {name} has unsupported manager {manager!r}")
    if not isinstance(mode, str) or not mode:
        fail(f"scenario {name} is missing package_mode")

    profiles = profile_set(scenario.get("profiles"), name)

    if "gaming" in profiles and manager != "dnf":
        fail(f"scenario {name} enables gaming outside DNF")
    if manager == "dnf" and "gaming" not in profiles:
        fail(f"DNF scenario {name} must cover gaming packages")

    required_profiles = {"workstation", "laptop", "development", "server"}
    missing_profiles = required_profiles - profiles
    if missing_profiles:
        fail(
            f"scenario {name} is not exhaustive; missing profiles: "
            f"{', '.join(sorted(missing_profiles))}"
        )

    if mode in {"native", "native-linuxbrew"} and "owned" not in profiles:
        fail(f"native scenario {name} must include owned")
    if mode == "linuxbrew" and "owned" in profiles:
        fail(f"Linuxbrew scenario {name} must not include owned")

    packages = selected_packages(catalog, manager, profiles)

    if manager == "brew":
        for cask in casks:
            cask_name = cask.get("name")
            if not isinstance(cask_name, str) or not cask_name:
                fail("cask entry is missing a name")
            group = cask.get("group", "core")
            if group != "core" and group not in profiles:
                fail(f"scenario {name} does not select cask {cask_name} from group {group}")

    supplemental_manager = scenario.get("supplemental_manager")
    supplemental_count = 0
    if supplemental_manager is not None:
        if mode != "native-linuxbrew":
            fail(f"scenario {name} has supplemental_manager outside native-linuxbrew")
        if supplemental_manager != "linuxbrew":
            fail(f"scenario {name} has unsupported supplemental manager")
        supplemental_count = len(
            selected_packages(
                catalog,
                supplemental_manager,
                profiles,
                explicit_only=True,
            )
        )
        if supplemental_count == 0:
            fail(f"scenario {name} selects no Linuxbrew supplements")

    print(
        f"PASS: {name}: {len(packages)} {manager} packages"
        + (
            f" and {supplemental_count} explicit {supplemental_manager} supplements"
            if supplemental_manager
            else ""
        )
    )


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    package_data = load_yaml(root / "home/.chezmoidata/packages.yaml")
    scenarios = load_json(root / "scripts/nightly-package-scenarios.json")

    packages = package_data.get("packages")
    if not isinstance(packages, dict):
        fail("packages.yaml is missing the packages mapping")

    catalog = packages.get("catalog")
    casks = packages.get("casks", [])
    if not isinstance(catalog, list) or not all(isinstance(item, dict) for item in catalog):
        fail("packages.catalog must be a list of mappings")
    if not isinstance(casks, list) or not all(isinstance(item, dict) for item in casks):
        fail("packages.casks must be a list of mappings")

    package_scenarios: list[dict[str, Any]] = []
    for section in ("linux", "macos"):
        entries = scenarios.get(section)
        if not isinstance(entries, list) or not all(isinstance(item, dict) for item in entries):
            fail(f"scenario section {section} must be a list of mappings")
        package_scenarios.extend(entries)

    covered_managers = {scenario.get("manager") for scenario in package_scenarios}
    missing_managers = REQUIRED_MANAGERS - covered_managers
    if missing_managers:
        fail(f"nightly has no scenarios for: {', '.join(sorted(missing_managers))}")

    for scenario in package_scenarios:
        validate_scenario(scenario, catalog, casks)

    degraded = scenarios.get("degraded")
    if not isinstance(degraded, list) or not degraded:
        fail("nightly must define degraded scenarios")
    for scenario in degraded:
        if not isinstance(scenario, dict) or scenario.get("package_mode") != "degraded":
            fail("invalid degraded scenario")

    print("PASS: every nightly package target selects all applicable packages")


if __name__ == "__main__":
    main()
