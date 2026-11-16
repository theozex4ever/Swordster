# Godot port: status and where to resume

**Paused on 2026-11-16 until the week of 2026-11-23.** This page records where the Godot port
([#4](https://github.com/theozex4ever/Swordster/issues/4)) stood when work stopped, and how to
pick it up again. Each open PR's body opens with a "Paused (resume here)" section. That section
has the exact done / not-done list and the next commands.

## Where main is

- **Commit:** main is at `21c8968`.
- **Content:** every combat slice is merged:
  - movement, dash and Converge;
  - all four swords with their ultimates;
  - all enemy types;
  - drops and swaps;
  - waves and the normal run (#18);
  - readable feedback, sound and the desktop HUD (#19);
  - texture-based sprite replacement (#21);
  - the feedback particle cap (#49).
- **Build:** `./build-godot.sh` builds the Windows ZIP and the Web export from Linux; see
  [`godot/README.md`](../godot/README.md).

## Open pull requests (all paused mid-round)

| PR | Issue | Review state | What is left |
|---|---|---|---|
| [#42](https://github.com/theozex4ever/Swordster/pull/42) | #41: make CI mutation checks fast enough to gate every PR | Round 2 FAIL. Fixes are pushed but not yet validated. Round 3 is the last review round. | Check the gate run on the head. Finish the local `render` section, the runner test and the checks. Verify the docs-only skip. Tidy the PR body. |
| [#46](https://github.com/theozex4ever/Swordster/pull/46) | #20: Android touch controls | Round 2 FAIL (two reviews agree). WIP fixes are pushed. Round 3 is the last review round. | The Web `touchcancel` fix and the per-finger cancel fix are written but not checked in a browser. Four touch mutations are stale. The new checks, mutations, capture-script fix and evidence are still to do. |
| [#48](https://github.com/theozex4ever/Swordster/pull/48) | #45: visual-replacement checks prove visibility and raw hit geometry | Round 1 FAIL. All findings are fixed in WIP. | Re-run the checks and the FAST visual section on the head. Run the remaining classic-mode mutations. Then the round-2 review. |

## Work order after the pause

1. **Finish the three PRs above.** Each needs one more fix pass and a review, and then a merge.
2. **After #42 merges:**
   - The full ("classic") mutation pass runs weekly instead of on every push to main. Its 24 jobs had been taking every Actions slot and queueing PR builds.
   - The main-push runs for `9adb718` and `21c8968` were cancelled on 2026-11-16 for that reason. Start one classic run on main by hand, from the Mutation checks workflow, to get a fresh full-pass result.
3. **#6, the maintainer's step:** upload the prepared build to the itch.io page and record the
   device checks. The full procedure is in [`itchio-setup.md`](itchio-setup.md), and results go in
   [`itchio-evidence.md`](itchio-evidence.md). The verified pair `20261116-121017-92c0c6f19`, from
   main `92c0c6f`, was built for this. A newer build may be used instead: rebuild from a clean
   main and follow section 2 of the setup doc.
4. **Then, in dependency order:**
   - #7: publish a selected retained build with rollback. Blocked by #6.
   - #22: full parity, performance and tester release recovery. Blocked by #7 and #20.
   - #23: cut over to Godot and retire the Python delivery workflow. Blocked by #22.

## Known issues

- **Flaky check on main.** The ice-field particle check in `colossus_cataclysm_checks.gd` can fail
  on CI. Its random stream is unseeded, and the check allows 260 px when embers can reach 272 px.
  PR #48 fixes it. Until that merges, re-run a red CI build once before treating that check as a
  real failure.
- **Real devices.** Real Windows machines, physical Android and real tab switching have not been
  checked yet. That is #6 and #22.
