# Plan — move this project's git remote to `github.com/lediz/hix` (branch `enhance`)

Status: **EXECUTED** — see §9 for the record. Original findings below are read-only observations.
Recorded: repo `/home/jack/Projects/hix-unified`, git 2.56.0.

---

## 0. Interpreting the target

`https://github.com/lediz/hix/tree/enhance` is a **web URL**, not a remote URL. It decomposes to:

- remote: `https://github.com/lediz/hix.git`
- branch: `enhance`

Goal: remote → `https://github.com/lediz/hix.git`, with this project's work published on branch `enhance`.

---

## 1. Current state (verified)

| Item | Value |
|---|---|
| Remotes | `upstream-hix` → `/home/jack/Projects/hix` (fetch), pushurl `DISABLED` |
| Current branch | `main` @ `8bd9726` ("docs: correct the counts and the test-mode caveats") |
| Upstream of `main` | `upstream-hix/main` @ `2e67926`, **ahead 33** |
| Working tree | clean (0 dirty files) |
| Tags | `v2.2`, `v2.1`, `v2.00.03`, `v2.00`, `ia-v0.2.1` |
| GitHub repo | exists, anonymously readable; branches `main` **and** `enhance`, both @ `ab31bb4` |
| GitHub tags | none |
| Size / LFS / submodules | 15.76 MiB pack, no LFS, no submodules, `.gitattributes` present |
| Worktrees | only `/home/jack/Projects/hix-unified` |

Sibling repo `/home/jack/Projects/hix` already has `origin` → `https://github.com/lediz/hix.git` with push `DISABLED` (read-only mirror by design). Its `origin/main` ref is stale at `8095424`.

---

## 2. Critical finding — the histories have diverged

- Common ancestor of local `main` and GitHub `main`/`enhance`: `8095424` ("2.2.01 Independent-audit").
- Local `main` is **36 commits ahead** of that ancestor.
- GitHub `enhance`/`main` carries **7 commits not present locally**:
  `abcd6ae` … `ab31bb4` — "Vrs. 2.3 - WDO MySql" → "2.3.10 Move /dll to /resources/dll" (Carles Aubia, 2026-10-05).
- Consequence: pushing local `main` to `enhance` is a **non-fast-forward**. It requires either a merge/rebase first, or a destructive `--force` that deletes those 7 upstream commits from `enhance`.

**Decision A (required):** merge upstream `enhance` into local `main` before pushing (recommended, non-destructive), **or** force-push (only if `enhance` is owned and those 7 commits are already superseded by the unified tree).

---

## 3. Blocker — no GitHub credentials exist

- `gh` CLI installed but **not logged in**.
- No credential helper (global or local), no `~/.git-credentials`, no `~/.netrc`.
- No SSH keys (`ssh -T git@github.com` → `Permission denied (publickey)`).
- `git ls-remote` works only because the repo is public — **push will fail until auth is set up**.

**Step 0 (prerequisite):** `gh auth login`, or a fine-grained PAT with Contents: Read/Write on `lediz/hix`, or add an SSH key and use `git@github.com:lediz/hix.git`.

→ See **`GIT_AUTH_PLAN.md`** for the full auth plan (verified auth surface, four options, verification gate, revocation). Note it also establishes that `lediz/hix` is a **fork of `carles9000/hix`**, which must be resolved before assuming push access to `enhance`.

---

## 4. Recommended plan

### Step 1 — add the GitHub remote (keep `upstream-hix`)

```bash
cd /home/jack/Projects/hix-unified
git remote add origin https://github.com/lediz/hix.git
git fetch origin
```

Rationale: `upstream-hix` is the local import source for the unified tree; removing it loses the ability to re-sync. Rename it to `hix-local` if clearer. Only delete it for a true "move".

### Step 2 — reconcile with `enhance` (Decision A)

```bash
git checkout main
git merge origin/enhance        # resolve conflicts, keep unified layout
```

Alternative, if force is intended:

```bash
git push --force-with-lease origin main:enhance
```

### Step 3 — publish on branch `enhance`

```bash
git push -u origin main:enhance
```

Local branch is named `main`; `-u` sets `origin/enhance` as its upstream, overriding `branch.main.remote/merge` (currently `upstream-hix` / `refs/heads/main`). For a 1:1 name, `git branch -m main enhance` first — that also changes the local default branch name.

### Step 4 — retarget HEAD / upstream (optional)

```bash
git remote set-head origin enhance
git branch --set-upstream-to=origin/enhance main
```

### Step 5 — push tags (GitHub has none, so no conflicts)

```bash
git push origin --tags
```

### Step 6 — keep the old push path disabled explicitly

```bash
git remote set-url --push upstream-hix DISABLED
```

---

## 5. Verification

```bash
git remote -v
git branch -vv                      # expect: main ... [origin/enhance]
git status -sb                      # expect: ## main...origin/enhance
git ls-remote --heads origin        # enhance tip == git rev-parse main
```

---

## 6. Rollback

```bash
git remote remove origin
git branch --set-upstream-to=upstream-hix/main main
```

Steps 1–2 rewrite no history, so rollback is trivial. A force-push (Step 2 alternative) is **not** reversible without the saved tip — record `ab31bb4d407204245adb2af62f1232a8b67e5b8a` before any force.

---

## 7. Risks / open questions

1. **Auth missing** — hard blocker; nothing pushable until Step 0 is done.
2. **Force-push would drop 7 upstream commits** from `enhance`. GitHub `main` sits at the same commit `ab31bb4` — do not touch `main` unless intended.
3. **`enhance` currently equals `main` on GitHub** — confirm `enhance` is the intended working branch, versus a new name such as `unified`.
4. Global config has `pull.rebase=true` and `push.autosetupremote=true` — the latter can silently create a same-named remote branch; use explicit `main:enhance` refspecs.
5. Commit identity is `Jack <jack@jackllm.local>` — GitHub will not attribute these 36 commits to your account unless that email is verified or the commits are rewritten.

---

## 8. Key SHAs (for reference / recovery)

| Ref | SHA |
|---|---|
| local `main` | `8bd9726` |
| `upstream-hix/main` | `2e679260e1bd51801012104cde682b1c533e0955` |
| GitHub `main` == GitHub `enhance` | `ab31bb4d407204245adb2af62f1232a8b67e5b8a` |
| merge-base (local vs GitHub) | `8095424545b63a211a622bfd48e3da4f70672e64` |

---

## 9. Execution record

Defaults used: **A**=merge, **B**=publish to `enhance`, **C**=keep `upstream-hix`, **D**=rewrite identity.

**Revision to C (later the same day):** `upstream-hix` (`/home/jack/Projects/hix`) was **removed**. The only remote is now `origin`, and `enhance` tracks `origin/enhance`. Rationale: after the identity rewrite the sibling repo still held the pre-rewrite commits (`2e67926` etc.), which are no longer ancestors of `enhance`; merging from it would have reintroduced `jack@jackllm.local` commits. To restore it deliberately: `git remote add upstream-hix /home/jack/Projects/hix`.

```bash
git remote add origin https://github.com/lediz/hix.git
git fetch origin                      # 36 local-only / 7 remote-only
git merge --no-edit origin/enhance    # 0 conflicts → 88fbe5c (parents 8bd9726 + ab31bb4)
git push -u origin main:enhance       # ab31bb4..88fbe5c, fast-forward, no force
git push origin --tags                # v2.2 v2.1 v2.00.03 v2.00 ia-v0.2.1
git remote set-head origin enhance
# (later) git remote remove upstream-hix   -- see the revision note above
gh api -X PATCH repos/lediz/hix -f default_branch=enhance
git branch -m main enhance            # local branch renamed to match
```

Outcome: `origin/enhance` is the default branch and carries the unified tree; `origin/main` remains at `ab31bb4` (untouched); the 7 upstream commits are preserved through the merge rather than a force-push. Upstream's `dll/ → resources/dll/` rename applied cleanly, with `UNIFIED.md` updated to match.

Post-execution note: history was subsequently rewritten so the 36 local commits carry `lediz <14312216+lediz@users.noreply.github.com>` instead of `jack@jackllm.local`; upstream commits (Carles Aubia) were left byte-identical. The SHAs in §8 above are therefore pre-rewrite values.
