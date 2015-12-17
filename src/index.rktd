(html
 (head (link ([href "/view.css"]
              [rel "stylesheet"]
              [type "text/css"]))

       (script ([src "/jquery-2.1.4.min.js"]
                [type "text/javascript"]))
       (script ([src "/jquery.timeago.js"]
                [type "text/javascript"]))
       (script ([src "/handlebars-v4.0.2.js"]
                [type "text/javascript"]))
       (script ([src "/data.js"]
                [type "text/javascript"]))
       (script ([src "/view.js"]
                [type "text/javascript"]))

       ;; { owner, repo, id }
       (script ([id "template_repo_section"]
                [type "application/x-template"])
         (div ([class "repo_section"]
               [id "{{id}}"])
           (div ([class "repo_head"])
             (div ([class "repo_head_buttons"])
                  (button ([type "button"]
                           [onclick "check_repo_for_updates('{{owner}}', '{{repo}}');"])
                    "Check for updates")
                  (button ([type "button"]
                           [onclick "repo_expand_all('{{id}}');"])
                    "Expand all")
                  (button ([type "buttom"]
                           [onclick "repo_collapse_all('{{id}}');"])
                          "Collapse all"))
             (h2 (span (#|[onclick "toggle_body('{{id}}');"]|#)
                       "{{owner}}/{{repo}}")))
           (div ([class "body_container"]))))

       ;; { ower, repo, ncommits, last_polled, master_chain : [ Commit, ... ] }
       ;; Commit = {id, class_picked, class_attn, index, short_sha, sha,
       ;;           author.date, author.name, message_line1, message, is_picked }
       (script ([id "template_repo_body"]
                [type "application/x-template"])
         (div
          "{{#if commits_ok}}"
          (div ([class "repo_status_line"])
            "{{ncommits}} commits since branch day; "
            "last checked for updates "
            (abbr ([class "timeago"] [title "{{last_polled}}"])
                  "at {{last_polled}}")
            (span ([class "repo_status_checking"])
                  "; checking for updates now"))
          (table ([class "repo_section_body"])
            "{{#each master_chain}}"
            (tr ([id "{{id}}"]
                 [class "commit_block {{class_evenodd}} {{class_picked}} {{class_attn}}"])
                (td ([class "commit_index"]) "{{index}}")
                (td ([class "commit_sha"])
                  (a ([href "https://github.com/{{../owner}}/{{../repo}}/commit/{{sha}}"])
                     "{{short_sha}}"))
                (td ([class "commit_date"])
                  (abbr ([title "{{author.date}}"]) "{{nice_date}}"))
                (td ([class "commit_author"]) "{{author.name}}")
                (td (div
                     (div ([class "commit_msg_line1 {{class_one_multi}}"]
                           [onclick "toggle_commit_full_message('{{id}}');"])
                       "{{message_line1}}")
                     (div ([class "commit_rest_msg"])
                          "{{{message_rest_lines}}}")))
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
             (h3 (span (#|[onclick "toggle_body('{{todo_id}}');"]|#)
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
       (select ([id "navigation"])
         (option "Select manager or repo"))
       (button ([type "button"]
                [onclick "check_all_for_updates();"])
         "Check for updates")
       (button ([type "button"]
                [onclick "clear_local_storage();"])
         "Clear local storage"))
  (h1 "Repository recent master commits")
  (div ([id "repo_section_container"]))
  (h1 "To do summary")
  (div ([id "todo_section_container"]))
  (div ([style "endblock"]) nbsp)
  (script "initialize_page();")))
