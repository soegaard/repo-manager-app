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

;; Some security/validation issues:

;; We use xexprs, which protect against HTML injection.

;; We VALIDATE incoming manager and owner/repo names by checking they
;; exist in the db. We RELY on names in db having no js-significant
;; chars (eg, "'"). See also issue below.

;; ISSUE: in a few places, we inject data into js scripts via '~a' ---
;; bad if the data can contain characters like "'". We should be fine,
;; because we only use strings derived from commit SHAs, `owner`,
;; `repo`, and `manager`. Commit SHAs never contain bad chars, and we
;; validate `owner`, `repo`, and `manager` wrt the db. So we're fine
;; as long as we never put bad names in the db during initialization.

;; ISSUE: There's currently no time/rate limiting on ajax/poll, which
;; forces calls to github.

;; TODO: Add current_build_sha to RepoInfo (w/ db table), show on view

(define-runtime-path web-dir "web-content")

(define-values (dispatch _make-url)
  (dispatch-rules
   [("view" (string-arg))
    (lambda (req manager)
      (unless (ok-manager? manager) (error 'page "unknown manager: ~e" manager))
      (manager-viewx manager))]
   [("ajax" "manager" (string-arg))
    (lambda (req manager)
      (unless (ok-manager? manager) (error 'page "unknown manager: ~e" manager))
      (json-response
       (for/list ([entry (db:get-manager-repos manager)])
         (hash 'owner (vector-ref entry 0) 'repo (vector-ref entry 1)))))]
   [("ajax" "repo" (string-arg) (string-arg))
    (lambda (req owner repo)
      (unless (ok-repo? owner repo) (error 'page "bad repo: ~e, ~e" owner repo))
      (json-response (get-repo-info owner repo)))]
   [("ajax" "poll-repo" (string-arg) (string-arg))
    (lambda (req owner repo)
      (unless (ok-repo? owner repo) (error 'age "bad repo: ~e, ~e" owner repo))
      (poll-repo owner repo))]
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
;;   commits : (Arrayof AnnotatedCommitInfo) or String(error),
;;   _ }

;; AnnotatedCommitInfo = {
;;   info : CommitInfo (see github.rkt),
;;   status_actual : String ("no" | "picked" | "pre-avail"),
;;   status_recommend : String (...),
;;   _ }

;; ============================================================

(define (poll-repo owner repo)
  (define (get-state)
    (list (db:get-branch-sha owner repo "master")
          (db:get-branch-sha owner repo "release")))
  (define old-state (get-state))
  (db:recache-ref/ts owner repo "heads/master")
  (db:recache-ref/ts owner repo "heads/release")
  (define new-state (get-state))
  (json-response (not (equal? new-state old-state))))

;; ----------------------------------------

(define (manager-viewx manager)
  `(html
    (head (link ([href "/view.css"]
                 [rel "stylesheet"]
                 [type "text/css"]))
          (script ([src "/jquery-2.1.4.min.js"]
                   [type "text/javascript"]))
          (script ([src "/jquery.timeago.js"]
                   [type "text/javascript"]))
          (script ([src "/handlebars-v4.0.2.js"]
                   [type "text/javascript"]))
          (script ([src "/view.js"]
                   [type "text/javascript"]))

          ;; { owner, repo }
          (script ([id "template_repo_section"]
                   [type "application/x-template"])
            (div ([class "repo_section"]
                  [id "{{id}}"])
              (div ([class "repo_head"])
                (div ([class "repo_head_buttons"])
                  (button ([type "button"]
                           [onclick "repo_expand_all('{{id}}');"])
                          "Expand all")
                  (button ([type "buttom"]
                           [onclick "repo_collapse_all('{{id}}');"])
                          "Collapse all"))
                (h2 (span ([onclick "toggle_body('{{id}}');"])
                          "{{owner}}/{{repo}}")))
              (div ([class "body_container"]))))

          ;; { ower, repo, ncommits, timestamp, commits : [ Commit, ... ] }
          ;; Commit = {id, class_picked, class_attn, index, short_sha, sha,
          ;;           author.date, author.name, message_line1, message, is_picked }
          (script ([id "template_repo_body"]
                   [type "application/x-template"])
            (div
             "{{#if commits_ok}}"
             (div ([class "repo_status_line"])
                  "{{ncommits}} commits since branch day; "
                  "last checked for updates "
                  (abbr ([class "timeago"] [title "{{timestamp}}"])
                        "at {{timestamp}}")
                  (span ([class "repo_status_checking"])
                        "; checking for updates now"))
             (table ([class "repo_section_body"])
               "{{#each commits}}"
               (tr ([id "{{id}}"]
                    [class "commit_block {{class_picked}} {{class_attn}}"])
                 (td ([class "commit_index"]) "{{index}}")
                 (td
                  (div ([class "commit_line"])
                    (span ([class "commit_elem commit_sha"])
                          (a ([href "https://github.com/{{../owner}}/{{../repo}}/commit/{{sha}}"])
                             "{{short_sha}}"))
                    (abbr ([class "commit_elem commit_date"]
                           [title "{{info.author.date}}"])
                          "{{nice_date}}")
                    (span ([class "commit_elem commit_author"]) "{{info.author.name}}")
                    (span ([class "commit_elem commit_msg_line1"]
                           [onclick "toggle_commit_full_message('{{id}}');"])
                          "{{message_line1}}"))
                  (div ([class "commit_full_msg"])
                       "{{{message_lines}}}"))
                 (td ([class "commit_action"])
                   "{{#if is_picked}}"
                   (span ([class "commit_action_picked"]) "picked")
                   "{{else}}"
                   (label
                    (input ([type "checkbox"] [name "action_{{sha}}"]
                            [class "commit_pick_checkbox"]
                            [onchange "update_commit_action('{{id}}','{{../owner}}','{{../repo}}','{{sha}}');"]))
                    "pick")
                   "{{/if}}"))
               "{{/each}}")
             "{{else}}"
             (div ([class "repo_error_line"]) "Error: {{error_line}}")
             "{{/if}}"))

          (script ([id "template_todo_section"]
                   [type "application/x-template"])
            (div ([class "todo_section"]
                  [id "{{todo_id}}"])
              (div ([class "todo_bookkeeping_line"])
                (h3 (span ([onclick "toggle_body('{{todo_id}}');"])
                          "{{owner}}/{{repo}}"))
                (div ([class "body_container"])))))

          (script ([id "template_todo_body"]
                   [type "application/x-template"])
            "{{#if commits_ok}}"
            (div ([class "todo_body"])
              (div ([class "todo_empty"])
                   "No todo items for this repo.")
              ;; Prologue
              "{{#if release_sha}}"
              (div ([class "todo_bookkeeping_line"])
                   "git pull; git checkout release")
              "{{else}}"
              (div ([class "todo_bookkeeping_line"])
                   "git pull; git checkout -b release {{branch_day_sha}}")
              "{{/if}}"
              ;; Commit lines
              "{{#each commits}}"
              "{{#unless is_picked}}"
              (div ([class "todo_commit_line"]
                    [id "todo_commit_{{sha}}"])
                "git cherry-pick -x " (span ([class "todo_commit_sha"]) "{{sha}}"))
              "{{/unless}}"
              "{{/each}}"
              ;; Epilogue
              (div ([class "todo_bookkeeping_line"])
                   "git push origin release"))
            "{{/if}}")
          )

    (body
     (div ([class "global_head_buttons"])
       (button ([type "button"] [onclick "checkx_for_updates();"]) "Check for updates"))
     (h1 "Repository recent master commits")
     (div ([id "repo_section_container"]))
     ;; ,@(for/list ([ri ris]) (repo-section ri))
     (h1 "To do summary")
     (div ([id "todo_section_container"]))
     ;; ,@(for/list ([ri ris]) (repo-todo-section ri))
     (div ([style "endblock"]) nbsp)
     (script ,(format "initialize_for_manager('~a');" manager)))))

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
