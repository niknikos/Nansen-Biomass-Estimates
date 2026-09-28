# Local safeguards on the laptop

This note records the laptop-side settings that implement layer 2 of the data-protection
model (docs/spec.md, Section 3.3) and the canary test that verifies them, the M0
acceptance check that "a local session cannot open the data zone or run commands".

None of these files are in the repository. The user settings live in
`~/.claude/settings.json`; the local project settings live in
`.claude/settings.local.json`, which `.gitignore` keeps out of Git. This note is the
reference copy, so that the configuration can be reviewed, rebuilt on another machine and
shown to partners on request (Section 14).

## 1. What the rules can and cannot do

Claude Code checks file paths against `Read(...)` and `Edit(...)` rules only.

- **Read rules** cover the Read tool and, on a best-effort basis, the other tools that read
  files, such as Grep and Glob, and `@` mentions in prompts. A Read deny rule also blocks
  the Edit and Write tools on the same path, including creating a file there; it does not
  cover NotebookEdit.
- **Edit rules** cover every built-in tool that edits files.
- **Grep and Glob rules have no effect.** A path rule written for `Grep(...)` or `Glob(...)`
  is accepted but never consulted, and Claude Code warns about it at start-up. Protection
  for Grep and Glob comes from the Read rule on the same path.
- **Shell commands are not governed by path rules.** A Bash or PowerShell command can read
  files that the file tools may not. Local sessions therefore deny the shell entirely
  (section 3), and real-data work runs outside Claude Code (Section 3.3, layer 4).

Path anchors, from the Claude Code permissions documentation:

| Pattern | Meaning |
| --- | --- |
| `//path` | Absolute path from the filesystem root |
| `~/path` | Path from the home directory |
| `/path` | Relative to the settings source (the project root in project settings, `~/.claude/` in user settings) |
| `path` or `./path` | Relative to the current directory |

On Windows, paths are normalised to POSIX form before matching, so `C:\Users\<user>`
becomes `/c/Users/<user>`. Rules for folders outside the project therefore start with
`//**/`, which matches the folder on every drive. A single leading `/` is not absolute: in
user settings it points into `~/.claude/`.

## 2. User settings (`~/.claude/settings.json`)

The safeguard-relevant part of the file that passed the test of 28 September 2026 (section
4), confirmed on the laptop that day. Two changes were made for this record: the Windows
user name in the hook path is replaced by `<user>`, and three keys unrelated to data
protection (`enableWorkflows`, `agentPushNotifEnabled`, `extraKnownMarketplaces`) are
omitted.

```json
{
  "env": {
    "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
    "DISABLE_FEEDBACK_COMMAND": "1"
  },
  "permissions": {
    "deny": [
      "Read(~/nansen_data/**)",
      "Edit(~/nansen_data/**)",
      "Read(//**/nansen_data/**)",
      "Edit(//**/nansen_data/**)",
      "Read(//**/*.duckdb)",
      "Edit(//**/*.duckdb)",
      "Read(//**/*.duckdb.wal)",
      "Edit(//**/*.duckdb.wal)",
      "Read(//**/*.duckdb.backup)",
      "Edit(//**/*.duckdb.backup)",
      "Read(//**/IMR_biotic_BES_database/**)",
      "Edit(//**/IMR_biotic_BES_database/**)",
      "Read(//**/NansenXMLs/**)",
      "Edit(//**/NansenXMLs/**)",
      "Read(//**/OneDrive_1_05-07-2026/**)",
      "Edit(//**/OneDrive_1_05-07-2026/**)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|PowerShell|WebFetch|WebSearch|Artifact|SendUserFile|Write|Edit|mcp__.*",
        "hooks": [
          {
            "type": "command",
            "command": "bash /c/Users/<user>/.bait/privacy/egress_guard.sh pre",
            "shell": "bash",
            "timeout": 20,
            "statusMessage": "BAIT egress guard"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|PowerShell|WebFetch|WebSearch|Artifact|SendUserFile|Write|Edit|mcp__.*",
        "hooks": [
          {
            "type": "command",
            "command": "bash /c/Users/<user>/.bait/privacy/egress_guard.sh post",
            "shell": "bash",
            "timeout": 20
          }
        ]
      }
    ]
  }
}
```

What each part does:

- **`env`** switches off the feedback survey and the `/feedback` command (layer 0). The
  repository's `.claude/settings.json` sets the same values for cloud sessions.
- **`nansen_data`** is this project's data zone. It is denied to reading and editing both
  in the home folder (`~/`) and on any drive (`//**/`), so that it stays protected if it
  moves.
- **The other `//**/` rules** deny reading and editing DuckDB files anywhere, and the BAIT
  database, the Nansen XML folder and a downloaded OneDrive folder on any drive. Each
  `Read` rule has a matching `Edit` rule, so NotebookEdit is covered too.
- **The hooks** run BAIT's egress guard before and after tools that can send content out
  of the machine. The guard belongs to BAIT's installation, outside this repository, and
  its script has not been reviewed as part of this project. The specification does not
  depend on it; it adds defence in depth.

User settings stay on the laptop and do not reach cloud sessions.

**History.** The version in place before 28 September 2026 denied only reading for the
DuckDB files and the BAIT, XML and OneDrive folders, had no `//**/nansen_data/**` rules,
and included a `Grep(...)` and a `Glob(...)` rule, which had no effect. It was replaced
after the review recorded in section 5.

## 3. Local project settings (`.claude/settings.local.json`)

This file sits in the repository folder on the laptop and is never committed. It makes a
local session opened by mistake read-only for code and unable to run anything. The
content below was confirmed verbatim on the laptop on 28 September 2026.

```json
{
  "permissions": {
    "deny": [
      "Bash",
      "PowerShell"
    ],
    "blockReadsOutsideWorkingDirectories": true
  }
}
```

- **`"Bash"` and `"PowerShell"`** without a pattern remove the shell tools from the session
  altogether.
- **`blockReadsOutsideWorkingDirectories`** makes the file tools refuse paths outside the
  session's working directories in every permission mode. It covers data folders that no
  deny rule names.

**The session must run in the folder itself.** The desktop app can run a session in a
separate working copy (a Git worktree). This file is not committed, so it would not be
present in such a copy, and neither the shell block nor the fence would apply. The canary
procedure checks the working directory before probing; anyone opening a local session on
this repository should make sure it is not a worktree.

## 4. The canary test

The test shows that a local session in the repository can neither open the data zone nor
run commands, and that the user-level deny rules hold on their own. Repeat it after any
change to these settings, after a Claude Code or desktop app update, and on every new
machine. The procedure and its scripts are in
[`safeguard-test/README.md`](safeguard-test/README.md).

### Test of 28 September 2026

**Conditions.** Windows 11 Enterprise, with PowerShell in Constrained Language Mode
(enforced on the machine). Sessions run in the Claude desktop app, version 2.9939.2
(d3e504), built 24 September 2026; the app does not show the bundled Claude Code version
separately. Settings as in sections 2 and 3. The folder `OneDrive_1_05-07-2026` no longer
exists on the laptop, so it was left out of the test (`-Skip`); its deny rules remain in
place. Tested by the project lead, guided from a cloud session.

**Phase A: a local session in the repository.** The working directory was confirmed as
the repository folder itself, not a worktree.

| Probe | What it tests | Outcome |
| --- | --- | --- |
| `@` mention of the `nansen_data` canary | Read rule applied to `@` mentions | Refused: the file was not attached |
| Read the `nansen_data` canary | Instruction layer | Claude declined, citing `CLAUDE.md`; no tool call |
| Read the `IMR_biotic_BES_database` canary | Instruction layer | Claude declined, citing `CLAUDE.md`; no tool call |
| Read a harmless file outside the repository | Fence (`blockReadsOutsideWorkingDirectories`) | Refused by the permission system |
| Run a Bash command | Shell deny | Refused: no shell tool in the session |
| Run a PowerShell command | Shell deny | Refused: no shell tool in the session |

**Phase B: a local session in an empty folder**, with the shell switched off by a settings
file in that folder (Claude confirmed it had no shell tool), so that only the user-level
deny rules applied. No permission dialog appeared at any point.

| Probe | Rule tested | Outcome |
| --- | --- | --- |
| Read the `nansen_data` canary | `Read(~/nansen_data/**)` | Refused |
| Read the `IMR_biotic_BES_database` canary | `Read(//**/IMR_biotic_BES_database/**)` | Refused |
| Read the `NansenXMLs` canary | `Read(//**/NansenXMLs/**)` | Refused |
| Read the `OneDrive_1_05-07-2026` canary | `Read(//**/OneDrive_1_05-07-2026/**)` | Not run: folder absent |
| Glob in `NansenXMLs` | Read rule applied to Glob | Refused |
| Grep in `IMR_biotic_BES_database` | Read rule applied to Grep | Refused |
| Write a file in `NansenXMLs` | `Edit(//**/NansenXMLs/**)` | Refused |
| Edit the `IMR_biotic_BES_database` canary | `Edit(//**/IMR_biotic_BES_database/**)` | Refused |
| Read `canary.duckdb` in the repository | `Read(//**/*.duckdb)` | Refused |

**Automated checks** (`Test-Canaries.ps1`): PASS. All six canaries were unchanged, no
write probe existed, and no token appeared in the two transcripts written during the test.

**Result: passed.** Every safeguard held, and each layer was seen to work on its own.

**Limitations.**

- In the repository session, `CLAUDE.md` led Claude to decline reads in the data zone
  before any tool was called. Those probes show that the instruction layer holds, but they
  did not exercise the permission layer in that session. The same deny rules were shown to
  work in Phase B, and the fence was shown to work in Phase A with a file outside the data
  zone. The procedure has been revised to expect this.
- The `.duckdb.wal` and `.duckdb.backup` rules were not probed individually; they follow
  the same pattern as the `.duckdb` rule, which was. The revised procedure probes all
  three.
- The OneDrive folder rules could not be tested, because the folder no longer exists.

### Earlier test

| Date | Version | OS | Read canary | List folder | Run command | Tested by |
| --- | --- | --- | --- | --- | --- | --- |
| Before 28 Sep 2026 (not recorded) | not recorded | Windows | Refused | Refused | Refused | Project lead |

That test used a single canary, `~/nansen_data/CANARY.txt`, and the earlier settings (see
"History" in section 2).

## 5. Points reviewed

These were observations on the earlier configuration, not failures of a test.

1. **R expands `~` differently from Claude Code on Windows.** *Resolved on
   28 September 2026.* Claude Code's `~` is the user profile (`C:\Users\<user>`); R's `~`
   is the Documents folder (BAIT's `CLAUDE.md` notes the same). On the laptop R reports
   `C:/Users/<user>/Documents`, not redirected into OneDrive, so `~/nansen_data` in R would
   have meant a different folder from the one the deny rules protect. `NANSEN_DATA_ROOT`
   is now set as an absolute path, `C:/Users/<user>/nansen_data`, in the personal
   `.Renviron` (`~/.Renviron`, that is `C:/Users/<user>/Documents/.Renviron`). After a
   restart, R returned the value and found the folder. The data folder sits directly under
   the profile folder, outside the OneDrive root, which is a separate folder beside it.
   (A project-level `.Renviron` would replace the personal one for that project rather
   than add to it, and is not used.)
2. **The canary covered `~/nansen_data` only.** *Resolved:* the test of 28 September 2026
   placed a canary in every protected folder that exists.
3. **The NotebookEdit gap.** *Resolved:* every `Read` rule now has a matching `Edit` rule.
4. **The inactive `Grep` and `Glob` rules.** *Resolved:* removed.
5. **`OneDrive_1_05-07-2026`** might sit inside a synchronised folder. *Resolved:* the
   folder no longer exists. Its deny rules are kept in case it reappears.
6. **The laptop has two user profiles in play.** *For awareness.* The repository sits under
   `C:\Users\Administrator`, while the data folders sit under the working user's profile.
   The `~/nansen_data` rules refer to the working user's profile only; the `//**/` rules
   match any location. Data folders should stay under the working user's profile, or be
   covered by `//**/` rules.

## 6. Not covered here

- **Layer 0** (model training off for the account) is an account setting, checked in the
  Claude privacy settings rather than on the laptop.
- **Writes to `outbox/` from a shell in cloud sessions** are not blocked by the project's
  `Edit(/outbox/**)` rule. For M0 this gap is covered by `CLAUDE.md` and human review of
  every diff; a PreToolUse hook or a CI check could close it later.
