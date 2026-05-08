(in-package #:mcp-sdk.examples.tests)

(deftest notes-server-list-roots-with-parsed-json-array
  (let ((server (make-notes-server
                 :transport (make-instance '<test-transport>))))
    (handle-message server
                    (make-request 40 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" mcp-sdk::*default-protocol-version*
                                   "capabilities" (mcp-sdk::make-object
                                                   "roots" (mcp-sdk::make-object
                                                            "listChanged" t)))))
    (ok (wait-for #'(lambda ()
                      (equal 40 (json-get (last-message server) "id")))))
    (handle-message server (make-notification "notifications/initialized"))

    (handle-message server
                    (make-request 41 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "notes/list-roots"
                                   "arguments" (mcp-sdk::make-object))))
    (ok (wait-for #'(lambda ()
                      (find-message-by-method server "roots/list"))))
    (handle-message server
                    (json-decode
                     "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"roots\":[{\"uri\":\"file:///workspace/project\",\"name\":\"Project\"}]}}"))
    (ok (wait-for #'(lambda ()
                      (equal 41 (json-get (last-message server) "id")))))
    (ok (= (length (json-get (response-result (last-message server)) "roots")) 1))
    (ok (equal (json-get (json-get (response-result (last-message server)) "roots")
                         '(0 "uri"))
               "file:///workspace/project"))
    (ok (equal (json-get (aref (json-get (response-result (last-message server)) "content") 0)
                         "text")
               (format nil "file:///workspace/project (Project)~%")))))

(deftest notes-server-completion
  (let ((server (make-notes-server
                 :transport (make-instance '<test-transport>))))
    (handle-message server
                    (make-request 50 "initialize"
                                  (mcp-sdk::make-object
                                   "protocolVersion" mcp-sdk::*default-protocol-version*)))
    (ok (wait-for #'(lambda ()
                      (equal 50 (json-get (last-message server) "id")))))
    (ok (json-get (json-get (response-result (last-message server)) "capabilities")
                  "completions"))
    (handle-message server (make-notification "notifications/initialized"))

    (handle-message server
                    (make-request 51 "tools/call"
                                  (mcp-sdk::make-object
                                   "name" "notes/create"
                                   "arguments" (mcp-sdk::make-object
                                                "title" "TODO note"
                                                "body" "buy milk"))))
    (ok (wait-for #'(lambda ()
                      (equal 51 (json-get (last-message server) "id")))))

    (handle-message server
                    (make-request 52 "completion/complete"
                                  (mcp-sdk::make-object
                                   "ref" (mcp-sdk::make-object
                                          "type" "ref/prompt"
                                          "name" "summarize-notes")
                                   "argument" (mcp-sdk::make-object
                                               "name" "focus"
                                               "value" "TO"))))
    (ok (wait-for #'(lambda ()
                      (equal 52 (json-get (last-message server) "id")))))
    (ok (equal (json-get (json-get (response-result (last-message server)) "completion")
                         '("values" 0))
               "TODO"))

    (handle-message server
                    (make-request 53 "completion/complete"
                                  (mcp-sdk::make-object
                                   "ref" (mcp-sdk::make-object
                                          "type" "ref/resource"
                                          "uri" "note://{id}")
                                   "argument" (mcp-sdk::make-object
                                               "name" "id"
                                               "value" ""))))
    (ok (wait-for #'(lambda ()
                      (equal 53 (json-get (last-message server) "id")))))
    (ok (equal (json-get (json-get (response-result (last-message server)) "completion")
                         '("values" 0))
               "1"))))
