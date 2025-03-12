module.exports = {
  // General settings
  extends: [
    'config:base',
    ':dependencyDashboard',
    ':semanticCommits',
    ':enablePreCommit',
  ],

  // Default label for PRs
  labels: ['dependencies'],

  // Pre-commit hooks manager
  regexManagers: [
    {
      fileMatch: ['(^|/)\.pre-commit-config\.yaml$'],
      matchStrings: [
        // Match pre-commit hook entries
        'repo: (?<depName>.*?)\n *rev: (?<currentValue>.*?)\n',
      ],
      datasourceTemplate: 'github-releases',
    },
  ],

  // Automatically merge minor and patch updates if tests pass
  packageRules: [
    {
      matchManagers: ['regex'],
      matchFileNames: ['**/.pre-commit-config.yaml'],
      automerge: true,
      automergeType: 'branch',
      matchUpdateTypes: ['minor', 'patch'],
    },
  ],

  // Standard repository configuration
  repositories: [
    {
      repository: "tkk2112/dotfiles" // Replace with your actual GitHub username
    }
  ],
};
