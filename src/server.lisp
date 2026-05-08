(in-package #:mcp-sdk)

(defclass <cancellation-token> ()
  ((cancelled-p :initform nil
                :accessor cancelled-p)
   (lock :initform (make-lock "mcp-sdk.cancellation-token.lock")
         :reader cancellation-token-lock)))

(defclass <request-context> ()
  ((server :initarg :server
           :reader context-server)
   (id :initarg :id
       :reader context-id)
   (request :initarg :request
            :reader context-request)
   (params :initarg :params
           :reader context-params)
   (progress-token :initarg :progress-token
                   :reader context-progress-token)
   (cancellation-token :initarg :cancellation-token
                       :reader context-cancellation-token)))

(defclass <pending-request> ()
  ((lock :initform (make-lock "mcp-sdk.pending-request.lock")
         :reader pending-request-lock)
   (condition-variable :initform (make-condition-variable)
                       :reader pending-request-condition-variable)
   (resolved-p :initform nil
               :accessor pending-request-resolved-p)
   (message :initform nil
            :accessor pending-request-message)))

(defclass <server> (<event-emitter>)
  ((name :initarg :name
         :reader server-name)
   (version :initarg :version
            :reader server-version)
   (transport :initarg :transport
              :reader server-transport)
   (worker-count :initarg :worker-count
                 :initform 2
                 :reader server-worker-count)
   (kernel :initform nil
           :accessor server-kernel)
   (started-p :initform nil
              :accessor server-started-p)
   (initialized-p :initform nil
                  :accessor server-initialized-p)
   (state-lock :initform (make-lock "mcp-sdk.server.state-lock")
               :reader server-state-lock)
   (tools :initform (make-hash-table :test #'equal)
          :reader server-tools)
   (resources :initform (make-hash-table :test #'equal)
              :reader server-resources)
   (prompts :initform (make-hash-table :test #'equal)
            :reader server-prompts)
   (active-requests :initform (make-hash-table :test #'equal)
                    :reader server-active-requests)
   (pending-outbound :initform (make-hash-table :test #'equal)
                     :reader server-pending-outbound)
   (next-request-id :initform 0
                    :accessor server-next-request-id)))

(defun server-on (server event listener)
  (on server event listener))

(defun server-off (server event listener)
  (off server event listener))

(defun make-server (&key name version transport (worker-count 2))
  (make-instance '<server>
                 :name name
                 :version version
                 :transport (or transport (make-stdio-transport))
                 :worker-count worker-count))

(defun ensure-kernel (server)
  (or (server-kernel server)
      (setf (server-kernel server)
            (lparallel:make-kernel (server-worker-count server)))))

(defun next-request-id (server)
  (with-lock-held ((server-state-lock server))
    (incf (server-next-request-id server))))

(defun method-params (message)
  (ensure-object (json-get message "params")))

(defun progress-token-from-params (params)
  (let ((meta (ensure-object (json-get params "_meta"))))
    (json-get meta "progressToken")))

(defun context-cancelled-p (context)
  (cancelled-p (context-cancellation-token context)))

(defun context-report-progress (context progress &optional total message)
  (let ((token (context-progress-token context)))
    (when token
      (let ((payload (make-object
                      "progressToken" token
                      "progress" progress)))
        (when total
          (setf (gethash "total" payload) total))
        (when message
          (setf (gethash "message" payload) message))
        (emit (context-server context) :progress-reported context payload)
        (send-notification (context-server context)
                           "notifications/progress"
                           payload)))))

(defun register-descriptor (table name descriptor)
  (setf (gethash name table) descriptor)
  descriptor)

(defun register-tool (server name &key title description input-schema output-schema annotations handler)
  (register-descriptor
   (server-tools server)
   name
   (list :name name
         :title title
         :description description
         :input-schema input-schema
         :output-schema output-schema
         :annotations annotations
         :handler handler)))

(defun register-resource (server name &key uri uri-template description mime-type handler)
  (register-descriptor
   (server-resources server)
   name
   (list :name name
         :uri uri
         :uri-template uri-template
         :description description
         :mime-type mime-type
         :handler handler)))

(defun register-prompt (server name &key description arguments handler)
  (register-descriptor
   (server-prompts server)
   name
   (list :name name
         :description description
         :arguments arguments
         :handler handler)))

(defmacro define-tool (server name (&optional context arguments) &body body)
  `(register-tool ,server ,name
                  :handler #'(lambda (,context ,arguments)
                               ,@body)))

(defmacro define-resource (server name (&optional context arguments) &body body)
  `(register-resource ,server ,name
                      :handler #'(lambda (,context ,arguments)
                                   ,@body)))

(defmacro define-prompt (server name (&optional context arguments) &body body)
  `(register-prompt ,server ,name
                    :handler #'(lambda (,context ,arguments)
                                 ,@body)))

(defvar *descriptor-object-fields*
  '(("title" . :title)
    ("description" . :description)
    ("inputSchema" . :input-schema)
    ("outputSchema" . :output-schema)
    ("annotations" . :annotations)
    ("uri" . :uri)
    ("uriTemplate" . :uri-template)
    ("mimeType" . :mime-type)))

(defun plist-descriptor->object (descriptor kind)
  (declare (ignore kind))
  (let ((object (make-object
                 "name" (getf descriptor :name))))
    (loop for (json-key . descriptor-key) in *descriptor-object-fields*
          do (when-let (value (getf descriptor descriptor-key))
               (setf (gethash json-key object) value)))
    (when-let (arguments (getf descriptor :arguments))
      (setf (gethash "arguments" object) (make-array-from-list arguments)))
    object))

(defun capabilities-object (server)
  (declare (ignore server))
  (make-object
   "prompts" (make-object)
   "resources" (make-object)
   "tools" (make-object)))

(defun implementation-object (server)
  (make-object
   "name" (server-name server)
   "version" (server-version server)))

(defun send-response (server id result)
  (transport-send-message (server-transport server)
                          (make-success-response id result)))

(defun send-error (server id code message &optional data)
  (transport-send-message (server-transport server)
                          (make-error-response id code message data)))

(defun send-notification (server method &optional params)
  (let ((message (make-object
                  "jsonrpc" "2.0"
                  "method" method)))
    (when params
      (setf (gethash "params" message) params))
    (transport-send-message (server-transport server) message)))

(defun resolve-pending-request (pending message)
  (with-lock-held ((pending-request-lock pending))
    (setf (pending-request-message pending) message
          (pending-request-resolved-p pending) t)
    (condition-notify (pending-request-condition-variable pending)))
  pending)

(defun send-request (server method &key params timeout)
  (let* ((id (next-request-id server))
         (pending (make-instance '<pending-request>))
         (message (make-object
                   "jsonrpc" "2.0"
                   "id" id
                   "method" method)))
    (when params
      (setf (gethash "params" message) params))
    (setf (gethash id (server-pending-outbound server)) pending)
    (unwind-protect
         (progn
           (transport-send-message (server-transport server) message)
           (with-lock-held ((pending-request-lock pending))
             (loop until (pending-request-resolved-p pending)
                   do (if timeout
                          (condition-wait (pending-request-condition-variable pending)
                                          (pending-request-lock pending)
                                          :timeout timeout)
                          (condition-wait (pending-request-condition-variable pending)
                                          (pending-request-lock pending)))))
           (let ((response (pending-request-message pending)))
             (if (json-get response "error")
                 (let ((error-object (json-get response "error")))
                   (raise-mcp-error
                    (json-get error-object "code")
                    (json-get error-object "message")
                    (json-get error-object "data")))
                 (json-get response "result"))))
      (remhash id (server-pending-outbound server)))))

(defun find-descriptor (table name kind)
  (or (gethash name table)
      (raise-mcp-error +json-rpc-invalid-params-error+
                       (format nil "Unknown ~A: ~A" kind name))))

(defun handle-ping-request (server context params)
  (declare (ignore server context params))
  (make-object))

(defun handle-tools-list-request (server context params)
  (declare (ignore context params))
  (let ((tools '()))
    (maphash #'(lambda (name descriptor)
                 (declare (ignore name))
                 (push (plist-descriptor->object descriptor :tool) tools))
             (server-tools server))
    (make-object "tools" (make-array-from-list (nreverse tools)))))

(defun handle-tools-call-request (server context params)
  (let* ((name (json-get params "name"))
         (descriptor (find-descriptor (server-tools server) name "tool"))
         (arguments (ensure-object (json-get params "arguments"))))
    (funcall (getf descriptor :handler) context arguments)))

(defun handle-resources-list-request (server context params)
  (declare (ignore context params))
  (let ((resources '()))
    (maphash #'(lambda (name descriptor)
                 (declare (ignore name))
                 (push (plist-descriptor->object descriptor :resource) resources))
             (server-resources server))
    (make-object "resources" (make-array-from-list (nreverse resources)))))

(defun find-resource-by-uri (server uri)
  (or (loop for descriptor being the hash-values of (server-resources server)
            when (and (getf descriptor :uri)
                      (string= (getf descriptor :uri) uri))
              do (return descriptor))
      (raise-mcp-error +json-rpc-invalid-params-error+
                       (format nil "Unknown resource uri: ~A" uri))))

(defun handle-resources-read-request (server context params)
  (let* ((uri (json-get params "uri"))
         (descriptor (find-resource-by-uri server uri)))
    (funcall (getf descriptor :handler) context params)))

(defun handle-prompts-list-request (server context params)
  (declare (ignore context params))
  (let ((prompts '()))
    (maphash #'(lambda (name descriptor)
                 (declare (ignore name))
                 (push (plist-descriptor->object descriptor :prompt) prompts))
             (server-prompts server))
    (make-object "prompts" (make-array-from-list (nreverse prompts)))))

(defun handle-prompts-get-request (server context params)
  (let* ((name (json-get params "name"))
         (descriptor (find-descriptor (server-prompts server) name "prompt"))
         (arguments (ensure-object (json-get params "arguments"))))
    (funcall (getf descriptor :handler) context arguments)))

(defvar *feature-request-handlers*
  '(("ping" . handle-ping-request)
    ("tools/list" . handle-tools-list-request)
    ("tools/call" . handle-tools-call-request)
    ("resources/list" . handle-resources-list-request)
    ("resources/read" . handle-resources-read-request)
    ("prompts/list" . handle-prompts-list-request)
    ("prompts/get" . handle-prompts-get-request)))

(defun perform-feature-request (server context method params)
  (if-let ((handler-name (cdr (assoc method *feature-request-handlers* :test #'string=))))
    (funcall (symbol-function handler-name) server context params)
    (raise-mcp-error +json-rpc-method-not-found-error+
                     (format nil "Unknown method: ~A" method))))

(defun handle-initialize-request (server context params)
  (declare (ignore context params))
  (setf (server-initialized-p server) nil)
  (make-object
   "protocolVersion" *default-protocol-version*
   "capabilities" (capabilities-object server)
   "serverInfo" (implementation-object server)))

(defun perform-request (server message)
  (let* ((method (json-get message "method"))
         (params (method-params message))
         (id (json-get message "id")))
    (cond
      ((string= method "initialize")
       (handle-initialize-request server nil params))
      ((and (not (server-initialized-p server))
            (not (string= method "initialize")))
       (raise-mcp-error +mcp-server-not-initialized-error+
                        "Server is not initialized"))
      (t
       (let ((token (make-instance '<cancellation-token>)))
         (setf (gethash id (server-active-requests server)) token)
         (unwind-protect
              (let ((context (make-instance '<request-context>
                                            :server server
                                            :id id
                                            :request message
                                            :params params
                                            :progress-token (progress-token-from-params params)
                                            :cancellation-token token)))
                (perform-feature-request server context method params))
           (remhash id (server-active-requests server))))))))

(defun complete-outbound-response (server message)
  (let ((pending (gethash (json-get message "id")
                          (server-pending-outbound server))))
    (when pending
      (resolve-pending-request pending message))))

(defun handle-request-message (server message)
  (let* ((id (json-get message "id"))
         (channel (let ((lparallel:*kernel* (ensure-kernel server)))
                    (lparallel:make-channel))))
    (emit server :request-received message)
    (let ((lparallel:*kernel* (server-kernel server)))
      (lparallel:submit-task channel
                             #'(lambda ()
                                 (handler-case
                                     (list :ok (perform-request server message))
                                   (mcp-error (condition)
                                     (list :mcp-error condition))
                                   (error (condition)
                                     (list :error condition))))))
    (make-thread
     #'(lambda ()
         (destructuring-bind (status payload)
             (lparallel:receive-result channel)
           (ecase status
             (:ok
              (send-response server id payload)
              (emit server :response-sent message payload))
             (:mcp-error
              (send-error server id
                          (mcp-error-code payload)
                          (mcp-error-message payload)
                          (mcp-error-data payload))
              (emit server :handler-failed message payload))
           (:error
            (send-error server id +json-rpc-internal-error+ "Internal error")
            (emit server :handler-failed message payload)))))
     :name "mcp-sdk.request-waiter")))

(defun handle-notification-message (server message)
  (let* ((method (json-get message "method"))
         (params (method-params message)))
    (emit server :notification-received message)
    (cond
      ((string= method "notifications/initialized")
       (setf (server-initialized-p server) t))
      ((string= method "notifications/cancelled")
       (let* ((request-id (json-get params "requestId"))
              (token (gethash request-id (server-active-requests server))))
         (when token
           (with-lock-held ((cancellation-token-lock token))
             (setf (cancelled-p token) t))
           (emit server :request-cancelled request-id))))
      (t nil))))

(defun handle-message (server message)
  (handler-case
      (cond
        ((request-message-p message)
         (handle-request-message server message))
        ((notification-message-p message)
         (handle-notification-message server message))
       ((response-message-p message)
        (complete-outbound-response server message))
       (t
         (send-error server nil +json-rpc-invalid-request-error+ "Invalid request")))
    (mcp-error (condition)
      (let ((id (json-get message "id")))
        (when id
          (send-error server id
                      (mcp-error-code condition)
                      (mcp-error-message condition)
                      (mcp-error-data condition)))))
    (error (condition)
      (declare (ignore condition))
      (let ((id (json-get message "id")))
        (when id
          (send-error server id +json-rpc-internal-error+ "Internal error")))))
  server)

(defun start-server (server)
  (ensure-kernel server)
  (setf (server-started-p server) t)
  (start-transport (server-transport server) server)
  (emit server :server-started server)
  server)

(defun stop-server (server)
  (when (server-started-p server)
    (stop-transport (server-transport server))
    (when (server-kernel server)
      (let ((lparallel:*kernel* (server-kernel server)))
        (lparallel:end-kernel :wait t))
      (setf (server-kernel server) nil))
    (setf (server-started-p server) nil)
    (emit server :server-stopped server))
  server)
