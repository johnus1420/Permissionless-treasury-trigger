;; =====================================================
;; PermissionlessTreasuryTrigger
;; Execute pre-approved treasury actions permissionlessly
;; =====================================================

;; -----------------------------
;; Data Variables
;; -----------------------------

(define-data-var admin principal tx-sender)
(define-data-var paused bool false)
(define-data-var next-action-id uint u0)

;; -----------------------------
;; Data Maps
;; -----------------------------

(define-map actions
  uint
  {
    recipient: principal,
    amount: uint,
    execute-after: uint,
    executed: bool
  }
)

;; -----------------------------
;; Errors
;; -----------------------------

(define-constant ERR-PAUSED (err u100))
(define-constant ERR-NOT-AUTHORIZED (err u101))
(define-constant ERR-NOT-READY (err u102))
(define-constant ERR-ALREADY-EXECUTED (err u103))
(define-constant ERR-NOT-FOUND (err u104))

;; -----------------------------
;; Helpers
;; -----------------------------

(define-read-only (is-admin)
  (is-eq tx-sender (var-get admin))
)

;; -----------------------------
;; Action Registration
;; -----------------------------

(define-public (register-action (recipient principal) (amount uint) (execute-after uint))
  (begin
    (asserts! (is-admin) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-NOT-READY)

    (let ((id (var-get next-action-id)))
      (map-set actions id {
        recipient: recipient,
        amount: amount,
        execute-after: execute-after,
        executed: false
      })
      (var-set next-action-id (+ id u1))
      (ok id)
    )
  )
)

;; -----------------------------
;; Permissionless Execution
;; -----------------------------

(define-public (execute-action (action-id uint))
  (begin
    ;; Fix 1: Corrected pause check
    (asserts! (not (var-get paused)) ERR-PAUSED)

    (let ((action (map-get? actions action-id)))
      (match action a
        (begin
          (asserts! (not (get executed a)) ERR-ALREADY-EXECUTED)
          ;; Note: In Clarity 1/2 use block-height. In Clarity 3+, stacks-block-height.
          (asserts! (>= stacks-block-height (get execute-after a)) ERR-NOT-READY)

          ;; mark executed BEFORE the transfer to prevent re-entrancy (best practice)
          (map-set actions action-id (merge a { executed: true }))

          (let (
            (recipient (get recipient a))
            (amount (get amount a))
          )
            ;; Fix 2: Wrap the as-contract correctly. 
            ;; We need to send from the contract to the recipient.
            (as-contract (stx-transfer? amount tx-sender recipient))
          )
        )
        ERR-NOT-FOUND ;; This is for the Option match (4 args)
      )
    )
  )
)

;; -----------------------------
;; Admin Controls
;; -----------------------------

(define-public (pause (flag bool))
  (begin
    (asserts! (is-admin) ERR-NOT-AUTHORIZED)
    (var-set paused flag)
    (ok true)
  )
)

;; -----------------------------
;; Read-only Views
;; -----------------------------

(define-read-only (get-action (action-id uint))
  (map-get? actions action-id)
)

(define-read-only (get-next-action-id)
  (var-get next-action-id)
)