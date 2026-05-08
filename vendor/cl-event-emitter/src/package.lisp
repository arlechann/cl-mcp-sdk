(in-package #:cl-user)

(defpackage #:event-emitter
  (:nicknames #:ee)
  (:use #:cl)
  (:import-from #:alexandria
                #:deletef)
  (:export #:<event-emitter>
           #:make-event-emitter
           #:emit
           #:on
           #:off
           #:once
           #:add-listener
           #:remove-listener))

