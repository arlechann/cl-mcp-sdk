(in-package #:cl-user)

(uiop:define-package #:mcp-sdk
  (:use #:cl)
  (:import-from #:alexandria
                #:copy-hash-table
                #:if-let
                #:when-let)
  (:import-from #:bordeaux-threads
                #:condition-notify
                #:condition-wait
                #:destroy-thread
                #:join-thread
                #:make-condition-variable
                #:make-lock
                #:make-thread
                #:with-lock-held)
  (:import-from #:event-emitter
                #:<event-emitter>
                #:emit
                #:off
                #:on)
  (:export
   #:*default-protocol-version*
   #:context-cancelled-p
   #:context-list-roots
   #:context-report-progress
   #:deep-copy-object
   #:define-prompt
   #:define-resource
   #:define-tool
   #:handle-message
   #:+json-rpc-invalid-request-error+
   #:+json-rpc-method-not-found-error+
   #:+json-rpc-invalid-params-error+
   #:+json-rpc-internal-error+
   #:+mcp-server-not-initialized-error+
   #:json-decode
   #:json-encode
   #:json-get
   #:make-server
   #:make-stdio-transport
   #:mcp-error
   #:mcp-error-code
   #:mcp-error-data
   #:mcp-error-message
   #:register-prompt
   #:register-resource
   #:register-tool
   #:send-notification
   #:send-request
   #:<server>
   #:server-off
   #:server-on
   #:start-server
   #:<stdio-transport>
   #:stop-server
   #:transport-send-message))
