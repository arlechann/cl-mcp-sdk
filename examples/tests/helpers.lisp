(in-package #:mcp-sdk.examples.tests)

(defclass <test-transport> (mcp-sdk::<transport>)
  ((messages :initform '()
             :accessor test-transport-messages)))

(defmethod mcp-sdk::transport-send-message ((transport <test-transport>) message)
  (setf (test-transport-messages transport)
        (append (test-transport-messages transport)
                (list message)))
  message)

(defmethod mcp-sdk::start-transport ((transport <test-transport>) server)
  (declare (ignore server))
  transport)

(defmethod mcp-sdk::stop-transport ((transport <test-transport>))
  transport)

(defun last-message (server)
  (car (last (test-transport-messages (mcp-sdk::server-transport server)))))

(defun all-messages (server)
  (test-transport-messages (mcp-sdk::server-transport server)))

(defun find-message-by-method (server method)
  (find method (all-messages server)
        :test #'string=
        :key #'(lambda (message)
                 (json-get message "method"))))

(defun find-message-by-id (server id)
  (find id (all-messages server)
        :test #'equal
        :key #'(lambda (message)
                 (json-get message "id"))))

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

(defun wait-for (thunk &key (timeout 2.0) (sleep 0.01))
  (let ((deadline (+ (get-internal-real-time)
                     (* timeout internal-time-units-per-second))))
    (loop for value = (funcall thunk)
          when value do (return value)
          when (> (get-internal-real-time) deadline)
            do (return nil)
          do (sleep sleep))))
