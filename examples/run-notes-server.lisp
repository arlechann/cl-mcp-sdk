(require :asdf)

(let ((*standard-output* *error-output*)
      (*trace-output* *error-output*)
      (*load-verbose* nil)
      (*load-print* nil)
      (*compile-verbose* nil)
      (*compile-print* nil)
      (asdf:*asdf-verbose* nil))
  (asdf:load-asd #P"/home/arle/workspace/common-lisp/cl-mcp-sdk/mcp-sdk-examples.asd")
  (asdf:load-system :mcp-sdk-examples))

(mcp-sdk.examples.notes:main)
(loop
  (sleep 1))
