(in-package #:cl-user)

(defpackage #:mcp-sdk/tests
  (:use #:cl
        #:mcp-sdk
        #:rove)
  (:import-from #:bordeaux-threads
                #:join-thread
                #:make-thread))
