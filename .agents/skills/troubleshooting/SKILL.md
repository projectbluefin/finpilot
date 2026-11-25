---
name: troubleshooting
description: >-
  Symptom to cause to fix for build, CI, and runtime failures, plus the
  pre-commit checklist. Use when something is broken or before opening a
  pull request.
---

# Troubleshooting

## Before a pull request

- [ ] Conventional Commit message.
- [ ] `just lint` — shellcheck on every tracked script.
- [ ] `just check` — Justfile syntax.
- [ ] `just test-unit` — the suite.
- [ ] `just validate-brewfiles` / `just validate-flatpaks` if those changed.
- [ ] `just build` if the image changed.

CI runs the same checks; running them locally only makes the pull request quiet.

## Build

| Symptom | Cause | Fix |
|---|---|---|
| `bootc container lint` fails on a nonempty `/run` | a script wrote to `/run` into an image layer | remove it in `90-cleanup.sh`; that phase deliberately does not mount `/run` as tmpfs |
| a third-party repository is live in the final image | a script enabled it and did not disable it | use `copr_install_isolated`, or disable it explicitly |
| the package layer rebuilds on every overlay edit | packages drifted into the overlay phase | keep packages in `20-packages-and-services.sh` |
| hadolint flags the Containerfile | a rule in `.github/hadolint.yaml` | fix it, or add a suppression with a reason |

## CI

| Symptom | Cause | Fix |
|---|---|---|
| `validate` never runs | branch protection names a check no workflow produces | the context must be exactly `validate` |
| Renovate logs a skip and opens nothing | `RENOVATE_TOKEN` is not set | expected; set the secret to turn Renovate on |
| Renovate fails on `Validate RENOVATE_TOKEN` | the token is expired or lacks the `workflow` scope | recreate the token |
| the promotion PR never opens | `stable` does not exist | create the branch |
| the promotion PR will not merge | `stable` requires an approval | set required approvals to 0 |
| an issue titled `ci: testing→main promotion conflict` opens | the shared promote workflow in `projectbluefin/actions` files that fixed title for *any* failure of its promote job, conflict or not; #796 was a transient GitHub API error (`502 Bad Gateway` from `gh` after the branch was already pushed) | open the run the issue links. If the failed step is `Build and maintain squash promotion PR` with a 5xx, and `auto/promote-main-to-stable`'s tree already matches `main` (`git rev-parse origin/main^{tree} origin/auto/promote-main-to-stable^{tree}`), nothing is wrong with the branches: re-run `promote-main-to-stable.yml` from the Actions tab so the gate and check approval run on the new head. The next successful run closes the issue itself |
| a Renovate PR waits forever | auto-merge is off | enable it in Settings |

## Runtime

The two most common first-boot surprises — no Flatpaks, and no `brew` — are in
the README's Troubleshooting section.

| Symptom | Cause | Fix |
|---|---|---|
| `ujust` shows no custom commands | `60-custom.just` was not written or imported | check that `10-overlay.sh` copied the recipes |

## Capturing what you learned

When a fix here was non-obvious, put it in the skill that owns the area, in the
same pull request. That is the only home for durable learning.
