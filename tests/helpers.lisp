(in-package #:mcp-sdk/tests)

(defclass <test-transport> (mcp-sdk::<transport>)
  ((messages :initform '()
             :accessor test-transport-messages)
   (started-p :initform nil
              :accessor test-transport-started-p)))

(defmethod mcp-sdk::transport-send-message ((transport <test-transport>) message)
  (setf (test-transport-messages transport)
        (append (test-transport-messages transport)
                (list message)))
  message)

(defmethod mcp-sdk::start-transport ((transport <test-transport>) server)
  (declare (ignore server))
  (setf (test-transport-started-p transport) t)
  transport)

(defmethod mcp-sdk::stop-transport ((transport <test-transport>))
  (setf (test-transport-started-p transport) nil)
  transport)

(defun make-test-server ()
  (make-server
   :name "test-server"
   :version "0.1.0"
   :transport (make-instance '<test-transport>)
   :worker-count 2))

(defun last-message (server)
  (car (last (test-transport-messages (mcp-sdk::server-transport server)))))

(defun all-messages (server)
  (test-transport-messages (mcp-sdk::server-transport server)))

(defun find-message-by-method (server method)
  (find method (all-messages server)
        :test #'string=
        :key #'(lambda (message)
                 (json-get message "method"))))

(defun make-request (id method &optional params)
  (let ((message (mcp-sdk::make-object
                  "jsonrpc" "2.0"
                  "id" id
                  "method" method)))
    (when params
      (setf (gethash "params" message) params))
    message))

(defun make-notification (method &optional params)
  (let ((message (mcp-sdk::make-object
                  "jsonrpc" "2.0"
                  "method" method)))
    (when params
      (setf (gethash "params" message) params))
    message))

(defun response-result (message)
  (json-get message "result"))

(defun response-error (message)
  (json-get message "error"))

(defun wait-for (thunk &key (timeout 2.0) (sleep 0.01))
  (let ((deadline (+ (get-internal-real-time)
                     (* timeout internal-time-units-per-second))))
    (loop for value = (funcall thunk)
          when value do (return value)
          when (> (get-internal-real-time) deadline)
            do (return nil)
          do (sleep sleep))))
