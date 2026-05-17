(in-package #:mcp-sdk/tests)

(deftest initialize-and-core-methods
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

    (handle-message session (make-request 1 "initialize"
                                          (mcp-sdk::make-object
                                           "protocolVersion" *default-protocol-version*)))
    (ok (wait-for #'(lambda ()
                      (let ((message (last-message session)))
                        (and message
                             (response-result message))))))
    (ok (equal (json-get (response-result (last-message session)) "protocolVersion")
               *default-protocol-version*))

    (handle-message session (make-notification "notifications/initialized"))

    (handle-message session (make-request 2 "tools/list"))
    (ok (wait-for #'(lambda ()
                      (equal 2 (json-get (last-message session) "id")))))
    (ok (= (length (json-get (response-result (last-message session)) "tools")) 1))

    (handle-message session
                    (make-request 3 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "echo"
                                   "arguments" (mcp-sdk::make-object
                                                "message" "hello"))))
    (ok (wait-for #'(lambda ()
                      (equal 3 (json-get (last-message session) "id")))))
    (ok (equal (json-get (aref (json-get (response-result (last-message session)) "content") 0) "text")
               "hello"))

    (handle-message session (make-request 4 "resources/list"))
    (ok (wait-for #'(lambda ()
                      (equal 4 (json-get (last-message session) "id")))))
    (ok (= (length (json-get (response-result (last-message session)) "resources")) 1))

    (handle-message session
                    (make-request 5 "resources/read"
                                  (mcp-sdk::make-object "uri" "resource:greeting")))
    (ok (wait-for #'(lambda ()
                      (equal 5 (json-get (last-message session) "id")))))
    (ok (equal (json-get (aref (json-get (response-result (last-message session)) "contents") 0) "text")
               "hello"))

    (handle-message session (make-request 6 "prompts/list"))
    (ok (wait-for #'(lambda ()
                      (equal 6 (json-get (last-message session) "id")))))
    (ok (= (length (json-get (response-result (last-message session)) "prompts")) 1))

    (handle-message session
                    (make-request 7 "prompts/get"
                                  (mcp-sdk::make-object
                                   "name" "greeter"
                                   "arguments" (mcp-sdk::make-object
                                                "subject" "world"))))
    (ok (wait-for #'(lambda ()
                      (equal 7 (json-get (last-message session) "id")))))
    (ok (equal (json-get (json-get (aref (json-get (response-result (last-message session)) "messages") 0) "content")
                         "text")
               "Hello, world"))))

(deftest reject-feature-before-initialize
  (let ((session (make-test-session)))
    (handle-message session (make-request 10 "tools/list"))
    (ok (wait-for #'(lambda ()
                      (response-error (last-message session)))))
    (ok (= (json-get (response-error (last-message session)) "code")
           mcp-sdk:+mcp-server-not-initialized-error+))))

(deftest exported-error-codes
  (ok (= mcp-sdk:+json-rpc-invalid-request-error+ -32600))
  (ok (= mcp-sdk:+json-rpc-method-not-found-error+ -32601))
  (ok (= mcp-sdk:+json-rpc-invalid-params-error+ -32602))
  (ok (= mcp-sdk:+json-rpc-internal-error+ -32603))
  (ok (= mcp-sdk:+mcp-server-not-initialized-error+ -32002)))

(deftest make-session-creates-independent-sessions
  (let* ((server-1 (make-test-server))
         (server-2 (make-test-server))
         (session-1 (mcp-sdk:make-session server-1))
         (session-2 (mcp-sdk:make-session server-2)))
    (ok (typep session-1 'mcp-sdk::<session>))
    (ok (not (eq session-1 session-2)))
    (ok (eq (mcp-sdk::session-definition session-1)
            (mcp-sdk::server-definition server-1)))
    (ok (typep (mcp-sdk::server-default-task-settings server-1)
               'mcp-sdk::task-settings))
    (ok (typep (mcp-sdk::session-task-settings session-1)
               'mcp-sdk::task-settings))
    (ok (not (eq (mcp-sdk::server-default-task-settings server-1)
                 (mcp-sdk::session-task-settings session-1))))
    (ok (not (eq (mcp-sdk::session-roots session-1)
                 (mcp-sdk::session-roots session-2))))))

(deftest progress-cancel-and-events
  (let* ((server (make-test-server))
        (session (mcp-sdk:make-session server))
        (events '()))
    (register-tool server "count"
                   :handler #'(lambda (session context arguments)
                                (declare (ignore session arguments))
                                (context-report-progress context 1 2 "started")
                                (loop repeat 200
                                      until (context-cancelled-p context)
                                      do (sleep 0.01))
                                (mcp-sdk::make-object "cancelled" (context-cancelled-p context))))
    (session-on session :request-cancelled
                #'(lambda (request-id)
                    (push request-id events)))

    (handle-message session (make-request 20 "initialize"))
    (wait-for #'(lambda ()
                  (equal 20 (json-get (last-message session) "id"))))
    (handle-message session (make-notification "notifications/initialized"))

    (handle-message session
                    (make-request 21 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "count"
                                   "_meta" (mcp-sdk::make-object
                                            "progressToken" "token-1"))))
    (ok (wait-for #'(lambda ()
                      (find-message-by-method session "notifications/progress"))))
    (handle-message session
                    (make-notification "notifications/cancelled"
                                       (mcp-sdk::make-object "requestId" 21)))
    (ok (wait-for #'(lambda ()
                      (equal 21 (car events)))))
    (ok (wait-for #'(lambda ()
                      (let ((message (last-message session)))
                        (and (equal 21 (json-get message "id"))
                             (response-result message))))))
    (ok (json-get (response-result (last-message session)) "cancelled"))))

(deftest logging-support
  (let ((session (make-test-session)))
    (handle-message session
                    (make-request 22 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" *default-protocol-version*)))
    (ok (wait-for #'(lambda ()
                      (equal 22 (json-get (last-message session) "id")))))
    (ok (json-get (json-get (response-result (last-message session)) "capabilities")
                  "logging"))
    (handle-message session (make-notification "notifications/initialized"))

    (mcp-sdk:log-message session "info" "before setLevel" :logger "test")
    (ok (null (find-message-by-method session "notifications/message")))

    (handle-message session
                    (make-request 23 "logging/setLevel"
                                  (mcp-sdk::make-object
                                   "level" "warning")))
    (ok (wait-for #'(lambda ()
                      (equal 23 (json-get (last-message session) "id")))))
    (ok (zerop (hash-table-count (response-result (last-message session)))))

    (mcp-sdk:log-message session :info "ignored" :logger "test")
    (ok (null (find-message-by-method session "notifications/message")))

    (mcp-sdk:log-message session "error"
                         (mcp-sdk::make-object "message" "emitted")
                         :logger "test")
    (ok (wait-for #'(lambda ()
                      (let ((message (find-message-by-method session "notifications/message")))
                        (and message
                             (equal "error" (json-get message '("params" "level")))
                             (equal "test" (json-get message '("params" "logger")))
                             (equal "emitted" (json-get message '("params" "data" "message"))))))))

    (handle-message session
                    (make-request 24 "logging/setLevel"
                                  (mcp-sdk::make-object
                                   "level" "bogus")))
    (ok (wait-for #'(lambda ()
                      (equal 24 (json-get (last-message session) "id")))))
    (ok (= (json-get (json-get (last-message session) "error") "code")
           +json-rpc-invalid-params-error+))))

(deftest outbound-request-roundtrip
  (let ((session (make-test-session)))
    (let ((thread (make-thread
                   #'(lambda ()
                       (send-request session "roots/list")))))
      (ok (wait-for #'(lambda ()
                        (equal "roots/list"
                               (json-get (first (all-messages session)) "method")))))
      (handle-message session
                      (mcp-sdk::make-object
                       "jsonrpc" "2.0"
                       "id" 1
                       "result" (mcp-sdk::make-object "roots" (make-array 0))))
      (join-thread thread)
      (ok t))))

(deftest roots-storage-is-not-shared
  (let ((session-1 (make-test-session))
        (session-2 (make-test-session)))
    (ok (not (eq (mcp-sdk::session-roots session-1)
                 (mcp-sdk::session-roots session-2))))))

(deftest resource-templates
  (let* ((server (make-test-server))
         (session (mcp-sdk:make-session server)))
    (register-resource server "note-template"
                       :uri-template "note://{id}"
                       :description "Templated note resource"
                       :mime-type "text/plain"
                       :handler #'(lambda (session context arguments)
                                    (declare (ignore session context))
                                    (mcp-sdk::make-object
                                     "contents"
                                     (vector (mcp-sdk::make-object
                                              "uri" (json-get arguments "uri")
                                              "mimeType" "text/plain"
                                              "text" "templated note")))))

    (handle-message session
                    (make-request 30 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" *default-protocol-version*)))
    (ok (wait-for #'(lambda ()
                      (equal 30 (json-get (last-message session) "id")))))
    (handle-message session (make-notification "notifications/initialized"))

    (handle-message session (make-request 31 "resources/templates/list"))
    (ok (wait-for #'(lambda ()
                      (equal 31 (json-get (last-message session) "id")))))
    (ok (= (length (json-get (response-result (last-message session)) "resourceTemplates")) 1))
    (ok (equal (json-get (aref (json-get (response-result (last-message session)) "resourceTemplates") 0)
                         "uriTemplate")
               "note://{id}"))

    (handle-message session
                    (make-request 32 "resources/read"
                                  (mcp-sdk::make-object "uri" "note://42")))
    (ok (wait-for #'(lambda ()
                      (equal 32 (json-get (last-message session) "id")))))
    (ok (equal (json-get (aref (json-get (response-result (last-message session)) "contents") 0)
                         "text")
               "templated note"))))

(deftest roots-support
  (let* ((server (make-test-server))
         (session (mcp-sdk:make-session server))
        (root-events '()))
    (register-tool server "show-roots"
                   :input-schema (mcp-sdk::make-object "type" "object")
                   :handler #'(lambda (session context arguments)
                                (declare (ignore context arguments))
                                (let ((roots (mcp-sdk:current-roots session)))
                                  (mcp-sdk::make-object
                                   "count" (length roots)))))
    (session-on session :roots-list-changed
                #'(lambda ()
                    (push :changed root-events)))

    (handle-message session
                    (make-request 33 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" *default-protocol-version*
                                   "capabilities" (mcp-sdk::make-object
                                                   "roots" (mcp-sdk::make-object
                                                            "listChanged" t)))))
    (ok (wait-for #'(lambda ()
                      (equal 33 (json-get (last-message session) "id")))))
    (handle-message session (make-notification "notifications/initialized"))
    (ok (wait-for #'(lambda ()
                      (find-message-by-method session "roots/list"))))
    (handle-message session
                    (mcp-sdk::make-object
                     "jsonrpc" "2.0"
                     "id" 1
                     "result" (mcp-sdk::make-object
                               "roots"
                               (vector (mcp-sdk::make-object
                                        "uri" "file:///workspace/project"
                                        "name" "Project")))))
    (ok (wait-for #'(lambda ()
                      (= (length (mcp-sdk:current-roots session)) 1))))

    (handle-message session
                    (make-request 34 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "show-roots"
                                   "arguments" (mcp-sdk::make-object))))
    (ok (wait-for #'(lambda ()
                      (equal 34 (json-get (last-message session) "id")))))
    (ok (= (json-get (response-result (last-message session)) "count") 1))

    (handle-message session (make-notification "notifications/roots/list_changed"))
    (ok (wait-for #'(lambda ()
                      root-events)))
    (ok (wait-for #'(lambda ()
                      (let ((message (car (last (remove-if-not
                                                 #'(lambda (entry)
                                                     (equal "roots/list"
                                                            (json-get entry "method")))
                                                 (all-messages session))))))
                        (equal 2 (json-get message "id"))))))
    (handle-message session
                    (mcp-sdk::make-object
                     "jsonrpc" "2.0"
                     "id" 2
                     "result" (mcp-sdk::make-object
                               "roots"
                               (vector (mcp-sdk::make-object
                                        "uri" "file:///workspace/updated"
                                        "name" "Updated")))))
    (ok (wait-for #'(lambda ()
                      (equal "file:///workspace/updated"
                             (mcp-sdk:json-get (mcp-sdk:current-roots session)
                                               '(0 "uri"))))))))

(deftest completion-support
  (let* ((server (make-test-server))
         (session (mcp-sdk:make-session server)))
    (register-prompt server "greeter"
                     :arguments (list (mcp-sdk::make-object
                                       "name" "subject"
                                       "required" t))
                     :completion-handler
                     #'(lambda (session context argument context-arguments)
                         (declare (ignore session context))
                         (ok (equal (json-get argument "name") "subject"))
                         (ok (equal (json-get context-arguments "tone") "casual"))
                         (mcp-sdk::make-object
                          "values" (vector "world" "writer")
                          "total" 2
                          "hasMore" :false)))
    (register-resource server "note-template"
                       :uri-template "note://{id}"
                       :completion-handler
                       #'(lambda (session context argument context-arguments)
                            (declare (ignore session context context-arguments))
                            (ok (equal (json-get argument "value") "4"))
                            '("42")))

    (handle-message session
                    (make-request 50 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" *default-protocol-version*)))
    (ok (wait-for #'(lambda ()
                      (equal 50 (json-get (last-message session) "id")))))
    (ok (json-get (json-get (response-result (last-message session)) "capabilities")
                  "completions"))
    (handle-message session (make-notification "notifications/initialized"))

    (handle-message session
                    (make-request 51 "completion/complete"
                                  (mcp-sdk::make-object
                                   "ref" (mcp-sdk::make-object
                                          "type" "ref/prompt"
                                          "name" "greeter")
                                   "argument" (mcp-sdk::make-object
                                               "name" "subject"
                                               "value" "w")
                                   "context" (mcp-sdk::make-object
                                              "arguments" (mcp-sdk::make-object
                                                           "tone" "casual")))))
    (ok (wait-for #'(lambda ()
                      (equal 51 (json-get (last-message session) "id")))))
    (ok (equal (json-get (json-get (response-result (last-message session)) "completion")
                         "total")
               2))
    (ok (equal (aref (json-get (json-get (response-result (last-message session))
                                         "completion")
                                "values")
                     0)
               "world"))

    (handle-message session
                    (make-request 52 "completion/complete"
                                  (mcp-sdk::make-object
                                   "ref" (mcp-sdk::make-object
                                          "type" "ref/resource"
                                          "uri" "note://{id}")
                                   "argument" (mcp-sdk::make-object
                                               "name" "id"
                                               "value" "4"))))
    (ok (wait-for #'(lambda ()
                      (equal 52 (json-get (last-message session) "id")))))
    (ok (equal (aref (json-get (json-get (response-result (last-message session))
                                         "completion")
                                "values")
                     0)
               "42"))))

(deftest tasks-support
  (let* ((server (make-test-server
                  :task-default-ttl-ms 100
                  :task-max-ttl-ms 1000
                  :task-poll-interval-ms 10
                  :task-list-page-size 1))
         (session (mcp-sdk:make-session server))
        (task-events '()))
    (session-on session :task-created
                #'(lambda (task)
                    (push (list :created (mcp-sdk::task-id task)) task-events)))
    (session-on session :task-completed
                #'(lambda (task result)
                    (declare (ignore result))
                    (push (list :completed (mcp-sdk::task-id task)) task-events)))
    (session-on session :task-failed
                #'(lambda (task payload)
                    (declare (ignore payload))
                    (push (list :failed (mcp-sdk::task-id task)) task-events)))
    (register-tool server "slow"
                   :task-support "optional"
                   :handler #'(lambda (session context arguments)
                                (declare (ignore session arguments))
                                (context-report-progress context 1 2 "started")
                                (sleep 0.05)
                                (context-report-progress context 2 2 "done")
                                (mcp-sdk::make-object
                                 "content"
                                 (vector (mcp-sdk::make-object
                                          "type" "text"
                                          "text" "slow done")))))
    (register-tool server "failing-tool"
                   :task-support "required"
                   :handler #'(lambda (session context arguments)
                                (declare (ignore session context arguments))
                                (mcp-sdk::make-object
                                 "content"
                                 (vector (mcp-sdk::make-object
                                          "type" "text"
                                          "text" "failed"))
                                 "isError" t)))
    (register-tool server "sync-only"
                   :handler #'(lambda (session context arguments)
                                (declare (ignore session context arguments))
                                (mcp-sdk::make-object
                                 "content"
                                 (vector (mcp-sdk::make-object
                                          "type" "text"
                                          "text" "sync only")))))

    (handle-message session
                    (make-request 60 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" *default-protocol-version*)))
    (ok (wait-for #'(lambda ()
                      (equal 60 (json-get (last-message session) "id")))))
    (ok (json-get (json-get (json-get (response-result (last-message session))
                                      "capabilities")
                            '("tasks" "requests" "tools"))
                  "call"))
    (handle-message session (make-notification "notifications/initialized"))

    (handle-message session (make-request 61 "tools/list"))
    (ok (wait-for #'(lambda ()
                      (equal 61 (json-get (last-message session) "id")))))
    (let* ((tools (coerce (json-get (response-result (last-message session)) "tools")
                          'list))
           (slow-tool (find "slow" tools :test #'string=
                            :key #'(lambda (entry)
                                     (json-get entry "name"))))
           (failing-tool (find "failing-tool" tools :test #'string=
                               :key #'(lambda (entry)
                                        (json-get entry "name")))))
      (ok (eq (getf (gethash "slow" (mcp-sdk::server-tools server))
                    :task-support)
              :optional))
      (ok (eq (getf (gethash "failing-tool" (mcp-sdk::server-tools server))
                    :task-support)
              :required))
      (ok (equal (json-get slow-tool '("execution" "taskSupport"))
                 "optional"))
      (ok (equal (json-get failing-tool '("execution" "taskSupport"))
                 "required")))

    (handle-message session
                    (make-request 62 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "sync-only"
                                   "arguments" (mcp-sdk::make-object)
                                   "task" (mcp-sdk::make-object))))
    (ok (wait-for #'(lambda ()
                      (equal 62 (json-get (last-message session) "id")))))
    (ok (= (json-get (json-get (last-message session) "error") "code")
           +json-rpc-method-not-found-error+))

    (handle-message session
                    (make-request 63 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "failing-tool"
                                   "arguments" (mcp-sdk::make-object))))
    (ok (wait-for #'(lambda ()
                      (equal 63 (json-get (last-message session) "id")))))
    (ok (= (json-get (json-get (last-message session) "error") "code")
           +json-rpc-method-not-found-error+))

    (handle-message session
                    (make-request 64 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "slow"
                                   "arguments" (mcp-sdk::make-object)
                                   "task" (mcp-sdk::make-object
                                           "ttl" 100)
                                   "_meta" (mcp-sdk::make-object
                                            "progressToken" "token-64"))))
    (ok (wait-for #'(lambda ()
                      (find-message-by-id session 64))))
    (let ((task (json-get (response-result (find-message-by-id session 64)) "task")))
      (ok (equal (json-get task "status") "working"))
      (ok (stringp (json-get task "taskId")))
      (let ((task-id (json-get task "taskId")))
        (ok (typep (mcp-sdk::find-task session task-id)
                   'event-emitter:<event-emitter>))
        (ok (eq (mcp-sdk::task-status (mcp-sdk::find-task session task-id))
                :working))
        (ok (wait-for #'(lambda ()
                          (find (list :created task-id)
                                task-events
                                :test #'equal))))
        (ok (wait-for #'(lambda ()
                          (let ((message (find-message-by-method session "notifications/progress")))
                            (equal (json-get message
                                             '("params" "_meta" "io.modelcontextprotocol/related-task" "taskId"))
                                   task-id)))))
        (handle-message session
                        (make-request 65 "tasks/get"
                                      (mcp-sdk::make-object "taskId" task-id)))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id session 65))))
        (ok (member (json-get (response-result (find-message-by-id session 65)) "status")
                    '("working" "completed")
                    :test #'string=))

        (handle-message session
                        (make-request 66 "tasks/result"
                                      (mcp-sdk::make-object "taskId" task-id)))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id session 66))))
        (ok (equal (json-get (response-result (find-message-by-id session 66))
                             '("_meta" "io.modelcontextprotocol/related-task" "taskId"))
                   task-id))
        (ok (equal (json-get (aref (json-get (response-result (find-message-by-id session 66))
                                             "content")
                                   0)
                             "text")
                   "slow done"))
        (ok (wait-for #'(lambda ()
                          (find (list :completed task-id)
                                task-events
                                :test #'equal))))))

    (handle-message session
                    (make-request 67 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "failing-tool"
                                   "arguments" (mcp-sdk::make-object)
                                   "task" (mcp-sdk::make-object))))
    (ok (wait-for #'(lambda ()
                      (find-message-by-id session 67))))
    (let ((task-id (json-get (response-result (find-message-by-id session 67))
                             '("task" "taskId"))))
      (handle-message session
                      (make-request 68 "tasks/result"
                                    (mcp-sdk::make-object "taskId" task-id)))
      (ok (wait-for #'(lambda ()
                        (find-message-by-id session 68))))
      (ok (equal (json-get (response-result (find-message-by-id session 68)) "isError")
                 t))
      (handle-message session
                      (make-request 69 "tasks/get"
                                    (mcp-sdk::make-object "taskId" task-id)))
      (ok (wait-for #'(lambda ()
                        (find-message-by-id session 69))))
      (ok (equal (json-get (response-result (find-message-by-id session 69)) "status")
                 "failed"))
      (ok (wait-for #'(lambda ()
                        (find (list :failed task-id)
                              task-events
                              :test #'equal)))))))

(deftest task-list-cancel-and-expiry
  (let* ((server (make-test-server
                  :task-default-ttl-ms 1000
                  :task-max-ttl-ms 1000
                  :task-poll-interval-ms 10
                  :task-list-page-size 1))
         (session (mcp-sdk:make-session server))
        (task-events '()))
    (session-on session :task-cancelled
                #'(lambda (task)
                    (push (list :cancelled (mcp-sdk::task-id task)) task-events)))
    (session-on session :task-expired
                #'(lambda (task-id)
                    (push (list :expired task-id) task-events)))
    (register-tool server "slow-cancellable"
                   :task-support "optional"
                   :handler #'(lambda (session context arguments)
                                (declare (ignore session arguments))
                                (loop repeat 100
                                      until (context-cancelled-p context)
                                      do (sleep 0.01))
                                (mcp-sdk::make-object
                                 "content"
                                 (vector (mcp-sdk::make-object
                                          "type" "text"
                                          "text" (if (context-cancelled-p context)
                                                     "cancelled"
                                                     "completed"))))))
    (handle-message session
                    (make-request 70 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" *default-protocol-version*)))
    (ok (wait-for #'(lambda ()
                      (equal 70 (json-get (last-message session) "id")))))
    (handle-message session (make-notification "notifications/initialized"))

    (flet ((create-task (request-id ttl)
             (handle-message session
                             (make-request request-id "tools/call"
                                           (mcp-sdk::make-object
                                            "name" "slow-cancellable"
                                            "arguments" (mcp-sdk::make-object)
                                            "task" (mcp-sdk::make-object "ttl" ttl))))
             (ok (wait-for #'(lambda ()
                               (find-message-by-id session request-id))))
             (json-get (response-result (find-message-by-id session request-id))
                       '("task" "taskId"))))
      (let ((task-id-1 (create-task 71 1000))
            (task-id-2 (create-task 72 1000)))
        (handle-message session (make-request 73 "tasks/list"))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id session 73))))
        (ok (= (length (json-get (response-result (find-message-by-id session 73)) "tasks")) 1))
        (ok (json-get (response-result (find-message-by-id session 73)) "nextCursor"))

        (handle-message session
                        (make-request 74 "tasks/list"
                                      (mcp-sdk::make-object
                                       "cursor" (json-get (response-result (find-message-by-id session 73))
                                                          "nextCursor"))))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id session 74))))
        (ok (= (length (json-get (response-result (find-message-by-id session 74)) "tasks")) 1))

        (handle-message session
                        (make-request 75 "tasks/cancel"
                                      (mcp-sdk::make-object "taskId" task-id-2)))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id session 75))))
        (ok (equal (json-get (response-result (find-message-by-id session 75)) "status")
                   "cancelled"))
        (ok (wait-for #'(lambda ()
                          (find (list :cancelled task-id-2)
                                task-events
                                :test #'equal))))

        (handle-message session
                        (make-request 76 "tasks/cancel"
                                      (mcp-sdk::make-object "taskId" task-id-2)))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id session 76))))
        (ok (= (json-get (json-get (find-message-by-id session 76) "error") "code")
               +json-rpc-invalid-params-error+))

        (sleep 1.1)
        (ok (wait-for #'(lambda ()
                          (find (list :expired task-id-1)
                                task-events
                                :test #'equal))))
        (handle-message session
                        (make-request 77 "tasks/get"
                                      (mcp-sdk::make-object "taskId" task-id-1)))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id session 77))))
        (ok (= (json-get (json-get (find-message-by-id session 77) "error") "code")
               +json-rpc-invalid-params-error+))))))
