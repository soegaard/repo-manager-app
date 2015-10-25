#lang racket/base
(require (rename-in racket/match [match-define defmatch])
         racket/cmdline
         racket/string
         "private/net.rkt"
         "private/catalog.rkt"
         "private/db.rkt")

(define (init-branch-day [commit "master"])
  (define catalog (get-catalog (src-catalog-url commit)))
  (for ([(o/r sha) (in-hash (get-checksum-table catalog))])
    ;; (eprintf "set ~a/~a to ~a\n" (car o/r) (cadr o/r) sha)
    (db:set-branch-day-sha (car o/r) (cadr o/r) sha)))

;; ============================================================

;; file contains: ((manager owner/repo ...) ...)
(define (init-managers managers-file)
  (define all-repos (call-with-input-file* "repos.rktd" read))
  (define assigned-repos (make-hash))
  (define managers (call-with-input-file* managers-file read))
  (for ([entry managers])
    (define manager (symbol->string (car entry)))
    (define repos
      (for/list ([o/r (cdr entry)])
        (unless (member o/r all-repos)
          (eprintf "** bad repo: ~s\n" o/r))
        (hash-set! assigned-repos o/r manager)
        (string-split (symbol->string o/r) "/")))
    ;; (eprintf "adding ~s managing ~s\n" manager repos)
    (db:create-manager manager repos))
  (for ([repo all-repos]
        #:when (not (hash-ref assigned-repos repo #f)))
    (eprintf "** unassigned repo: ~s\n" repo)))

;; ============================================================

(module+ main
  (require racket/cmdline)

  (define DB-FILE (the-db-file))
  (define COMMIT #f)
  (define MANAGERS-FILE #f)

  (command-line
   #:once-each
   [("--db-file") db-file "Use/create database at db-file" (set! DB-FILE db-file)]
   [("--commit") commit "Use release catalog at <commit> for branch-day" (set! COMMIT commit)]
   [("--managers") managers-file "Use file to initialize managers" (set! MANAGERS-FILE managers-file)]
   #:args ()
   (parameterize ((the-db-file DB-FILE))
     (when COMMIT
       (printf "Initializing branch-day table\n")
       (init-branch-day COMMIT))
     (when MANAGERS-FILE
       (printf "Initializing managers table\n")
       (init-managers MANAGERS-FILE)))))
