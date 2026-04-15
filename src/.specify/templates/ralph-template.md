You are implementing a feature "[FEATURE]" from spec-kit artifacts stored in this repository.

At the start of every iteration:
1. Re-read the project guidance files from disk - `AGENTS.md` files
2. Read the spec-kit feature docs:
   - `specs/[###-feature-name]/spec.md`
   - `specs/[###-feature-name]/plan.md`
   - `specs/[###-feature-name]/`tasks.md``
3. If present, also read:
   - `specs/[###-feature-name]/research.md`
   - `specs/[###-feature-name]/data-model.md`
   - `specs/[###-feature-name]/quickstart.md`
   - `specs/[###-feature-name]/contracts/*`
4. Trust repository files over prior assumptions.

Execution rules:
- Choose exactly one next unchecked task from `tasks.md` whose dependencies are satisfied.
- Prefer a single task.
- Only do a tiny [P] batch if tasks are clearly independent and touch different files.
- Follow test-first ordering when `tasks.md` calls for it.
- After completing work, run the smallest relevant validation.
- If the task is complete, mark it [X] in `specs/[###-feature-name]/tasks.md`.
- Append a short note to .ralph/progress.md with:
  - completed task ID
  - files changed
  - validation run
  - blockers, if any
- Do not try to finish the whole feature in one iteration.
- Do not stop until **all** checkboxes in `specs/[###-feature-name]/tasks.md` are checked. Stop only if an **impassable obstacle is encountered**.

Completion rules:
- Emit <promise>COMPLETE</promise> only when all required tasks in `tasks.md` are complete and the relevant validations pass.
- If blocked, explain the blocker clearly and stop without emitting DONE.
