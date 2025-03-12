module.exports = {
  extends: [
    "config:recommended",
    ":dependencyDashboard",
    ":semanticCommits",
    ":enablePreCommit"
  ],
  labels: ["dependencies"],
  ansible: {
    fileMatch: [
      "(^|/)tasks/[^/]+\\.ya?ml$"
    ]
  },
  lockFileMaintenance: {
    enabled: true
  },
  automerge: true,
  ignoreTests: false,
  configMigration: true,
  repositories: [{"repository": "tkk2112/dotfiles"}]
  "vulnerabilityAlerts": {
    "enabled": true
  }
};
