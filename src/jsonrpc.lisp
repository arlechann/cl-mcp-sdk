(in-package #:mcp-sdk)

(defun json-encode (object)
  (jonathan:to-json object))

(defun json-decode (string)
  (jonathan:parse string :as :hash-table))

(defun make-success-response (id result)
  (make-object
   "jsonrpc" "2.0"
   "id" id
   "result" result))

(defun make-error-object (code message &optional data)
  (let ((object (make-object
                 "code" code
                 "message" message)))
    (when data
      (setf (gethash "data" object) data))
    object))

(defun make-error-response (id code message &optional data)
  (make-object
   "jsonrpc" "2.0"
   "id" id
   "error" (make-error-object code message data)))

(defun notification-message-p (message)
  (and (json-get message "method")
       (null (json-get message "id"))))

(defun request-message-p (message)
  (and (json-get message "method")
       (not (null (json-get message "id")))))

(defun response-message-p (message)
  (and (not (json-get message "method"))
       (not (null (json-get message "id")))
       (or (json-get message "result")
           (json-get message "error")
           (let ((presentp nil))
             (multiple-value-bind (value foundp)
                 (gethash "result" message)
               (declare (ignore value))
               (setf presentp foundp))
             presentp))))
