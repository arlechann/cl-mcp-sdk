(in-package #:mcp-sdk)

(defparameter *default-protocol-version* "2025-11-25")

(defparameter +missing-json-value+ (gensym "MISSING-JSON-VALUE"))

(defun plist-object-p (value)
  (and (consp value)
       (evenp (length value))
       (loop for (key ignored) on value by #'cddr
             always (stringp key))))

(defun deep-copy-object (table)
  (labels ((deep-copy-value (value)
             (cond
               ((object-p value)
                (let ((copy (make-hash-table :test #'equal)))
                  (maphash #'(lambda (key nested-value)
                               (setf (gethash key copy)
                                     (deep-copy-value nested-value)))
                           value)
                  copy))
               ((stringp value)
                value)
               ((vectorp value)
                (map 'vector #'deep-copy-value value))
               ((listp value)
                (mapcar #'deep-copy-value value))
               (t value))))
    (deep-copy-value table)))

(defun normalize-json-value (value)
  (cond
    ((object-p value)
     (deep-copy-object value))
    ((stringp value)
     value)
    ((plist-object-p value)
     (apply #'make-object value))
    ((vectorp value)
     (map 'vector #'normalize-json-value value))
    ((listp value)
     (mapcar #'normalize-json-value value))
    (t value)))

(defun make-object (&rest entries)
  (let ((table (make-hash-table :test #'equal)))
    (loop for (key value) on entries by #'cddr
          do (setf (gethash key table)
                   (normalize-json-value value)))
    table))

(defun object-p (value)
  (typep value 'hash-table))

(defun ensure-object (value)
  (if (object-p value)
      value
      (make-object)))

(defun json-get (object key &optional default)
  (labels ((json-get-1 (target segment)
             (cond
               ((object-p target)
               (multiple-value-bind (value presentp)
                    (gethash segment target)
                  (if presentp value +missing-json-value+)))
               ((and (listp target)
                     (integerp segment)
                     (<= 0 segment)
                     (< segment (length target)))
                (nth segment target))
               ((and (vectorp target)
                     (integerp segment)
                     (<= 0 segment)
                     (< segment (length target)))
                (aref target segment))
               (t +missing-json-value+))))
    (if (listp key)
        (loop with current = object
              for segment in key
              do (setf current (json-get-1 current segment))
              if (eq current +missing-json-value+)
                do (return default)
              finally (return current))
        (let ((value (json-get-1 object key)))
          (if (eq value +missing-json-value+)
              default
              value)))))

(defun (setf json-get) (value object key &optional default)
  (declare (ignore default))
  (labels ((json-set-1 (target segment new-value)
             (cond
               ((object-p target)
                (setf (gethash segment target) new-value))
               ((and (listp target)
                     (integerp segment)
                     (<= 0 segment)
                     (< segment (length target)))
                (setf (nth segment target) new-value))
               ((and (vectorp target)
                     (integerp segment)
                     (<= 0 segment)
                     (< segment (length target)))
                (setf (aref target segment) new-value))
               (t
                (error "Cannot set JSON path segment ~S on ~S" segment target)))))
    (if (listp key)
        (let* ((parent-path (butlast key))
               (segment (car (last key)))
               (parent (if parent-path
                           (json-get object parent-path +missing-json-value+)
                           object)))
          (when (eq parent +missing-json-value+)
            (error "Cannot set JSON path ~S because parent path is missing" key))
          (json-set-1 parent segment (normalize-json-value value)))
        (json-set-1 object key (normalize-json-value value)))))

(defun make-array-from-list (items)
  (map 'vector #'normalize-json-value items))

(defun maybe-object (&rest pairs)
  (let ((table (make-object)))
    (loop for (key value) on pairs by #'cddr
          when value
            do (setf (gethash key table)
                     (normalize-json-value value)))
    table))
