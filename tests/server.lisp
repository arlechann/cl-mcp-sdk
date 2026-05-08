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
