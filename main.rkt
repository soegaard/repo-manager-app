#lang racket/base
(require (rename-in racket/match [match-define defmatch])
         racket/string
         racket/list
         racket/runtime-path
         web-server/servlet
         web-server/servlet-env
         web-server/stuffers/serialize
         web-server/compat/0/coerce
         "private/db.rkt"
         "private/github.rkt")
(provide (all-defined-out))

;; TODO: Add current_build_sha to RepoInfo (w/ db table), show on view

(define-runtime-path web-dir "web-content")

(define-values (dispatch _make-url)
  (dispatch-rules
   [("view" (string-arg))
    (lambda (req manager) (manager-view manager req))]
   [("ajax" "manager" (string-arg))
    '(lambda (req manager) ...)]
   [("ajax" "repo" (string-arg) (string-arg))
    '(lambda (req owner repo) ....)]
   [("ajax" "poll") ;; POST [ { owner : String, repo : String }, ... ]
    '(lambda (req) ....)]
   ))

;; ManagerInfo = {
;;   manager : String,
;;   repos : Arrayof { owner : String, repo : String },
;;   _ }

;; RepoInfo = {
;;   owner : String,
;;   repo : String,
;;   last_polled : Date (string or integer???),
;;   branch_day_sha : String,
;;   current_master_sha : String / null,
;;   current_release_sha : String / null,
;;   master_commits : Arrayof AnnotatedCommitInfo,
;;   _ }

;; AnnotatedCommitInfo = {
;;   info : CommitInfo (see github.rkt),
;;   status_actual : String (...),
;;   status_recommend : String (...),
;;   _ }

;; ============================================================

(define (manager-view manager req)
  (define repos (db:get-manager-repos manager))
  
  `(html
    (head (title ,(format "Repositories managed by ~a" manager))
          (link ([href "/view.css"]
                 [rel "stylesheet"]
                 [type "text/css"]))
          (script ([src "/jquery-2.1.4.min.js"]
                   [type "text/javascript"]))
          (script ([src "/view.js"]
                   [type "text/javascript"])))
    (body
     (h1 "Repository status")
     ,@(for/list ([repo repos]) (repo-section manager repo req))
     (h1 "To do summary")
     (div ([id "todo"]
           [class "todo_section"])
          "Not yet implemented"))))

(define (repo-section manager owner+repo req)
  (defmatch (vector owner repo) owner+repo)
  `(div ([class "repo_section"]
         [id ,(format "repo_section/~a/~a" owner repo)])
    (h2 ,(format "Repo ~a/~a " owner repo)
        ,(make-ext-link (github:make-repo-link owner repo)))
    ,(repo-section-body manager owner repo req)))

(define (repo-section-body manager owner repo req)
  (define acis (get-annotated-master-chain owner repo))
  `(div ([class "repo_section_body"])
    ,@(for/list ([aci acis]) (commit-block manager owner repo aci req))))

;; FIXME: need to add status text / action listboxes
(define (commit-block manager owner repo aci req)
  (define ci (hash-ref aci 'info))
  (define picked? (equal? (hash-ref aci 'status_actual) "picked"))
  (define attn? (equal? (hash-ref aci 'status_recommend) "attn"))
  (define id (format "commit_~a" (commit-sha ci)))
  (define onclick-code (format "toggle_commit_full_message('~a');" id))
  `(div ([class ,(format "commit_block ~a ~a"
                         (if picked? "commit_picked" "commit_unpicked")
                         (if attn? "commit_attn" "commit_no_attn"))]
         [id ,id])
    (div ([class "commit_line"]
          [onclick ,onclick-code])
     (span ([class "commit_sha"]) ,(shorten-sha (commit-sha ci)))
     (span ([class "commit_date"]) ,(nicer-date (author-date (commit-author ci))))
     (span ([class "commit_author"]) ,(author-name (commit-author ci)))
     (span ([class "commit_msg_line1"]) ,(string-first-line (commit-message ci))))
    (div ([class "commit_full_msg"]) ,@(string-newlines->brs (commit-message ci)))
    ))

(define (shorten-sha s)
  (substring s 0 8))

(define (nicer-date s)
  (string-replace s #rx"[TZ]" " "))

(define (make-ext-link url)
  `(a ([class "external_link"] [href ,url]) "[link]"))

(define (string-first-line s)
  (define line (read-line (open-input-string s)))
  (if (eof-object? line) "" line))

(define (string-newlines->brs s)
  (define lines (string-split s "\n"))
  (add-between lines '(br)))

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
