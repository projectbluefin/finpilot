---
name: skill-improvement
description: Record durable finpilot-specific learning after discovering a command, convention, workaround, or failure mode.
---

# Skill Improvement

## When to Use

- A task reveals a finpilot-specific command, constraint, workaround, or
  failure mode.
- Updating a local skill, task router, or agent instruction.
- Preparing a pull request or handoff after nontrivial work.

## When NOT to Use

- The finding is a factory-wide rule owned by `projectbluefin/common`.
- The information is transient task state, a backlog item, or a resolved PR.
- The work contains no reusable learning.

## Core Process

1. Decide whether the finding is specific to finpilot or factory-wide.
2. Update the closest relevant local skill with the timeless operating rule and
   its validation command.
3. Route factory-wide learning to `projectbluefin/common`; never edit
   `ublue-os/*`.
4. Validate the updated guidance in the same change as the implementation.

Do not create changelogs, session logs, task notes, or "append here" documents.
They become stale and are not part of the repository knowledge base. Keep
temporary state in the agent session workspace and record only verified,
reusable guidance in a skill.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "The lesson is obvious." | If it changed how this task was performed, future agents need it. |
| "I will document it later." | The implementation context is most accurate in the same PR. |
| "A session note is quicker." | Session notes rot; skills are the durable operating model. |

## Red Flags

- A nontrivial task ends without a relevant skill update.
- A skill contains session history, an issue list, or unresolved task state.
- A finpilot-specific lesson is written only in a PR comment or commit message.

## Verification

- Confirm the learning is specific to finpilot rather than a factory-wide rule.
- Update the relevant skill with the command, boundary, and validation evidence.
- Route factory-wide learning to `projectbluefin/common`; never edit
  `ublue-os/*`.
