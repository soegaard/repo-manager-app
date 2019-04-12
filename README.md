# Repo Manager Web App

This is a web application to help repo managers with the Racket
release process.

 - Run `racket make.rkt` to produce the static web content. This only
   needs to be done once (or after a change to `src/index.rktd`).

 - Run `racket init.rkt --commit $SHA` to produce the release-constant
   data. `$SHA` should be the commit of the branch-day release catalog
   (ie, the catalog checksums should be merge bases for `master` and
   `release` on all repos that have `release` branches).

 - If there are new repos or the assignment of repos to managers has
   changed, update the manager information:
   - Update `src/repos.rktd` with the output from the release-catalog
     command `racket scripts/show-sources.rkt ...` (add parentheses).
   - Update `src/managers.rktd` with new manager assignments.
   - Run `racket update-managers.rkt` to check the new assignments and
     update the release info.
   - Repeat the previous steps if there are unassigned repos.

 - Serve the `web-content` directory.

 - Periodically run `racket update.rkt` to cache new information from
   github.
