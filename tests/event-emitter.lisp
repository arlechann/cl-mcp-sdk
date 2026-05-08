(in-package #:mcp-sdk/tests)

(defun call-with-spy (callback)
  (let ((called 0))
    (funcall callback
             #'(lambda (&rest args)
                 (declare (ignore args))
                 (incf called)
                 (values)))
    called))

(defmacro with-spy (spy &body body)
  `(call-with-spy
    #'(lambda (,spy)
        (declare (ignorable ,spy))
        ,@body)))

(deftest vendored-event-emitter
  (ok (let ((emitter (event-emitter:make-event-emitter))
            (fn #'(lambda () nil)))
        (eq (event-emitter:on emitter :test fn)
            fn)))
  (ok (= (with-spy spy
           (let ((emitter (event-emitter:make-event-emitter)))
             (event-emitter:on emitter :test spy)
             (event-emitter:emit emitter :test)))
         1))
  (ok (= (with-spy spy
           (let ((emitter (event-emitter:make-event-emitter)))
             (let ((token (event-emitter:once emitter :test spy)))
               (event-emitter:off emitter :test token)
               (event-emitter:emit emitter :test))))
         0)))
