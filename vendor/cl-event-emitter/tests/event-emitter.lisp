(in-package #:event-emitter.tests)

(defun call-with-spy (callback)
  (let ((called 0))
    (funcall callback
             #'(lambda (&rest args)
                 (declare (ignore args))
                 (incf called)
                 (values)))
    called))

(defmacro with-spy (spy &body body)
  `(call-with-spy #'(lambda (,spy) 
                      (declare (ignorable ,spy))
                      ,@body)))

(deftest test-event-emitter
  (ok (let ((emitter (make-event-emitter))
            (fn #'(lambda () nil)))
        (eq (on emitter :test-event-1 fn)
            fn)))
  (ok (let ((emitter (make-event-emitter)))
        (eq (emit emitter :test-event-1)
            :test-event-1)))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (on emitter :test-event-1 spy)))
         0))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (emit emitter :test-event-1)))
         0))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (on emitter :test-event-1 spy)
             (emit emitter :test-event-1)))
         1))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (on emitter :test-event-1 spy)
             (emit emitter :test-event-1)
             (emit emitter :test-event-1)))
         2))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (on emitter :test-event-1 spy)
             (emit emitter :test-event-2)))
         0))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (on emitter :test-event-1 spy)
             (emit emitter :test-event-1)
             (emit emitter :test-event-2)))
         1))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (on emitter :test-event-1 spy)
             (off emitter :test-event-1 spy)
             (emit emitter :test-event-1)))
         0))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (on emitter :test-event-1 spy)
             (emit emitter :test-event-1)
             (off emitter :test-event-1 spy)
             (emit emitter :test-event-1)))
         1))
  (ok (= (with-spy spy1
           (with-spy spy2
             (let ((emitter (make-event-emitter)))
               (on emitter :test-event-1 spy1)
               (on emitter :test-event-1 spy2))))
         0))
  (ok (= (with-spy spy1
           (with-spy spy2
             (let ((emitter (make-event-emitter)))
               (on emitter :test-event-1 spy1)
               (on emitter :test-event-1 spy2)
               (emit emitter :test-event-1))))
         1))
  (ok (= (with-spy spy1
           (with-spy spy2
             (let ((emitter (make-event-emitter)))
               (on emitter :test-event-1 spy2)
               (on emitter :test-event-1 spy1)
               (emit emitter :test-event-1))))
         1))
  (ok (= (with-spy spy1
           (with-spy spy2
             (let ((emitter (make-event-emitter)))
               (on emitter :test-event-1 spy1)
               (on emitter :test-event-2 spy2)
               (emit emitter :test-event-2))))
         0))
  (ok (= (with-spy spy1
           (with-spy spy2
             (let ((emitter (make-event-emitter)))
               (on emitter :test-event-1 spy2)
               (on emitter :test-event-2 spy1)
               (emit emitter :test-event-2))))
         1))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (once emitter :test-event-1 spy)))
         0))
  (ok (= (with-spy spy
           (let* ((emitter (make-event-emitter))
                  (once-fn (once emitter :test-event-1 spy)))
             (off emitter :test-event-1 once-fn)
             (emit emitter :test-event-1)))
         0))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (once emitter :test-event-1 spy)
             (emit emitter :test-event-1)))
         1))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (once emitter :test-event-1 spy)
             (emit emitter :test-event-1)
             (emit emitter :test-event-1)))
         1))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (once emitter :test-event-1 spy)
             (emit emitter :test-event-2)))
         0))
  (ok (= (with-spy spy
           (let ((emitter (make-event-emitter)))
             (once emitter :test-event-1 spy)
             (emit emitter :test-event-1)
             (emit emitter :test-event-2)))
         1))
  )
