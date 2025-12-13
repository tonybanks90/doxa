# Doxa Migration: LMSR → Bonding Curve with Parimutuel Payouts

## 🎯 Executive Summary

This document identifies the gaps between the **current LMSR-based implementation** and the **target bonding curve prediction market** described in `target.md`. The goal is to migrate to a system with:
- Independent linear bonding curves per outcome
- **No selling** (buy-only until resolution)
- Parimutuel payouts where winners get stake back + proportional share of losing pools

---

## ✅ E2E Test Results (2025-12-09)

| Component | Status | Notes |
|-----------|--------|-------|
| MarketFactory deployment | ✅ Pass | Creates ICRC-151 ledger with YES/NO tokens |
| Vault deployment | ✅ Pass | Registers markets, provides subaccounts |
| MarketTrade deployment | ✅ Pass | Registers binary market with vault |
| Market creation | ✅ Pass | Binary market #1 created with bonding curves |
| Bonding curves visible | ✅ Pass | yesCurve/noCurve with basePrice=1000, priceSlope=50 |
| sellTokens disabled | ✅ Pass | Returns "Selling is not supported" error |
| buyTokens slippage | ✅ Pass | Detects 9900% price increase correctly |
| buyTokens execution | ✅ Pass | Reaches vault interaction (fails on ckBTC as expected) |

---

## 🔴 Critical Gaps to Address

### 1. **Pricing Model: LMSR → Bonding Curve**

**Current (LMSR):**
```motoko
// Uses cost function: C = b * ln(e^(qYes/b) + e^(qNo/b))
private func costFunction(qYes : Float, qNo : Float, b : Float) : Float
private func calculatePrice(qYes : Float, qNo : Float, b : Float, outcome : BinaryToken) : Float
```

**Target (Bonding Curve):**
```
Price = basePrice + (priceSlope × currentSupply)
Cost for n shares = n × (basePrice + priceSlope × (currentSupply + n/2))
```

**Action Required:**
- [ ] Replace LMSR math functions with linear bonding curve formulas
- [ ] Add `basePrice` and `priceSlope` parameters to market config
- [ ] Each outcome (YES/NO) should have **independent** pricing curves

---

### 2. **Selling Must Be Disabled**

**Current:** `sellTokens()` function exists and works

**Target:** 
> "Selling is not supported in bonding curve markets. Positions are locked until market resolution."

**Action Required:**
- [ ] Modify `sellTokens()` to return error for bonding curve markets
- [ ] Or remove selling entirely and add clear error message

---

### 3. **Missing: Holder Stake Tracking**

**Current:** Tracks `balance` per user (Float)
```motoko
type HolderBalance = {
  user : Principal;
  balance : Float;
};
```

**Target:** Must track `totalPaid` (satoshis invested) per user per outcome
```motoko
type HolderPosition = {
  shares : Nat64;
  totalPaid : Nat64;  // ← MISSING
  avgPrice : Float;   // ← MISSING  
};
```

**Action Required:**
- [ ] Extend holder tracking to include `totalPaid` per outcome
- [ ] Track positions separately for YES and NO outcomes
- [ ] Store as: `marketId → outcome → principal → HolderPosition`

---

### 4. **Missing: Pool Balance Tracking**

**Current:** Only tracks `totalVolumeSatoshis` (total traded)

**Target:** Need separate pool balances per outcome
```
YES poolBalance: 100,000,000 sats
NO poolBalance: 75,000,000 sats
```

**Action Required:**
- [ ] Add `poolBalance : Nat64` to each outcome's config
- [ ] Update on every buy (increases pool)
- [ ] Used for payout calculations

---

### 5. **Missing: `claimWinnings()` Function**

**Current:** No payout mechanism exists after resolution

**Target Flow:**
1. Market resolves with winning outcome
2. Winners call `claimWinnings(marketId)`
3. Payout = stake + (winnerShares / totalWinnerShares) × losingPoolBalance
4. Burn winner's tokens, pay from vault

**Action Required:**
- [ ] Implement `claimWinnings(marketId)` function
- [ ] Add `claimed : Bool` tracking per holder
- [ ] Calculate proportional share of losing pool
- [ ] Integrate with Vault.pay_ckbtc()

---

### 6. **Missing: `resolveMarket()` Function**

**Current:** No resolution mechanism found

**Target:**
```motoko
resolveMarket(marketId : Nat, winningOutcome : MarketResolution) : async Result<(), Text>
```

**Action Required:**
- [ ] Implement `resolveMarket()` callable only by resolver
- [ ] Validate market has expired
- [ ] Set `resolved` field with winning outcome
- [ ] Disable further trading

---

## 🟡 Minor Issues

### 7. Registration Parameters
**Current:** Uses `b : Float` (LMSR liquidity parameter)
**Target:** Should use `basePrice : Nat64` and `priceSlope : Nat64`

### 8. Price Representation
**Current:** Prices as Float (0.0-1.0 probability)
**Target:** Prices in satoshis (Nat64)

---

## 📋 Migration Checklist

### Phase 1: Core Math Changes
- [ ] Create bonding curve pricing functions
- [ ] Add outcome-specific supply tracking
- [ ] Add pool balance tracking per outcome

### Phase 2: Holder Tracking
- [ ] Extend HolderPosition type with totalPaid
- [ ] Track positions by outcome (YES/NO separate)
- [ ] Update on every purchase

### Phase 3: Disable Selling
- [ ] Return "selling not supported" error
- [ ] Update frontend to hide sell UI

### Phase 4: Resolution & Payouts
- [ ] Implement resolveMarket()
- [ ] Implement claimWinnings()
- [ ] Integrate with Vault for payouts

### Phase 5: Testing
- [ ] Update deploy_and_test.sh with new test cases
- [ ] Test full flow: create → buy → resolve → claim

---

## 🔧 Files to Modify

| File | Changes Required |
|------|------------------|
| `MarketTrade/markets.mo` | Bonding curve math, holder tracking, claimWinnings, resolveMarket |
| `MarketFactory/factory.mo` | Update registration params (basePrice, priceSlope) |
| `Vault/vault.mo` | No changes needed - already supports pay_ckbtc |
| `deploy_and_test.sh` | Add resolution and claim tests |

---

## 📊 Architecture Diagram: Target State

```
┌─────────────────────────────────────────────────────────────┐
│                        MarketFactory                         │
│  Creates ICRC-151 ledger + YES/NO tokens                    │
│  Registers market with MarketTrade                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         MarketTrade                          │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │ YES Bonding Curve│  │ NO Bonding Curve │                 │
│  │ basePrice: 1000  │  │ basePrice: 1000  │                 │
│  │ slope: 50        │  │ slope: 50        │                 │
│  │ supply: 46,236   │  │ supply: 38,298   │                 │
│  │ pool: 100M sats  │  │ pool: 75M sats   │                 │
│  └─────────────────┘  └─────────────────┘                   │
│                                                              │
│  Holders: [{Alice, YES, 31227 shares, 50M paid}, ...]       │
│                                                              │
│  Functions:                                                  │
│    buyTokens() ✓                                            │
│    sellTokens() ✗ (disabled)                                │
│    resolveMarket() (NEW)                                    │
│    claimWinnings() (NEW)                                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                           Vault                              │
│  pull_ckbtc() - takes funds from users on buy               │
│  pay_ckbtc() - pays winners on claim                        │
└─────────────────────────────────────────────────────────────┘
```
