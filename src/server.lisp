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
   (task-id :initarg :task-id
            :initform nil
            :reader context-task-id)
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

(defclass <task> (<event-emitter>)
  ((id :initarg :id
       :reader task-id)
   (request-method :initarg :request-method
                   :reader task-request-method)
   (request-params :initarg :request-params
                   :reader task-request-params)
   (request-id :initarg :request-id
               :reader task-request-id)
   (status :initarg :status
           :accessor task-status)
   (status-message :initarg :status-message
                   :initform nil
                   :accessor task-status-message)
   (created-at :initarg :created-at
               :reader task-created-at)
   (last-updated-at :initarg :last-updated-at
                    :accessor task-last-updated-at)
   (created-ticks :initarg :created-ticks
                  :reader task-created-ticks)
   (last-updated-ticks :initarg :last-updated-ticks
                       :accessor task-last-updated-ticks)
   (ttl-ms :initarg :ttl-ms
           :reader task-ttl-ms)
   (poll-interval-ms :initarg :poll-interval-ms
                     :reader task-poll-interval-ms)
   (result-kind :initform nil
                :accessor task-result-kind)
   (result-payload :initform nil
                   :accessor task-result-payload)
   (lock :initform (make-lock "mcp-sdk.task.lock")
         :reader task-lock)
   (condition-variable :initform (make-condition-variable)
                       :reader task-condition-variable)
   (cancellation-token :initarg :cancellation-token
                       :reader task-cancellation-token)))

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
   (tasks :initform (make-hash-table :test #'equal)
          :reader server-tasks)
   (task-order :initform '()
               :accessor server-task-order)
   (client-capabilities :initform (make-object)
                        :accessor server-client-capabilities)
   (logging-level :initform nil
                  :accessor server-logging-level)
   (roots :initform (make-array 0)
          :accessor server-roots)
   (task-default-ttl-ms :initarg :task-default-ttl-ms
                        :initform 60000
                        :reader server-task-default-ttl-ms)
   (task-max-ttl-ms :initarg :task-max-ttl-ms
                    :initform 300000
                    :reader server-task-max-ttl-ms)
   (task-poll-interval-ms :initarg :task-poll-interval-ms
                          :initform 1000
                          :reader server-task-poll-interval-ms)
   (task-list-page-size :initarg :task-list-page-size
                        :initform 50
                        :reader server-task-list-page-size)
   (task-max-count :initarg :task-max-count
                   :initform 1000
                   :reader server-task-max-count)
   (next-request-id :initform 0
                    :accessor server-next-request-id)))

(defun server-on (server event listener)
  (on server event listener))

(defun server-off (server event listener)
  (off server event listener))

(defun make-server (&key name
                         version
                         transport
                         (worker-count 2)
                         (task-default-ttl-ms 60000)
                         (task-max-ttl-ms 300000)
                         (task-poll-interval-ms 1000)
                         (task-list-page-size 50)
                         (task-max-count 1000))
  (make-instance '<server>
                 :name name
                 :version version
                 :transport (or transport (make-stdio-transport))
                 :worker-count worker-count
                 :task-default-ttl-ms task-default-ttl-ms
                 :task-max-ttl-ms task-max-ttl-ms
                 :task-poll-interval-ms task-poll-interval-ms
                 :task-list-page-size task-list-page-size
                 :task-max-count task-max-count))

(defun ensure-kernel (server)
  (or (server-kernel server)
      (setf (server-kernel server)
            (lparallel:make-kernel (server-worker-count server)))))

(defun next-request-id (server)
  (with-lock-held ((server-state-lock server))
    (incf (server-next-request-id server))))

(defun now-ticks ()
  (get-internal-real-time))

(defun ticks->milliseconds (ticks)
  (floor (* ticks 1000) internal-time-units-per-second))

(defun elapsed-milliseconds (start-ticks)
  (ticks->milliseconds (- (now-ticks) start-ticks)))

(defun current-timestamp-string ()
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ"
            year month day hour minute second)))

(defun task-terminal-p (task)
  (member (task-status task)
          '(:completed :failed :cancelled)))

(defun task-status-name (status)
  (ecase status
    (:working "working")
    (:completed "completed")
    (:failed "failed")
    (:cancelled "cancelled")))

(defun related-task-meta (task-id)
  (make-object
   "io.modelcontextprotocol/related-task"
   (make-object "taskId" task-id)))

(defun attach-related-task-meta (object task-id)
  (when (object-p object)
    (let ((meta (ensure-object (json-get object "_meta"))))
      (setf (json-get meta "io.modelcontextprotocol/related-task")
            (make-object "taskId" task-id))
      (setf (json-get object "_meta") meta)))
  object)

(defun attach-related-task-meta-to-error-data (data task-id)
  (let ((payload (if (object-p data)
                     data
                     (make-object))))
    (attach-related-task-meta payload task-id)))

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
        (when (context-task-id context)
          (attach-related-task-meta payload (context-task-id context)))
        (emit (context-server context) :progress-reported context payload)
        (send-notification (context-server context)
                           "notifications/progress"
                           payload)))))

(defun current-roots (server)
  (with-lock-held ((server-state-lock server))
    (deep-copy-object (server-roots server))))

(defun normalize-task-support (task-support)
  (etypecase task-support
    (null nil)
    (keyword
     (ecase task-support
       (:forbidden :forbidden)
       (:optional :optional)
       (:required :required)))
    (string
     (cond
       ((string= task-support "forbidden")
        :forbidden)
       ((string= task-support "optional")
        :optional)
       ((string= task-support "required")
        :required)
       (t
        (raise-mcp-error +json-rpc-invalid-params-error+
                         (format nil "Invalid task support: ~A" task-support)))))))

(defun task-support-name (task-support)
  (ecase task-support
    (:forbidden "forbidden")
    (:optional "optional")
    (:required "required")))

(defun normalize-logging-level (level)
  (etypecase level
    (keyword
     (ecase level
       (:debug :debug)
       (:info :info)
       (:notice :notice)
       (:warning :warning)
       (:error :error)
       (:critical :critical)
       (:alert :alert)
       (:emergency :emergency)))
    (string
     (cond
       ((string= level "debug") :debug)
       ((string= level "info") :info)
       ((string= level "notice") :notice)
       ((string= level "warning") :warning)
       ((string= level "error") :error)
       ((string= level "critical") :critical)
       ((string= level "alert") :alert)
       ((string= level "emergency") :emergency)
       (t
        (raise-mcp-error +json-rpc-invalid-params-error+
                         (format nil "Invalid logging level: ~A" level)))))))

(defun logging-level-name (level)
  (ecase level
    (:debug "debug")
    (:info "info")
    (:notice "notice")
    (:warning "warning")
    (:error "error")
    (:critical "critical")
    (:alert "alert")
    (:emergency "emergency")))

(defun logging-level-priority (level)
  (ecase level
    (:debug 7)
    (:info 6)
    (:notice 5)
    (:warning 4)
    (:error 3)
    (:critical 2)
    (:alert 1)
    (:emergency 0)))

(defun logging-enabled-p (server level)
  (let ((minimum-level (server-logging-level server)))
    (and minimum-level
         (<= (logging-level-priority (normalize-logging-level level))
             (logging-level-priority minimum-level)))))

(defun log-message (server level data &key logger)
  (let ((normalized-level (normalize-logging-level level)))
    (when (logging-enabled-p server normalized-level)
      (let ((params (make-object
                     "level" (logging-level-name normalized-level)
                     "data" data)))
        (when logger
          (setf (gethash "logger" params) logger))
        (send-notification server "notifications/message" params)
        (emit server :log-message server params))))
  nil)

(defun register-descriptor (table name descriptor)
  (setf (gethash name table) descriptor)
  descriptor)

(defun register-tool (server name &key title description input-schema output-schema annotations handler task-support)
  (register-descriptor
   (server-tools server)
   name
   (list :name name
         :title title
         :description description
         :input-schema input-schema
         :output-schema output-schema
         :annotations annotations
         :handler handler
         :task-support (normalize-task-support task-support))))

(defun register-resource (server name &key uri uri-template description mime-type handler completion-handler)
  (register-descriptor
   (server-resources server)
   name
   (list :name name
         :uri uri
         :uri-template uri-template
         :description description
         :mime-type mime-type
         :handler handler
         :completion-handler completion-handler)))

(defun register-prompt (server name &key description arguments handler completion-handler)
  (register-descriptor
   (server-prompts server)
   name
   (list :name name
         :description description
         :arguments arguments
         :handler handler
         :completion-handler completion-handler)))

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
  (let ((object (make-object
                 "name" (getf descriptor :name))))
    (loop for (json-key . descriptor-key) in *descriptor-object-fields*
          do (when-let (value (getf descriptor descriptor-key))
               (setf (gethash json-key object) value)))
    (when-let (arguments (getf descriptor :arguments))
      (setf (gethash "arguments" object) (make-array-from-list arguments)))
    (when (and (eq kind :tool)
               (getf descriptor :task-support))
      (setf (gethash "execution" object)
            (make-object
             "taskSupport" (task-support-name (getf descriptor :task-support)))))
    object))

(defun capabilities-object (server)
  (let ((capabilities (make-object
                       "prompts" (make-object)
                       "resources" (make-object)
                       "tools" (make-object))))
    (setf (gethash "tasks" capabilities)
          (make-object
           "list" (make-object)
           "cancel" (make-object)
           "requests" (make-object
                       "tools" (make-object
                                "call" (make-object)))))
    (setf (gethash "logging" capabilities)
          (make-object))
    (when (or (loop for descriptor being the hash-values of (server-prompts server)
                    thereis (getf descriptor :completion-handler))
              (loop for descriptor being the hash-values of (server-resources server)
                    thereis (getf descriptor :completion-handler)))
      (setf (gethash "completions" capabilities)
            (make-object)))
    capabilities))

(defun implementation-object (server)
  (make-object
   "name" (server-name server)
   "version" (server-version server)))

(defun roots-capability-p (server)
  (json-get (server-client-capabilities server) "roots"))

(defun refresh-roots (server &key timeout)
  (unless (roots-capability-p server)
    (raise-mcp-error +json-rpc-invalid-request-error+
                     "Client does not advertise roots capability"))
  (let ((roots (or (json-get (send-request server "roots/list" :timeout timeout) "roots")
                   (make-array 0))))
    (with-lock-held ((server-state-lock server))
      (setf (server-roots server) roots))
    roots))

(defun refresh-roots-async (server &key timeout)
  (make-thread
   #'(lambda ()
       (handler-case
           (refresh-roots server :timeout timeout)
         (error ()
           nil)))
   :name "mcp-sdk.refresh-roots"))

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

(defun normalize-task-ttl-ms (server params)
  (let ((requested-ttl (json-get (ensure-object (json-get params "task")) "ttl")))
    (if (and (numberp requested-ttl)
             (plusp requested-ttl))
        (min (floor requested-ttl)
             (server-task-max-ttl-ms server))
        (server-task-default-ttl-ms server))))

(defun task-expired-p (task)
  (>= (elapsed-milliseconds (task-created-ticks task))
      (task-ttl-ms task)))

(defun task->object (task)
  (let ((object (make-object
                 "taskId" (task-id task)
                 "status" (task-status-name (task-status task))
                 "createdAt" (task-created-at task)
                 "lastUpdatedAt" (task-last-updated-at task)
                 "ttl" (task-ttl-ms task)
                 "pollInterval" (task-poll-interval-ms task))))
    (when (task-status-message task)
      (setf (gethash "statusMessage" object)
            (task-status-message task)))
    object))

(defun task-not-found (task-id)
  (raise-mcp-error +json-rpc-invalid-params-error+
                   (format nil "Unknown taskId: ~A" task-id)))

(defun cleanup-expired-tasks (server)
  (let ((expired-tasks '()))
    (with-lock-held ((server-state-lock server))
      (maphash #'(lambda (task-id task)
                   (declare (ignore task-id))
                   (when (task-expired-p task)
                     (push task expired-tasks)))
               (server-tasks server))
      (dolist (task expired-tasks)
        (remhash (task-id task) (server-tasks server))
        (deletef (server-task-order server)
                 (task-id task)
                 :test #'string=)))
    (dolist (task expired-tasks)
      (emit task :expired (task-id task)))))

(defun maybe-expire-task (server task)
  (let ((expired-p nil))
    (with-lock-held ((server-state-lock server))
      (when (and (gethash (task-id task) (server-tasks server))
                 (task-expired-p task))
        (remhash (task-id task) (server-tasks server))
        (deletef (server-task-order server)
                 (task-id task)
                 :test #'string=)
        (setf expired-p t)))
    (when expired-p
      (emit task :expired (task-id task)))))

(defun schedule-task-expiry (server task)
  (make-thread
   #'(lambda ()
       (sleep (/ (task-ttl-ms task) 1000.0))
       (maybe-expire-task server task))
   :name (format nil "mcp-sdk.task-expiry.~A" (task-id task))))

(defun find-task (server task-id)
  (cleanup-expired-tasks server)
  (with-lock-held ((server-state-lock server))
    (or (gethash task-id (server-tasks server))
        (task-not-found task-id))))

(defun update-task-status (task status &optional status-message)
  (with-lock-held ((task-lock task))
    (setf (task-status task) status
          (task-status-message task) status-message
          (task-last-updated-at task) (current-timestamp-string)
          (task-last-updated-ticks task) (now-ticks))
    (condition-notify (task-condition-variable task))))

(defun finalize-task-success (task result)
  (with-lock-held ((task-lock task))
    (unless (eq (task-status task) :cancelled)
      (setf (task-result-kind task) :success
            (task-result-payload task) result)
      (if (json-get result "isError")
          (setf (task-status task) :failed
                (task-status-message task) "Tool execution failed")
          (setf (task-status task) :completed
                (task-status-message task) nil))
      (setf (task-last-updated-at task) (current-timestamp-string)
            (task-last-updated-ticks task) (now-ticks)))
    (condition-notify (task-condition-variable task)))
  (unless (eq (task-status task) :cancelled)
    (emit task
          (if (eq (task-status task) :failed)
              :failed
              :completed)
          task
          result)))

(defun finalize-task-error (task condition)
  (with-lock-held ((task-lock task))
    (unless (eq (task-status task) :cancelled)
      (setf (task-result-kind task) :json-rpc-error
            (task-result-payload task)
            (make-object
             "code" (mcp-error-code condition)
             "message" (mcp-error-message condition)
             "data" (mcp-error-data condition))
            (task-status task) :failed
            (task-status-message task) (mcp-error-message condition)
            (task-last-updated-at task) (current-timestamp-string)
            (task-last-updated-ticks task) (now-ticks)))
    (condition-notify (task-condition-variable task)))
  (unless (eq (task-status task) :cancelled)
    (emit task
          :failed
          task
          (task-result-payload task))))

(defun finalize-task-internal-error (task condition)
  (declare (ignore condition))
  (with-lock-held ((task-lock task))
    (unless (eq (task-status task) :cancelled)
      (setf (task-result-kind task) :json-rpc-error
            (task-result-payload task)
            (make-object
             "code" +json-rpc-internal-error+
             "message" "Internal error")
            (task-status task) :failed
            (task-status-message task) "Internal error"
            (task-last-updated-at task) (current-timestamp-string)
            (task-last-updated-ticks task) (now-ticks)))
    (condition-notify (task-condition-variable task)))
  (unless (eq (task-status task) :cancelled)
    (emit task
          :failed
          task
          (task-result-payload task))))

(defun make-task (server method params request-id cancellation-token)
  (cleanup-expired-tasks server)
  (with-lock-held ((server-state-lock server))
    (when (>= (hash-table-count (server-tasks server))
              (server-task-max-count server))
      (raise-mcp-error +json-rpc-internal-error+
                       "Task limit exceeded"))
    (let* ((task-id (frugal-uuid:make-v7-string))
           (timestamp (current-timestamp-string))
           (ticks (now-ticks))
           (task (make-instance '<task>
                                :id task-id
                                :request-method method
                                :request-params (deep-copy-object params)
                                :request-id request-id
                                :status :working
                                :status-message "The operation is now in progress."
                                :created-at timestamp
                                :last-updated-at timestamp
                                :created-ticks ticks
                                :last-updated-ticks ticks
                                :ttl-ms (normalize-task-ttl-ms server params)
                                :poll-interval-ms (server-task-poll-interval-ms server)
                                :cancellation-token cancellation-token)))
      (on task :created
          #'(lambda (emitted-task)
              (emit server :task-created emitted-task)))
      (on task :completed
          #'(lambda (emitted-task result)
              (emit server :task-completed emitted-task result)))
      (on task :failed
          #'(lambda (emitted-task payload)
              (emit server :task-failed emitted-task payload)))
      (on task :cancelled
          #'(lambda (emitted-task)
              (emit server :task-cancelled emitted-task)))
      (on task :expired
          #'(lambda (task-id)
              (emit server :task-expired task-id)))
      (setf (gethash task-id (server-tasks server)) task)
      (push task-id (server-task-order server))
      (emit task :created task)
      (schedule-task-expiry server task)
      task)))

(defun wait-for-task-completion (task)
  (with-lock-held ((task-lock task))
    (loop until (or (task-terminal-p task)
                    (task-expired-p task))
          do (condition-wait (task-condition-variable task)
                             (task-lock task)
                             :timeout 0.05))))

(defun task-result-response (task)
  (ecase (task-result-kind task)
    (:success
     (attach-related-task-meta
      (deep-copy-object (task-result-payload task))
      (task-id task)))
    (:json-rpc-error
     (let ((payload (task-result-payload task)))
       (raise-mcp-error
        (json-get payload "code")
        (json-get payload "message")
        (attach-related-task-meta-to-error-data
         (json-get payload "data")
         (task-id task)))))))

(defun parse-list-cursor (params)
  (let ((cursor (json-get params "cursor")))
    (cond
      ((null cursor)
       0)
      ((and (stringp cursor)
            (every #'digit-char-p cursor))
       (parse-integer cursor))
      (t
       (raise-mcp-error +json-rpc-invalid-params-error+
                        "Invalid cursor")))))

(defun find-descriptor (table name kind)
  (or (gethash name table)
      (raise-mcp-error +json-rpc-invalid-params-error+
                       (format nil "Unknown ~A: ~A" kind name))))

(defun handle-ping-request (server context params)
  (declare (ignore server context params))
  (make-object))

(defun handle-logging-set-level-request (server context params)
  (declare (ignore context))
  (setf (server-logging-level server)
        (normalize-logging-level (json-get params "level")))
  (make-object))

(defun handle-tools-list-request (server context params)
  (declare (ignore context params))
  (let ((tools '()))
    (maphash #'(lambda (name descriptor)
                 (declare (ignore name))
                 (push (plist-descriptor->object descriptor :tool) tools))
             (server-tools server))
    (make-object "tools" (make-array-from-list (nreverse tools)))))

(defun task-request-p (params)
  (json-get params "task"))

(defun task-supported-p (descriptor)
  (member (getf descriptor :task-support)
          '(:optional :required)))

(defun task-required-p (descriptor)
  (eq (getf descriptor :task-support) :required))

(defun enforce-tool-task-mode (descriptor params)
  (cond
    ((and (task-required-p descriptor)
          (not (task-request-p params)))
     (raise-mcp-error +json-rpc-method-not-found-error+
                      "This tool requires task execution"))
    ((and (task-request-p params)
          (not (task-supported-p descriptor)))
     (raise-mcp-error +json-rpc-method-not-found-error+
                      "This tool does not support task execution"))))

(defun execute-task-tool-call (server task descriptor message params)
  (let ((arguments (ensure-object (json-get params "arguments"))))
    (let ((lparallel:*kernel* (server-kernel server)))
      (lparallel:submit-task
       (lparallel:make-channel)
       #'(lambda ()
           (let ((context (make-instance '<request-context>
                                         :server server
                                         :id (task-request-id task)
                                         :request message
                                         :params params
                                         :progress-token (progress-token-from-params params)
                                         :task-id (task-id task)
                                         :cancellation-token (task-cancellation-token task))))
             (handler-case
                 (finalize-task-success
                  task
                  (funcall (getf descriptor :handler) context arguments))
               (mcp-error (condition)
                 (finalize-task-error task condition))
               (error (condition)
                 (finalize-task-internal-error task condition)))))))))

(defun create-task-result (task)
  (let ((result (make-object
                 "task" (task->object task))))
    (attach-related-task-meta result (task-id task))
    result))

(defun handle-task-augmented-tools-call-request (server context descriptor params)
  (let* ((request (context-request context))
         (task (make-task server
                          "tools/call"
                          params
                          (context-id context)
                          (context-cancellation-token context))))
    (execute-task-tool-call server task descriptor request params)
    (create-task-result task)))

(defun handle-tools-call-request (server context params)
  (let* ((name (json-get params "name"))
         (descriptor (find-descriptor (server-tools server) name "tool"))
         (arguments (ensure-object (json-get params "arguments"))))
    (enforce-tool-task-mode descriptor params)
    (if (task-request-p params)
        (handle-task-augmented-tools-call-request server context descriptor params)
        (funcall (getf descriptor :handler) context arguments))))

(defun handle-resources-list-request (server context params)
  (declare (ignore context params))
  (let ((resources '()))
    (maphash #'(lambda (name descriptor)
                 (declare (ignore name))
                 (when (getf descriptor :uri)
                   (push (plist-descriptor->object descriptor :resource) resources)))
             (server-resources server))
    (make-object "resources" (make-array-from-list (nreverse resources)))))

(defun handle-resource-templates-list-request (server context params)
  (declare (ignore context params))
  (let ((resource-templates '()))
    (maphash #'(lambda (name descriptor)
                 (declare (ignore name))
                 (when (getf descriptor :uri-template)
                   (push (plist-descriptor->object descriptor :resource) resource-templates)))
             (server-resources server))
    (make-object
     "resourceTemplates"
     (make-array-from-list (nreverse resource-templates)))))

(defun uri-template-matches-p (uri-template uri)
  (labels ((consume-placeholder (position)
             (or (position #\} uri-template :start position)
                 (error "Invalid URI template: ~A" uri-template)))
           (matches-from (template-index uri-index)
             (cond
               ((= template-index (length uri-template))
                (= uri-index (length uri)))
               ((char= (char uri-template template-index) #\{)
                (let* ((placeholder-end (consume-placeholder (1+ template-index)))
                       (next-template-index (1+ placeholder-end)))
                  (if (= next-template-index (length uri-template))
                      t
                      (loop for next-uri-index from uri-index below (length uri)
                            thereis (and (char= (char uri next-uri-index)
                                                (char uri-template next-template-index))
                                         (matches-from next-template-index next-uri-index))))))
               ((and (< uri-index (length uri))
                     (char= (char uri-template template-index)
                            (char uri uri-index)))
                (matches-from (1+ template-index) (1+ uri-index)))
               (t nil))))
    (matches-from 0 0)))

(defun find-resource-by-uri (server uri)
  (or (loop for descriptor being the hash-values of (server-resources server)
            when (and (getf descriptor :uri)
                      (string= (getf descriptor :uri) uri))
              do (return descriptor))
      (loop for descriptor being the hash-values of (server-resources server)
            when (and (getf descriptor :uri-template)
                      (uri-template-matches-p (getf descriptor :uri-template) uri))
              do (return descriptor))
      (raise-mcp-error +json-rpc-invalid-params-error+
                       (format nil "Unknown resource uri: ~A" uri))))

(defun find-resource-by-template-uri (server uri)
  (or (loop for descriptor being the hash-values of (server-resources server)
            when (and (getf descriptor :uri-template)
                      (string= (getf descriptor :uri-template) uri))
              do (return descriptor))
      (raise-mcp-error +json-rpc-invalid-params-error+
                       (format nil "Unknown resource template uri: ~A" uri))))

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

(defun handle-tasks-get-request (server context params)
  (declare (ignore context))
  (task->object
   (find-task server (json-get params "taskId"))))

(defun handle-tasks-result-request (server context params)
  (declare (ignore context))
  (let ((task (find-task server (json-get params "taskId"))))
    (unless (task-terminal-p task)
      (wait-for-task-completion task)
      (when (task-expired-p task)
        (cleanup-expired-tasks server)
        (task-not-found (task-id task))))
    (task-result-response task)))

(defun handle-tasks-list-request (server context params)
  (declare (ignore context))
  (cleanup-expired-tasks server)
  (let* ((offset (parse-list-cursor params))
         (task-ids (with-lock-held ((server-state-lock server))
                     (copy-list (server-task-order server))))
         (page-size (server-task-list-page-size server))
         (page (subseq task-ids
                       (min offset (length task-ids))
                       (min (length task-ids)
                            (+ offset page-size))))
         (tasks (mapcar #'(lambda (task-id)
                            (task->object (find-task server task-id)))
                        page))
         (next-offset (+ offset (length page))))
    (let ((result (make-object
                   "tasks" (make-array-from-list tasks))))
      (when (< next-offset (length task-ids))
        (setf (gethash "nextCursor" result)
              (princ-to-string next-offset)))
      result)))

(defun handle-tasks-cancel-request (server context params)
  (declare (ignore context))
  (let ((task (find-task server (json-get params "taskId"))))
    (when (task-terminal-p task)
      (raise-mcp-error +json-rpc-invalid-params-error+
                       "Cannot cancel a terminal task"))
    (with-lock-held ((cancellation-token-lock (task-cancellation-token task)))
      (setf (cancelled-p (task-cancellation-token task)) t))
    (setf (task-result-kind task) :json-rpc-error
          (task-result-payload task)
          (make-object
           "code" +json-rpc-invalid-params-error+
           "message" "Task was cancelled"))
    (update-task-status task :cancelled "The task was cancelled by request.")
    (emit task :cancelled task)
    (task->object task)))

(defun ensure-completion-values-vector (values)
  (cond
    ((vectorp values)
     values)
    ((listp values)
     (make-array-from-list values))
    (t
     (raise-mcp-error +json-rpc-invalid-params-error+
                      "Completion values must be a list or vector"))))

(defun normalize-completion-result (result)
  (cond
    ((and (object-p result)
          (json-get result "completion"))
     result)
    ((object-p result)
     (let* ((values (ensure-completion-values-vector
                     (or (json-get result "values")
                         '())))
            (completion (make-object
                         "values" values
                         "total" (or (json-get result "total")
                                     (length values))
                         "hasMore" (or (json-get result "hasMore")
                                       :false))))
       (make-object "completion" completion)))
    ((or (listp result)
         (vectorp result))
     (let ((values (ensure-completion-values-vector result)))
       (make-object
        "completion" (make-object
                      "values" values
                      "total" (length values)
                      "hasMore" :false))))
    (t
     (raise-mcp-error +json-rpc-invalid-params-error+
                      "Completion handler must return an object, list, or vector"))))

(defun find-completion-descriptor (server ref)
  (let ((ref-type (json-get ref "type")))
    (cond
      ((string= ref-type "ref/prompt")
       (find-descriptor (server-prompts server)
                        (json-get ref "name")
                        "prompt"))
      ((string= ref-type "ref/resource")
       (find-resource-by-template-uri server (json-get ref "uri")))
      (t
       (raise-mcp-error +json-rpc-invalid-params-error+
                        (format nil "Unknown completion ref type: ~A" ref-type))))))

(defun handle-completion-complete-request (server context params)
  (let* ((ref (ensure-object (json-get params "ref")))
         (argument (ensure-object (json-get params "argument")))
         (completion-context (ensure-object (json-get params "context")))
         (context-arguments (ensure-object (json-get completion-context "arguments")))
         (descriptor (find-completion-descriptor server ref))
         (handler (getf descriptor :completion-handler)))
    (unless handler
      (raise-mcp-error +json-rpc-invalid-params-error+
                       "Completion is not supported for the requested reference"))
    (normalize-completion-result
     (funcall handler context argument context-arguments))))

(defvar *feature-request-handlers*
  '(("ping" . handle-ping-request)
    ("logging/setLevel" . handle-logging-set-level-request)
    ("tools/list" . handle-tools-list-request)
    ("tools/call" . handle-tools-call-request)
    ("tasks/get" . handle-tasks-get-request)
    ("tasks/result" . handle-tasks-result-request)
    ("tasks/list" . handle-tasks-list-request)
    ("tasks/cancel" . handle-tasks-cancel-request)
    ("completion/complete" . handle-completion-complete-request)
    ("resources/list" . handle-resources-list-request)
    ("resources/templates/list" . handle-resource-templates-list-request)
    ("resources/read" . handle-resources-read-request)
    ("prompts/list" . handle-prompts-list-request)
    ("prompts/get" . handle-prompts-get-request)))

(defun perform-feature-request (server context method params)
  (if-let ((handler-name (cdr (assoc method *feature-request-handlers* :test #'string=))))
    (funcall (symbol-function handler-name) server context params)
    (raise-mcp-error +json-rpc-method-not-found-error+
                     (format nil "Unknown method: ~A" method))))

(defun handle-initialize-request (server context params)
  (declare (ignore context))
  (setf (server-initialized-p server) nil)
  (setf (server-client-capabilities server)
        (ensure-object (json-get params "capabilities")))
  (with-lock-held ((server-state-lock server))
    (setf (server-roots server) (make-array 0)))
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

(defun inline-request-method-p (method)
  (member method
          '("tasks/get"
            "tasks/result"
            "tasks/list"
            "tasks/cancel")
          :test #'string=))

(defun execute-request (server message)
  (handler-case
      (list :ok (perform-request server message))
    (mcp-error (condition)
      (list :mcp-error condition))
    (error (condition)
      (list :error condition))))

(defun process-request-result (server message status payload)
  (let ((id (json-get message "id")))
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

(defun handle-request-message (server message)
  (let* ((id (json-get message "id"))
         (method (json-get message "method")))
    (emit server :request-received message)
    (if (inline-request-method-p method)
        (make-thread
         #'(lambda ()
             (destructuring-bind (status payload)
                 (execute-request server message)
               (process-request-result server message status payload)))
         :name "mcp-sdk.inline-request")
        (let ((channel (let ((lparallel:*kernel* (ensure-kernel server)))
                         (lparallel:make-channel))))
          (let ((lparallel:*kernel* (server-kernel server)))
            (lparallel:submit-task channel
                                   #'(lambda ()
                                       (execute-request server message))))
          (make-thread
           #'(lambda ()
               (destructuring-bind (status payload)
                   (lparallel:receive-result channel)
                 (process-request-result server message status payload)))
           :name "mcp-sdk.request-waiter")))))

(defun handle-notification-message (server message)
  (let* ((method (json-get message "method"))
         (params (method-params message)))
    (emit server :notification-received message)
    (cond
      ((string= method "notifications/initialized")
       (setf (server-initialized-p server) t)
       (when (roots-capability-p server)
         (refresh-roots-async server)))
      ((string= method "notifications/cancelled")
       (let* ((request-id (json-get params "requestId"))
              (token (gethash request-id (server-active-requests server))))
         (when token
           (with-lock-held ((cancellation-token-lock token))
             (setf (cancelled-p token) t))
           (emit server :request-cancelled request-id))))
      ((string= method "notifications/roots/list_changed")
       (refresh-roots-async server)
       (emit server :roots-list-changed))
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
