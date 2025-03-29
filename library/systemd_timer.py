#!/usr/bin/python

import os
from typing import Any

from ansible.module_utils.basic import AnsibleModule

DOCUMENTATION = """
---
module: systemd_timer
short_description: Manage systemd timers (alternative to cron)
description:
  - This module allows creating, updating, and managing systemd timers as an alternative to cron jobs.
  - By default, it creates user timers unless system=true is specified.
options:
  name:
    description:
      - Name of the timer/service (without .timer/.service extension)
    required: true
    type: str
  job:
    description:
      - Command to run
    required: true
    type: str
  state:
    description:
      - Whether the timer should be present or absent
    default: present
    choices: [ present, absent ]
    type: str
  schedule:
    description:
      - Timer schedule in systemd OnCalendar format
    required: true
    type: str
  user:
    description:
      - User for which the timer is installed (only for user timers)
    type: str
  system:
    description:
      - If true, creates system-wide timer instead of user timer
    default: false
    type: bool
  enabled:
    description:
      - Whether the timer should be enabled
    default: true
    type: bool
"""

EXAMPLES = """
- name: Create daily backup timer for the current user
  systemd_timer:
    name: daily-backup
    job: "/usr/local/bin/backup.sh"
    schedule: "*-*-* 03:00:00"

- name: Create system-wide hourly maintenance timer
  systemd_timer:
    name: hourly-maintenance
    job: "/usr/local/bin/maintenance.sh"
    schedule: "*-*-* *:00:00"
    system: true
"""


def create_service_file(name: str, job: str) -> str:
    """Create a systemd service file content.

    Args:
        name: Name of the service
        job: Command to execute

    Returns:
        Formatted service file content
    """
    return f"""[Unit]
Description={name} service

[Service]
Type=oneshot
ExecStart={job}

[Install]
WantedBy=default.target
"""


def create_timer_file(name: str, schedule: str) -> str:
    """Create a systemd timer file content.

    Args:
        name: Name of the timer
        schedule: Timer schedule in systemd OnCalendar format

    Returns:
        Formatted timer file content
    """
    return f"""[Unit]
Description={name} timer

[Timer]
OnCalendar={schedule}
Persistent=true

[Install]
WantedBy=timers.target
"""


def ensure_directory_exists(module: AnsibleModule, base_dir: str) -> None:
    """Ensure the directory exists.

    Args:
        module: Ansible module instance
        base_dir: Directory to create
    """
    if not os.path.exists(base_dir) and not module.check_mode:
        try:
            os.makedirs(base_dir, exist_ok=True)
        except OSError as err:
            module.fail_json(msg=f"Failed to create directory {base_dir}: {err}")


def check_file_needs_update(module: AnsibleModule, file_path: str, new_content: str) -> bool:
    """Check if a file needs to be updated.

    Args:
        module: Ansible module instance
        file_path: Path to the file
        new_content: New content to write

    Returns:
        True if the file needs to be updated, False otherwise
    """
    if not os.path.exists(file_path):
        return True

    try:
        with open(file_path) as f:
            current_content = f.read()
        return current_content != new_content
    except OSError as err:
        module.fail_json(msg=f"Failed to read existing file {file_path}: {err}")
        return False  # Never reached but keeps type checker happy


def write_file(module: AnsibleModule, file_path: str, content: str) -> None:
    """Write content to a file.

    Args:
        module: Ansible module instance
        file_path: Path to the file
        content: Content to write
    """
    try:
        with open(file_path, "w") as f:
            f.write(content)
    except OSError as err:
        module.fail_json(msg=f"Failed to write file {file_path}: {err}")


def create_files(
    module: AnsibleModule,
    base_dir: str,
    service_file: str,
    timer_file: str,
    service_content: str,
    timer_content: str,
) -> bool:
    """Create the service and timer files.

    Args:
        module: Ansible module instance
        base_dir: Directory to create files in
        service_file: Path to service file
        timer_file: Path to timer file
        service_content: Content for service file
        timer_content: Content for timer file

    Returns:
        True if files were created/updated, False otherwise
    """
    # Create the base directory if it doesn't exist
    ensure_directory_exists(module, base_dir)

    # Check if files need updates
    service_changed = check_file_needs_update(module, service_file, service_content)
    timer_changed = check_file_needs_update(module, timer_file, timer_content)

    if service_changed or timer_changed:
        if not module.check_mode:
            # Write the files
            if service_changed:
                write_file(module, service_file, service_content)
            if timer_changed:
                write_file(module, timer_file, timer_content)
        return True
    return False


def build_systemctl_cmd(command: str, systemctl_args: str, timer_name: str | None = None) -> str:
    """Build a systemctl command string.

    Args:
        command: The systemctl command (daemon-reload, start, etc.)
        systemctl_args: Additional arguments for systemctl
        timer_name: Optional timer name

    Returns:
        Formatted systemctl command string
    """
    cmd = f"systemctl{' ' + systemctl_args if systemctl_args else ''} {command}"
    if timer_name:
        cmd += f" {timer_name}.timer"
    return cmd


def handle_present_state(
    module: AnsibleModule,
    name: str,
    job: str,
    schedule: str,
    base_dir: str,
    systemctl_args: str,
    enabled: bool,
) -> bool:
    """Handle the 'present' state for timer.

    Args:
        module: Ansible module instance
        name: Timer name
        job: Command to execute
        schedule: Timer schedule
        base_dir: Base directory for files
        systemctl_args: Arguments for systemctl
        enabled: Whether to enable the timer

    Returns:
        True if changes were made, False otherwise
    """
    service_file = os.path.join(base_dir, f"{name}.service")
    timer_file = os.path.join(base_dir, f"{name}.timer")

    service_content = create_service_file(name, job)
    timer_content = create_timer_file(name, schedule)

    files_changed = create_files(
        module,
        base_dir,
        service_file,
        timer_file,
        service_content,
        timer_content,
    )

    if files_changed and not module.check_mode:
        # Reload systemd
        module.run_command(build_systemctl_cmd("daemon-reload", systemctl_args))

        # Enable and start the timer if requested
        if enabled:
            module.run_command(build_systemctl_cmd("enable", systemctl_args, name))
            module.run_command(build_systemctl_cmd("start", systemctl_args, name))

    return files_changed


def handle_absent_state(
    module: AnsibleModule,
    name: str,
    base_dir: str,
    systemctl_args: str,
) -> bool:
    """Handle the 'absent' state for timer.

    Args:
        module: Ansible module instance
        name: Timer name
        base_dir: Base directory for files
        systemctl_args: Arguments for systemctl

    Returns:
        True if changes were made, False otherwise
    """
    service_file = os.path.join(base_dir, f"{name}.service")
    timer_file = os.path.join(base_dir, f"{name}.timer")

    if os.path.exists(timer_file) or os.path.exists(service_file):
        if not module.check_mode:
            # Stop and disable the timer
            module.run_command(build_systemctl_cmd("stop", systemctl_args, name), ignore_errors=True)
            module.run_command(build_systemctl_cmd("disable", systemctl_args, name), ignore_errors=True)

            # Remove the files
            if os.path.exists(timer_file):
                os.remove(timer_file)
            if os.path.exists(service_file):
                os.remove(service_file)

            # Reload systemd
            module.run_command(build_systemctl_cmd("daemon-reload", systemctl_args))

        return True

    return False


def main() -> None:
    """Main execution path for the module."""
    module = AnsibleModule(
        argument_spec=dict(
            name=dict(required=True, type="str"),
            job=dict(required=True, type="str"),
            state=dict(default="present", choices=["present", "absent"], type="str"),
            schedule=dict(required=True, type="str"),
            user=dict(type="str"),
            system=dict(default=False, type="bool"),
            enabled=dict(default=True, type="bool"),
        ),
        supports_check_mode=True,
    )

    name = module.params["name"]
    job = module.params["job"]
    state = module.params["state"]
    schedule = module.params["schedule"]
    user = module.params["user"]
    system = module.params["system"]
    enabled = module.params["enabled"]

    # Determine where to place the timer files
    if system:
        base_dir = "/etc/systemd/system"
        systemctl_args = ""
    else:
        if user:
            module.fail_json(msg="User parameter can only be used with system=true")
        base_dir = os.path.expanduser("~/.config/systemd/user")
        systemctl_args = "--user"

    result: dict[str, Any] = dict(
        changed=False,
        msg="",
        diff=dict(
            before="",
            after="",
        ),
    )

    # Handle the requested state
    if state == "present":
        result["changed"] = handle_present_state(
            module,
            name,
            job,
            schedule,
            base_dir,
            systemctl_args,
            enabled,
        )
    elif state == "absent":
        result["changed"] = handle_absent_state(module, name, base_dir, systemctl_args)

    module.exit_json(**result)


if __name__ == "__main__":
    main()
