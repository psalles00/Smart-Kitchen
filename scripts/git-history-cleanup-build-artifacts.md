# Git history cleanup for build artifacts

This is intentionally a guide, not an auto-run script.

Use it only after the current cleanup commit is reviewed and after coordinating with anyone else using this repository.
Rewriting history changes commit hashes and requires a force-push.

## What this removes from history

- build
- build-copilot-*
- build-copilot-*.log
- Backups
- ref
- device-recovery
- tmp-debug
- tmp-device-recovery
- .DS_Store

## Recommended tool

On macOS:

```bash
brew install git-filter-repo
```

## Safe workflow

1. Create a fresh mirror clone.
2. Rewrite history in the mirror clone only.
3. Validate size reduction.
4. Force-push the cleaned history.
5. Re-clone locally instead of trying to repair the old clone.

## Commands

```bash
git clone --mirror <REMOTE_URL> SmartKitchen-history-clean.git
cd SmartKitchen-history-clean.git

git filter-repo \
  --invert-paths \
  --path build \
  --path-glob 'build-copilot-*' \
  --path-glob 'build-copilot-*.log' \
  --path Backups \
  --path ref \
  --path device-recovery \
  --path tmp-debug \
  --path tmp-device-recovery \
  --path .DS_Store

git count-objects -vH
du -sh .

git push --force --mirror
```

## After the force-push

Every local clone should be replaced with a fresh clone.
If someone keeps the old clone and pulls, they will keep the old large history around.

## Notes

- This does not affect app runtime data, SwiftData stores, CloudKit containers, signing team, or entitlements.
- This only rewrites repository history.
- If you want an extra safety layer, archive the current repository folder before the mirror-clone rewrite.
