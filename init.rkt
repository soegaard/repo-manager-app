#lang racket/base
(require (rename-in racket/match [match-define defmatch])
         racket/cmdline
         racket/file
         racket/string
         racket/runtime-path
         json
         "private/net.rkt"
         "private/catalog.rkt")
(provide (all-defined-out))

(define-runtime-path config-file "web-content/data/base.json")
(define-runtime-path repos-file "src/repos.rktd")
(define-runtime-path managers-file "src/managers.rktd")

;; release-info : ... -> {branch_day : BranchDayCommits, managers : Managers}
(define (release-info bd-commit)
  (hash 'branch_day (branch-day-commits bd-commit)
        'managers (managers-info)))

;; branch-day-commits : -> {owner/repo : sha, ...}
(define (branch-day-commits [bd-commit "master"])
  (define catalog (get-catalog (src-catalog-url bd-commit)))
  (for/hash ([(o/r sha) (in-hash (get-checksum-table catalog))])
    (values (string->symbol (format "~a/~a" (car o/r) (cadr o/r))) sha)))

;; managers.rktd: ((manager owner/repo ...) ...)
;; repos.rktd: (owner/repo ...)

;; managers-info : ... -> {manager : [owner/repo, ...], ...}
(define (managers-info)
  (define all-repos (call-with-input-file* repos-file read))
  (define managers (call-with-input-file* managers-file read))
  (define assigned-repos (make-hash))
  (define managers-h
    (for/hash ([entry managers])
      (define manager (car entry))
      (define repos
        (for/list ([o/r (cdr entry)])
          (unless (member o/r all-repos)
            (eprintf "** bad repo: ~s\n" o/r))
          (hash-set! assigned-repos o/r manager)
          (symbol->string o/r)))
      (values manager repos)))
  (for ([repo all-repos]
        #:when (not (hash-ref assigned-repos repo #f)))
    (eprintf "** unassigned repo: ~s\n" repo))
  managers-h)

;; ============================================================

(module+ main
  (require racket/cmdline)
  (define COMMIT "master")
  (command-line
   #:once-each
   [("--commit") commit "Use release catalog at <commit> for branch-day"
    (set! COMMIT commit)]
   #:args ()
   (begin
     (make-parent-directory* config-file)
     (call-with-output-file* config-file
       #:exists 'truncate/replace
       (lambda (o) (write-json (release-info COMMIT) o))))))
