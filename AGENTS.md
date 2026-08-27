## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five canonical triage labels defined for this repository. See `docs/agents/triage-labels.md`.

### Domain docs

This repository uses a single-context domain-doc layout. See `docs/agents/domain.md`.

### CI infrastructure incidents

If GitHub Actions fails before repository commands run, do not change product code or repeatedly rerun the workflow. After two consecutive attempts show the same infrastructure error, follow the recovery policy in `docs/manual/09-local-docker-and-ci-testing.md`.
