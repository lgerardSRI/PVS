;;;;;;;;;;;;;;;;;;;;;;;;;;;;; -*- Mode: Lisp -*- ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ics-pvs.lisp -- 
;; Author          : Harald Ruess
;; Created On      : Tue May 14 11:32:58 PDT 2002
;; Last Modified By: Harald Ruess
;; Last Modified On: Tue May 14 11:32:58 PDT 2002
;; Update Count    : 1
;; Status          : Unknown, Use with caution!
;; 
;; HISTORY
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package :pvs)

;; Global variables

(defvar *pvs-to-ics-hash* 
  (make-hash-table :hash-function 'pvs-sxhash :test 'tc-eq))

(defvar *ics-to-pvs-translation* nil)

(defvar *ics-to-pvs-hash* 
  (make-hash-table :test 'eql))

(defvar *pvs-to-ics-symtab* 
  (make-hash-table :hash-function 'pvs-sxhash :test 'tc-eq))

(defvar *unique-name-ics-counter* 0)

(defvar *ics-nonlin* nil)

(defvar *ics-debug* nil)

(defun pvs-to-ics-reset ()
  (clrhash *pvs-to-ics-hash*)
  (clrhash *ics-to-pvs-hash*)
  (clrhash *pvs-to-ics-symtab*)
  (setf *unique-name-ics-counter* 0))

(defun pvs-to-ics-add-hash (expr wrapper)
  #+icsdebug(assert (expr? expr))
  #+icsdebug(assert (wrap? wrapper))
  (setf (gethash expr *pvs-to-ics-hash*) wrapper)
  (when *ics-to-pvs-translation*
    (setf (gethash wrapper *pvs-to-ics-hash*) expr)))


;; Wrapping and unwrapping ICS values in order to finalize 
;; objects of these types.

(defstruct (wrap
	    (:predicate wrap?)
	    (:constructor make-wrap (address))
	    (:print-function
	     (lambda (p s k)
	       (declare (ignore k))
               (format t "<#wrap: ~a>" (wrap-address p)))))
  address)

(defun wrap (value)
  #+icsdebug(assert (integerp value))
  (make-wrap value))

(defun unwrap (w)
  #+icsdebug(assert (wrap? w))
  (wrap-address w))

(defun wrap= (w1 w2)
  #+icsdebug(assert (wrap? w1))
  #+icsdebug(assert (wrap? w2))
  (= (wrap-address w1) (wrap-address w2)))

(defun wrap-finalize! (w)
  #+icsdebug(assert (wrap? w))
  (excl:schedule-finalization w 'wrap-free!))

(defun wrap-free! (w)
  #+icsdebug(assert (wrap? w))
  (ics_deregister (unwrap w)))

(defstruct (term-wrap
	    (:include wrap)
	    (:predicate term-wrap?)
	    (:constructor make-term-wrap (address))
	    (:print-function
	     (lambda (p s k)
	       (declare (ignore k))
	       (format s "<#term: ~a>" (wrap-address p))))))

(defun term-wrap (value)
   #+icsdebug(assert (integerp value))
   (make-term-wrap value))

(defun term-unwrap (w)
  #+icsdebug(assert (term-wrap? w))
  (wrap-address w))

(defstruct (atom-wrap
	    (:include wrap)
	    (:predicate atom-wrap?)
	    (:constructor make-atom-wrap (address))
	    (:print-function
	     (lambda (p s k)
	       (declare (ignore k))
	       (format s "<#atom: ~a>" (wrap-address p))))))

(defun atom-wrap (value)
   #+icsdebug(assert (integerp value))
   (make-atom-wrap value))

(defun atom-unwrap (w)
   #+icsdebug(assert (atom-wrap? w))
  (wrap-address w))

(defstruct (prop-wrap
	    (:include wrap)
	    (:predicate prop-wrap?)
	    (:constructor make-prop-wrap (address))
	    (:print-function
	     (lambda (p s k)
	       (declare (ignore k))
	       (format s "<#prop: ~a>" (wrap-address p))))))

(defun prop-wrap (value)
   #+icsdebug(assert (integerp value))
   (make-prop-wrap value))

(defun prop-unwrap (w)
   #+icsdebug(assert (prop-wrap? w))
  (wrap-address w))

(defstruct (state-wrap
	    (:include wrap)
	    (:predicate state-wrap?)
	    (:constructor make-state-wrap (address))
	    (:print-function
	     (lambda (p s k)
	       (declare (ignore k))
	       (format s "<#state: ~a>" (wrap-address p))))))

(defun state-wrap (value)
    #+icsdebug(assert (integerp value))
   (make-state-wrap value))

(defun state-unwrap (w)
   #+icsdebug(assert (state-wrap? w))
  (wrap-address w))


;; Check if ICS predicate holds

(defmacro holds (arg)
  `(plusp ,arg))


;; ICS-PVS error handling

(ff:defun-foreign-callable ics_error (fname msg)
  (error (format nil "~a: ~a" (excl:native-to-string fname)
		 (excl:native-to-string msg))))

(ff:def-foreign-call register_lisp_error_function (index))

;; PVS decision procedure interface

(defun ics-init (&optional full (verbose 0))
  (declare (ignore full))
  (declare (ignore verbose))
  (multiple-value-bind (dummy error)
      (ignore-errors (ics_caml_startup))
    (declare (ignore dummy))
    (cond (error
	   (setq *decision-procedures* (remove 'ics *decision-procedures*))
	   (pvs-message "Trouble loading ICS, so it is not available"))
	  (t (register_lisp_error_function
	      (nth-value 1 (ff:register-function `ics_error)))))))


(defun ics-current-context-pp ()
  (declare (special *dp-state*))
  (ics_context_pp (state-unwrap *dp-state*)))


(defun ics-empty-state ()
  (let ((empty (state-wrap (ics_context_empty))))
    (wrap-finalize! empty)
    empty))

(defun ics-d-consistent (value)
   #+icsdebug(assert (integerp value))
  (let ((state (state-wrap (ics_d_consistent value))))
    (wrap-finalize! state)
    state))
    
(defmethod ics-process (state (expr expr))
   #+icsdebug(assert (state-wrap? state))
  (let* ((atom (translate-to-ics expr))
	 (result (ics_process (state-unwrap state) (atom-unwrap atom))))
    (cond ((not (zerop (ics_is_consistent result)))
	   (ics-d-consistent result))
	  ((not (zerop (ics_is_inconsistent result)))
	   :unsat)
	  ((not (zerop (ics_is_redundant result)))
	   :valid))))

(defun ics-is-valid (state expr)
   #+icsdebug(assert (state-wrap? state))
   #+icsdebug(assert (expr? expr))
   (let ((atom (translate-to-ics expr)))
     #+icsdebug(assert (atom-wrap? atom))
     (eql (ics-process state atom) :valid)))

(defun ics-is-unsat (state expr)
   #+icsdebug(assert (state-wrap? state))
   (let ((atom (translate-to-ics expr)))
     #+icsdebug(assert (atom-wrap? atom))
     (eql (ics-process state atom) :unsat)))      

(defun ics-state-unchanged? (state1 state2)
    #+icsdebug(assert (state-wrap? state1))
    #+icsdebug(assert (state-wrap? state2))
   (zerop (ics_context_eq (state-unwrap state1) (state-unwrap state2))))

(defmethod ics-sat (state expr)
   #+icsdebug(assert (state-wrap? state))
   #+icsdebug(assert (expr? expr))
   (let ((prop (translate-prop-to-ics expr)))
     #+icsdebug(assert (prop-wrap? prop))
     (let ((result (ics_prop_sat (state-unwrap state) (prop-unwrap prop))))
       (if (not (zerop (ics_is_none result)))
	   :unsat
	 (let* ((assignment (ics_value_of result)))
	   (cons :sat assignment))))))

;; Return a unique name for an expression
	
(defun unique-name-ics (expr)
  (or (gethash expr *pvs-to-ics-symtab*)
      (progn
        ; (pvs-message "~%Abstract : ~a" expr)
	(let ((name (format nil "~a__~d"
			    (if (name-expr? expr) (symbol-name (id expr)) "new")
			    *unique-name-ics-counter*)))
	  (setf *unique-name-ics-counter* (1+ *unique-name-ics-counter*))
	  (setf (gethash expr *pvs-to-ics-symtab*) name)))))


;; Translating from PVS expressions to ICS terms

;; An atom is either an equality, disequality, an arithmetic
;; constraint, or some other expression of Boolean type

(defmethod translate-to-ics (expr)
  (or (gethash expr *pvs-to-ics-hash*)
      (let ((atom (translate-posatom-to-ics* expr)))
	 #+icsdebug(assert (integerp atom))
	(let ((wrapper (atom-wrap atom)))
	  (wrap-finalize! wrapper)
	  (pvs-to-ics-add-hash expr wrapper)
	  wrapper))))

(defmethod translate-posatom-to-ics* ((expr expr))
  "Fallthrough method: Boolean expressions 'b' are translated as 'b = true'"
  (let ((ics-term (translate-term-to-ics* expr)))
     #+icsdebug(assert (integerp ics-term))
    (ics_atom_mk_equal ics-term (ics_term_mk_true))))

(defmethod translate-posatom-to-ics* ((expr name-expr))
  (declare (special *true*))
  (declare (special *false*))
  (cond ((tc-eq expr *true*)
	 (ics_atom_mk_true))
	((tc-eq expr *false*)
	 (ics_atom_mk_false))
	(t
	 (call-next-method))))

(defmethod translate-posatom-to-ics* ((expr equation))
  (ics_atom_mk_equal (translate-term-to-ics* (args1 expr))
		     (translate-term-to-ics* (args2 expr))))

(defmethod translate-posatom-to-ics* ((expr disequation))
  (ics_atom_mk_diseq (translate-term-to-ics* (args1 expr))
		     (translate-term-to-ics* (args2 expr))))


(defmethod translate-posatom-to-ics* ((expr application))
  (let ((op (operator expr)))
    (if (not (name-expr? op))
	(call-next-method)
      (cond ((tc-eq op (greatereq-operator))
	     (ics_atom_mk_ge (translate-term-to-ics* (args1 expr))
			     (translate-term-to-ics* (args2 expr))))
	    ((tc-eq op (greater-operator))
	     (ics_atom_mk_gt (translate-term-to-ics* (args1 expr))
			     (translate-term-to-ics* (args2 expr))))
	    ((tc-eq op (less-operator))
	     (ics_atom_mk_lt (translate-term-to-ics* (args1 expr))
			     (translate-term-to-ics* (args2 expr))))
	    ((tc-eq op (lesseq-operator))
	     (ics_atom_mk_le (translate-term-to-ics* (args1 expr))
			     (translate-term-to-ics* (args2 expr))))
	    ((tc-eq op (integer_pred))
             (ics_atom_mk_true))  ; ignore for now
	     ; (ics_atom_mk_int (translate-term-to-ics* (args1 expr))))
	    ((or (tc-eq op (real_pred))
		 (tc-eq op (rational_pred)))
             (ics_atom_mk_true)) ; ignore for now
	     ; (ics_atom_mk_real (translate-term-to-ics* (args1 expr))))
	    ((tc-eq op (number-field_pred)) ; ignore
	     (ics_atom_mk_true))
	    (t
	     (call-next-method))))))

(defmethod translate-posatom-to-ics* ((expr negation))
  (cond ((tc-eq (operator expr) (integer_pred))
	 (ics_atom_mk_nonint (translate-term-to-ics* (args1 expr))))
	(t
	 (translate-negatom-to-ics* (args1 expr)))))

(defmethod translate-negatom-to-ics* ((expr expr))
  "Fallthrough method: Negations of Boolean expressions 'b' are translated as 'b = false'"
  (let ((ics-term (translate-term-to-ics* expr)))
    (ics_atom_mk_equal ics-term (ics_term_mk_false))))

(defmethod translate-negatom-to-ics* ((expr name-expr))
  (declare (special *true*))
  (declare (special *false*))
  (cond ((tc-eq expr *true*)
	 (ics_atom_mk_false))
	((tc-eq expr *false*)
	 (ics_atom_mk_true))
	(t
	 (call-next-method))))

(defmethod translate-negatom-to-ics* ((expr negation))
  (translate-posatom-to-ics* (args1 expr)))

(defmethod translate-negatom-to-ics* ((expr equation))
  (ics_atom_mk_diseq (translate-term-to-ics* (args1 expr))
		     (translate-term-to-ics* (args2 expr))))

(defmethod translate-negatom-to-ics* ((expr disequation))
  (ics_atom_mk_equal (translate-term-to-ics* (args1 expr))
		     (translate-term-to-ics* (args2 expr))))

(defmethod translate-negatom-to-ics* ((expr application))
  (let ((op (operator expr)))
    (if (not (name-expr? op))
	(call-next-method)
      (cond ((tc-eq op (greatereq-operator))
	     (ics_atom_mk_lt (translate-term-to-ics* (args1 expr))
			     (translate-term-to-ics* (args2 expr))))
	    ((tc-eq op (greater-operator))
	     (ics_atom_mk_le (translate-term-to-ics* (args1 expr))
			     (translate-term-to-ics* (args2 expr))))
	    ((tc-eq op (less-operator))
	     (ics_atom_mk_ge (translate-term-to-ics* (args1 expr))
			     (translate-term-to-ics* (args2 expr))))
	    ((tc-eq op (lesseq-operator))
	     (ics_atom_mk_gt (translate-term-to-ics* (args1 expr))
			     (translate-term-to-ics* (args2 expr))))
	    (t
	     (call-next-method))))))


(defmethod translate-term-to-ics* :around ((expr expr))
  (call-next-method))

(defmethod translate-term-to-ics* ((expr expr))
  (ics_term_mk_var (unique-name-ics expr)))

(defmethod translate-term-to-ics* ((expr name-expr))
  (declare (special *true*))
  (declare (special *false*))
  (cond ((tc-eq expr *true*)
	 (ics_term_mk_true))
	((tc-eq expr *false*)
	 (ics_term_mk_false))
	(t
	 (call-next-method))))

(defmethod translate-term-to-ics* ((expr number-expr))
  (ics_term_mk_num (q-of-number-expr expr)))

(defun q-of-number-expr (expr)
  (ics_num_of_string (write-to-string (number expr))))

(defmethod translate-term-to-ics* ((expr application))
  (let ((op (operator expr)))
    (cond ((tc-eq op (plus-operator))
	   (ics_term_mk_add (translate-term-to-ics* (args1 expr))
			     (translate-term-to-ics* (args2 expr))))
	  ((tc-eq op (difference-operator))
	   (ics_term_mk_sub (translate-term-to-ics* (args1 expr))
			    (translate-term-to-ics* (args2 expr))))
	  ((tc-eq op (unary-minus-operator))
	   (ics_term_mk_unary_minus (translate-term-to-ics* (args1 expr))))
	  ((tc-eq op (times-operator))
	   (translate-mult-to-ics* (args1 expr) (args2 expr)))
	  ((and *ics-nonlin*
		(tc-eq op (divides-operator)))
	   (ics_term_mk_div (translate-term-to-ics* (args1 expr))
			    (translate-term-to-ics* (args2 expr))))
	  (t
	   (let ((opterm (translate-term-to-ics* op))
		 (argterms (translate-term-list-to-ics* (arguments expr))))
	     (ics_term_mk_apply opterm argterms))))))


(defmethod translate-mult-to-ics* ((expr1 number-expr) (expr2 expr))
  (ics_term_mk_multq (q-of-number-expr expr1)
		     (translate-term-to-ics* expr2)))

(defmethod translate-mult-to-ics* ((expr1 expr) (expr2 number-expr))
  (ics_term_mk_multq (q-of-number-expr expr2)
		     (translate-term-to-ics* expr1)))

(defmethod translate-mult-to-ics* ((expr1 expr) (expr2 expr))
  (let ((term1 (translate-term-to-ics* expr1))
	(term2 (translate-term-to-ics* expr2)))
    (if *ics-nonlin*
	(ics_term_mk_mult term1 term2)
      (let ((mult (translate-term-to-ics* (times-operator)))
	    (args (ics_cons term1 (ics_cons term2 (ics_nil)))))
	(ics_term_mk_apply mult args)))))
      
	
(defmethod translate-term-to-ics* ((expr let-expr))
  (with-slots (operator argument) expr
    (let ((reduced-expr (substit (expression operator)
			  (pairlis-args (bindings operator)
					(argument* expr)))))
      (translate-term-to-ics* reduced-expr))))

(defmethod translate-term-to-ics* ((expr record-expr))
  (let ((exprs (mapcar #'expression (sort-assignments (assignments expr)))))
    (ics_term_mk_tuple (translate-term-list-to-ics* exprs))))

(defun sort-assignments (assignments)
  (sort (copy-list assignments)
	#'string-lessp
	:key #'(lambda (assignment) (id (caar (arguments assignment))))))

(defmethod translate-term-to-ics* ((expr tuple-expr))
  (ics_term_mk_tuple (translate-term-list-to-ics* (exprs expr))))
	
(defmethod translate-to-ics* ((expr coercion))
  (with-slots (operator argument) expr
    (let ((reduced-expr (substit (expression operator)
			  (pairlis-args (bindings operator)
					(argument* expr)))))
      (translate-term-to-ics* reduced-expr))))

(defun translate-term-list-to-ics* (exprs)
  (cond ((null exprs)
	 (ics_nil))
	((expr? exprs)
         (ics_cons (translate-term-to-ics* (ics_nil))))
	(t
	 (let ((trm (translate-term-to-ics* (car exprs))))
	   (ics_cons trm (translate-term-list-to-ics* (cdr exprs)))))))

(defmethod translate-term-to-ics* ((expr projection-application))
  (let* ((arg (argument expr))
	 (width (width-of (type arg)))
	 (index (1- (index expr))))
    (ics_term_mk_proj index width (translate-term-to-ics* arg))))

#+workinprogress
(defmethod translate-term-to-ics* ((expr injection-application))
  (let ((arg (translate-to-prove (argument expr)))
	(index (1- (index expr))))
    (ics_term_mk_inj index arg)))

#+workinprogress
(defmethod translate-term-to-ics* ((expr extraction-application))
  (let* ((arg (translate-to-prove (argument expr)))
	 (index (1- (index expr))))
    (ics_term_mk_out index arg)))

;#+workinprogress
;(defmethod translate-term-to-ics* ((expr injection?-application))
;  (let ((arg (translate-to-prove (argument expr))))
; (mk-funtype (type (argument expr)) (type expr)))
;	 (index (1- (index expr))))
;    (ics_term_mk_out index arg)))


(defmethod translate-term-to-ics* ((expr field-application))
  (with-slots (id argument type) expr
    (let* ((fields (fields (find-supertype (type argument))))
	   (pos (position id (sort-fields fields)
			  :test #'(lambda (x y) (eq x (id y)))))
	   (trm (translate-term-to-ics* argument)))
      (ics_term_mk_proj pos (length fields) trm))))

(defmethod width-of ((type tupletype))
  (length (types type)))

(defmethod width-of ((type subtype))
  (width-of (find-supertype type)))


;;; Update expressions
;;; Translate expressions of the form
;;; A WITH [ (0) := 1 ],
;;;    where A is an array of type int->int, into
;;; (apply int ARRAYSTORE A 0 1)
;;;
;;; f WITH [ (0,0) := 0],
;;;    where f is a function of type int,int->int into
;;; (APPLY int UPDATE f (0 0) 0)
;;;
;;; g WITH [ (0) := h, (1) (x,y) := 0, (1) (x,y)' := 1 ]
;;;    where g and h are functions of type
;;;    T = [function[int -> function[state[T0],state[T0] -> int]]
;;;
;;; This generates the form
;;;
;;; (apply function[state[T0],state[T0] -> int]
;;;        update
;;;        (apply function[state[T0],state[T0] -> int]
;;;               update
;;;               (apply function[state[T0],state[T0] -> int]
;;;                      update
;;;                      g (0) h)
;;;               (1) (apply int update g(1) (x y) 0))
;;;        (1) (apply int update g(1) (x' y') 1))


(defmethod translate-term-to-ics* ((expr update-expr))
  (translate-assignments-to-ics*
   (assignments expr)
   (translate-term-to-ics* (expression expr))
   (type expr)))

(defun translate-assignments-to-ics* (assigns trbasis type)
  (cond ((null assigns) trbasis)
	(t (translate-assignments-to-ics*
	    (cdr assigns)
	    (translate-assignment-to-ics* (car assigns) trbasis type)
	    type))))

(defun translate-assignment-to-ics* (assign trbasis type)
  (translate-assign-args-to-ics*
   (arguments assign)
   (expression assign)
   trbasis
   (find-supertype type)))

(defmethod translate-assign-args-to-ics* ((args null) value trbasis type)
  (declare (ignore trbasis))
  (declare (ignore type))
  (translate-term-to-ics* value))

(defmethod translate-assign-args-to-ics* ((args cons) value trbasis type)
  "args are of the form '((x y) (a) (1)' for 'f WITH [(x,y)`a`1 := ...]' "
  (let* ((sorted-fields (when (recordtype? type) (fields type)))
	 (position 
	  (typecase type
	   (recordtype (position (id (caar args)) sorted-fields :test #'eq :key #'id))
	   (tupletype (1- (number (caar args))))
	   (funtype (if (singleton? (car args))
		  (translate-term-to-ics* (caar args))
		(ics_term_mk_tuple (translate-term-list-to-ics* (car args)))))
	   (t 
	    (translate-term-to-ics* (caar args)))))
	 (next-trbasis-type     
	  (find-supertype 
	   (typecase type
	    (recordtype (type (find (id (caar args)) (fields type) :test #'eq :key #'id)))
	    (tupletype (nth (1- (number (caar args))) (types type)))
	    (funtype (range type))
	    (t (range (type (caar args)))))))
	 (next-trbasis
	  (typecase type
	   (recordtype
	    (make-ics-field-application
	     (mk-funtype type next-trbasis-type)
	     (position (id (caar args)) sorted-fields :test #'eq :key #'id)
	     (length (fields type))
	     trbasis))
	   (tupletype
	    (make-ics-projection-application
	     next-trbasis-type (number (caar args)) (length (types type)) trbasis))
	   (funtype (make-ics-assign-application
	       type
	       trbasis
	       (if (singleton? (car args))
		   (translate-term-to-ics* (caar args))
		 (ics_term_mk_tuple (translate-term-list-to-ics* (car args))))))
	   (t 
	    (make-ics-assign-application
	     (type (caar args))
	     (translate-term-to-ics* (caar args))
	     trbasis)))))
    (ics_term_mk_update
      trbasis 
      (ics_term_mk_num (ics_num_of_int position)) 
      (translate-assign-args-to-ics* (cdr args) value next-trbasis next-trbasis-type))))

(defun make-ics-field-application (field-accessor-type fieldnum length term)
  "Forget about the 'field-accessor-type' for now"
  (declare (ignore field-accessor-type))
   #+icsdebug(assert (integerp fieldnum))
   #+icsdebug(assert (integerp length))
  (ics_term_mk_proj fieldnum length term))

(defun make-ics-projection-application (type number length term)
  "Forget about the 'type' for now"
  (declare (ignore type))
   #+icsdebug(assert (integerp number))
   #+icsdebug(assert (integerp length))
  (ics_term_mk_proj (1- number) length term))

(defun make-ics-assign-application (fun-type term term-args)
  "Forget about the 'fun-type' for now"
  (declare (ignore fun-type))
  (ics_term_mk_select term term-args))


;; Translations for satisfiability solver

(defmethod translate-prop-to-ics (expr)
  (let* ((prop (translate-prop-to-ics* expr))
         (wrapper (prop-wrap prop)))
    (wrap-finalize! wrapper)
    wrapper))

(defmethod translate-prop-to-ics* ((expr expr))
  "Fallthrough method"
  (let ((wrapper (translate-to-ics expr)))
    (assert (not (null wrapper)))
    (ics_prop_mk_poslit (atom-unwrap wrapper))))

(defmethod translate-prop-to-ics* ((expr name-expr))
  (ics_prop_mk_var (ics_name_of_string (format nil "~s"  (id expr)))))

(defmethod translate-prop-to-ics* ((expr negation))
  (let ((trm1 (translate-prop-to-ics* (args1 expr))))
    (ics_prop_mk_neg trm1)))

(defmethod translate-prop-to-ics* ((expr conjunction))
  (let ((trm1 (translate-prop-to-ics* (args1 expr)))
	(trm2 (translate-prop-to-ics* (args2 expr))))
    (ics_prop_mk_conj (ics_cons trm1 (ics_cons trm2 (ics_nil))))))

(defmethod translate-prop-to-ics* ((expr disjunction))
  (let ((trm1 (translate-prop-to-ics* (args1 expr)))
	(trm2 (translate-prop-to-ics* (args2 expr))))
    (ics_prop_mk_disj (ics_cons trm1 (ics_cons trm2 (ics_nil))))))

(defmethod translate-prop-to-ics* ((expr implication))
  (let ((trm1 (translate-prop-to-ics* (args1 expr)))
	(trm2 (translate-prop-to-ics* (args2 expr))))
    (ics_prop_mk_disj (ics_cons (ics_prop_mk_neg trm1) (ics_cons trm2 (ics_nil))))))

(defmethod translate-prop-to-ics* ((expr iff-or-boolean-equation))
  (let ((trm1 (translate-prop-to-ics* (args1 expr)))
	(trm2 (translate-prop-to-ics* (args2 expr))))
    (ics_prop_mk_iff (ics_cons trm1 (ics_cons trm2 (ics_nil))))))

(defmethod translate-prop-to-ics* ((expr let-expr))
  (break "to do"))






