---
name: close-task
description: The only way a bead gets closed. Reads the bead's acceptance criteria, checks each against named evidence, and closes with bd close only if every criterion has proof.
argument-hint: "<bead-id>"
---

# close-task

Never run `bd close` outside this skill.

## Procedure

1. `bd show $0`. Extract the **Acceptance Criteria** block. If it is empty, do not close; say the bead has no criteria and stop.
2. Split the criteria into individual items. For each item, find **named evidence** of one of these kinds:
   - a **file**: path, and the relevant lines or bytes (`ls -l`, `head`, hexdump, image opened)
   - **command output**: the exact command and the lines that satisfy the criterion
   - **seen on screen**: something I (the user) stated in this conversation that I saw — quote my words. Never assume I saw it.
   Evidence must exist now, in this session's transcript or on disk. "It should work" or "the code does X" is not evidence.
3. Build a table: criterion → evidence (kind + name) → PASS / MISSING.
4. If any row is MISSING: **do not close.** Print the table and say exactly what is missing and what would prove it.
5. If every row is PASS: write the table as the reason and close:
   ```bash
   bd close $0 --reason "$(cat <<'R'
   criterion 1: <text> — evidence: <kind> <name/lines>
   criterion 2: ...
   R
   )"
   ```
   Then `bd show $0` and confirm status is `closed`.
6. If the bead owns a PRD §12 "Not yet verified" item, the reason must also state the verification result in one line (verified / not verified / partial, and what was observed).

## Rules
- One bead per invocation. No `--force`.
- Do not edit acceptance criteria to make them pass.
