(in-package #:cl-user)

(defpackage #:mcp-sdk.examples.notes
  (:use #:cl)
  (:import-from #:bordeaux-threads
                #:make-lock
                #:with-lock-held)
  (:export #:main
           #:make-notes-server))

(in-package #:mcp-sdk.examples.notes)

(defun make-object (&rest entries)
  (let ((table (make-hash-table :test #'equal)))
    (loop for (key value) on entries by #'cddr
          do (setf (gethash key table) value))
    table))

(defun schema (json)
  (mcp-sdk:json-decode json))

(defun note-content (text)
  (make-object
   "content"
   (vector (make-object
            "type" "text"
            "text" text))))

(defun prompt-message (text)
  (make-object
   "role" "user"
   "content" (make-object
              "type" "text"
              "text" text)))

(defun note->object (id note)
  (make-object
   "id" id
   "title" (mcp-sdk:json-get note "title")
   "body" (mcp-sdk:json-get note "body")))

(defun note-summary-line (id note)
  (format nil "[~A] ~A" id (mcp-sdk:json-get note "title")))

(defun sorted-note-ids (notes)
  (sort (loop for id being the hash-keys of notes
              collect id)
        #'<))

(defun collect-note-lines (notes)
  (loop for id in (sorted-note-ids notes)
        for note = (gethash id notes)
        collect (note-summary-line id note)))

(defun notes-index-text (notes)
  (let ((lines (collect-note-lines notes)))
    (if lines
        (with-output-to-string (stream)
          (dolist (line lines)
            (write-line line stream)))
        "ノートはまだありません。")))

(defun latest-note-id (notes)
  (car (last (sorted-note-ids notes))))

(defun note-id-from-uri (uri)
  (let ((prefix "note://"))
    (when (and (stringp uri)
               (<= (length prefix) (length uri))
               (string= prefix uri :end2 (length prefix)))
      (parse-integer (subseq uri (length prefix)) :junk-allowed t))))

(defun make-notes-server ()
  (let ((server (mcp-sdk:make-server
                 :name "notes-server"
                 :version "0.1.0"))
        (notes (make-hash-table))
        (lock (make-lock "notes-server.notes"))
        (next-id 0))
    (labels ((create-note (title body)
               (with-lock-held (lock)
                 (incf next-id)
                 (let ((id next-id)
                       (note (make-object
                              "title" title
                              "body" body)))
                   (setf (gethash id notes) note)
                   (values id note))))
             (find-note (id)
               (with-lock-held (lock)
                 (gethash id notes)))
             (delete-note (id)
               (with-lock-held (lock)
                 (prog1 (gethash id notes)
                   (remhash id notes))))
             (snapshot-notes ()
               (with-lock-held (lock)
                 (let ((copy (make-hash-table)))
                   (maphash #'(lambda (id note)
                                (setf (gethash id copy)
                                      (mcp-sdk:deep-copy-object note)))
                            notes)
                   copy))))
      (mcp-sdk:register-tool
       server
       "notes/create"
       :title "Create Note"
       :description "タイトルと本文からノートを作成します。"
       :input-schema
       (schema
        "{\"type\":\"object\",\"properties\":{\"title\":{\"type\":\"string\"},\"body\":{\"type\":\"string\"}},\"required\":[\"title\",\"body\"]}")
       :handler #'(lambda (context arguments)
                    (declare (ignore context))
                    (multiple-value-bind (id note)
                        (create-note (or (mcp-sdk:json-get arguments "title") "")
                                     (or (mcp-sdk:json-get arguments "body") ""))
                      (make-object
                       "note" (note->object id note)
                       "content"
                       (vector (make-object
                                "type" "text"
                                "text" (format nil "created note ~A" id)))))))
      (mcp-sdk:register-tool
       server
       "notes/list"
       :title "List Notes"
       :description "現在のノート一覧を返します。"
       :input-schema
       (schema
        "{\"type\":\"object\",\"properties\":{}}")
       :handler #'(lambda (context arguments)
                    (declare (ignore context arguments))
                    (let ((snapshot (snapshot-notes)))
                      (note-content (notes-index-text snapshot)))))
      (mcp-sdk:register-tool
       server
       "notes/get"
       :title "Get Note"
       :description "ID を指定してノートを返します。"
       :input-schema
       (schema
        "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"integer\"}},\"required\":[\"id\"]}")
       :handler #'(lambda (context arguments)
                    (declare (ignore context))
                    (let* ((id (mcp-sdk:json-get arguments "id"))
                           (note (find-note id)))
                      (if note
                          (make-object
                           "note" (note->object id note)
                           "content"
                           (vector (make-object
                                    "type" "text"
                                    "text" (mcp-sdk:json-get note "body"))))
                          (note-content (format nil "note ~A was not found" id))))))
      (mcp-sdk:register-tool
       server
       "notes/delete"
       :title "Delete Note"
       :description "ID を指定してノートを削除します。"
       :input-schema
       (schema
        "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"integer\"}},\"required\":[\"id\"]}")
       :handler #'(lambda (context arguments)
                    (declare (ignore context))
                    (let ((id (mcp-sdk:json-get arguments "id")))
                      (if (delete-note id)
                          (note-content (format nil "deleted note ~A" id))
                          (note-content (format nil "note ~A was not found" id))))))
      (mcp-sdk:register-resource
       server
       "notes-index"
       :uri "note://index"
       :description "ノート一覧を返します。"
       :mime-type "text/plain"
       :handler #'(lambda (context params)
                    (declare (ignore context params))
                    (let ((snapshot (snapshot-notes)))
                      (make-object
                       "contents"
                       (vector (make-object
                                "uri" "note://index"
                                "mimeType" "text/plain"
                                "text" (notes-index-text snapshot)))))))
      (mcp-sdk:register-resource
       server
       "latest-note"
       :uri "note://latest"
       :description "最新のノートを返します。"
       :mime-type "text/plain"
       :handler #'(lambda (context params)
                    (declare (ignore context params))
                    (let* ((snapshot (snapshot-notes))
                           (id (latest-note-id snapshot))
                           (note (and id (gethash id snapshot))))
                      (make-object
                       "contents"
                       (vector (make-object
                                "uri" "note://latest"
                                "mimeType" "text/plain"
                                "text"
                                (if note
                                    (format nil "~A~%~%~A"
                                            (mcp-sdk:json-get note "title")
                                            (mcp-sdk:json-get note "body"))
                                    "ノートはまだありません。")))))))
      (mcp-sdk:register-resource
       server
       "note-by-id"
       :uri-template "note://{id}"
       :description "ID を含む URI からノートを返します。"
       :mime-type "text/plain"
       :handler #'(lambda (context params)
                    (declare (ignore context))
                    (let* ((uri (mcp-sdk:json-get params "uri"))
                           (id (note-id-from-uri uri))
                           (note (and id (find-note id))))
                      (make-object
                       "contents"
                       (vector (make-object
                                "uri" uri
                                "mimeType" "text/plain"
                                "text"
                                (if note
                                    (format nil "~A~%~%~A"
                                            (mcp-sdk:json-get note "title")
                                            (mcp-sdk:json-get note "body"))
                                    (format nil "note ~A was not found" id)))))))
      (mcp-sdk:register-prompt
       server
       "summarize-notes"
       :description "ノート一覧を要約するためのプロンプトを返します。"
       :arguments
       (list (make-object
              "name" "focus"
              "description" "要約で重点的に扱いたい観点"
              "required" :false))
       :handler #'(lambda (context arguments)
                    (declare (ignore context))
                    (let* ((snapshot (snapshot-notes))
                           (focus (or (mcp-sdk:json-get arguments "focus")
                                      "重要な論点"))
                           (prompt (format nil
                                           "以下のノート一覧を読み、~A を中心に要約してください。~%~%~A"
                                           focus
                                           (notes-index-text snapshot))))
                      (make-object
                       "messages"
                       (vector (prompt-message prompt))))))
      (mcp-sdk:register-prompt
       server
       "rewrite-note"
       :description "指定したノートを LLM 向けに整形するプロンプトを返します。"
       :arguments
       (list (make-object
              "name" "id"
              "description" "整形対象のノート ID"
              "required" t))
       :handler #'(lambda (context arguments)
                    (declare (ignore context))
                    (let* ((id (mcp-sdk:json-get arguments "id"))
                           (note (find-note id))
                           (prompt
                             (if note
                                 (format nil
                                         "次のノートを、AI エージェントが読みやすい箇条書きに変換してください。~%タイトル: ~A~%本文: ~A"
                                         (mcp-sdk:json-get note "title")
                                         (mcp-sdk:json-get note "body"))
                                 (format nil "note ~A was not found" id))))
                      (make-object
                       "messages"
                       (vector (prompt-message prompt))))))
      server)))

(defun main ()
  (mcp-sdk:start-server (make-notes-server)))
