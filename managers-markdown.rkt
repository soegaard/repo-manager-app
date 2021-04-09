#lang typed/racket

;; this file generates the text that appears
;; on https://github.com/racket/racket/wiki/Release-repo-managers/


;; each element is a list containing a manager's name
;; and then a list of the repos they manage
(define managers-list
  (cast
   ;; FIXME use local path
   (file->value "/tmp/managers.rktd")
   (Listof (Listof Symbol))))

(first managers-list)

;; this produces the "by-manager" list lines
(define (manager->list-1 [mgr : (Listof Symbol)])
  (match-define (cons manager repos) mgr)
  (cons (~a "*" manager "*:")
        (for/list : (Listof String)
          ([repo (in-list repos)])
          (~a " - **"repo"**"))))

;; this produces the by-repo list lines
(define (manager->list-2 [mgr : (Listof Symbol)])
  (match-define (cons manager repos) mgr)
  (for/list : (Listof String)
    ([repo (in-list repos)])
    (~a " - **"repo"** is managed by *"manager"*")))

(define (line-list->text [lines : (Listof String)])
  (apply string-append
         (add-between lines "\n")))

(define manager-lines-1
  (append
   (list "## Listing by manager"
         "")
  (apply
   append
   (add-between
    (map manager->list-1 managers-list)
    (list "")))))

(define manager-lines-2
  (append
   (list "## Listing by repository"
         "")
   (sort
    (apply append
           (map manager->list-2 managers-list))
    string<?)))


(display
 (line-list->text
  (append
   manager-lines-1
   manager-lines-2)))


