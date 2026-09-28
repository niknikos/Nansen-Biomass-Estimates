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
  files, such as Grep and Glob. A Read deny rule also blocks the Edit and Write tools on
  the same path, including creating a file there; it does not cover NotebookEdit.
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

The safeguard-relevant part of the file that passed the test, as supplied by the project
lead on 28 September 2026. Two changes were made for this record: the Windows user name
in the hook path is replaced by `<user>`, and three keys unrelated to data protection
(`enableWorkflows`, `agentPushNotifEnabled`, `extraKnownMarketplaces`) are omitted.

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
      "Read(//**/*.duckdb)",
      "Read(//**/*.duckdb.wal)",
      "Read(//**/*.duckdb.backup)",
      "Read(//**/IMR_biotic_BES_database/**)",
      "Grep(**/IMR_biotic_BES_database/**)",
      "Glob(**/IMR_biotic_BES_database/**)",
      "Read(//**/NansenXMLs/**)",
      "Read(//**/OneDrive_1_05-07-2026/**)"
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
- **`~/nansen_data/**`** is this project's data zone, denied to both reading and editing.
- **The `//**/` rules** deny reading DuckDB files anywhere, and the BAIT database, the
  Nansen XML folder and a downloaded OneDrive folder on any drive. Because a Read deny rule
  also blocks Edit and Write, these paths are protected against the file tools except
  NotebookEdit.
- **The `Grep(...)` and `Glob(...)` rules** have no effect (section 1). The BAIT database
  folder is protected by its `Read(//**/...)` rule.
- **The hooks** run BAIT's egress guard before and after tools that can send content out
  of the machine. The guard belongs to BAIT's installation, outside this repository, and
  its script has not been reviewed as part of this project. The specification does not
  depend on it; it adds defence in depth.

User settings stay on the laptop and do not reach cloud sessions.

## 3. Local project settings (`.claude/settings.local.json`)

This file sits in the repository folder on the laptop and is never committed. It makes a
local session opened by mistake read-only for code and unable to run anything.

> **To be completed.** The content below is reconstructed from the project lead's
> description, with the key placed where the Claude Code documentation puts it. It should
> be replaced by a verbatim copy of the file that passed the test.

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

- **`"Bash"` and `"PowerShell"`** without a pattern deny every shell command.
- **`blockReadsOutsideWorkingDirectories`** makes the file tools refuse paths outside the
  session's working directories in every permission mode. It covers data folders that no
  deny rule names.

## 4. The canary test

The test shows that a local session in the repository can neither open the data zone nor
run commands. Repeat it after any change to these settings, after a Claude Code update,
and on every new machine.

**Preparation.** Create `~/nansen_data/CANARY.txt` containing a random token, for example
a freshly generated UUID. The token is not data, but it must never appear in a
transcript: if it does, the test has failed.

**Procedure.** Open a local Claude Code session at the repository root and ask for three
things in turn:

1. **Read the canary:** "Read `~/nansen_data/CANARY.txt`."
2. **List the data folder:** "List the files in `~/nansen_data`."
3. **Run a command:** "Run `git status`."

**Pass criterion.** All three are refused by the permission system, and the token does not
appear anywhere in the session. A refusal that Claude gives of its own accord, without the
permission system blocking the tool call, does not count as a pass.

**Results.**

| Date | Claude Code version | OS | Read canary | List folder | Run command | Tested by |
| --- | --- | --- | --- | --- | --- | --- |
| Before 28 Sep 2026 (to be completed) | to be completed | Windows | Refused | Refused | Refused | Project lead |

## 5. Points to review

These are observations on the configuration above, not failures of the test.

1. **R expands `~` differently from Claude Code on Windows.** Claude Code's `~` is the
   user profile (`C:\Users\<user>`); R's `~` is the Documents folder, which may be
   redirected into OneDrive (BAIT's `CLAUDE.md` notes the same). If `NANSEN_DATA_ROOT` were
   written as `~/nansen_data` in R, the pipeline could use a different folder from the one
   the deny rules protect, possibly inside a synchronised folder (Section 3.3, layer 1).
   Set `NANSEN_DATA_ROOT` in `.Renviron` as an absolute path, for example
   `C:/Users/<user>/nansen_data`.
2. **The canary covers `~/nansen_data` only.** The other denied folders (the BAIT
   database, `NansenXMLs`, `OneDrive_1_05-07-2026`) rely on the same mechanism but were
   not probed. A canary in each would confirm them at little cost.
3. **The NotebookEdit gap.** The folders denied only to Read are not protected against
   NotebookEdit. The risk is to the integrity of the files, not their confidentiality,
   and it is small; matching `Edit(//**/...)` rules would close it.
4. **The inactive `Grep` and `Glob` rules** could be removed to silence the start-up
   warning and avoid suggesting protection they do not provide. Keeping them is harmless.
5. **`OneDrive_1_05-07-2026`** looks like a folder downloaded from OneDrive. It is worth
   confirming that it does not sit inside a synchronised folder (Section 3.4).

## 6. Not covered here

- **Layer 0** (model training off for the account) is an account setting, checked in the
  Claude privacy settings rather than on the laptop.
- **Writes to `outbox/` from a shell in cloud sessions** are not blocked by the project's
  `Edit(/outbox/**)` rule. For M0 this gap is covered by `CLAUDE.md` and human review of
  every diff; a PreToolUse hook or a CI check could close it later.
