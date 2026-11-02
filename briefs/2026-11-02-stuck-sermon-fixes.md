# Brief: Land the stuck-sermon fixes (TAB-122, TAB-123)

**Project:** Tablet Notes
**Created:** 2026-11-02
**Status:** open

## Task

Three open PRs fix sermons that get stuck before processing: #85 (TAB-122, the reaper gives
job-less sermons a processing job) and #86/#87 (TAB-123, the client job sweep skips sermons stuck
in "processing" or "preparing"). #86 and #87 have the same title and appear to duplicate each other.
Pick the better TAB-123 PR, close the other, and get #85 and the kept TAB-123 PR to a mergeable,
verified state.

- #85: https://github.com/baisethomas/tablet-notes-v3/pull/85
- #86: https://github.com/baisethomas/tablet-notes-v3/pull/86
- #87: https://github.com/baisethomas/tablet-notes-v3/pull/87

## Complete means

- [ ] Exactly one TAB-123 PR is open. The other is closed with a comment that links the one kept and says why.
- [ ] #85 and the kept TAB-123 PR are rebased on current `main`, have no conflicts, and pass CI.
- [ ] On a build that includes both fixes, a sermon left in "processing" or "preparing" with no job gets picked up and finishes, and the result is shown on a simulator or device.
- [ ] `.ratchet/STATE.md` reflects TAB-122 and TAB-123 as ready to merge.

## Evidence required

- Link to the closed duplicate PR and the comment on it explaining the choice.
- CI run links (green) for both remaining PRs, at their latest head SHA.
- A screenshot or short recording, before and after, of a stuck sermon recovering on simulator or device, with the build or commit noted.
- Test output for any tests added or changed for the reaper or job sweep.

## Reserved for the operator

- merge
- deploy / TestFlight / App Store submission
- send / publish
- closing or deleting anything beyond the one duplicate TAB-123 PR

## Original intake

> Go ahead and write that brief

(In reply to the CoS recommendation: "Tablet Notes looks like the strongest first brief, since it has two live bug fixes waiting on review.")

## Notes from the CoS

Chosen first because 1.0.1 is live and these are user-facing reliability fixes that are already
written and only waiting on review. #87 (+236/-8) is larger than #86 (+135/-9), but which to keep
is a review call, not size. This project runs local, so verification needs a simulator or device.
