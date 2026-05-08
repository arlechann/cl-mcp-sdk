(in-package #:cl-user)

(asdf:defsystem "mcp-sdk-examples"
  :depends-on ("mcp-sdk-examples/echo-server"
               "mcp-sdk-examples/notes-server")
  :components ())

(asdf:defsystem "mcp-sdk-examples/echo-server"
  :depends-on ("mcp-sdk")
  :pathname "examples/"
  :serial t
  :components ((:file "echo-server")))

(asdf:defsystem "mcp-sdk-examples/notes-server"
  :depends-on ("mcp-sdk" "bordeaux-threads")
  :pathname "examples/"
  :serial t
  :components ((:file "notes-server")))

(asdf:defsystem "mcp-sdk-examples/tests"
  :depends-on ("mcp-sdk-examples/notes-server"
               "rove")
  :serial t
  :components ((:module "examples/tests"
                :serial t
                :components ((:file "package")
                             (:file "helpers")
                             (:file "notes-server"))))
  :perform (asdf:test-op (op c)
                    (declare (ignore op))
                    (uiop:symbol-call :rove :run c)))
