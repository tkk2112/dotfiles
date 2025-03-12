module.exports = {
  extends: [
    "config:recommended",
    ":dependencyDashboard",
    ":semanticCommits",
    ":enablePreCommit"
  ],
  labels: ["dependencies"],
  repositories: [{"repository": "tkk2112/dotfiles"}]
};