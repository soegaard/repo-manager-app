#lang racket/base
(require (rename-in racket/match [match-define defmatch])
         racket/string
         racket/list
         racket/runtime-path
         json
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
     (h1 "Repository recent master commits")
     ,@(for/list ([repo repos]) (repo-section manager repo req))
     (h1 "To do summary")
     ,@(for/list ([repo repos]) (repo-todo-section repo req))
     (div ([style "endblock"]) nbsp))))

(define (repo-section manager owner+repo req)
  (defmatch (vector owner repo) owner+repo)
  (define id (format "repo_section_~a_~a" owner repo))
  (define onclick-code (format "toggle_repo_section_body('~a');" id))
  ;; FIXME: accordion instead, maybe?
  `(div ([class "repo_section"]
         [id ,id])
    (div ([class "repo_head"])
         (div ([class "repo_head_buttons"])
              ,(make-repo-button "Expand all" (format "repo_expand_all('~a');" id))
              ,(make-repo-button "Collapse all" (format "repo_collapse_all('~a');" id))
              #| ,(make-ext-link (github:make-repo-link owner repo)) |#)
         (h2 (span ([onclick ,onclick-code]) ,(format "~a/~a " owner repo))))
    ,(repo-section-body manager owner repo req)))

(define (make-repo-button label code)
  `(button ([class "repo_button"]
            [type "button"]
            [onclick ,code])
    ,label))

(define (repo-section-body manager owner repo req)
  (define acis (get-annotated-master-chain owner repo))
  `(div
    (table ([class "repo_section_body"])
           ,@(for/list ([aci acis]) (commit-block manager owner repo aci req)))
    (script ,(format "register_repo_commits('~a', '~a', '~a');"
                     owner repo
                     (jsexpr->string (for/list ([aci acis]) (commit-sha (hash-ref aci 'info))))))))

;; FIXME: need to add status text / action listboxes
(define (commit-block manager owner repo aci req)
  (define ci (hash-ref aci 'info))
  (define picked? (equal? (hash-ref aci 'status_actual) "picked"))
  (define attn? (equal? (hash-ref aci 'status_recommend) "attn"))
  (define id (format "commit_~a" (commit-sha ci)))
  (define onclick-code (format "toggle_commit_full_message('~a');" id))
  `(tr ([class ,(format "commit_block ~a ~a"
                        (if picked? "commit_picked" "commit_unpicked")
                        (if attn? "commit_attn" "commit_no_attn"))]
        [id ,id])
    (td
     (div ([class "commit_line"]
           [onclick ,onclick-code])
          (span ([class "commit_elem commit_sha"]) ,(shorten-sha (commit-sha ci)))
          (span ([class "commit_elem commit_date"]) ,(nicer-date (author-date (commit-author ci))))
          (span ([class "commit_elem commit_author"]) ,(author-name (commit-author ci)))
          (span ([class "commit_elem commit_msg_line1"]) ,(string-first-line (commit-message ci))))
     (div ([class "commit_full_msg"]) ,@(string-newlines->brs (commit-message ci))))
    (td ([class "commit_action"])
        ,(if picked?
             `(span ([class "commit_action_picked"]) "picked")
             (make-commit-action-select id owner repo (commit-sha ci))))))

(define (make-commit-action-select id owner repo sha)
  (define name (format "action_~a" sha))
  `(span
    (input ([type "checkbox"] [name ,name] [class "commit_pick_checkbox"]
            [onchange ,(format "update_commit_action('~a', '~a', '~a', '~a');" id owner repo sha)]))
    (label ([for ,name]) "pick")))

(define (repo-todo-section owner+repo req)
  (defmatch (vector owner repo) owner+repo)
  (define id (format "todo_repo_~a_~a" owner repo))
  (define onclick-code (format "toggle_todo_body('~a');" id))
  `(div ([class "todo_section"]
         [id ,id])
    (h2 (span ([onclick ,onclick-code]) ,(format "~a/~a" owner repo)))
    (div ([class "todo_body"])
         (div ([class "todo_empty"])
              "No todo items for this repo.")
         ,(repo-todo-prologue owner repo)
         ,@(for/list ([aci (get-annotated-master-chain owner repo)]
                      #:when (equal? "no" (hash-ref aci 'status_actual))) ;; FIXME
             (todo-commit-line owner repo (commit-sha (hash-ref aci 'info))))
         ,(repo-todo-epilogue owner repo))))

(define (repo-todo-prologue owner repo)
  (cond [(db:get-branch owner repo "release")
         `(div ([class "todo_bookkeeping_line"])
           "git pull; git checkout release")]
        [else
         (define branch-day-sha (db:get-branch-day-sha owner repo))
         `(div ([class "todo_bookkeeping_line"])
           "git pull; git checkout -b release " (span ,branch-day-sha))]))

(define (repo-todo-epilogue owner repo)
  `(div ([class "todo_bookkeeping_line"])
    "git push origin release"))

(define (todo-commit-line owner repo sha)
  `(div ([class "todo_commit_line"]
         [id ,(format "todo_commit_~a" sha)])
    "git cherry-pick -x " (span ([class "todo_commit_sha"]) ,sha)))

;; ============================================================

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
