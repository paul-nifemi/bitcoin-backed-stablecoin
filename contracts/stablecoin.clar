;; Title: Bitcoin-Backed Stablecoin - Decentralized Bitcoin-Backed Stablecoin Protocol
;; Summary: Multi-collateral CDP system enabling STX and xBTC holders to mint USDX stablecoins
;; Description: 
;; Bitcoin-Backed Stablecoin is a decentralized finance protocol that allows users to deposit STX and xBTC 
;; as collateral to mint USDX, a USD-pegged stablecoin. The protocol features automated 
;; liquidation mechanisms, real-time price oracles, and robust risk management to maintain 
;; the stability of the USDX peg while providing capital efficiency for Bitcoin ecosystem users.
;;
;; Key Features:
;; - Multi-asset collateral support (STX, xBTC)
;; - Over-collateralized lending with configurable ratios
;; - Automated liquidation engine for risk management
;; - Decentralized price oracle system
;; - SIP-010 compliant USDX stablecoin token

;; CONSTANTS AND CONFIGURATION

(define-constant CONTRACT_OWNER tx-sender)

;; Error Codes
(define-constant ERR_NOT_AUTHORIZED (err u1000))
(define-constant ERR_VAULT_NOT_FOUND (err u1001))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u1002))
(define-constant ERR_VAULT_UNDERCOLLATERALIZED (err u1003))
(define-constant ERR_LIQUIDATION_NOT_ALLOWED (err u1004))
(define-constant ERR_INVALID_AMOUNT (err u1005))
(define-constant ERR_ORACLE_PRICE_STALE (err u1006))
(define-constant ERR_MINIMUM_COLLATERAL_RATIO (err u1007))
(define-constant ERR_VAULT_ALREADY_EXISTS (err u1008))
(define-constant ERR_INSUFFICIENT_USDX_BALANCE (err u1009))
(define-constant ERR_TRANSFER_FAILED (err u1010))

;; Protocol Parameters
(define-constant LIQUIDATION_RATIO u150) ;; 150% - liquidation threshold
(define-constant MINIMUM_COLLATERAL_RATIO u200) ;; 200% - minimum for new vaults
(define-constant LIQUIDATION_PENALTY u110) ;; 10% liquidation penalty
(define-constant STABILITY_FEE_RATE u2) ;; 2% annual stability fee
(define-constant MAX_PRICE_AGE u3600) ;; 1 hour max price staleness
(define-constant MAX_VAULTS_PER_USER u10) ;; Maximum vaults per user
(define-constant MAX_MINT_AMOUNT u1000000000000) ;; Maximum USDX mint per transaction

;; DATA STRUCTURES

;; Vault Data Structure
(define-map vaults
  { vault-id: uint }
  {
    owner: principal,
    stx-collateral: uint,
    xbtc-collateral: uint,
    debt: uint,
    last-update: uint,
    is-active: bool,
  }
)

;; User Vault Tracking
(define-map user-vaults
  { user: principal }
  { vault-ids: (list 10 uint) }
)

;; Oracle Price Feeds
(define-map price-feeds
  { asset: (string-ascii 10) }
  {
    price: uint,
    timestamp: uint,
    confidence: uint,
  }
)

;; Protocol State Variables
(define-data-var total-vaults uint u0)
(define-data-var total-debt uint u0)
(define-data-var total-stx-collateral uint u0)
(define-data-var total-xbtc-collateral uint u0)

;; Access Control
(define-map authorized-liquidators
  principal
  bool
)
(define-map oracle-operators
  principal
  bool
)

;; USDX STABLECOIN TOKEN (SIP-010 COMPLIANT)

(define-fungible-token usdx)

(define-data-var token-name (string-ascii 32) "BitVault USD")
(define-data-var token-symbol (string-ascii 10) "USDX")
(define-data-var token-uri (optional (string-utf8 256)) none)
(define-data-var token-decimals uint u6)

;; SIP-010 Standard Functions
(define-read-only (get-name)
  (ok (var-get token-name))
)

(define-read-only (get-symbol)
  (ok (var-get token-symbol))
)

(define-read-only (get-decimals)
  (ok (var-get token-decimals))
)

(define-read-only (get-balance (who principal))
  (ok (ft-get-balance usdx who))
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply usdx))
)

(define-read-only (get-token-uri)
  (ok (var-get token-uri))
)

(define-public (transfer
    (amount uint)
    (from principal)
    (to principal)
    (memo (optional (buff 34)))
  )
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (or (is-eq from tx-sender) (is-eq from contract-caller))
      ERR_NOT_AUTHORIZED
    )
    (asserts! (not (is-eq from to)) ERR_INVALID_AMOUNT)
    (ft-transfer? usdx amount from to)
  )
)

;; ORACLE SYSTEM

(define-public (set-oracle-operator
    (operator principal)
    (authorized bool)
  )
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq operator tx-sender)) ERR_INVALID_AMOUNT)
    (ok (map-set oracle-operators operator authorized))
  )
)

(define-public (update-price
    (asset (string-ascii 10))
    (price uint)
    (confidence uint)
  )
  (begin
    (asserts! (default-to false (map-get? oracle-operators tx-sender))
      ERR_NOT_AUTHORIZED
    )
    (asserts! (> price u0) ERR_INVALID_AMOUNT)
    (asserts! (and (>= confidence u1) (<= confidence u100)) ERR_INVALID_AMOUNT)
    (asserts! (> (len asset) u0) ERR_INVALID_AMOUNT)
    (ok (map-set price-feeds { asset: asset } {
      price: price,
      timestamp: stacks-block-height,
      confidence: confidence,
    }))
  )
)

(define-read-only (get-price (asset (string-ascii 10)))
  (let ((price-data (map-get? price-feeds { asset: asset })))
    (match price-data
      feed (if (< (- stacks-block-height (get timestamp feed)) MAX_PRICE_AGE)
        (ok (get price feed))
        ERR_ORACLE_PRICE_STALE
      )
      ERR_ORACLE_PRICE_STALE
    )
  )
)

;; VAULT MANAGEMENT

(define-public (create-vault
    (stx-amount uint)
    (xbtc-amount uint)
  )
  (let (
      (vault-id (+ (var-get total-vaults) u1))
      (stx-price (unwrap! (get-price "STX") ERR_ORACLE_PRICE_STALE))
      (xbtc-price (unwrap! (get-price "xBTC") ERR_ORACLE_PRICE_STALE))
      (total-collateral-value (+ (* stx-amount stx-price) (* xbtc-amount xbtc-price)))
      (user-vaults-list (default-to (list)
        (get vault-ids (map-get? user-vaults { user: tx-sender }))
      ))
    )
    (asserts! (> stx-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= xbtc-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (< vault-id u1000000) ERR_INVALID_AMOUNT)
    (asserts! (is-none (map-get? vaults { vault-id: vault-id }))
      ERR_VAULT_ALREADY_EXISTS
    )
    ;; Transfer STX collateral to contract
    (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))
    ;; Create new vault
    (map-set vaults { vault-id: vault-id } {
      owner: tx-sender,
      stx-collateral: stx-amount,
      xbtc-collateral: xbtc-amount,
      debt: u0,
      last-update: stacks-block-height,
      is-active: true,
    })
    ;; Update user vault list
    (map-set user-vaults { user: tx-sender } { vault-ids: (unwrap! (as-max-len? (append user-vaults-list vault-id) u10)
      ERR_INVALID_AMOUNT
    ) }
    )
    ;; Update protocol statistics
    (var-set total-vaults vault-id)
    (var-set total-stx-collateral (+ (var-get total-stx-collateral) stx-amount))
    (var-set total-xbtc-collateral
      (+ (var-get total-xbtc-collateral) xbtc-amount)
    )
    (ok vault-id)
  )
)

(define-public (add-collateral
    (vault-id uint)
    (stx-amount uint)
    (xbtc-amount uint)
  )
  (let ((vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR_VAULT_NOT_FOUND)))
    (asserts! (> vault-id u0) ERR_INVALID_AMOUNT)
    (asserts! (is-eq (get owner vault) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active vault) ERR_VAULT_NOT_FOUND)
    (asserts! (> stx-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= xbtc-amount u0) ERR_INVALID_AMOUNT)
    ;; Transfer additional STX collateral
    (try! (stx-transfer? stx-amount tx-sender (as-contract tx-sender)))
    ;; Update vault collateral
    (map-set vaults { vault-id: vault-id }
      (merge vault {
        stx-collateral: (+ (get stx-collateral vault) stx-amount),
        xbtc-collateral: (+ (get xbtc-collateral vault) xbtc-amount),
        last-update: stacks-block-height,
      })
    )
    ;; Update protocol statistics
    (var-set total-stx-collateral (+ (var-get total-stx-collateral) stx-amount))
    (var-set total-xbtc-collateral
      (+ (var-get total-xbtc-collateral) xbtc-amount)
    )
    (ok true)
  )
)

(define-public (mint-usdx
    (vault-id uint)
    (amount uint)
  )
  (let (
      (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
      (stx-price (unwrap! (get-price "STX") ERR_ORACLE_PRICE_STALE))
      (xbtc-price (unwrap! (get-price "xBTC") ERR_ORACLE_PRICE_STALE))
      (collateral-value (+ (* (get stx-collateral vault) stx-price)
        (* (get xbtc-collateral vault) xbtc-price)
      ))
      (new-debt (+ (get debt vault) amount))
      (collateral-ratio (/ (* collateral-value u100) new-debt))
    )
    (asserts! (> vault-id u0) ERR_INVALID_AMOUNT)
    (asserts! (is-eq (get owner vault) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active vault) ERR_VAULT_NOT_FOUND)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (< amount MAX_MINT_AMOUNT) ERR_INVALID_AMOUNT)
    (asserts! (>= collateral-ratio MINIMUM_COLLATERAL_RATIO)
      ERR_MINIMUM_COLLATERAL_RATIO
    )
    ;; Mint USDX tokens to user
    (try! (ft-mint? usdx amount tx-sender))
    ;; Update vault debt
    (map-set vaults { vault-id: vault-id }
      (merge vault {
        debt: new-debt,
        last-update: stacks-block-height,
      })
    )
    ;; Update protocol statistics
    (var-set total-debt (+ (var-get total-debt) amount))
    (ok true)
  )
)

(define-public (burn-usdx
    (vault-id uint)
    (amount uint)
  )
  (let (
      (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
      (user-balance (ft-get-balance usdx tx-sender))
    )
    (asserts! (> vault-id u0) ERR_INVALID_AMOUNT)
    (asserts! (is-eq (get owner vault) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active vault) ERR_VAULT_NOT_FOUND)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= user-balance amount) ERR_INSUFFICIENT_USDX_BALANCE)
    (asserts! (>= (get debt vault) amount) ERR_INVALID_AMOUNT)
    ;; Burn USDX tokens from user
    (try! (ft-burn? usdx amount tx-sender))
    ;; Reduce vault debt
    (map-set vaults { vault-id: vault-id }
      (merge vault {
        debt: (- (get debt vault) amount),
        last-update: stacks-block-height,
      })
    )
    ;; Update protocol statistics
    (var-set total-debt (- (var-get total-debt) amount))
    (ok true)
  )
)

(define-public (withdraw-collateral
    (vault-id uint)
    (stx-amount uint)
  )
  (let (
      (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
      (stx-price (unwrap! (get-price "STX") ERR_ORACLE_PRICE_STALE))
      (xbtc-price (unwrap! (get-price "xBTC") ERR_ORACLE_PRICE_STALE))
      (remaining-stx (- (get stx-collateral vault) stx-amount))
      (remaining-collateral-value (+ (* remaining-stx stx-price) (* (get xbtc-collateral vault) xbtc-price)))
      (debt (get debt vault))
    )
    (asserts! (> vault-id u0) ERR_INVALID_AMOUNT)
    (asserts! (is-eq (get owner vault) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active vault) ERR_VAULT_NOT_FOUND)
    (asserts! (> stx-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (get stx-collateral vault) stx-amount)
      ERR_INSUFFICIENT_COLLATERAL
    )
    ;; Check collateral ratio if debt exists
    (if (> debt u0)
      (asserts!
        (>= (/ (* remaining-collateral-value u100) debt) MINIMUM_COLLATERAL_RATIO)
        ERR_MINIMUM_COLLATERAL_RATIO
      )
      true
    )
    ;; Transfer collateral back to user
    (try! (as-contract (stx-transfer? stx-amount tx-sender (get owner vault))))
    ;; Update vault
    (map-set vaults { vault-id: vault-id }
      (merge vault {
        stx-collateral: remaining-stx,
        last-update: stacks-block-height,
      })
    )
    ;; Update protocol statistics
    (var-set total-stx-collateral (- (var-get total-stx-collateral) stx-amount))
    (ok true)
  )
)

;; LIQUIDATION ENGINE

(define-public (set-liquidator
    (liquidator principal)
    (authorized bool)
  )
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq liquidator tx-sender)) ERR_INVALID_AMOUNT)
    (ok (map-set authorized-liquidators liquidator authorized))
  )
)

(define-read-only (calculate-health-factor (vault-id uint))
  (match (map-get? vaults { vault-id: vault-id })
    vault (match (get-price "STX")
      stx-price (match (get-price "xBTC")
        xbtc-price (let (
            (collateral-value (+ (* (get stx-collateral vault) stx-price)
              (* (get xbtc-collateral vault) xbtc-price)
            ))
            (debt (get debt vault))
          )
          (if (is-eq debt u0)
            (ok u999999) ;; Infinite health factor for no debt
            (ok (/ (* collateral-value u100) debt))
          )
        )
        stx-err
        ERR_ORACLE_PRICE_STALE
      )
      xbtc-err
      ERR_ORACLE_PRICE_STALE
    )
    ERR_VAULT_NOT_FOUND
  )
)

(define-public (liquidate-vault (vault-id uint))
  (let (
      (vault (unwrap! (map-get? vaults { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
      (health-factor (unwrap! (calculate-health-factor vault-id) ERR_ORACLE_PRICE_STALE))
      (debt (get debt vault))
      (stx-collateral (get stx-collateral vault))
      (xbtc-collateral (get xbtc-collateral vault))
      (liquidation-amount (/ (* debt LIQUIDATION_PENALTY) u100))
    )
    (asserts! (default-to false (map-get? authorized-liquidators tx-sender))
      ERR_NOT_AUTHORIZED
    )
    (asserts! (get is-active vault) ERR_VAULT_NOT_FOUND)
    (asserts! (< health-factor LIQUIDATION_RATIO) ERR_LIQUIDATION_NOT_ALLOWED)
    (asserts! (>= (ft-get-balance usdx tx-sender) debt)
      ERR_INSUFFICIENT_USDX_BALANCE
    )
    ;; Burn liquidator's USDX to cover debt
    (try! (ft-burn? usdx debt tx-sender))
    ;; Calculate collateral distribution to liquidator
    (let (
        (stx-to-liquidator (/ (* stx-collateral liquidation-amount) debt))
        (xbtc-to-liquidator (/ (* xbtc-collateral liquidation-amount) debt))
      )
      ;; Transfer STX collateral to liquidator
      (try! (as-contract (stx-transfer? stx-to-liquidator tx-sender tx-sender)))
      ;; Deactivate vault and update collateral
      (map-set vaults { vault-id: vault-id }
        (merge vault {
          debt: u0,
          stx-collateral: (- stx-collateral stx-to-liquidator),
          xbtc-collateral: (- xbtc-collateral xbtc-to-liquidator),
          is-active: false,
          last-update: stacks-block-height,
        })
      )
      ;; Update protocol statistics
      (var-set total-debt (- (var-get total-debt) debt))
      (var-set total-stx-collateral
        (- (var-get total-stx-collateral) stx-to-liquidator)
      )
      (var-set total-xbtc-collateral
        (- (var-get total-xbtc-collateral) xbtc-to-liquidator)
      )
      (ok true)
    )
  )
)

;; READ-ONLY FUNCTIONS

(define-read-only (get-vault (vault-id uint))
  (map-get? vaults { vault-id: vault-id })
)

(define-read-only (get-user-vaults (user principal))
  (map-get? user-vaults { user: user })
)

(define-read-only (get-protocol-stats)
  {
    total-vaults: (var-get total-vaults),
    total-debt: (var-get total-debt),
    total-stx-collateral: (var-get total-stx-collateral),
    total-xbtc-collateral: (var-get total-xbtc-collateral),
    total-usdx-supply: (ft-get-supply usdx),
  }
)

(define-read-only (is-vault-safe (vault-id uint))
  (match (calculate-health-factor vault-id)
    health-factor (ok (>= health-factor LIQUIDATION_RATIO))
    error (err error)
  )
)

(define-read-only (get-liquidation-ratio)
  (ok LIQUIDATION_RATIO)
)

(define-read-only (get-minimum-collateral-ratio)
  (ok MINIMUM_COLLATERAL_RATIO)
)

;; ADMIN FUNCTIONS

(define-public (emergency-shutdown)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    ;; Emergency shutdown implementation would go here
    (ok true)
  )
)

;; INITIALIZATION

;; Initialize contract owner as oracle operator
(map-set oracle-operators CONTRACT_OWNER true) 
;; Initialize price feeds with placeholder values
(map-set price-feeds { asset: "STX" } {
  price: u1000000, ;; $1.00 in micro-units
  timestamp: stacks-block-height,
  confidence: u95,
}) 
(map-set price-feeds { asset: "xBTC" } {
  price: u100000000000, ;; $100,000 in micro-units
  timestamp: stacks-block-height,
  confidence: u95,
})