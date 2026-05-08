(in-package #:mcp-sdk)

(defconstant +json-rpc-invalid-request-error+ -32600)
(defconstant +json-rpc-method-not-found-error+ -32601)
(defconstant +json-rpc-invalid-params-error+ -32602)
(defconstant +json-rpc-internal-error+ -32603)
(defconstant +mcp-server-not-initialized-error+ -32002)

(define-condition mcp-error (error)
  ((code :initarg :code
         :reader mcp-error-code)
   (message :initarg :message
            :reader mcp-error-message)
   (data :initarg :data
         :initform nil
         :reader mcp-error-data))
  (:report (lambda (condition stream)
             (format stream "~A (~A)"
                     (mcp-error-message condition)
                     (mcp-error-code condition)))))

(defun raise-mcp-error (code message &optional data)
  (error 'mcp-error :code code :message message :data data))
