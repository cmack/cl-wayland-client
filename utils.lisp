(uiop:define-package #:com.andrewsoutar.cl-wayland-client/utils
  (:use #:cl #:alexandria #:cffi)
  (:import-from #:cxml-dom)
  (:export #:make-collector #:collect #:get-attribute #:parse-dotted #:lispify)
  (:export #:do-collecting #:nest #:c-access))
(cl:in-package #:com.andrewsoutar.cl-wayland-client/utils)

(defun make-collector ()
  (let ((ret (cons nil nil)))
    (setf (car ret) ret)
    ret))

(defun collect (collector &rest things)
  (when things
    (setf (car collector) (last (setf (cdar collector) things))))
  (cdr collector))

(defun get-attribute (element name)
  (when-let ((attr (dom:get-attribute-node element name)))
    (dom:value attr)))

(defun parse-dotted (name interface-name)
  (if-let ((pos (position #\. name)))
    (values (subseq name 0 pos) (subseq name (1+ pos)))
    (values interface-name name)))

(defun lispify (&rest names)
  (format nil "~{~A~^-~}" (mapcar (compose (curry #'substitute #\- #\_) #'string-upcase) names)))

(defmacro do-collecting (bindings &body body)
  `(mapcar (lambda ,(mapcar #'first bindings) ,@body) ,@(mapcar #'second bindings)))

(defmacro nest (&body forms)
  (do* ((dummy (cons nil nil))
        (tail dummy)
        (remaining-forms forms (rest remaining-forms)))
       ((endp remaining-forms)
        (caar dummy))
    (setf (car tail) (append (car tail) (setf tail (cons (first remaining-forms) nil))))))

(defmacro c-access (type base &rest forms)
  (let (deref
        (type `(:pointer ,type)))
    (flet ((val ()
             (cond ((not deref) base)
                   ((and (listp base) (case (first base)
                                        (mem-aptr `(mem-aref ,@(rest base)))
                                        (foreign-slot-pointer `(foreign-slot-value ,@(rest base))))))
                   (t `(mem-ref ,base :pointer))))
           (pointer-type ()
             (assert (and (listp type) (= 2 (length type)) (eql (car type) :pointer)))
             (second type)))
      (do () ((endp forms) (val))
        (let ((operator (pop forms)))
          (etypecase operator
            ((eql :+)
             (setf base `(mem-aptr ,(val) ',(pointer-type) ,(pop forms))
                   deref nil))
            ((cons t null)
             (setf base `(mem-aptr ,(val) ',(pointer-type) ,(first operator))
                   type (second type)
                   deref t))
            ((eql :.)
             (assert deref)
             (let ((slot-name (pop forms)))
               (setf base `(foreign-slot-pointer ,base ',type ',slot-name)
                     type (foreign-slot-type type slot-name))))
            ((eql :->)
             (let ((slot-name (pop forms)))
               (setf base `(foreign-slot-pointer ,(val) ',(pointer-type) ',slot-name)
                     type (foreign-slot-type (pointer-type) slot-name)
                     deref t)))
            ((eql :&)
             (assert deref)
             (setf type `(:pointer ,type) deref nil))
            ((eql :*)
             (setf base (val) type (pointer-type) deref t))))))))
