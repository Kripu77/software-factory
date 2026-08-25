---
name: deslop
description: Use after implement, before review, to strip AI slop from the branch vs main.
---

# Remove AI code slop

Diff against main. Remove slop introduced on this branch. Keep behavior.

- Extra comments
- Abnormal defensive checks or try/catch on trusted paths
- `any` / panic casts used only to bypass types
- Nested spaghetti that wants an early return
- Style that does not match the file

Keep the summary to 1-3 sentences. Do not merge.
