status: sketch

This project encodes a linting policy to check for human-understandable git history. Use to make your PRs better.

usage:
```
history_lint.rb path/to/my/repo base_branch my_branch > stats.tsv
libreoffice stats.tsv
```

This shows a matrix of your commits and which files changed, and a score for each.
A higher score is worse.
