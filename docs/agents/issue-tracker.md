# Issue tracker: GitHub

Specs and tickets live in GitHub Issues for `theozex4ever/Swordster`.
Use the `gh` CLI with explicit `--repo theozex4ever/Swordster` for issue operations.
Publishing a spec or ticket means creating a GitHub issue; fetching it means
reading its full body and comments.

## Conventions

- Confirm the target repository with `gh repo view --json nameWithOwner` before
  the first issue creation in a session. Target this repository explicitly.
- Create issues with `gh issue create --title TITLE --body-file FILE`, adding
  the explicit repository and applicable labels. Write multiline text to a
  temporary file and use `--body-file`; preserve real newlines.
- Read with `gh issue view NUMBER --json number,title,body,labels,comments`.
- List with `gh issue list --state open --json number,title,body,labels`, using
  label filters where needed; read comments when evaluating individual issues.
- Apply the role labels from `triage-labels.md`. Fully specified specs and
  implementation tickets use `ready-for-agent`.
- Link tickets to their spec with native sub-issues: create with `--parent NUMBER`
  or use `gh issue edit PARENT --add-sub-issue CHILD`.
- Record native blocking edges with `--blocked-by NUMBER` on creation or
  `gh issue edit CHILD --add-blocked-by BLOCKER`. Create blockers first.
  If GitHub rejects native relationships as unavailable, use explicit parent
  references and `Blocked by: #NUMBER` entries in the bodies.
- A ticket is startable only when every blocker is closed. A ready label alone
  does not mean its dependencies are complete.
- Comment with `gh issue comment NUMBER --body-file FILE`. Resolve through
  merged PRs with closing references; when closing directly, post the resolution
  before `gh issue close NUMBER`. A skill's limits on closing parents still apply.

## Pull requests as a triage surface

PRs as a request surface: no.

## Wayfinding operations

For wayfinder, the map is a GitHub issue labelled `wayfinder:map`; decision tickets
are native sub-issues labelled `wayfinder:research`, `wayfinder:prototype`,
`wayfinder:grilling` or `wayfinder:task`, with native blocking edges as above.
These decision issues use wayfinder labels rather than triage labels.
The frontier consists of open child issues with all blockers closed and no assignee.
Claim with `gh issue edit NUMBER --add-assignee @me` before working.
Resolve by commenting, closing, and appending a named link and gist to the map.
Create wayfinder labels only when that flow is used and needs them.
