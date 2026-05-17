(in-package #:cl-user)

(defpackage #:mcp-sdk.examples.echo
  (:use #:cl)
  (:export #:main
           #:make-echo-server))

(in-package #:mcp-sdk.examples.echo)

(defun make-object (&rest entries)
  (let ((table (make-hash-table :test #'equal)))
    (loop for (key value) on entries by #'cddr
          do (setf (gethash key table) value))
    table))

(defun text-content (text)
  (make-object
   "content"
   (vector (make-object
            "type" "text"
            "text" text))))

(defun echo-schema ()
  (mcp-sdk:json-decode
   "{\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\"}},\"required\":[\"text\"]}"))

(defun make-echo-server ()
  (let ((server (mcp-sdk:make-server
                 :name "echo-server"
                 :version "0.1.0")))
    (mcp-sdk:register-tool
     server
     "echo"
     :title "Echo"
     :description "受け取ったテキストをそのまま返します。"
     :input-schema (echo-schema)
     :handler #'(lambda (session context arguments)
                  (declare (ignore session context))
                  (text-content (or (mcp-sdk:json-get arguments "text")
                                    ""))))
    server))

(defun main ()
  (mcp-sdk:start-server (make-echo-server)))
