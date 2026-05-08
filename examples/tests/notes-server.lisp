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
