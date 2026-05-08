(defsystem "event-emitter"
  :version "0.0.1"
  :author "arlechann"
  :license "CC0-1.0"
  :depends-on ("alexandria")
  :pathname "vendor/cl-event-emitter/"
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "event-emitter"))))
  :description "Vendored event-emitter system for mcp-sdk."
  :in-order-to ((test-op (test-op "event-emitter/tests"))))

(defsystem "event-emitter/tests"
  :pathname "vendor/cl-event-emitter/"
  :depends-on ("event-emitter"
               "rove")
  :components ((:module "tests"
                :components
                ((:file "package")
                 (:file "event-emitter"))))
  :description "Vendored event-emitter test system."
  :perform (test-op (op c) (symbol-call :rove :run c)))
