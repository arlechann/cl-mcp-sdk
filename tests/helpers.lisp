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

(defun make-test-server (&rest initargs)
  (apply #'make-server
         :name "test-server"
         :version "0.1.0"
         :transport (make-instance '<test-transport>)
         :worker-count 2
         initargs))

(defun make-test-session (&rest initargs)
  (mcp-sdk:make-session (apply #'make-test-server initargs)))

(defun make-core-feature-session ()
  (let* ((server (make-test-server))
         (session (mcp-sdk:make-session server)))
    (register-tool server "echo"
                   :description "Echo back arguments"
                   :input-schema (mcp-sdk::make-object "type" "object")
                   :handler #'(lambda (session context arguments)
                                (declare (ignore session context))
                                (mcp-sdk::make-object
                                 "content"
                                 (vector (mcp-sdk::make-object
                                          "type" "text"
                                          "text" (json-get arguments "message"))))))
    (register-resource server "greeting"
                       :uri "resource:greeting"
                       :mime-type "text/plain"
                       :handler #'(lambda (session context arguments)
                                    (declare (ignore session context arguments))
                                    (mcp-sdk::make-object
                                     "contents"
                                     (vector (mcp-sdk::make-object
                                              "uri" "resource:greeting"
                                              "mimeType" "text/plain"
                                              "text" "hello")))))
    (register-prompt server "greeter"
                     :arguments (list (mcp-sdk::make-object
                                       "name" "subject"
                                       "required" t))
                     :handler #'(lambda (session context arguments)
                                  (declare (ignore session context))
                                  (mcp-sdk::make-object
                                   "messages"
                                   (vector (mcp-sdk::make-object
                                            "role" "user"
                                            "content" (mcp-sdk::make-object
                                                       "type" "text"
                                                       "text" (format nil "Hello, ~A"
                                                                      (json-get arguments "subject"))))))))
    (values server session)))

(defun last-message (session)
  (car (last (test-transport-messages (mcp-sdk::session-transport session)))))

(defun all-messages (session)
  (test-transport-messages (mcp-sdk::session-transport session)))

(defun find-message-by-method (session method)
  (find method (all-messages session)
        :test #'string=
        :key #'(lambda (message)
                 (json-get message "method"))))

(defun find-message-by-id (session id)
  (find id (all-messages session)
        :test #'equal
        :from-end t
        :key #'(lambda (message)
                 (and (or (response-result message)
                          (response-error message))
                      (json-get message "id")))))

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
