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

;; Repo URL forms:
;; - "git://github.com/OWNER/REPO/?path=PATH"
;; - "https://github.com/OWNER/REPO.git?path=PATH"
;; - "github://github.com/OWNER/REPO/master"

(define github-git-rx #rx"^git://github\\.com/([^?/#]+)/([^/?#]+)/?")
(define github-https-rx #rx"^https://github[.]com/([^?/#]+)/([^/?#]+)[.]git/?")
(define github-github-rx #rx"^github://github[.]com/([^?/#]+)/([^/?#]+)/?")

;; url->owner+repo : String -> (list String String)/#f
(define (url->owner+repo url)
  (cond [(or (regexp-match github-git-rx url)
             (regexp-match github-https-rx url)
             (regexp-match github-github-rx url))
         => (lambda (m)
              (defmatch (list _ owner repo) m)
              (list owner repo))]
        [else #f]))

(module+ test
  (require rackunit)

  (check-equal? (url->owner+repo "git://github.com/owner/repo")
                (list "owner" "repo"))
  (check-equal? (url->owner+repo "git://github.com/owner/repo#branch")
                (list "owner" "repo"))
  (check-equal? (url->owner+repo "git://github.com/owner/repo?path=path")
                (list "owner" "repo"))
  (check-equal? (url->owner+repo "git://github.com/owner/repo?path=path#branch")
                (list "owner" "repo"))

  (check-equal? (url->owner+repo "https://github.com/owner/repo.git")
                (list "owner" "repo"))
  (check-equal? (url->owner+repo "https://github.com/owner/repo.git?path=path")
                (list "owner" "repo"))
  (check-equal? (url->owner+repo "https://github.com/owner/repo.git#branch")
                (list "owner" "repo"))
  (check-equal? (url->owner+repo "https://github.com/owner/repo.git?path=path#branch")
                (list "owner" "repo"))

  (check-equal? (url->owner+repo "github://github.com/owner/repo")
                (list "owner" "repo"))
  (check-equal? (url->owner+repo "github://github.com/owner/repo/branch")
                (list "owner" "repo")))
