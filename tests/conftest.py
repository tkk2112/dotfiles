"""
Configuration file for pytest.
"""

from typing import Any


def pytest_configure(config: Any) -> None:
    """Add markers for pytest."""
    config.addinivalue_line(
        "markers",
        "ansible: mark test as an Ansible module test",
    )
