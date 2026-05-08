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
