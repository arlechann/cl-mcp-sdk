(in-package #:cl-user)

(defpackage #:mcp-sdk.examples.tests
  (:use #:cl
        #:mcp-sdk
        #:rove)
  (:import-from #:mcp-sdk.examples.notes
                #:make-notes-server))
