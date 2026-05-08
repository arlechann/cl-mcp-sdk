(in-package #:event-emitter)

(defclass <event-emitter> ()
  ((listeners
    :initform (make-hash-table :test #'eq)
    :type hash-table)))

(defun make-event-emitter ()
  (make-instance '<event-emitter>))

(defgeneric emit (event-emitter event &rest args))
(defgeneric on (event-emitter event listener))
(defgeneric off (event-emitter event listener))
(defgeneric add-listener (event-emitter event listener))
(defgeneric remove-listener (event-emitter event listener))
(defgeneric once (event-emitter event listener))

(defmethod emit ((event-emitter <event-emitter>) event &rest args)
  (mapc #'(lambda (listener)
            (apply listener args))
        (gethash event (slot-value event-emitter 'listeners) nil))
  event)

(defmethod on ((event-emitter <event-emitter>) event listener)
  (push listener
        (gethash event (slot-value event-emitter 'listeners) nil))
  listener)

(defmethod off ((event-emitter <event-emitter>) event listener)
  (deletef (gethash event
                    (slot-value event-emitter 'listeners)
                    nil)
           listener
           :test #'eq)
  listener)

(defmethod add-listener ((event-emitter <event-emitter>) event listener)
  (on event-emitter event listener))

(defmethod remove-listener ((event-emitter <event-emitter>) event listener)
  (off event-emitter event listener))

(defmethod once ((event-emitter <event-emitter>) event listener)
  (labels ((once-listener (&rest args)
             (off event-emitter event #'once-listener)
             (apply listener args)))
    (on event-emitter event #'once-listener)))
