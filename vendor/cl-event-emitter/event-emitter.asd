(defsystem "event-emitter"
  :version "0.0.1"
  :author "arlechann"
  :license "CC0-1.0"
  :depends-on (:alexandria)
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "event-emitter"))))
  :description ""
  :in-order-to ((test-op (test-op "event-emitter/tests"))))

(defsystem "event-emitter/tests"
  :author ""
  :license ""
  :depends-on ("event-emitter"
               "rove")
  :components ((:module "tests"
                :components
                ((:file "package")
                 (:file "event-emitter"))))
  :description "Test system for event-emitter"
  :perform (test-op (op c) (symbol-call :rove :run c)))
