%% lat:begin %%
# Before starting work

- Run `lat search` to find sections relevant to your task. Read them to understand the design intent before writing code.
- Run `lat expand` on user prompts to expand any `[[refs]]` — this resolves section names to file locations and provides context.

# Post-task checklist (REQUIRED — do not skip)

After EVERY task, before responding to the user:

- [ ] Update `lat.md/` if you added or changed any functionality, architecture, tests, or behavior
- [ ] Run `lat check` — all wiki links and code refs must pass
- [ ] Do not skip these steps. Do not consider your task done until both are complete.

---

# What is lat.md?

This project uses [lat.md](https://www.npmjs.com/package/lat.md) to maintain a structured knowledge graph of its architecture, design decisions, and test specs in the `lat.md/` directory. It is a set of cross-linked markdown files that describe **what** this project does and **why** — the domain concepts, key design decisions, business logic, and test specifications. Use it to ground your work in the actual architecture rather than guessing.

# Commands

```bash
lat locate "Section Name"      # find a section by name (exact, fuzzy)
lat refs "file#Section"        # find what references a section
lat search "natural language"  # semantic search across all sections
lat expand "user prompt text"  # expand [[refs]] to resolved locations
lat check                      # validate all links and code refs
```

Run `lat --help` when in doubt about available commands or options.

If `lat search` fails because no API key is configured, explain to the user that semantic search requires a key provided via `LAT_LLM_KEY` (direct value), `LAT_LLM_KEY_FILE` (path to key file), or `LAT_LLM_KEY_HELPER` (command that prints the key). Supported key prefixes: `sk-...` (OpenAI) or `vck_...` (Vercel). If the user doesn't want to set it up, use `lat locate` for direct lookups instead.

# Syntax primer

- **Section ids**: `lat.md/path/to/file#Heading#SubHeading` — full form uses project-root-relative path (e.g. `lat.md/tests/search#RAG Replay Tests`). Short form uses bare file name when unique (e.g. `search#RAG Replay Tests`, `cli#search#Indexing`).
- **Wiki links**: `[[target]]` or `[[target|alias]]` — cross-references between sections. Can also reference source code: `[[src/foo.ts#myFunction]]`.
- **Source code links**: Wiki links in `lat.md/` files can reference functions, classes, constants, and methods in TypeScript/JavaScript/Python/Rust/Go/C files. Use the full path: `[[src/config.ts#getConfigDir]]`, `[[src/server.ts#App#listen]]` (class method), `[[lib/utils.py#parse_args]]`, `[[src/lib.rs#Greeter#greet]]` (Rust impl method), `[[src/app.go#Greeter#Greet]]` (Go method), `[[src/app.h#Greeter]]` (C struct). `lat check` validates these exist.
- **Code refs**: `// @lat: [[section-id]]` (JS/TS/Rust/Go/C) or `# @lat: [[section-id]]` (Python) — ties source code to concepts

# Test specs

Key tests can be described as sections in `lat.md/` files (e.g. `tests.md`). Add frontmatter to require that every leaf section is referenced by a `// @lat:` or `# @lat:` comment in test code:

```markdown
---
lat:
  require-code-mention: true
---
# Tests

Authentication and authorization test specifications.

## User login

Verify credential validation and error handling for the login endpoint.

### Rejects expired tokens
Tokens past their expiry timestamp are rejected with 401, even if otherwise valid.

### Handles missing password
Login request without a password field returns 400 with a descriptive error.
```

Every section MUST have a description — at least one sentence explaining what the test verifies and why. Empty sections with just a heading are not acceptable. (This is a specific case of the general leading paragraph rule below.)

Each test in code should reference its spec with exactly one comment placed next to the relevant test — not at the top of the file:

```python
# @lat: [[tests#User login#Rejects expired tokens]]
def test_rejects_expired_tokens():
    ...

# @lat: [[tests#User login#Handles missing password]]
def test_handles_missing_password():
    ...
```

Do not duplicate refs. One `@lat:` comment per spec section, placed at the test that covers it. `lat check` will flag any spec section not covered by a code reference, and any code reference pointing to a nonexistent section.

# Section structure

Every section in `lat.md/` **must** have a leading paragraph — at least one sentence immediately after the heading, before any child headings or other block content. The first paragraph must be ≤250 characters (excluding `[[wiki link]]` content). This paragraph serves as the section's overview and is used in search results, command output, and RAG context — keeping it concise guarantees the section's essence is always captured.

```markdown
# Good Section

Brief overview of what this section documents and why it matters.

More detail can go in subsequent paragraphs, code blocks, or lists.

## Child heading

Details about this child topic.
```

```markdown
# Bad Section

## Child heading

Details about this child topic.
```

The second example is invalid because `Bad Section` has no leading paragraph. `lat check` validates this rule and reports errors for missing or overly long leading paragraphs.
%% lat:end %%

# Development workflow (REQUIRED for every task and every skill)

These rules bind all work in this repository, including work done inside any skill. Repository: `helpmebrands/reward-app`. Integration branch: `develop`.

## 1. Conventional commits

Every commit message follows [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary`, imperative mood, lower-case summary, no trailing period. Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `build`, `ci`, `perf`. Reference the issue in the footer (`Closes #123` or `Refs #123`). Breaking changes use `!` after the type and a `BREAKING CHANGE:` footer.

## 2. Brainstorms become issues

Any brainstorm, planning session or bug analysis for a fix or a feature ends by creating a GitHub issue with `gh issue create`. Do not leave the outcome only in chat. The issue body carries the problem, the agreed approach, and acceptance criteria written as testable statements.

## 3. Large work becomes an Epic with sub-issues

When the work is large or complex (more than one PR's worth), create one issue whose title begins with `EPIC: ` describing the goal, then one sub-issue per implementation task. No label is needed: an issue that contains sub-issues is an epic. Each sub-issue must be independently implementable and independently testable. Attach sub-issues to the epic:

```sh
gh issue create --title "EPIC: <goal>" --body "<goal, scope, done criteria>"
gh issue create --title "<task>" --body "Part of #<epic>. <acceptance criteria>"
# link: the REST endpoint needs the sub-issue's numeric database id, not its number
gh api "repos/{owner}/{repo}/issues/<epic>/sub_issues" \
  -F sub_issue_id="$(gh api repos/{owner}/{repo}/issues/<sub> --jq .id)"
```

## 4. Implementation entry points

Most development runs at the epic level with `implement epic ###` (skill `implement-epic`). A single issue can be run with `implement issue ###` (skill `implement-issue`). Both skills apply rules 5 to 8 below.

## 5. TDD, red then green

For every behaviour change: write the failing test first (`npm test` must show it red), then write the minimum code to make it pass (green), then refactor with the suite still green. Do not write implementation before a failing test exists. Tests live in `tests/`, run under Vitest, and the pure domain layer in `src/domain/` is where most tests belong. Update `lat.md/` test specs when tests are added.

## 6. Worktrees, always

All development happens on a git worktree, never on the checkout in the main working directory. One worktree per issue, on a branch named `<type>/<issue#>-<slug>` (e.g. `feat/42-locked-credit-reminders`), created from up-to-date `develop`. Use the `EnterWorktree` tool when available; otherwise `git worktree add ../reward-app-<issue#> -b <branch> develop`.

## 7. Epic flow: auto-merge sub-issues, human gate on the epic

When implementing an epic, work through its open sub-issues in order. For each sub-issue: worktree, TDD, commit, open a PR against `develop`, wait for CI to pass, merge it automatically (`gh pr merge --squash --delete-branch`), then remove the worktree. After the last sub-issue is merged, stop and ask the human before closing the epic. Never close the epic without that approval.

## 8. Issue flow: PR, then human gate

When implementing a single issue: worktree, TDD, commit, open a PR against `develop`, then stop and ask the human. Only on their approval: merge the PR, remove the worktree, and close the issue. Do not merge without that approval.

## 9. Flutter and Dart rules

These rules apply to all Flutter and Dart code in this repository, including the Flutter app introduced by epic #64.

- **Formatting**: all Dart code must be formatted with `flutter format .` before committing.
- **Packages**: only [Flutter Favorite](https://pub.dev/packages?q=is%3Aflutter-favorite) packages may be added without confirmation. Any other package choice must be approved by a human before it is added to `pubspec.yaml`.
- **Native dependencies**: use Swift Package Manager for iOS and macOS dependencies. Do not introduce CocoaPods without human approval.
- **UI library**: use the Material library for UI. Do not use Cupertino widgets.
- **Widget Preview**: every UI component must be available in Widget Preview (a `@Preview` in `previews.dart` or alongside the widget).
- **Flutter version**: the minimum supported Flutter version is 3.35. Do not rely on APIs that require a newer version without human approval.
