# Plan — resolve the missing GitHub auth

Status: **EXECUTED** — auth resolved and scopes trimmed; see `GIT_REMOTE_MIGRATION_PLAN.md` §9 for the migration record. Original findings below are read-only probes.
Companion document: `GIT_REMOTE_MIGRATION_PLAN.md` (this is Step 0 / the blocker in that plan).

---

## 1. Auth surface on this machine (verified)

| Item | State |
|---|---|
| `gh` CLI | **v2.102.0 installed**, `~/.config/gh` absent → never authenticated |
| `credential.helper` | unset in local, `~/.config/git/config` (global, 969 B), and system (no `/etc/gitconfig`) |
| Credential stores | `~/.git-credentials`, `~/.netrc` — absent |
| SSH | `~/.ssh` contains **only `known_hosts`** (created by a probe); no keys; `ssh -T git@github.com` → `Permission denied (publickey)`; `ssh-keygen` available |
| Secret Service | **available** — `org.freedesktop.secrets` owned by `gnome-keyring-daemon` (pid 1270); `/usr/lib/git-core/git-credential-libsecret` exists and runs clean (rc=0, no error) |
| git built-in helpers | `credential-store`, `credential-cache`, `credential-libsecret` all present in `/usr/lib/git-core/` |
| Network | `api.github.com` → HTTP 200, 0.4 s, no proxy |
| API rate limit | unauthenticated: **27/60 remaining** (shared IP) — a token also fixes this |
| Browser for device flow | `xdg-open` + `chromium` present → `gh auth login --web` viable headlessly |
| Token env vars | none (`GH_TOKEN`, `GITHUB_TOKEN` unset) |

---

## 2. Finding that changes the auth question

`lediz/hix` is a **fork of `carles9000/hix`** (public, owner `lediz`, id `14312216`). Unauthenticated API returns `permissions: null`, so write access is unknowable until you authenticate.

**Step A — confirm identity/access before choosing a mechanism:**

- If you **are** `lediz` → direct push to `enhance` works.
- If you are **not** `lediz` → you cannot push to `lediz/hix` at all. Fallback: fork to your own account, push `enhance` there, open a PR into `lediz/hix:enhance`. This changes the remote URL in the migration plan.

Also note: the fork's `pushed_at` is `2026-10-06T02:14:50Z`, ~10 h newer than the `enhance` tip `ab31bb4` — there has been recent activity; re-fetch before pushing.

---

## 3. Option 1 — `gh auth login` + gh as git credential helper (recommended)

```bash
gh auth login --hostname github.com --git-protocol https --web   # device code, open in chromium
gh auth setup-git                                               # wires gh in as git credential helper
gh auth status
gh api repos/lediz/hix --jq .permissions                        # expect push: true
```

- Runs in your own terminal (interactive TTY — cannot be driven from an agent shell).
- Token stored in `~/.config/gh/hosts.yml` (plaintext, 0600) or keyring if gh detects it.
- Bonus: raises API limit to 5000/hr, enables `gh repo view` / PR creation for the divergence step.
- Scopes gh requests: `repo`, `read:org` (classic-token equivalent). For least privilege prefer Option 2.

---

## 4. Option 2 — fine-grained PAT + gnome-keyring via libsecret (least privilege, no gh)

1. Create token: `https://github.com/settings/personal-access-tokens/new`
   - Resource owner: **lediz** → Repository: **hix** only
   - Permissions: **Contents: Read and write** (add *Pull requests: Read and write* if PRs wanted)
   - Expiration: set one (e.g. 90 days)
2. Register the helper (already installed, just unconfigured):

```bash
git config --global credential.https://github.com.helper libsecret
```

3. First `git push` prompts for username + token → stored in the login keyring.
4. Verify: `secret-tool search --all service github.com` (or `git credential fill` in a test).

---

## 5. Option 3 — SSH key (if you prefer no token expiry)

```bash
ssh-keygen -t ed25519 -C "hix-unified" -f ~/.ssh/id_ed25519 -N ''
cat ~/.ssh/id_ed25519.pub     # add at https://github.com/settings/keys
ssh -T git@github.com         # expect: Hi <login>!
```

Then the remote becomes `git@github.com:lediz/hix.git` instead of the HTTPS URL — a deviation from the target URL in the migration plan, so pick this only deliberately.

---

## 6. Option 4 — plaintext `~/.git-credentials` (not recommended)

```bash
git config --global credential.helper store
```

Writes an unencrypted token to disk. Only acceptable in a throwaway/ephemeral environment. If used: `chmod 600 ~/.git-credentials`.

---

## 7. Never do these (token-leak patterns)

- `git remote set-url https://user:TOKEN@github.com/...` — embeds the token in `.git/config`, reflogs, and error output.
- Pasting the token into a chat, a commit message, or a shell command line (it lands in `~/.bash_history`). Use an interactive prompt or `read -rs`.
- Committing `.git-credentials` / `.netrc` into the repo.

---

## 8. Post-auth verification (gate before any push)

```bash
gh auth status                                                  # or: git credential fill (protocol=https host=github.com)
gh api repos/lediz/hix --jq '{p:.permissions,u:.user.login}'   # push must be true
git ls-remote https://github.com/lediz/hix                    # now rate-limited per-account
```

---

## 9. Related follow-up — commit attribution

Local identity is `Jack <jack@jackllm.local>`, which GitHub will not link or verify. After auth, decide:

- set `git config user.email "14312216+lediz@users.noreply.github.com"` (the account's noreply address; `gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"'`) for future commits — **substitute the placeholder, do not copy it verbatim** (an unfilled `<your-github-noreply>` once landed in `.git/config`)
- accept the 36 existing commits as unlinked, or rewrite them (`git filter-repo` / rebase) **before** the first push — cheaper to decide now than after the branch is public.
- Optional: enable commit signing (`gpg` or `ssh` key) so pushed commits show as Verified.

---

## 10. Revocation / rollback

```bash
gh auth logout                              # removes gh session + helper
git config --global --unset credential.https://github.com.helper
```

### Scope maintenance — `gh auth refresh` (not `refresh-scopes`)

`gh` 2.102.0 has no `refresh-scopes` subcommand. `gh auth` offers: `login`, `logout`, `refresh`, `setup-git`, `status`, `switch`, `token`.

```bash
gh auth refresh --remove-scopes workflow    # idempotent removal of listed scopes
gh auth refresh --reset-scopes              # back to gh's default set
gh auth refresh --scopes repo,read:org      # exact set (subject to the caveat below)
```

- **Irreducible minimum for gh OAuth: `repo`, `read:org`, `gist`** — they cannot be removed. `workflow` is the only commonly-present scope that can be dropped.
- `gh auth login -s/--scopes` only *adds* scopes; it cannot go below that baseline.
- `refresh` requires an interactive TTY (web/device flow) and **mints a new token**. Verify afterwards:
  ```bash
  gh auth status                                   # confirm the scope list
  gh auth token | tr -d '\n' | sha256sum | cut -c1-12   # fingerprint should change
  ```
- **Server-side revocation of an OAuth token is UI-only**: `https://github.com/settings/applications` → *Authorized OAuth Apps* → **GitHub CLI** → Revoke. This invalidates *every* gh token for the account. `gh api /applications/grants` returns `404` (deprecated) — there is no self-service REST revoke.
- Fine-grained PATs (Option 2) are the exception: individually revocable at `https://github.com/settings/tokens`, which is the main operational argument for preferring them.

---

## 11. Recommended sequence

1. Answer Step A (are you `lediz`?) — determines whether the migration plan's remote URL is even valid.
2. Run Option 1 in your terminal (fastest, unblocks everything, also fixes rate limits).
3. Run the §8 verification gate; record the `permissions.push` result.
4. Only then return to `GIT_REMOTE_MIGRATION_PLAN.md` Step 1 (`git remote add origin …`).

---

## 12. Open decisions

| # | Question | Blocks |
|---|---|---|
| A | Is the authenticated GitHub account `lediz` (or a collaborator on the fork)? | remote URL validity, push vs PR |
| B | `gh`-managed auth (Option 1) or standalone PAT + keyring (Option 2)? | §3 vs §4 |
| C | HTTPS or SSH as the transport? | remote URL, migration plan §4 Step 1 |
| D | Rewrite commit identity before first push? | migration plan §7 risk 5 |
