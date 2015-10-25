#lang racket/base
(require (rename-in racket/match [match-define defmatch])
         racket/string
         racket/list
         racket/date
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
    (lambda (req manager) (manager-view manager))]
   [("ajax" "manager" (string-arg))
    '(lambda (req manager) ...)]
   [("ajax" "repo-html" (string-arg) (string-arg))
    (lambda (req owner repo)
      (repo-section-body (get-repo-info owner repo)))]
   [("ajax" "todo-html" (string-arg) (string-arg))
    (lambda (req owner repo)
      (repo-todo-body (get-repo-info owner repo)))]
   [("ajax" "poll" (string-arg))
    (lambda (req manager) (poll manager))]
   ))

(define (json-response jsexpr #:headers [headers null])
  (response/output (lambda (out) (write-json jsexpr out))
                   #:mime-type #"application/json"
                   #:headers headers))

;; RepoInfo = {
;;   owner : String,
;;   repo : String,
;;   last_polled : Date (string or integer???),
;;   branch_day_sha : String,
;;   master_sha : String / null,
;;   release_sha : String / null,
;;   commits : Arrayof AnnotatedCommitInfo,
;;   _ }

;; AnnotatedCommitInfo = {
;;   info : CommitInfo (see github.rkt),
;;   status_actual : String (...),
;;   status_recommend : String (...),
;;   _ }

;; Not yet implemented:
;; 
;; ManagerInfo = {
;;   manager : String,
;;   repos : Arrayof { owner : String, repo : String },
;;   _ }

;; ============================================================

;; FIXME: add time/rate limit of some sort...
(define (poll manager)
  (define repos (db:get-manager-repos manager))
  (define updated
    (filter values
      (for/list ([owner+repo repos])
        (defmatch (vector owner repo) owner+repo)
        (define (get-state)
          (list (db:get-branch-sha owner repo "master")
                (db:get-branch-sha owner repo "release")))
        (define old-state (get-state))
        (db:recache-ref/ts owner repo "heads/master")
        (db:recache-ref/ts owner repo "heads/release")
        (define new-state (get-state))
        (and (not (equal? new-state old-state))
             (hash 'owner owner 'repo repo)))))
  (json-response updated))

;; ----------------------------------------

(define (manager-view manager)
  (define repos (db:get-manager-repos manager))
  (define ris (for/list ([o+r repos]) (defmatch (vector owner repo) o+r) (get-repo-info owner repo)))
  `(html
    (head (title ,(format "Repositories managed by ~a" manager))
          (link ([href "/view.css"]
                 [rel "stylesheet"]
                 [type "text/css"]))
          (script ([src "/jquery-2.1.4.min.js"]
                   [type "text/javascript"]))
          (script ([src "/jquery.timeago.js"]
                   [type "text/javascript"]))
          (script ([src "/view.js"]
                   [type "text/javascript"]))
          (script ,(format "manager = '~a';" manager)))
    (body
     (div ([class "global_head_buttons"])
          ,(make-button "Check for updates" "check_for_updates();"))
     (h1 "Repository recent master commits")
     ,@(for/list ([ri ris]) (repo-section ri))
     (h1 "To do summary")
     ,@(for/list ([ri ris]) (repo-todo-section ri))
     (div ([style "endblock"]) nbsp))))

(define (repo-section ri)
  (define owner (hash-ref ri 'owner))
  (define repo (hash-ref ri 'repo))
  (define id (format "repo_section_~a_~a" owner repo))
  (define onclick-code (format "toggle_body('~a');" id))
  `(div ([class "repo_section"]
         [id ,id])
    (div ([class "repo_head"])
         (div ([class "repo_head_buttons"])
              ,(make-button "Expand all" (format "repo_expand_all('~a');" id))
              ,(make-button "Collapse all" (format "repo_collapse_all('~a');" id)))
         (h2 (span ([onclick ,onclick-code]) ,(format "~a/~a " owner repo))))
    (div ([class "body_container"])
         ,(repo-section-body ri))))

(define (make-button label code)
  `(button ([type "button"] [onclick ,code]) ,label))

(define (repo-section-body ri)
  (define owner (hash-ref ri 'owner))
  (define repo (hash-ref ri 'repo))
  (define acis (hash-ref ri 'commits))
  (define timestamp (seconds->datestring (hash-ref ri 'last_polled)))
  `(div
    (div ([class "repo_status_line"])
         ,(format "~a commits; " (length acis))
         "last checked for updates "
         (abbr ([class "timeago"] [title ,timestamp]) "at " ,timestamp))
    (table ([class "repo_section_body"])
           ,@(for/list ([aci acis] [i (in-naturals 1)]) (commit-block owner repo aci i)))
    (script ,(format "register_repo_commits('~a', '~a', '~a');"
                     owner repo
                     (jsexpr->string (for/list ([aci acis]) (commit-sha (hash-ref aci 'info))))))))

;; FIXME: need to add status text / action listboxes
(define (commit-block owner repo aci i)
  (define ci (hash-ref aci 'info))
  (define picked? (equal? (hash-ref aci 'status_actual) "picked"))
  (define attn? (equal? (hash-ref aci 'status_recommend) "attn"))
  (define id (format "commit_~a" (commit-sha ci)))
  (define onclick-code (format "toggle_commit_full_message('~a');" id))
  `(tr ([id ,id]
        [class ,(format "commit_block ~a ~a"
                        (if picked? "commit_picked" "commit_unpicked")
                        (if attn? "commit_attn" "commit_no_attn"))])
    (td ([class "commit_index"]) ,(format "~a" i))
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
    (label
     (input ([type "checkbox"] [name ,name] [class "commit_pick_checkbox"]
             [onchange ,(format "update_commit_action('~a', '~a', '~a', '~a');" id owner repo sha)]))
     "pick")))

;; ----------------------------------------

(define (repo-todo-section ri)
  (define owner (hash-ref ri 'owner))
  (define repo (hash-ref ri 'repo))
  (define id (format "todo_repo_~a_~a" owner repo))
  (define onclick-code (format "toggle_body('~a');" id))
  `(div ([class "todo_section"]
         [id ,id])
    (h2 (span ([onclick ,onclick-code]) ,(format "~a/~a" owner repo)))
    (div ([class "body_container"])
         ,(repo-todo-body ri))))

(define (repo-todo-body ri)
  (define owner (hash-ref ri 'owner))
  (define repo (hash-ref ri 'repo))
  `(div ([class "todo_body"])
    (div ([class "todo_empty"])
         "No todo items for this repo.")
    ,(repo-todo-prologue ri)
    ,@(for/list ([aci (hash-ref ri 'commits)]
                 #:when (equal? "no" (hash-ref aci 'status_actual))) ;; FIXME
        (todo-commit-line owner repo (commit-sha (hash-ref aci 'info))))
    ,(repo-todo-epilogue)))

(define (repo-todo-prologue ri)
  (cond [(hash-ref ri 'release_sha)
         `(div ([class "todo_bookkeeping_line"])
           "git pull; git checkout release")]
        [else
         `(div ([class "todo_bookkeeping_line"])
           "git pull; git checkout -b release "
           (span ,(hash-ref ri 'branch_day_sha)))]))

(define (repo-todo-epilogue)
  `(div ([class "todo_bookkeeping_line"])
    "git push origin release"))

(define (todo-commit-line owner repo sha)
  `(div ([class "todo_commit_line"]
         [id ,(format "todo_commit_~a" sha)])
    "git cherry-pick -x " (span ([class "todo_commit_sha"]) ,sha)))

;; ============================================================

(define (shorten-sha s)
  (substring s 0 8))

(define (seconds->datestring s)
  (parameterize ((date-display-format 'iso-8601))
    ;; racket/date doesn't actually do iso-8601 quite right...
    (string-append (date->string (seconds->date s #f) #t) "Z")))

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
