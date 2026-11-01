# baton

Hand parts of a Claude Code task to worker sessions running beside you. Each worker runs on the subscription account with the most quota left and works in its own git worktree, in a pane you can watch and type into. Your main session briefs the workers, reviews their branches, merges them and cleans up.

```
you ── main session (plans, reviews, merges)
        ├─ worker billing-refund   account "work"  (5% used)   worktree .baton/worktrees/billing-refund
        ├─ worker auth-passwords   account "side"  (30% used)  worktree .baton/worktrees/auth-passwords
        └─ worker reports-csv      account "spare" (41% used)  worktree .baton/worktrees/reports-csv
```

An `Agent` subagent spends your own session's quota. A baton worker is a separate `claude` process on another account, so a long task can keep going after your account hits its 5-hour limit.

## Install

As a Claude Code plugin:

```
/plugin marketplace add hazlijohar95/baton
/plugin install baton@baton
```

The skill runs its bundled script. To use `baton` yourself from a terminal, link it onto your PATH:

```
ln -s "$(pwd)/bin/baton" ~/.local/bin/baton
```

Needs `git`, `jq` and Claude Code. Panes open in [Rex](https://superlogical.com) when you're inside a Rex terminal, or in tmux when you're inside tmux. Anywhere else, baton prints the command for you to run in another terminal.

## Accounts

baton reads your accounts from the first of these it finds:

1. `~/.config/baton/accounts`, one account per line: `<name> <CLAUDE_CONFIG_DIR>`. Leave the folder out for your default `~/.claude` login. baton can't see usage this way, so it takes accounts in file order.
2. [Consolidatex](https://github.com/hazlijohar95/consolidatex)'s `acc ls --json`, which includes each account's usage. baton picks the account with the most quota left, skips any that are capped or at 90% or more, and spreads workers across accounts nobody here is using. When those run out it doubles up on a worker's account before touching the one your main session runs on.
3. Your current account alone. Workers still get their own worktrees and panes.

## Use

Ask in plain words: "get the three TODO items done in parallel on my other accounts", or "I'm nearly at my limit, hand the rest of this off". The skill decides whether splitting pays off. It won't split a small change, or two changes to the same function.

The commands, if you want to drive it yourself:

| Command | What it does |
|---|---|
| `baton accounts` | Accounts a worker can start on, most quota left first. |
| `baton spawn <task> <brief-file>` | New worktree and branch `baton/<task>`, worker opened in a pane. `--account`, `--model`, `--permission-mode`, `--base` override the defaults. |
| `baton status [<task>]` | Each worker's account, state, commits and last message. |
| `baton wait [<task>]` | Block until the workers stop, either finished or waiting on you. |
| `baton tell <task> <message>` | Send a worker a follow-up. |
| `baton done <task> [--force]` | Close the pane, remove the worktree, and delete the branch once merged. |

Workers start with no memory of your conversation. The brief file is all they know. baton adds the worker rules on top of it: stay in the worktree, commit as you go, don't push or merge, and finish with a report.

To prepare each new worktree (install dependencies, copy `.env`, pick free ports), add an executable `.baton/setup` to your project. It runs inside the new worktree with `BATON_MAIN` set to your main checkout.

## How it knows a worker is done

Each worker starts with its own `--settings` file, which adds `SessionStart`, `UserPromptSubmit` and `Stop` hooks for that one session. Nothing is added to your global settings. The hooks record the session's state and final message in `.git/baton/<task>/`, which is where `status` and `wait` read them.

## Develop

```
test/run.sh                     # end-to-end tests with stub claude, rex and acc; runs under macOS bash 3.2
claude plugin eval skills/baton --allow-tools Write,Edit,Bash --scaffold
                                # the skill's eval cases, with and without the skill (real, billed runs)
```

## License

MIT
