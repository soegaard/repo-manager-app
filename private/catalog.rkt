#lang racket/base
(require (rename-in racket/match [match-define defmatch])
         racket/string
         "net.rkt")
(provide (all-defined-out))

;; get-catalog : String -> Catalog
(define (get-catalog url)
  (get/url url #:handle read))

;; get-checksum-table : Catalog -> (Hash (List String String) => String)
(define (get-checksum-table catalog)
  (define t (make-hash))
  (for ([(pkg info) (in-hash catalog)])
    (define src (hash-ref info 'source))
    (define checksum (hash-ref info 'checksum))
    (cond [(url->owner+repo src)
           => (lambda (o/r) (hash-set! t o/r checksum))]))
  t)

;; ----------------------------------------

;; Catalog for branch-day initialization
(define (src-catalog-url [commit "master"])
  (format "https://raw.githubusercontent.com/racket/release-catalog/~a/release-catalog/pkgs-all" commit))

;; Catalog of current release candidate
(define (pre-catalog-url)
  "http://pre-release.racket-lang.org/catalog/pkgs-all")

;; ----------------------------------------

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
              #|
              (unless (member branch '(#f "master"))
                (error 'init "non-master branch in source: ~s" url))
              |#
              (list owner repo))]
        [else #f]))
