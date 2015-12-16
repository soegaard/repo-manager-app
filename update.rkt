#lang racket/base
(require (rename-in racket/match [match-define defmatch])
         racket/runtime-path
         racket/date
         json
         racket/string
         "private/github.rkt"
         "private/db.rkt")
(provide (all-defined-out))

(define MAX-CHAIN-LENGTH 500)
(define-runtime-path data-dir "web-content/data")
(define-runtime-path config-file "web-content/data/config.json")

(define config (call-with-input-file* config-file read-json))

(define (add-commits owner repo start-sha base-sha commits)
  (let loop ([sha start-sha] [n MAX-CHAIN-LENGTH])
    (when (and sha (positive? n) (not (equal? sha base-sha)))
      (define ci (db:get-commit owner repo sha))
      (hash-set! commits sha (trim-commit ci))
      (define parents (hash-ref ci 'parents null))
      (when (= (length parents) 1)
        (define parent (car parents))
        (loop (hash-ref parent 'sha) (sub1 n))))))

(define (trim-commit ci)
  (hash-copy-keys #hasheq() ci '(sha url author committer message parents)))

(define (hash-copy-keys dest src keys)
  (for/fold ([dest dest]) ([key keys])
    (hash-set dest key (hash-ref src key))))

(for ([(o/r branch-day-sha) (in-hash (hash-ref config 'branch_day null))])
  (defmatch (list owner repo) (string-split (symbol->string o/r) "/"))
  (define-values (master-ri master-ts)
    (db:get-ref/ts owner repo "heads/master"))
  (define-values (release-ri release-ts)
    (db:get-ref/ts owner repo "heads/release"))
  (define master-sha (and master-ri (ref-sha master-ri)))
  (define release-sha (and release-ri (ref-sha release-ri)))
  (define ts-d (seconds->date (min master-ts release-ts) #f))
  (define ts (parameterize ((date-display-format 'iso-8601))
               (string-append (date->string ts-d #t) "Z")))
  (define commits (make-hash))
  (add-commits owner repo master-sha branch-day-sha commits)
  (add-commits owner repo release-sha branch-day-sha commits)
  (define repo-info
    (hash 'owner owner
          'repo repo
          'last_polled ts
          'master_sha master-sha
          'release_sha release-sha
          'commits (hash-values commits)))
  (define out-file (build-path data-dir (format "repo_~a_~a" owner repo)))
  (eprintf "Writing ~s\n" (path->string out-file))
  (call-with-output-file* out-file
    #:exists 'truncate/replace
    (lambda (o) (write-json repo-info o))))
