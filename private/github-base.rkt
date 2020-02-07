#lang racket/base
(require racket/file
         racket/port
         racket/match
         net/url
         net/base64
         json
         "net.rkt"
         (only-in pkg/private/stage
                  github-client_id
                  github-client_secret))
(provide get/github
         head/github
         delete/github
         post/github
         put/github)

;; ============================================================
;; Github

(define USER-AGENT (format "User-Agent: rmculpepper/repo-manager-app/~a" (version)))
(define ACCEPT "Accept: application/vnd.github.v3+json")

(define (wrap/no-data who0 proc)
  (lambda (url #:headers [headers null]
          #:handle [handle1 read-json]
          #:handle2 [handle2 (lambda (in headers) (handle1 in))]
          #:fail [fail "failed"] #:who [who who0]
          #:user-credentials? [user-credentials? #f])
    (proc url
          #:headers (list* USER-AGENT ACCEPT
                           (append (get-authorization-headers user-credentials?)
                                   headers))
          #:handle2 handle2 #:fail fail #:who who)))

(define (wrap/data who0 proc)
  (lambda (url #:headers [headers null]
          #:handle [handle1 read-json]
          #:handle2 [handle2 (lambda (in headers) (handle1 in))]
          #:fail [fail "failed"] #:who [who who0]
          #:user-credentials? [user-credentials? #f]
          #:data [data #f])
    (proc url
          #:headers (list* USER-AGENT ACCEPT
                           (append (get-authorization-headers user-credentials?)
                                   headers))
          #:handle2 handle2 #:fail fail #:who who #:data data)))

(define get/github (wrap/no-data 'get/github get/url))
(define head/github (wrap/no-data 'head/github head/url))
(define delete/github (wrap/no-data 'delete/github delete/url))

(define post/github (wrap/data 'post/github post/url))
(define put/github (wrap/data 'put/github put/url))

;; ----------------------------------------

;; create authorization headers (one or zero) from user/client credentials
(define (get-authorization-headers user-credentials?)
  (cond [(and user-credentials? github-user-credentials)
         (match-define (list user-token) github-user-credentials)
         (list (format "Authorization: token ~a" user-token))]
        [user-credentials?
         (error 'get-authorization-header "user credentials required but not available")]
        [(and (github-client_id) (github-client_secret))
         (list (format "Authorization: basic ~a"
                       (base64-encode
                        (string->bytes/utf-8
                         (format "~a:~a" (github-client_id) (github-client_secret)))
                        "")))]
        [else null]))

;; add credentials to url; deprecated by github since 2019-11
(define (add-credentials url user-credentials?)
  (cond [(and user-credentials? github-user-credentials)
         (url-add-query url (list (cons 'access_token github-user-credentials)))]
        [user-credentials?
         (error 'add-credentials "user credentials required but not available")]
        [else
         (url-add-query url (github-client-credentials))]))

;; The user credentials are optional; stored in $PREFS/github-user-credentials.rktd.
;; If present, the file contains a single sexpr: a string containing a user token.

;; The client credentials are stored in $PREFS/github-poll-client.rktd.
;; The file contains an sexpr of the form (list client-id client-secret), where
;; both client-{id,secret} are strings.

(define github-user-credentials
  (let ([file (build-path (find-system-path 'pref-dir) "github-user-credentials.rktd")])
    (and (file-exists? file)
         (file->value file))))

(let ([credentials-file
       (build-path (find-system-path 'pref-dir) "github-poll-client.rktd")])
  (cond [(file-exists? credentials-file)
         (define credentials (file->value credentials-file))
         (github-client_id (car credentials))
         (github-client_secret (cadr credentials))]
        [else
         (eprintf "! No github credentials found.\n")]))

(define (github-client-credentials)
  (cond [(and (github-client_id)
              (github-client_secret))
         (list (cons 'client_id (github-client_id))
               (cons 'client_secret (github-client_secret)))]
        [else null]))

;; ----------------------------------------

(define (build-url base
                   #:path [path-parts null]
                   #:query [query-parts null]
                   #:fragment [fragment #f])
  (build-url* base path-parts query-parts fragment))

(define (build-url* base path-parts query-parts fragment)
  (match base
    [(? string)
     (build-url* (string->url base) path-parts query-parts fragment)]
    [(url scheme user host port path-absolute? path query old-fragment)
     (define path* (append path (map build-path/param path-parts)))
     (define query* (append query query-parts))
     (define fragment* (or fragment old-fragment))
     (url scheme user host port path-absolute? path query fragment*)]))

(define (build-path/param p)
  (cond [(path/param? p) p]
        [else (path/param p null)]))
