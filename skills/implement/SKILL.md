---
name: implement
description: Use when implementing a spec or GitHub ticket in this checkout.
---

# Implement

Implement only the ticket you were given.

1. Read CONTEXT-MAP, this repo CONTEXT.md, ADRs, docs/agents if they exist.
2. Find a similar, recently-merged example in this repo (a file or PR doing the same kind of thing) and match its patterns. If none exists, say so in the PR description.
3. Use `/tdd` at pre-agreed seams.
4. Typecheck often. Run focused tests often. Full suite once at the end.
5. `/unslop` against main.
6. Open or update a PR. Do not merge.
7. Stop and ask for `/code-review` then `/loop-on-ci`.

## Review feedback

When you act on a review comment on your PR, resolve its thread. Threads you did not act on, or replied to with a dispute, stay unresolved with a reply.

```bash
# List threads with ids
gh api graphql -f query='query($owner:String!,$name:String!,$pr:Int!){repository(owner:$owner,name:$name){pullRequest(number:$pr){reviewThreads(first:100){nodes{id isResolved comments(first:1){nodes{path body}}}}}}}' -F owner=<owner> -F name=<repo> -F pr=<number>

# Resolve one addressed thread
gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -F id=<thread-id>

# Reply to a skipped or disputed thread (leave unresolved)
gh api graphql -f query='mutation($id:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id,body:$body}){comment{url}}}' -F id=<thread-id> -f body='<why skipped or disputed>'
```

## Extra rules

- No code comments
- Small focused changes
- Do not refactor adjacent code unless the ticket says so
- No type assertions; follow local TypeScript/Go practice
- PR title: `Type/<issue.number>/<short description>` (Feat, Bug, Arch, Chore, Refactor, General)
- PR description: human, at most 3 sentences, then mermaid. Feature: before and after when a prior shape exists, after-only when net-new. Bug: before and after. Use short paragraphs with a blank line between them. A blank line before any list or fence. Cite the ticket as a markdown link. A line never starts with #n. After-state mermaid also lands in the product repo docs tree in the same PR. Update the existing page for that subsystem. Do not add a new file per PR. If the bug revealed a missing architecture page, add that page and persist only the corrected after-state. README or QUICKSTART only when the diagram is user-facing. Internals stay in docs. Bug before-state stays on the PR.
- Never merge. A person merges.
