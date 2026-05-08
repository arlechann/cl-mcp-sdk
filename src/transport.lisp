(in-package #:mcp-sdk)

(defclass <transport> ()
  ())

(defgeneric transport-send-message (transport message))
(defgeneric start-transport (transport server))
(defgeneric stop-transport (transport))

(defclass <stdio-transport> (<transport>)
  ((input :initarg :input
          :initform *standard-input*
          :reader transport-input)
   (output :initarg :output
           :initform *standard-output*
           :reader transport-output)
   (write-lock :initform (make-lock "mcp-sdk.transport.write-lock")
               :reader transport-write-lock)
   (read-thread :initform nil
                :accessor transport-read-thread)
   (running-p :initform nil
              :accessor transport-running-p)))

(defun make-stdio-transport (&key (input *standard-input*)
                                  (output *standard-output*))
  (make-instance '<stdio-transport>
                 :input input
                 :output output))

(defmethod transport-send-message ((transport <stdio-transport>) message)
  (with-lock-held ((transport-write-lock transport))
    (write-line (json-encode message) (transport-output transport))
    (finish-output (transport-output transport)))
  message)

(defmethod start-transport ((transport <stdio-transport>) server)
  (setf (transport-running-p transport) t)
  (setf (transport-read-thread transport)
        (make-thread
         #'(lambda ()
             (loop while (transport-running-p transport)
                   for line = (read-line (transport-input transport) nil nil)
                   while line
                   do (handler-case
                          (handle-message server (json-decode line))
                        (error (condition)
                          (declare (ignore condition))))
                   finally (setf (transport-running-p transport) nil)))
         :name "mcp-sdk.stdio.read-loop"))
  transport)

(defmethod stop-transport ((transport <stdio-transport>))
  (setf (transport-running-p transport) nil)
  (let ((thread (transport-read-thread transport)))
    (when thread
      (ignore-errors (destroy-thread thread))
      (setf (transport-read-thread transport) nil)))
  transport)
