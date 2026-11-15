# this fork

Personal fork of [cursor/plugins](https://github.com/cursor/plugins), used to run a customized pstack in Claude Code.

## layout

- `pstack/` is the source. Edit here.
- `harness/pstack/claude-code/` is the Claude Code build, generated from `pstack/`. Never edit it by hand.
- `.claude-plugin/marketplace.json` is renamed to `pstack-fork`, so it never clashes with the official `cursor-plugins` marketplace.
- `fork/` and `.github/workflows/sync-upstream.yml` exist only in this fork.

## change pstack

```bash
# edit pstack/skills/..., pstack/agents/..., etc.
node scripts/generate-pstack-harness-trees.mjs
git add -A && git commit -m "feat(pstack): ..." && git push
claude plugin marketplace update pstack-fork
claude plugin update pstack@pstack-fork
```

Restart Claude Code (or start a new session) to pick up the new version.

## stay in sync with upstream

- **Automatic:** `.github/workflows/sync-upstream.yml` runs every Monday at 06:17 UTC (or on demand from the Actions tab). It merges `cursor/plugins` main into this fork's `main`, regenerates the Claude tree, and pushes.
- **By hand:** `fork/sync-upstream.sh --push`. The report is written to `.git/pstack-sync-report.md`.

### the report

Before each merge the script compares two things under `pstack/`: everything this fork changed relative to upstream, and everything upstream changed since the last sync. For each file in both lists, the report shows how upstream changed it, plus your own diff for comparison.

- **Overlap, clean merge:** the merge is pushed, and an issue titled "pstack sync: upstream changed files you changed" lists the diffs.
- **Conflict:** nothing is merged or pushed. An issue titled "pstack sync: merge conflicts" lists the diffs and the conflicted files, and the run fails.
- **No overlap:** the merge is pushed quietly. The run summary still shows the counts.

If the workflow can't open an issue (issues are off on the fork), the run fails instead, so GitHub emails you. The full report is on the run's summary page.

The sync merges and never rebases, so your commits stay intact and history is never force-pushed. Conflicts inside `harness/pstack/` resolve themselves, because the tree is regenerated. Conflicts in `.claude-plugin/marketplace.json` keep the fork's version. Any other conflict is a real clash between your edit and upstream's, and you resolve it by hand.

## install (once)

```bash
claude plugin marketplace add krishchilvery/cursor-plugins
claude plugin install pstack@pstack-fork
```

Then run `/pstack:setup-pstack` once.
