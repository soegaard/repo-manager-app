#lang racket/base
(require racket/string
         "net.rkt"
         "github-base.rkt")
(provide (all-defined-out))

(define (gh-endpoint . args)
  (string-join (cons "https://api.github.com" args) "/"))

;; ============================================================
;; COMMITS (https://developer.github.com/v3/git/commits/)

;; Get a commit
(define (github:get-commit owner repo sha)
  (get/github (gh-endpoint "repos" owner repo "git/commits" sha)))
;; CommitInfo = {
;;   sha : String,
;;   author : AuthorInfo, committer : AuthorInfo,
;;   message : String,
;;   parents : [ { sha : String, _ }, ... ],
;;   _ }
;; AuthorInfo = { date = String, name = String, email = String }

(define (commit-sha ci) (hash-ref ci 'sha))
(define (commit-author ci) (hash-ref ci 'author))
(define (commit-committer ci) (hash-ref ci 'committer))
(define (commit-message ci) (hash-ref ci 'message))
(define (commit-parents ci) (hash-ref ci 'parents))
(define (parent-sha pi) (hash-ref pi 'sha))
(define (commit-parent-sha ci)
  (define parents (commit-parents ci))
  (cond [(= (length parents) 1)
         (parent-sha (car parents))]
        [else (error 'commit-parent-sha "multiple parents\n  commit: ~s" (commit-sha ci))]))

(define (author-date ai) (hash-ref ai 'date))
(define (author-name ai) (hash-ref ai 'name))
(define (author-email ai) (hash-ref ai 'email))

;; ============================================================
;; REFERENCES (https://developer.github.com/v3/git/refs/)

;; Get a reference
(define (github:get-ref owner repo ref)
  (get/github (gh-endpoint "repos" owner repo "git/refs" ref)
              #:fail (lambda _ #f)))
;; RefInfo = { ref : String, object : { type : "commit", sha : String, _ }, _ }

(define (ref-sha ri) (hash-ref (hash-ref ri 'object) 'sha))


;; ============================================================
;; Create links to github.com

(define (github:make-repo-link owner repo)
  (format "https://github.com/~a/~a/" owner repo))

(define (github:make-commit-link owner repo commit)
  (format "https://github.com/~a/~a/commit/~a" owner repo commit))
