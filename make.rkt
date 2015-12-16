#lang racket/base
(require xml
         racket/runtime-path)

(define-runtime-path index-src "web-src/index.rktd")
(define-runtime-path index-html "web-content/index.html")

(define (make-html in out)
  (define xe (call-with-input-file* in read))
  (call-with-output-file* out
    #:exists 'truncate/replace
    (lambda (out) (write-xexpr xe out #:insert-newlines? #f))))

(module+ main
  (make-html index-src index-html))
