(in-package #:mcp-sdk/tests)

(deftest initialize-and-core-methods
  (let ((server (make-test-server)))
    (register-tool server "echo"
                   :description "Echo back arguments"
                   :input-schema (mcp-sdk::make-object "type" "object")
                   :handler #'(lambda (context arguments)
                                (declare (ignore context))
                                (mcp-sdk::make-object
                                 "content"
                                 (vector (mcp-sdk::make-object
                                          "type" "text"
                                          "text" (json-get arguments "message"))))))
    (register-resource server "greeting"
                       :uri "resource:greeting"
                       :mime-type "text/plain"
                       :handler #'(lambda (context arguments)
                                    (declare (ignore context arguments))
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
                     :handler #'(lambda (context arguments)
                                  (declare (ignore context))
                                  (mcp-sdk::make-object
                                   "messages"
                                   (vector (mcp-sdk::make-object
                                            "role" "user"
                                            "content" (mcp-sdk::make-object
                                                       "type" "text"
                                                       "text" (format nil "Hello, ~A"
                                                                      (json-get arguments "subject"))))))))

    (handle-message server (make-request 1 "initialize"
                                         (mcp-sdk::make-object
                                          "protocolVersion" *default-protocol-version*)))
    (ok (wait-for #'(lambda ()
                      (let ((message (last-message server)))
                        (and message
                             (response-result message))))))
    (ok (equal (json-get (response-result (last-message server)) "protocolVersion")
               *default-protocol-version*))

    (handle-message server (make-notification "notifications/initialized"))

    (handle-message server (make-request 2 "tools/list"))
    (ok (wait-for #'(lambda ()
                      (equal 2 (json-get (last-message server) "id")))))
    (ok (= (length (json-get (response-result (last-message server)) "tools")) 1))

    (handle-message server
                    (make-request 3 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "echo"
                                   "arguments" (mcp-sdk::make-object
                                                "message" "hello"))))
    (ok (wait-for #'(lambda ()
                      (equal 3 (json-get (last-message server) "id")))))
    (ok (equal (json-get (aref (json-get (response-result (last-message server)) "content") 0) "text")
               "hello"))

    (handle-message server (make-request 4 "resources/list"))
    (ok (wait-for #'(lambda ()
                      (equal 4 (json-get (last-message server) "id")))))
    (ok (= (length (json-get (response-result (last-message server)) "resources")) 1))

    (handle-message server
                    (make-request 5 "resources/read"
                                  (mcp-sdk::make-object "uri" "resource:greeting")))
    (ok (wait-for #'(lambda ()
                      (equal 5 (json-get (last-message server) "id")))))
    (ok (equal (json-get (aref (json-get (response-result (last-message server)) "contents") 0) "text")
               "hello"))

    (handle-message server (make-request 6 "prompts/list"))
    (ok (wait-for #'(lambda ()
                      (equal 6 (json-get (last-message server) "id")))))
    (ok (= (length (json-get (response-result (last-message server)) "prompts")) 1))

    (handle-message server
                    (make-request 7 "prompts/get"
                                  (mcp-sdk::make-object
                                   "name" "greeter"
                                   "arguments" (mcp-sdk::make-object
                                                "subject" "world"))))
    (ok (wait-for #'(lambda ()
                      (equal 7 (json-get (last-message server) "id")))))
    (ok (equal (json-get (json-get (aref (json-get (response-result (last-message server)) "messages") 0) "content")
                         "text")
               "Hello, world"))))

(deftest reject-feature-before-initialize
  (let ((server (make-test-server)))
    (handle-message server (make-request 10 "tools/list"))
    (ok (wait-for #'(lambda ()
                      (response-error (last-message server)))))
    (ok (= (json-get (response-error (last-message server)) "code")
           mcp-sdk:+mcp-server-not-initialized-error+))))

(deftest exported-error-codes
  (ok (= mcp-sdk:+json-rpc-invalid-request-error+ -32600))
  (ok (= mcp-sdk:+json-rpc-method-not-found-error+ -32601))
  (ok (= mcp-sdk:+json-rpc-invalid-params-error+ -32602))
  (ok (= mcp-sdk:+json-rpc-internal-error+ -32603))
  (ok (= mcp-sdk:+mcp-server-not-initialized-error+ -32002)))

(deftest progress-cancel-and-events
  (let ((server (make-test-server))
        (events '()))
    (register-tool server "count"
                   :handler #'(lambda (context arguments)
                                (declare (ignore arguments))
                                (context-report-progress context 1 2 "started")
                                (loop repeat 200
                                      until (context-cancelled-p context)
                                      do (sleep 0.01))
                                (mcp-sdk::make-object "cancelled" (context-cancelled-p context))))
    (server-on server :request-cancelled
               #'(lambda (request-id)
                   (push request-id events)))

    (handle-message server (make-request 20 "initialize"))
    (wait-for #'(lambda ()
                  (equal 20 (json-get (last-message server) "id"))))
    (handle-message server (make-notification "notifications/initialized"))

    (handle-message server
                    (make-request 21 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "count"
                                   "_meta" (mcp-sdk::make-object
                                            "progressToken" "token-1"))))
    (ok (wait-for #'(lambda ()
                      (find-message-by-method server "notifications/progress"))))
    (handle-message server
                    (make-notification "notifications/cancelled"
                                       (mcp-sdk::make-object "requestId" 21)))
    (ok (wait-for #'(lambda ()
                      (equal 21 (car events)))))
    (ok (wait-for #'(lambda ()
                      (let ((message (last-message server)))
                        (and (equal 21 (json-get message "id"))
                             (response-result message))))))
    (ok (json-get (response-result (last-message server)) "cancelled"))))

(deftest outbound-request-roundtrip
  (let ((server (make-test-server)))
    (let ((thread (make-thread
                   #'(lambda ()
                       (send-request server "roots/list")))))
      (ok (wait-for #'(lambda ()
                        (equal "roots/list"
                               (json-get (first (all-messages server)) "method")))))
      (handle-message server
                      (mcp-sdk::make-object
                       "jsonrpc" "2.0"
                       "id" 1
                       "result" (mcp-sdk::make-object "roots" #())))
      (join-thread thread)
      (ok t))))

(deftest resource-templates
  (let ((server (make-test-server)))
    (register-resource server "note-template"
                       :uri-template "note://{id}"
                       :description "Templated note resource"
                       :mime-type "text/plain"
                       :handler #'(lambda (context arguments)
                                    (declare (ignore context))
                                    (mcp-sdk::make-object
                                     "contents"
                                     (vector (mcp-sdk::make-object
                                              "uri" (json-get arguments "uri")
                                              "mimeType" "text/plain"
                                              "text" "templated note")))))

    (handle-message server
                    (make-request 30 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" *default-protocol-version*)))
    (ok (wait-for #'(lambda ()
                      (equal 30 (json-get (last-message server) "id")))))
    (handle-message server (make-notification "notifications/initialized"))

    (handle-message server (make-request 31 "resources/templates/list"))
    (ok (wait-for #'(lambda ()
                      (equal 31 (json-get (last-message server) "id")))))
    (ok (= (length (json-get (response-result (last-message server)) "resourceTemplates")) 1))
    (ok (equal (json-get (aref (json-get (response-result (last-message server)) "resourceTemplates") 0)
                         "uriTemplate")
               "note://{id}"))

    (handle-message server
                    (make-request 32 "resources/read"
                                  (mcp-sdk::make-object "uri" "note://42")))
    (ok (wait-for #'(lambda ()
                      (equal 32 (json-get (last-message server) "id")))))
    (ok (equal (json-get (aref (json-get (response-result (last-message server)) "contents") 0)
                         "text")
               "templated note"))))

(deftest roots-support
  (let ((server (make-test-server))
        (root-events '()))
    (register-tool server "show-roots"
                   :input-schema (mcp-sdk::make-object "type" "object")
                   :handler #'(lambda (context arguments)
                                (declare (ignore arguments))
                                (let ((roots (context-list-roots context)))
                                  (mcp-sdk::make-object
                                   "count" (length roots)))))
    (server-on server :roots-list-changed
               #'(lambda ()
                   (push :changed root-events)))

    (handle-message server
                    (make-request 33 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" *default-protocol-version*
                                   "capabilities" (mcp-sdk::make-object
                                                   "roots" (mcp-sdk::make-object
                                                            "listChanged" t)))))
    (ok (wait-for #'(lambda ()
                      (equal 33 (json-get (last-message server) "id")))))
    (handle-message server (make-notification "notifications/initialized"))

    (handle-message server
                    (make-request 34 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "show-roots"
                                   "arguments" (mcp-sdk::make-object))))
    (ok (wait-for #'(lambda ()
                      (find-message-by-method server "roots/list"))))
    (handle-message server
                    (mcp-sdk::make-object
                     "jsonrpc" "2.0"
                     "id" 1
                     "result" (mcp-sdk::make-object
                               "roots"
                               (vector (mcp-sdk::make-object
                                        "uri" "file:///workspace/project"
                                        "name" "Project")))))
    (ok (wait-for #'(lambda ()
                      (equal 34 (json-get (last-message server) "id")))))
    (ok (= (json-get (response-result (last-message server)) "count") 1))

    (handle-message server (make-notification "notifications/roots/list_changed"))
    (ok (wait-for #'(lambda ()
                      root-events)))))

(deftest completion-support
  (let ((server (make-test-server)))
    (register-prompt server "greeter"
                     :arguments (list (mcp-sdk::make-object
                                       "name" "subject"
                                       "required" t))
                     :completion-handler
                     #'(lambda (context argument context-arguments)
                         (declare (ignore context))
                         (ok (equal (json-get argument "name") "subject"))
                         (ok (equal (json-get context-arguments "tone") "casual"))
                         (mcp-sdk::make-object
                          "values" (vector "world" "writer")
                          "total" 2
                          "hasMore" :false)))
    (register-resource server "note-template"
                       :uri-template "note://{id}"
                       :completion-handler
                       #'(lambda (context argument context-arguments)
                            (declare (ignore context context-arguments))
                            (ok (equal (json-get argument "value") "4"))
                            '("42")))

    (handle-message server
                    (make-request 50 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" *default-protocol-version*)))
    (ok (wait-for #'(lambda ()
                      (equal 50 (json-get (last-message server) "id")))))
    (ok (json-get (json-get (response-result (last-message server)) "capabilities")
                  "completions"))
    (handle-message server (make-notification "notifications/initialized"))

    (handle-message server
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
                      (equal 51 (json-get (last-message server) "id")))))
    (ok (equal (json-get (json-get (response-result (last-message server)) "completion")
                         "total")
               2))
    (ok (equal (aref (json-get (json-get (response-result (last-message server))
                                         "completion")
                                "values")
                     0)
               "world"))

    (handle-message server
                    (make-request 52 "completion/complete"
                                  (mcp-sdk::make-object
                                   "ref" (mcp-sdk::make-object
                                          "type" "ref/resource"
                                          "uri" "note://{id}")
                                   "argument" (mcp-sdk::make-object
                                               "name" "id"
                                               "value" "4"))))
    (ok (wait-for #'(lambda ()
                      (equal 52 (json-get (last-message server) "id")))))
    (ok (equal (aref (json-get (json-get (response-result (last-message server))
                                         "completion")
                                "values")
                     0)
               "42"))))

(deftest tasks-support
  (let ((server (make-test-server
                 :task-default-ttl-ms 100
                 :task-max-ttl-ms 1000
                 :task-poll-interval-ms 10
                 :task-list-page-size 1))
        (task-events '()))
    (server-on server :task-created
               #'(lambda (task)
                   (push (list :created (mcp-sdk::task-id task)) task-events)))
    (server-on server :task-completed
               #'(lambda (task result)
                   (declare (ignore result))
                   (push (list :completed (mcp-sdk::task-id task)) task-events)))
    (server-on server :task-failed
               #'(lambda (task payload)
                   (declare (ignore payload))
                   (push (list :failed (mcp-sdk::task-id task)) task-events)))
    (register-tool server "slow"
                   :task-support "optional"
                   :handler #'(lambda (context arguments)
                                (declare (ignore arguments))
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
                   :handler #'(lambda (context arguments)
                                (declare (ignore context arguments))
                                (mcp-sdk::make-object
                                 "content"
                                 (vector (mcp-sdk::make-object
                                          "type" "text"
                                          "text" "failed"))
                                 "isError" t)))
    (register-tool server "sync-only"
                   :handler #'(lambda (context arguments)
                                (declare (ignore context arguments))
                                (mcp-sdk::make-object
                                 "content"
                                 (vector (mcp-sdk::make-object
                                          "type" "text"
                                          "text" "sync only")))))

    (handle-message server
                    (make-request 60 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" *default-protocol-version*)))
    (ok (wait-for #'(lambda ()
                      (equal 60 (json-get (last-message server) "id")))))
    (ok (json-get (json-get (json-get (response-result (last-message server))
                                      "capabilities")
                            '("tasks" "requests" "tools"))
                  "call"))
    (handle-message server (make-notification "notifications/initialized"))

    (handle-message server (make-request 61 "tools/list"))
    (ok (wait-for #'(lambda ()
                      (equal 61 (json-get (last-message server) "id")))))
    (let* ((tools (coerce (json-get (response-result (last-message server)) "tools")
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

    (handle-message server
                    (make-request 62 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "sync-only"
                                   "arguments" (mcp-sdk::make-object)
                                   "task" (mcp-sdk::make-object))))
    (ok (wait-for #'(lambda ()
                      (equal 62 (json-get (last-message server) "id")))))
    (ok (= (json-get (json-get (last-message server) "error") "code")
           +json-rpc-method-not-found-error+))

    (handle-message server
                    (make-request 63 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "failing-tool"
                                   "arguments" (mcp-sdk::make-object))))
    (ok (wait-for #'(lambda ()
                      (equal 63 (json-get (last-message server) "id")))))
    (ok (= (json-get (json-get (last-message server) "error") "code")
           +json-rpc-method-not-found-error+))

    (handle-message server
                    (make-request 64 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "slow"
                                   "arguments" (mcp-sdk::make-object)
                                   "task" (mcp-sdk::make-object
                                           "ttl" 100)
                                   "_meta" (mcp-sdk::make-object
                                            "progressToken" "token-64"))))
    (ok (wait-for #'(lambda ()
                      (find-message-by-id server 64))))
    (let ((task (json-get (response-result (find-message-by-id server 64)) "task")))
      (ok (equal (json-get task "status") "working"))
      (ok (stringp (json-get task "taskId")))
      (let ((task-id (json-get task "taskId")))
        (ok (typep (mcp-sdk::find-task server task-id)
                   'event-emitter:<event-emitter>))
        (ok (eq (mcp-sdk::task-status (mcp-sdk::find-task server task-id))
                :working))
        (ok (wait-for #'(lambda ()
                          (find (list :created task-id)
                                task-events
                                :test #'equal))))
        (ok (wait-for #'(lambda ()
                          (let ((message (find-message-by-method server "notifications/progress")))
                            (equal (json-get message
                                             '("params" "_meta" "io.modelcontextprotocol/related-task" "taskId"))
                                   task-id)))))
        (handle-message server
                        (make-request 65 "tasks/get"
                                      (mcp-sdk::make-object "taskId" task-id)))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id server 65))))
        (ok (member (json-get (response-result (find-message-by-id server 65)) "status")
                    '("working" "completed")
                    :test #'string=))

        (handle-message server
                        (make-request 66 "tasks/result"
                                      (mcp-sdk::make-object "taskId" task-id)))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id server 66))))
        (ok (equal (json-get (response-result (find-message-by-id server 66))
                             '("_meta" "io.modelcontextprotocol/related-task" "taskId"))
                   task-id))
        (ok (equal (json-get (aref (json-get (response-result (find-message-by-id server 66))
                                             "content")
                                   0)
                             "text")
                   "slow done"))
        (ok (wait-for #'(lambda ()
                          (find (list :completed task-id)
                                task-events
                                :test #'equal))))))

    (handle-message server
                    (make-request 67 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "failing-tool"
                                   "arguments" (mcp-sdk::make-object)
                                   "task" (mcp-sdk::make-object))))
    (ok (wait-for #'(lambda ()
                      (find-message-by-id server 67))))
    (let ((task-id (json-get (response-result (find-message-by-id server 67))
                             '("task" "taskId"))))
      (handle-message server
                      (make-request 68 "tasks/result"
                                    (mcp-sdk::make-object "taskId" task-id)))
      (ok (wait-for #'(lambda ()
                        (find-message-by-id server 68))))
      (ok (equal (json-get (response-result (find-message-by-id server 68)) "isError")
                 t))
      (handle-message server
                      (make-request 69 "tasks/get"
                                    (mcp-sdk::make-object "taskId" task-id)))
      (ok (wait-for #'(lambda ()
                        (find-message-by-id server 69))))
      (ok (equal (json-get (response-result (find-message-by-id server 69)) "status")
                 "failed"))
      (ok (wait-for #'(lambda ()
                        (find (list :failed task-id)
                              task-events
                              :test #'equal)))))))

(deftest task-list-cancel-and-expiry
  (let ((server (make-test-server
                 :task-default-ttl-ms 1000
                 :task-max-ttl-ms 1000
                 :task-poll-interval-ms 10
                 :task-list-page-size 1))
        (task-events '()))
    (server-on server :task-cancelled
               #'(lambda (task)
                   (push (list :cancelled (mcp-sdk::task-id task)) task-events)))
    (server-on server :task-expired
               #'(lambda (task-id)
                   (push (list :expired task-id) task-events)))
    (register-tool server "slow-cancellable"
                   :task-support "optional"
                   :handler #'(lambda (context arguments)
                                (declare (ignore arguments))
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
    (handle-message server
                    (make-request 70 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" *default-protocol-version*)))
    (ok (wait-for #'(lambda ()
                      (equal 70 (json-get (last-message server) "id")))))
    (handle-message server (make-notification "notifications/initialized"))

    (flet ((create-task (request-id ttl)
             (handle-message server
                             (make-request request-id "tools/call"
                                           (mcp-sdk::make-object
                                            "name" "slow-cancellable"
                                            "arguments" (mcp-sdk::make-object)
                                            "task" (mcp-sdk::make-object "ttl" ttl))))
             (ok (wait-for #'(lambda ()
                               (find-message-by-id server request-id))))
             (json-get (response-result (find-message-by-id server request-id))
                       '("task" "taskId"))))
      (let ((task-id-1 (create-task 71 1000))
            (task-id-2 (create-task 72 1000)))
        (handle-message server (make-request 73 "tasks/list"))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id server 73))))
        (ok (= (length (json-get (response-result (find-message-by-id server 73)) "tasks")) 1))
        (ok (json-get (response-result (find-message-by-id server 73)) "nextCursor"))

        (handle-message server
                        (make-request 74 "tasks/list"
                                      (mcp-sdk::make-object
                                       "cursor" (json-get (response-result (find-message-by-id server 73))
                                                          "nextCursor"))))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id server 74))))
        (ok (= (length (json-get (response-result (find-message-by-id server 74)) "tasks")) 1))

        (handle-message server
                        (make-request 75 "tasks/cancel"
                                      (mcp-sdk::make-object "taskId" task-id-2)))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id server 75))))
        (ok (equal (json-get (response-result (find-message-by-id server 75)) "status")
                   "cancelled"))
        (ok (wait-for #'(lambda ()
                          (find (list :cancelled task-id-2)
                                task-events
                                :test #'equal))))

        (handle-message server
                        (make-request 76 "tasks/cancel"
                                      (mcp-sdk::make-object "taskId" task-id-2)))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id server 76))))
        (ok (= (json-get (json-get (find-message-by-id server 76) "error") "code")
               +json-rpc-invalid-params-error+))

        (sleep 1.1)
        (ok (wait-for #'(lambda ()
                          (find (list :expired task-id-1)
                                task-events
                                :test #'equal))))
        (handle-message server
                        (make-request 77 "tasks/get"
                                      (mcp-sdk::make-object "taskId" task-id-1)))
        (ok (wait-for #'(lambda ()
                          (find-message-by-id server 77))))
        (ok (= (json-get (json-get (find-message-by-id server 77) "error") "code")
               +json-rpc-invalid-params-error+))))))
