#!/usr/bin/python

import os
import sys
import unittest
from unittest import mock

from ansible.module_utils.testing import patch_module_args

# Add module path to import the systemd_timer module
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../library")))
import systemd_timer


class AnsibleExitJson(Exception):
    """Exception class to capture exit json"""

    pass


class AnsibleFailJson(Exception):
    """Exception class to capture fail json"""

    pass


class TestSystemdTimer(unittest.TestCase):
    """Test cases for systemd_timer module"""

    def setUp(self) -> None:
        """Set up test environment"""
        self.mock_module_helper = mock.patch.multiple(
            "ansible.module_utils.basic.AnsibleModule",
            exit_json=mock.MagicMock(side_effect=AnsibleExitJson),
            fail_json=mock.MagicMock(side_effect=AnsibleFailJson),
        )
        self.mock_module_helper.start()
        self.addCleanup(self.mock_module_helper.stop)

    def test_module_fail_when_required_args_missing(self) -> None:
        """Test module fails when required args are missing"""
        with patch_module_args({}):  # Empty args to cause failure
            with self.assertRaises(AnsibleFailJson):
                systemd_timer.main()

    @mock.patch("systemd_timer.os.path.exists", return_value=False)
    @mock.patch("systemd_timer.os.makedirs")
    @mock.patch("systemd_timer.os.path.expanduser", return_value="/home/user/.config/systemd/user")
    @mock.patch("builtins.open", new_callable=mock.mock_open)
    @mock.patch("systemd_timer.AnsibleModule.run_command")
    def test_create_user_timer(
        self,
        mock_run_command: mock.MagicMock,
        mock_open: mock.MagicMock,
        mock_expanduser: mock.MagicMock,
        mock_makedirs: mock.MagicMock,
        mock_exists: mock.MagicMock,
    ) -> None:
        """Test creating a user timer"""
        with patch_module_args(
            {
                "name": "test-timer",
                "job": '/bin/echo "Hello World"',
                "schedule": "*-*-* 03:00:00",
                "state": "present",
                "enabled": True,
            },
        ):
            with self.assertRaises(AnsibleExitJson):
                systemd_timer.main()

        # Check if directories were created
        mock_makedirs.assert_called_once_with("/home/user/.config/systemd/user", exist_ok=True)

        # Check if files were written
        mock_open.assert_any_call("/home/user/.config/systemd/user/test-timer.service", "w")
        mock_open.assert_any_call("/home/user/.config/systemd/user/test-timer.timer", "w")

        # Check if systemd was reloaded and timer enabled/started
        mock_run_command.assert_any_call("systemctl --user daemon-reload")
        mock_run_command.assert_any_call("systemctl --user enable test-timer.timer")
        mock_run_command.assert_any_call("systemctl --user start test-timer.timer")

    @mock.patch("systemd_timer.os.path.exists", return_value=False)
    @mock.patch("systemd_timer.os.makedirs")
    @mock.patch("builtins.open", new_callable=mock.mock_open)
    @mock.patch("systemd_timer.AnsibleModule.run_command")
    def test_create_system_timer(
        self,
        mock_run_command: mock.MagicMock,
        mock_open: mock.MagicMock,
        mock_makedirs: mock.MagicMock,
        mock_exists: mock.MagicMock,
    ) -> None:
        """Test creating a system timer"""
        with patch_module_args(
            {
                "name": "test-system-timer",
                "job": '/bin/echo "Hello System"',
                "schedule": "*-*-* 04:00:00",
                "state": "present",
                "system": True,
                "enabled": True,
            },
        ):
            with self.assertRaises(AnsibleExitJson):
                systemd_timer.main()

        # Check if directories were created
        mock_makedirs.assert_called_once_with("/etc/systemd/system", exist_ok=True)

        # Check if files were written
        mock_open.assert_any_call("/etc/systemd/system/test-system-timer.service", "w")
        mock_open.assert_any_call("/etc/systemd/system/test-system-timer.timer", "w")

        # Check if systemd was reloaded and timer enabled/started
        mock_run_command.assert_any_call("systemctl daemon-reload")
        mock_run_command.assert_any_call("systemctl enable test-system-timer.timer")
        mock_run_command.assert_any_call("systemctl start test-system-timer.timer")

    @mock.patch("systemd_timer.os.path.expanduser", return_value="/home/user/.config/systemd/user")
    @mock.patch("systemd_timer.os.path.exists", side_effect=lambda path: True)
    @mock.patch("systemd_timer.os.remove")
    @mock.patch("systemd_timer.AnsibleModule.run_command")
    def test_remove_timer(
        self,
        mock_run_command: mock.MagicMock,
        mock_remove: mock.MagicMock,
        mock_exists: mock.MagicMock,
        mock_expanduser: mock.MagicMock,
    ) -> None:
        """Test removing a timer"""
        with patch_module_args(
            {
                "name": "test-timer",
                "job": '/bin/echo "Hello"',
                "schedule": "*-*-* 03:00:00",
                "state": "absent",
            },
        ):
            with self.assertRaises(AnsibleExitJson):
                systemd_timer.main()

        # Check if files were removed
        mock_remove.assert_any_call("/home/user/.config/systemd/user/test-timer.timer")
        mock_remove.assert_any_call("/home/user/.config/systemd/user/test-timer.service")

        # Check if systemd was reloaded
        mock_run_command.assert_any_call("systemctl --user stop test-timer.timer", ignore_errors=True)
        mock_run_command.assert_any_call("systemctl --user disable test-timer.timer", ignore_errors=True)
        mock_run_command.assert_any_call("systemctl --user daemon-reload")

    @mock.patch("systemd_timer.os.path.expanduser", return_value="/home/user/.config/systemd/user")
    @mock.patch("systemd_timer.os.path.exists", return_value=True)
    @mock.patch("builtins.open", new_callable=mock.mock_open)
    @mock.patch("systemd_timer.AnsibleModule.run_command")
    def test_update_existing_timer(
        self,
        mock_run_command: mock.MagicMock,
        mock_open: mock.MagicMock,
        mock_exists: mock.MagicMock,
        mock_expanduser: mock.MagicMock,
    ) -> None:
        """Test updating an existing timer"""
        # Setup the mock to return different content when reading existing files
        mock_open.return_value.__enter__.return_value.read.return_value = "old content"

        with patch_module_args(
            {
                "name": "test-timer",
                "job": '/bin/echo "Updated"',
                "schedule": "*-*-* 05:00:00",
                "state": "present",
                "enabled": True,
            },
        ):
            with self.assertRaises(AnsibleExitJson):
                systemd_timer.main()

        # Check if files were written (should be called because content differs)
        mock_open.assert_any_call("/home/user/.config/systemd/user/test-timer.service", "w")
        mock_open.assert_any_call("/home/user/.config/systemd/user/test-timer.timer", "w")

        # Check if systemd was reloaded
        mock_run_command.assert_any_call("systemctl --user daemon-reload")

    @mock.patch("systemd_timer.os.path.expanduser", return_value="/home/user/.config/systemd/user")
    @mock.patch("systemd_timer.os.path.exists", return_value=True)
    def test_check_mode(
        self,
        mock_exists: mock.MagicMock,
        mock_expanduser: mock.MagicMock,
    ) -> None:
        """Test check mode functionality"""
        with patch_module_args(
            {
                "name": "test-timer",
                "job": '/bin/echo "Hello"',
                "schedule": "*-*-* 03:00:00",
                "state": "present",
                "_ansible_check_mode": True,
            },
        ):
            with mock.patch("builtins.open", mock.mock_open(read_data="old content")) as m:
                with self.assertRaises(AnsibleExitJson):
                    systemd_timer.main()

                # In check mode, open should be called for reading but not for writing
                for call in m.mock_calls:
                    if len(call) >= 2 and isinstance(call[1], tuple) and len(call[1]) >= 2:
                        # Check that no write mode was used
                        self.assertNotEqual(call[1][1], "w", "open() should not be called with write mode in check mode")


if __name__ == "__main__":
    unittest.main()
