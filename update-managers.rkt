#lang racket/base
(require racket/cmdline
         json
         "init.rkt")
(provide (all-defined-out))

;; Run this after init.rkt to re-check and update the manager
;; information of an existing configuration based on new
;; src/{repos,managers}.rktd files.

;; ============================================================

(module+ main
  (require racket/cmdline)
  (command-line
   #:args ()
   (let ()
     (unless (file-exists? config-file)
       (error 'update-managers "config file doesn't exist: ~e" config-file))
     (define release-info
       (call-with-input-file config-file
         (lambda (in) (read-json in))))
     (define release-info*
       (hash-set release-info 'managers (managers-info)))
     (call-with-output-file* config-file
       #:exists 'truncate/replace
       (lambda (o) (write-json release-info* o))))))
