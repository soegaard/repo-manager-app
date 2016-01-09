#lang racket/base
(require (rename-in racket/match [match-define defmatch])
         racket/runtime-path
         racket/date
         racket/string
         json
         "private/github.rkt")
(provide (all-defined-out))

(define MAX-CHAIN-LENGTH 500)
(define-runtime-path data-dir "web-content/data")
(define-runtime-path config-file "web-content/data/base.json")

(define config (call-with-input-file* config-file read-json))
(define branch-day-map (hash-ref config 'branch_day '#hash()))

;; ========================================

(define (update)
  (for ([o/r (in-hash-keys branch-day-map)])
    (update1 o/r)))

(define (update1 o/r)
  (define ts (* 1000 (current-seconds)))
  (defmatch (list owner repo) (string-split (symbol->string o/r) "/"))
  (define branch-day-sha (hash-ref branch-day-map o/r))
  (defmatch (list master-sha release-sha refs-etag) (get-refs+etag owner repo))
  (define commits (make-hash))
  (define out-file (build-path data-dir (format "repo_~a_~a.json" owner repo)))
  (add-commits-from-file commits out-file)
  (add-commits owner repo master-sha branch-day-sha commits)
  (add-commits owner repo release-sha branch-day-sha commits)
  (define repo-info
    (hash 'owner owner
          'repo repo
          'timestamp ts
          'refs_etag refs-etag
          'master_sha master-sha
          'release_sha release-sha
          'commits (hash-values commits)))
  (printf "writing ~s\n" (path->string out-file))
  (call-with-output-file* out-file
    #:exists 'truncate/replace
    (lambda (o) (write-json repo-info o))))

(define (get-refs+etag owner repo)
  (defmatch (cons info etag) (github:get-refs+etag owner repo))
  (define h
    (for/hash ([refinfo (in-list info)])
      (values (hash-ref refinfo 'ref) (hash-ref* refinfo 'object 'sha))))
  (list (hash-ref h "refs/heads/master" #f)
        (hash-ref h "refs/heads/release" #f)
        etag))

(define (add-commits-from-file commits out-file)
  (let ([old-repo-info
         (with-handlers ([exn:fail? (lambda _ #f)])
           (call-with-input-file* out-file read-json))])
    (when old-repo-info
      (for ([ci (in-list (hash-ref old-repo-info 'commits null))])
        (hash-set! commits (hash-ref ci 'sha) ci)))))

(define (add-commits owner repo start-sha base-sha commits)
  (define cache (make-hash))
  (let loop ([sha start-sha] [n MAX-CHAIN-LENGTH])
    (when (zero? n)
      (eprintf "WARNING: chain too long for ~a/~a\n" owner repo))
    (when (and sha (positive? n) (not (equal? sha base-sha)))
      (define ci (get-commit owner repo sha cache))
      (hash-set! commits sha ci)
      (define parents (hash-ref ci 'parents null))
      (when (= (length parents) 1)
        (define parent (car parents))
        (loop (hash-ref parent 'sha) (sub1 n))))))

(define (get-commit owner repo sha cache)
  (or (hash-ref cache sha #f)
      (let ([commits (github:get-commits owner repo sha)])
        (for ([ci (in-list commits)])
          ;; (eprintf "  caching ~s\n" (hash-ref ci 'sha))
          (hash-set! cache (hash-ref ci 'sha) ci))
        (hash-ref cache sha))))

;; ========================================

(module+ main
  (eprintf "Updating\n")
  (update))
