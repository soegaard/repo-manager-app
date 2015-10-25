#lang racket/base
(require (rename-in racket/match [match-define defmatch])
         racket/cmdline
         "private/net.rkt"
         "private/db.rkt")

(define (init [commit "master"])
  (define catalog
    (get/url (get-catalog-url commit)
             #:handle read))
  (define t (make-hash))
  (for ([(pkg info) (in-hash catalog)])
    (define src (hash-ref info 'source))
    (define checksum (hash-ref info 'checksum))
    (cond [(url->owner+repo src)
           => (lambda (o/r) (hash-set! t o/r checksum))]))
  (for ([(o/r sha) (in-hash t)])
    (eprintf "set ~a/~a to ~a\n" (car o/r) (cadr o/r) sha)
    (db:set-branch-day-sha (car o/r) (cadr o/r) sha)))

(define (get-catalog-url [commit "master"])
  (format "https://raw.githubusercontent.com/racket/release-catalog/~a/release-catalog/pkgs-all" commit))

;; ============================================================

(define github-rx
  (regexp
   (string-append "^"
                  "git://github\\.com/([^?/#]+)/([^/?#]+)/?"
                  "(?:[?]path=([^?#]*))?"
                  "(?:#([^/?#]+))?"
                  "$")))

;; url->owner+repo : String -> (list String String)/#f
(define (url->owner+repo url)
  (cond [(regexp-match github-rx url)
         => (lambda (m)
              (defmatch (list _ owner repo path branch) m)
              (unless (member branch '(#f "master"))
                (error 'init "non-master branch in source: ~s" url))
              (list owner repo))]
        [else #f]))

;; ============================================================

(module+ main
  (require racket/cmdline)

  (define DB-FILE (the-db-file))
  (define COMMIT "master")

  (command-line
   #:once-each
   [("--db-file") db-file "Use/create database at db-file" (set! DB-FILE db-file)]
   [("--commit") commit "Use commit of release catalog" (set! COMMIT commit)]
   #:args ()
   (parameterize ((the-db-file DB-FILE))
     (init COMMIT))))
