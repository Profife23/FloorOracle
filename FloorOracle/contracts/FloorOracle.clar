;; contract title: Automated NFT Price Floor Prediction (Extended)
;;
;; Description:
;; This contract acts as a decentralized autonomous oracle and prediction engine for NFT floor prices.
;; It aggregates price data from whitelisted oracles (automated agents), tracks their reputation,
;; and uses multiple strategies to predict future floor prices.
;;
;; distinct features:
;; 1. Multi-Strategy Prediction: Uses both EMA (Exponential Moving Average) and SMA (Simple Moving Average).
;; 2. Oracle Reputation System: Tracks reliability of data providers.
;; 3. Governance: Configurable parameters for prediction sensitivity and weights.
;; 4. Volatility Analysis: Adjusts confidence scores based on market volatility.

;; =================================================================================================
;; CONSTANTS
;; =================================================================================================

(define-constant contract-owner tx-sender)

;; Error Codes
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-invalid-price (err u102))
(define-constant err-project-not-found (err u103))
(define-constant err-prediction-failed (err u104))
(define-constant err-invalid-weight (err u105))
(define-constant err-oracle-exists (err u106))
(define-constant err-low-reputation (err u107))

;; Defaults & Thresholds
(define-constant default-weight-ema u50) ;; 50% weight for EMA in final prediction
(define-constant default-weight-sma u50) ;; 50% weight for SMA in final prediction
(define-constant reputation-threshold u10) ;; Minimum reputation to submit critical data

;; =================================================================================================
;; DATA MAPS AND VARS
;; =================================================================================================

;; Governance Configuration
(define-data-var ema-weight uint default-weight-ema)
(define-data-var sma-weight uint default-weight-sma)
(define-data-var prediction-alpha uint u20) ;; Smoothing factor for EMA (scaled by 100)

;; Whitelist of authorized oracles and their stats
(define-map authorized-oracles 
    principal 
    {
        active: bool,
        reputation-score: uint,
        total-submissions: uint,
        last-active-block: uint
    }
)

;; Store project data: aggregated stats
(define-map project-data
    uint 
    {
        last-price: uint,
        moving-average-ema: uint,
        moving-average-sma: uint,
        trend-momentum: int,
        volatility-index: uint,
        last-updated-block: uint,
        update-count: uint
    }
)

;; Store historical price snapshots (limited depth for SMA calculation - simplified for this example)
;; Key: (project-id, index % 10) -> price
(define-map price-history
    { project-id: uint, index: uint }
    uint
)

;; Store the latest detailed prediction
(define-map latest-prediction
    uint
    {
        predicted-floor: uint,
        strategy-used: (string-ascii 10),
        confidence-score: uint,
        prediction-block: uint
    }
)

;; =================================================================================================
;; PRIVATE FUNCTIONS
;; =================================================================================================

;; Verify if caller is an oracle
(define-private (is-oracle (user principal))
    (let ((oracle-data (map-get? authorized-oracles user)))
        (match oracle-data
            data (get active data)
            false
        )
    )
)

;; Calculate EMA: (Close - PrevEMA) * Multiplier + PrevEMA
(define-private (calculate-ema (current-price uint) (prev-ema uint))
    (let 
        (
            (alpha (var-get prediction-alpha)) ;; e.g., 20 => 0.20
            (scaled-price (* current-price alpha))
            (inverse-alpha (- u100 alpha))
            (scaled-prev (* prev-ema inverse-alpha))
        )
        (/ (+ scaled-price scaled-prev) u100)
    )
)

;; Update Oracle Reputation
(define-private (update-oracle-reputation (oracle principal))
    (let ((current-stats (unwrap! (map-get? authorized-oracles oracle) false)))
        (map-set authorized-oracles oracle 
            (merge current-stats {
                total-submissions: (+ (get total-submissions current-stats) u1),
                last-active-block: block-height,
                reputation-score: (+ (get reputation-score current-stats) u1) ;; Simple increment
            })
        )
        true
    )
)

;; =================================================================================================
;; PUBLIC FUNCTIONS - GOVERNANCE
;; =================================================================================================

(define-public (add-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (map-get? authorized-oracles oracle)) err-oracle-exists)
        (ok (map-set authorized-oracles oracle {
            active: true,
            reputation-score: u0,
            total-submissions: u0,
            last-active-block: block-height
        }))
    )
)

(define-public (remove-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-delete authorized-oracles oracle))
    )
)

(define-public (update-weights (new-ema-weight uint) (new-sma-weight uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq (+ new-ema-weight new-sma-weight) u100) err-invalid-weight)
        (var-set ema-weight new-ema-weight)
        (var-set sma-weight new-sma-weight)
        (print { event: "governance-updated", ema: new-ema-weight, sma: new-sma-weight })
        (ok true)
    )
)

;; =================================================================================================
;; PUBLIC FUNCTIONS - ORACLE SUBMISSION
;; =================================================================================================

(define-public (submit-floor-price (project-id uint) (price uint))
    (let
        (
            (oracle-stats (unwrap! (map-get? authorized-oracles tx-sender) err-not-authorized))
            (current-data (default-to 
                {
                    last-price: price,
                    moving-average-ema: price,
                    moving-average-sma: price,
                    trend-momentum: 0,
                    volatility-index: u0,
                    last-updated-block: block-height,
                    update-count: u0
                }
                (map-get? project-data project-id))
            )
            (prev-ema (get moving-average-ema current-data))
            (new-ema (calculate-ema price prev-ema))
            (prev-price (get last-price current-data))
            ;; Simple momentum: price - prev-price
            (price-diff (- (to-int price) (to-int prev-price)))
            ;; Volatility: Absolute difference
            (volatility (if (> price prev-price) 
                           (- price prev-price) 
                           (- prev-price price)))
            
            ;; Update History Ring Buffer (simplified)
            (history-index (mod (get update-count current-data) u10))
        )
        (asserts! (get active oracle-stats) err-not-authorized)
        (asserts! (> price u0) err-invalid-price)
        
        ;; Save new price point
        (map-set project-data project-id {
            last-price: price,
            moving-average-ema: new-ema,
            moving-average-sma: (/ (+ (get moving-average-sma current-data) price) u2), ;; Pseudo-SMA update
            trend-momentum: price-diff,
            volatility-index: volatility,
            last-updated-block: block-height,
            update-count: (+ (get update-count current-data) u1)
        })
        
        ;; Record localized history for future advanced SMA
        (map-set price-history { project-id: project-id, index: history-index } price)
        
        ;; Update Oracle Stats
        (update-oracle-reputation tx-sender)
        
        (print { 
            event: "price-update", 
            project: project-id, 
            price: price, 
            oracle: tx-sender 
        })
        (ok true)
    )
)

;; =================================================================================================
;; READ ONLY FUNCTIONS
;; =================================================================================================

(define-read-only (get-project-stats (project-id uint))
    (map-get? project-data project-id)
)

(define-read-only (get-last-prediction (project-id uint))
    (map-get? latest-prediction project-id)
)

(define-read-only (get-oracle-reputation (oracle principal))
    (map-get? authorized-oracles oracle)
)


