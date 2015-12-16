#lang racket/base
(require (rename-in racket/match [match-define defmatch])
         racket/string
         racket/list
         racket/date
         racket/runtime-path
         json
         web-server/servlet
         web-server/servlet-env
         web-server/stuffers/serialize
         web-server/compat/0/coerce
         "private/db.rkt"
         "private/github.rkt")
(provide (all-defined-out))

;; Some security/validation issues:

;; We use xexprs, which protect against HTML injection.

;; We VALIDATE incoming manager and owner/repo names by checking they
;; exist in the db. We RELY on names in db having no js-significant
;; chars (eg, "'"). See also issue below.

;; ISSUE: in a few places, we inject data into js scripts via '~a' ---
;; bad if the data can contain characters like "'". We should be fine,
;; because we only use strings derived from commit SHAs, `owner`,
;; `repo`, and `manager`. Commit SHAs never contain bad chars, and we
;; validate `owner`, `repo`, and `manager` wrt the db. So we're fine
;; as long as we never put bad names in the db during initialization.

;; ISSUE: There's currently no time/rate limiting on ajax/poll, which
;; forces calls to github.

;; TODO: Add current_build_sha to RepoInfo (w/ db table), show on view

(define-runtime-path web-dir "web-content")

(define-values (dispatch _make-url)
  (dispatch-rules
   [("ajax" "manager" (string-arg))
    (lambda (req manager)
      (unless (ok-manager? manager) (error 'page "unknown manager: ~e" manager))
      (json-response
       (for/list ([entry (db:get-manager-repos manager)])
         (hash 'owner (vector-ref entry 0) 'repo (vector-ref entry 1)))))]
   [("ajax" "repo" (string-arg) (string-arg))
    (lambda (req owner repo)
      (unless (ok-repo? owner repo) (error 'page "bad repo: ~e, ~e" owner repo))
      (json-response (get-repo-info owner repo)))]
   [("ajax" "poll-repo" (string-arg) (string-arg))
    (lambda (req owner repo)
      (unless (ok-repo? owner repo) (error 'age "bad repo: ~e, ~e" owner repo))
      (poll-repo owner repo))]
   ))

(define (json-response jsexpr #:headers [headers null])
  (response/output (lambda (out) (write-json jsexpr out))
                   #:mime-type #"application/json"
                   #:headers headers))

;; RepoInfo = {
;;   owner : String,
;;   repo : String,
;;   last_polled : Date (string or integer???),
;;   branch_day_sha : String,
;;   master_sha : String / null,
;;   release_sha : String / null,
;;   commits : (Arrayof AnnotatedCommitInfo) or String(error),
;;   _ }

;; AnnotatedCommitInfo = {
;;   info : CommitInfo (see github.rkt),
;;   status_actual : String ("no" | "picked" | "pre-avail"),
;;   status_recommend : String (...),
;;   _ }

;; ============================================================

(define (poll-repo owner repo)
  (define (get-state)
    (list (db:get-branch-sha owner repo "master")
          (db:get-branch-sha owner repo "release")))
  (define old-state (get-state))
  (db:recache-ref/ts owner repo "heads/master")
  (db:recache-ref/ts owner repo "heads/release")
  (define new-state (get-state))
  (json-response (not (equal? new-state old-state))))

;; ============================================================

(module+ main
  (require racket/cmdline)

  (define PORT 80)
  (define DB-FILE (the-db-file))
  (define LOG-FILE "/dev/stdout")

  (command-line
   #:once-each
   [("-p" "--port") port "Listen on given port" (set! PORT (string->number port))]
   [("--db-file") db-file "Use/create database at db-file" (set! DB-FILE db-file)]
   #:args ()
   (parameterize ((the-db-file DB-FILE))
     (serve/servlet dispatch
                    #:port PORT
                    #:servlet-regexp #rx""
                    #:command-line? #t
                    #:extra-files-paths (list (path->string web-dir))
                    #:log-file LOG-FILE))))
