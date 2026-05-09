(defsystem "mcp-sdk"
  :version "0.0.1"
  :author "arlechann"
  :license "CC0-1.0"
  :depends-on ("alexandria"
               "event-emitter"
               "frugal-uuid"
               "jonathan"
               "bordeaux-threads"
               "lparallel"
               "uiop")
  :serial t
  :components ((:module "src"
                :serial t
                :components
                ((:file "package")
                 (:file "util")
                 (:file "conditions")
                 (:file "jsonrpc")
                 (:file "transport")
                 (:file "server"))))
  :description ""
  :in-order-to ((test-op (test-op "mcp-sdk/tests"))))

(defsystem "mcp-sdk/tests"
  :author "arlechann"
  :license "CC0-1.0"
  :depends-on ("mcp-sdk"
               "rove")
  :serial t
  :components ((:module "tests"
                :serial t
                :components
                ((:file "package")
                 (:file "helpers")
                 (:file "server")
                 (:file "transport"))))
  :description "Test system for mcp-sdk"
  :perform (test-op (op c)
                    (asdf:test-system "event-emitter/tests")
                    (symbol-call :rove :run c)))
