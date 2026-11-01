---
name: baton
description: Hand parts of a coding task to 1-3 parallel Claude Code worker sessions, each on its own subscription account (the one with the most quota left) and its own git worktree, open in Rex or tmux panes beside you; then review, merge and clean up. Use this when a task splits into independent pieces that would each take a while, when the user wants work done in parallel or spread across their accounts, says they are near the 5-hour or weekly limit, or asks to fan out, spin up workers, or use another account or terminal for part of the work. Also use it to check on, message, merge or clean up workers already running. Not for small or single-file changes, and not for subagents inside this one session.
---

# Baton

You stay the main session: you plan, brief, review and merge. Workers do the pieces. A worker is a separate `claude` process, so it spends another account's quota (an `Agent` subagent spends yours), works in its own worktree so it can't collide with you, and runs in a pane the user can watch and type into.

Run the bundled script as `baton` if it's on PATH, else as `scripts/baton` from this skill's folder. `baton help` lists every command.

## Decide whether to hand off

Hand a piece to a worker only when all of these hold:

- **Independent.** It touches files no other piece touches. Two pieces that edit the same function or file will conflict at merge; give them to one worker, or run them one after another. Say so to the user if they asked for parallel and it wouldn't work.
- **Big enough.** Several files or more than a few minutes of work. Writing a brief and reviewing the result costs you real time and tokens; a quick edit is cheaper to do yourself.
- **Checkable.** You can say how to tell it's done: a test, a command, a behavior.

At most 3 workers. Your review is the bottleneck, and every worker's diff is yours to vouch for.

## Hand off

1. Run `baton accounts` to see which accounts have room, and `baton status` for workers already running.
2. Commit your own changes first. Workers branch from your current commit and won't see uncommitted work.
3. Write one brief per piece to a file in a scratch folder. The worker starts with no memory of this conversation, so the brief is all it knows:

   ```
   Goal: <one sentence: what to build or fix, and why>
   Scope: <files or folders this worker owns>. Leave alone: <the other workers' areas>.
   Context: <decisions already made, conventions, files to read first>
   Done when: <a checkable result>
   Verify with: <exact commands>
   ```

   baton adds the worker rules itself: stay in the worktree, commit as you go, don't push or merge, finish with a report.
4. Start each worker: `baton spawn <task> <brief-file>`. `<task>` is a short name like `billing-api`; the branch becomes `baton/<task>`. baton picks the account with the most room that nobody here is using. Pass `--account <id>` only when the user names one, and `--model` or `--permission-mode` only when the user asks.
5. Wait without spending tokens: run `baton wait` as a background command, so you're notified when every worker has stopped. Do your own share of the work meanwhile, or nothing. Don't poll `baton status` in a loop.

## Review and merge

When `baton wait` returns, read each worker's `state` and last message:

- **stopped** with a report: review it. A last message that is a question means the worker is waiting on you; answer with `baton tell <task> "<answer>"` and wait again.
- **exited**: the session ended (closed or crashed) and can't be messaged. Look at what's on its branch before deciding.

If workers fail, don't quietly redo their work in this session. The user handed it off to spare this account's quota, so tell them what went wrong and offer the options: start fresh workers, do it here, or wait.

Review each branch as you would a pull request: `git log <base>..baton/<task>` and `git diff <base>...baton/<task>`, and run its checks in its worktree (`.baton/worktrees/<task>`). The report says what the worker believes; the diff and the checks say what happened. Send fixes with `baton tell`, or drop the work.

Merge the good branches into the base one at a time, the way the project merges, and run the checks after each.

## Clean up

Run `baton done <task>` for every worker you started. It closes the pane, removes the worktree and deletes the branch. It refuses while the branch has unmerged commits or the worktree has uncommitted changes. Pass `--force` only when you mean to throw that work away, and tell the user what was dropped. Don't end your turn with workers still running unless the user knows and wants that.

## Limits

- baton skips accounts that are capped or at 90% or more. If none has room, tell the user when the soonest one resets rather than starting on a full account.
- A worker that hits its own limit mid-task stops, and its last message says so. Tell the user. With Consolidatex, `acc continue <account>` run in that worktree resumes the conversation on another account.
- If your own session is close to its limit, hand off what you can, tell the user which workers are running, and stop. The workers keep going without you.

## Project setup

If new worktrees need preparing (installing dependencies, copying `.env`, choosing free ports), the project can add an executable `.baton/setup`. baton runs it inside each new worktree with `BATON_MAIN` set to the main checkout, and removes the worktree if it fails.
