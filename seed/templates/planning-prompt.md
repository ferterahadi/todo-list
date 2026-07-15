# Planning Prompt

Use this prompt to kick off a planning session for any project folder.

---

## Prompt (copy-paste, fill in the @path)

```
I want you to help me plan this project: @projects/work/<project-name>

Do the following end to end:

1. **Ask me questions first** — before writing anything, ask me:
   - What is this project? What problem does it solve?
   - Where does it live? (repo, service, system)
   - What's the expected outcome / definition of done?
   - Any constraints? (deadline, tech stack, team dependencies)
   - Any prior work or context I should point you to?

2. **Research** — once I answer, if I point you to a codebase or doc, read it and extract relevant context. Summarize what you found in research/findings.md.

3. **Write plan.md** — fill in the project's plan.md with goal, context, constraints, scope, and key decisions based on what I told you and what you found.

4. **Write tasks.md** — break the work into a concrete checklist. Each task should be specific enough that a future agent session can execute it without asking questions.

5. **Confirm** — show me plan.md and tasks.md and ask if anything needs adjusting before we finalize.

Start with step 1.
```

---

## Tips

- Swap `@projects/work/<project-name>` with the actual folder path
- If the project touches another repo, add it: `@/path/to/other/repo`
- After planning is done, future sessions just need: `@projects/work/<project-name> — work through tasks.md`
