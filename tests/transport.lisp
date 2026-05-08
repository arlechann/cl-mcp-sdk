(in-package #:mcp-sdk/tests)

(deftest recursive-object-helpers
  (let* ((object (mcp-sdk::make-object
                  "meta" (list "progressToken" "token-1")
                  "items" (list (list "name" "a")
                                (mcp-sdk::make-object "name" "b"))))
         (copy (mcp-sdk:deep-copy-object object)))
    (ok (equal (json-get object '("meta" "progressToken")) "token-1"))
    (ok (equal (json-get object '("items" 0 "name")) "a"))
    (ok (equal (json-get object '("items" 1 "name")) "b"))
    (setf (json-get object '("meta" "progressToken")) "token-2")
    (ok (equal (json-get object '("meta" "progressToken")) "token-2"))
    (setf (json-get object '("items" 1 "name")) "updated")
    (ok (equal (json-get object '("items" 1 "name")) "updated"))
    (setf (json-get (first (json-get copy "items")) "name") "changed")
    (ok (equal (json-get object '("items" 0 "name")) "a"))))

(deftest stdio-transport-json-roundtrip
  (let* ((encoded (json-encode (mcp-sdk::make-object
                                "jsonrpc" "2.0"
                                "id" 1
                                "method" "ping")))
         (decoded (json-decode encoded)))
    (ok (equal (json-get decoded "jsonrpc") "2.0"))
    (ok (equal (json-get decoded "method") "ping"))))

(deftest stdio-transport-default-streams
  (let ((transport (mcp-sdk:make-stdio-transport)))
    (ok (eq (mcp-sdk::transport-input transport) *standard-input*))
    (ok (eq (mcp-sdk::transport-output transport) *standard-output*))))
