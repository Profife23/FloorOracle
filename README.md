# FloorOracle

I designed **FloorOracle** to serve as a high-fidelity, decentralized autonomous oracle and prediction engine specifically tailored for the NFT ecosystem. In the volatile world of digital collectibles, simple "spot price" reporting is often insufficient and dangerous for DeFi protocols. I built this contract to act as a sophisticated middleware that ingests raw market data and outputs refined, mathematically backed price forecasts.

By utilizing a multi-strategy approach—combining Exponential Moving Averages (EMA) with Simple Moving Averages (SMA) and adjusting for real-time market momentum—I have created a system that provides not just a price, but a "Confidence Score" that reflects the health and reliability of the current market trend.

---

## Table of Contents

1. Abstract and Technical Philosophy
2. Mathematical Framework
3. System Architecture
4. Detailed Logic: Private Functions
5. Detailed Logic: Public Governance Functions
6. Detailed Logic: Public Oracle & Prediction Functions
7. Detailed Logic: Read-Only Functions
8. Error Code Specification
9. Integration and Implementation Guide
10. Contribution and Developer Standards
11. Security and Risk Mitigation
12. Comprehensive MIT License

---

## Abstract and Technical Philosophy

I believe that the biggest hurdle for NFT-backed lending and derivatives is the "low liquidity manipulation" risk. To combat this, FloorOracle does not treat every data point equally. I engineered this contract to prioritize historical stability over sudden, irrational spikes.

I implemented a **Reputation-Based Data Ingestion** model. Oracles are not just whitelisted; they must maintain an active presence on-chain to build a reputation score. Furthermore, the contract employs an **Algorithmic Time Decay** mechanism. As time passes without a fresh data update, I programmatically dampen the predicted floor price to account for the increased uncertainty of stale data.

---

## Mathematical Framework

I have implemented two core statistical models within this Clarity contract to ensure price stability.

### 1. Exponential Moving Average (EMA)

The EMA is designed to be responsive to new trends while filtering out noise. I use a fixed `prediction-alpha` (20%) to determine the weight of the latest price.


### 2. Simple Moving Average (SMA)

To provide a counterbalance to the EMA, I maintain an SMA. In this implementation, I use a rolling calculation that acts as a stabilizer, preventing the EMA from over-reacting to short-term wash trading.

### 3. Confidence Scoring Algorithm

The Confidence Score () is a composite value derived from:

* **Freshness:**  decreases as `block-height` increases relative to the last update.
* **Consensus:**  decreases as the spread between EMA and SMA widens.
* **Volatility:**  is penalized by the absolute difference between the last two price points.

---

## System Architecture

I structured the contract into four distinct layers to ensure maximum security and gas efficiency:

1. **Data Persistence Layer:** Uses `define-map` structures for authorized oracles, project statistics, and historical price snapshots.
2. **Validation Layer:** A set of private functions that enforce authorization and data integrity before state changes occur.
3. **Computational Layer:** The "Engine" where the EMA, SMA, and confidence calculations are performed.
4. **Interface Layer:** The public-facing functions that allow oracles to submit data and users to query predictions.

---

## Detailed Logic: Private Functions

These functions are internal to the contract. I designed them to handle the "heavy lifting" and security checks that the public functions rely on.

* **`is-oracle (user principal)`**
I use this function as the primary gatekeeper. It queries the `authorized-oracles` map to verify if a caller is not only whitelisted but also marked as `active`. It returns a boolean.
* **`calculate-ema (current-price uint, prev-ema uint)`**
This is the core math utility. I implemented this using scaled integer arithmetic to simulate floating-point logic. It retrieves the `prediction-alpha`, performs the weighted multiplication, and returns the new EMA value.
* **`update-oracle-reputation (oracle principal)`**
Every time an oracle provides data, I invoke this function. It increments the `total-submissions` and `reputation-score`. I also update the `last-active-block` to ensure we can track which nodes are currently maintaining the network.

---

## Detailed Logic: Public Governance Functions

Only the `contract-owner` (the deployer) can execute these. I built these to give the protocol "knobs and dials" to adjust as the NFT market matures.

* **`add-oracle (oracle principal)`**
Adds a new address to the whitelist. I enforce a check to ensure the oracle doesn't already exist to prevent state bloat. It initializes the reputation stats to zero.
* **`remove-oracle (oracle principal)`**
Removes an oracle from the map. I designed this for rapid response in case an oracle node is compromised or providing malicious data.
* **`update-weights (new-ema-weight uint, new-sma-weight uint)`**
This allows the owner to change how the final prediction is weighted. For example, in a very stable market, I might set EMA to 80%. In a volatile market, I would set SMA to 80%. I included an `asserts!` to ensure the total weight always equals 100%.

---

## Detailed Logic: Public Oracle & Prediction Functions

These are the primary entry points for data flow and forecasting.

* **`submit-floor-price (project-id uint, price uint)`**
This is the data ingestion engine. When an oracle calls this, I perform several actions:
1. Validate the oracle's identity and activity status.
2. Calculate the new EMA.
3. Calculate the `trend-momentum` (the delta between this price and the last).
4. Update the `volatility-index`.
5. Store the price in a ring-buffer `price-history` for future advanced SMA analysis.


* **`generate-prediction (project-id uint)`**
This is the most complex function in the contract, exceeding 50 lines of logic. I designed it to:
1. Apply **Momentum-Adjustment**: Projects a price based on the current trend.
2. Apply **Volatility-Adjustment**: Forces the prediction closer to the SMA if the market is erratic.
3. Execute **Time Decay**: If the data is more than 100 blocks old, I automatically slash the prediction by 20% to protect against stale-price exploitation.
4. Generate a **Confidence Score**: Based on spread divergence and data age.



---

## Detailed Logic: Read-Only Functions

These functions do not cost gas and are used by front-ends and other contracts to observe the state.

* **`get-project-stats (project-id uint)`**
Returns a comprehensive tuple of the project's current state, including EMA, SMA, momentum, and the block height of the last update.
* **`get-last-prediction (project-id uint)`**
Retrieves the most recently cached prediction. This is useful for UIs that don't need to trigger a fresh (and computationally expensive) prediction calculation.
* **`get-oracle-reputation (oracle principal)`**
I provide this so that the community can audit which oracles are the most reliable. It returns the reputation score and activity history of any given principal.

---

## Error Code Specification

I have standardized error reporting to ensure that integrating developers can easily handle exceptions:

| Error Code | Name | Logic Trigger |
| --- | --- | --- |
| `u100` | `err-owner-only` | Unauthorized governance attempt. |
| `u101` | `err-not-authorized` | Non-whitelisted caller attempting to submit data. |
| `u102` | `err-invalid-price` | Submission of a zero or negative price. |
| `u103` | `err-project-not-found` | Requesting data for a project with no history. |
| `u105` | `err-invalid-weight` | Governance weights do not sum to 100%. |
| `u106` | `err-oracle-exists` | Attempting to add an existing oracle. |

---

## Integration and Implementation Guide

For developers looking to integrate FloorOracle into their lending platforms, I recommend the following workflow:

1. **Check Confidence:** Always check the `confidence-score` before liquidating an NFT. If the score is below 50, I suggest pausing liquidations as the price may be manipulated.
2. **Project ID Mapping:** Maintain an off-chain mapping of NFT contract addresses to the `project-id` used in this contract.
3. **Event Listening:** Listen for the `prediction-generated` event to update your platform's UI in real-time as oracles submit new data.

---

## Security and Risk Mitigation

I have implemented several safeguards to ensure the integrity of the price feed:

* **Overflow Protection:** All calculations use Clarity's checked arithmetic to prevent integer overflows.
* **Stale Data Dampening:** By penalizing prices that haven't been updated within 100 blocks, I mitigate the risk of "Oracle Lag" during market crashes.
* **Multi-Strategy Divergence:** If Strategy A (EMA) and Strategy B (SMA) diverge too significantly, the confidence score drops, alerting users that the market is in a state of price discovery or manipulation.

---

## Comprehensive MIT License

**Copyright (c) 2026 FloorOracle Contributors**

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---
