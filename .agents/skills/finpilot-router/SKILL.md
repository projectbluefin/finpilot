---
name: finpilot-router
description: >-
  Task router for the finpilot repo: which skill covers what, and the
  overview → domain → PR-checklist sequence. Use when unsure which skill
  fits, or to add a skill to the routing table.
---

# finpilot Router

## When to Use

- You don't know which skill covers your task
- You want the standard sequence before starting a multi-phase task
- You are adding, renaming, or removing a skill
- You are onboarding a new agent or contributor

## When NOT to Use

- You already know the area — load the matching skill directly, not this one
- You need mechanics (build, CI, runtime) — those live in the domain skills

## Core Process

1. **Run the standard sequence** for an unfamiliar multi-phase task: start with
   `finpilot-overview`, continue with the domain skill, finish with
   `finpilot-pr-checklist`.
2. **Find your task in the table** below and load the matching skill.

| I need to…                                     | Load                                      |
| ---------------------------------------------- | ----------------------------------------- |
| Bootstrap a new fork                           | `finpilot-onboarding`                  |
| Add/remove a package                           | `finpilot-packages`                    |
| Change Brewfiles, Flatpaks, or ujust           | `finpilot-custom`                      |
| Change Containerfile, Justfile, or build/\*.sh | `finpilot-build`                       |
| Fix CI or Renovate                             | `finpilot-ci` / `finpilot-maintain`    |
| Open a PR                                      | `finpilot-pr-checklist`                |
| Debug a build or deploy failure                | `finpilot-troubleshooting`             |
| Follow a worked example                        | `finpilot-examples`                    |
| Initialize/ rename this template               | `finpilot-templates`                   |
| Orient to repo architecture                    | `finpilot-overview`                    |
| Capture a durable lesson                       | `skill-improvement`                    |
| Pick a skill for a new task                    | `finpilot-router` (this skill)         |

## Common Rationalizations

| Rationalization                                          | Reality                                              |
| -------------------------------------------------------- | ---------------------------------------------------- |
| "The router table is in AGENTS.md — update it there."    | AGENTS.md holds rules. This skill owns the routing table, so it stays in sync with the skill set. |
| "Every skill should list where it fits."                 | One table means one place to update; skills point here instead. |

## Red Flags

- A second routing table appears in AGENTS.md, `.agents/skills/README.md`, or a skill — route edits to this file
- A new skill exists but is missing from this table

## Verification

- [ ] The table lists every skill in `.agents/skills/`
- [ ] AGENTS.md and `.agents/skills/README.md` point here instead of carrying their own tables
- [ ] `name` frontmatter matches the directory name
