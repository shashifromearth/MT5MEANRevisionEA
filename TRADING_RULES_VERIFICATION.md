# 📋 Trading Rules Verification & Fixes

## ✅ **STEP 1: Define the Mean** - **VERIFIED**

### **Option A: Asian Midpoint** ✅
- ✅ Asian range: 00:00-05:00 UTC
- ✅ Mean = (Asian High + Asian Low) ÷ 2
- ✅ Implemented in `CalculateAsianMidpoint()`

### **Option B: Session VWAP** ✅
- ✅ Session VWAP (5m)
- ✅ Implemented in `CalculateSessionVWAP()`

**Status:** ✅ **CORRECT**

---

## ❌ **STEP 2: Distance Filter** - **NEEDS FIX**

### **Requirement:**
- ✅ Minimum distance: ≥ 1 × ATR(14) OR ≥ 0.3% of price

### **Current Implementation:**
- ❌ 0.5 × ATR(14) (RELAXED)
- ❌ 0.15% of price (RELAXED)

### **Fix Required:**
- ✅ Change back to: 1 × ATR(14) OR 0.3% of price

**Status:** ❌ **NEEDS FIX**

---

## ⚠️ **STEP 3: Exhaustion Confirmation** - **NEEDS FIX**

### **Requirement:**
- ❌ **No exhaustion → no entry** (MANDATORY)

### **Current Implementation:**
- ❌ Exhaustion is "preferred but not required"
- ❌ Trade can proceed without exhaustion

### **Fix Required:**
- ✅ Make exhaustion **MANDATORY**
- ✅ Reject trade if no exhaustion pattern

### **Exhaustion Patterns (All Verified):**

#### **A. Long Wick Candle** ✅
- ✅ Wick ≥ 50% of candle range
- ✅ Close NOT at extreme
- ✅ Implemented correctly

#### **B. Inside Candle** ✅
- ✅ High & low inside previous candle
- ✅ Implemented correctly

#### **C. 2 Small Body Candles** ⚠️
- ✅ Bodies < 40% of prior impulse
- ⚠️ Currently uses candle at index 2 as reference
- ⚠️ Should find largest range in last 5-10 candles
- ⚠️ **NEEDS FIX**

**Status:** ❌ **NEEDS FIX** (Make mandatory + fix small bodies detection)

---

## ✅ **STEP 4: Entry** - **VERIFIED**

### **SHORT Setup** ✅
- ✅ Sell at low of exhaustion candle - 0.2 pip
- ✅ Implemented in `CSellTrade::GetEntryPrice()`

### **LONG Setup** ✅
- ✅ Buy at high of exhaustion candle + 0.2 pip
- ✅ Implemented in `CBuyTrade::GetEntryPrice()`

**Status:** ✅ **CORRECT**

---

## ✅ **STEP 5: Stop Loss** - **VERIFIED**

### **Requirement:**
- ✅ 2 pips beyond recent swing extreme
- ✅ OR 0.5 × ATR(14) (whichever is tighter)
- ✅ Never move SL

### **Implementation:**
- ✅ Uses last 5 candles for swing extremes
- ✅ Calculates both: swing + 2 pips AND 0.5×ATR
- ✅ Returns tighter (closer to entry)
- ✅ SL is set at trade execution (not moved)

**Status:** ✅ **CORRECT**

---

## ✅ **STEP 6: Take Profit** - **VERIFIED**

### **Option A: Return to Mean** ✅
- ✅ TP = Mean (Asian midpoint or VWAP)
- ✅ Highest win rate (65-70%)
- ✅ Implemented as `TO_MEAN`

### **Option B: 75% of Distance** ✅
- ✅ TP = 75% of distance to mean
- ✅ Implemented as `SEVENTY_FIVE_PERCENT`

**Status:** ✅ **CORRECT**

---

## ⚠️ **STEP 7: Trade Limits** - **NEEDS CLARIFICATION**

### **Requirement:**
- ⚠️ Max 2 trades per session
- ✅ 1 loss → wait 15 min
- ✅ 2 losses → STOP for session

### **Current Implementation:**
- ❌ Max 6 trades per day (not per session)
- ✅ 1 loss → wait 15 min
- ✅ 2 losses → STOP

### **Issue:**
- Multiple sessions per day (London, NY)
- If "per session" = 2 trades per London + 2 trades per NY = 4 trades/day
- If "per day" = 2 trades total per day

### **Fix Required:**
- ⚠️ Need clarification: Per session or per day?
- ⚠️ If per session: Need to track trades per session (London vs NY)
- ⚠️ If per day: Change from 6 to 2

**Status:** ⚠️ **NEEDS CLARIFICATION/FIX**

---

## ❌ **INVALID SETUPS** - **VERIFIED**

### **1. Strong Trend Day (HTF BOS)** ✅
- ✅ Checked in `CheckTrendFilter()`
- ✅ Rejects if strong trend detected

### **2. Price Already Crossed Mean** ✅
- ✅ Checked in `CheckPriceCrossedMean()`
- ✅ Rejects if crossed in last 3 candles

### **3. News Candle** ✅
- ✅ Checked in `CheckNewsFilter()`
- ✅ Placeholder (returns false for now)

### **4. Large Momentum Candles** ✅
- ✅ Checked in `CheckMomentumCandles()`
- ✅ Rejects if large momentum detected

**Status:** ✅ **CORRECT**

---

## 📊 **Summary of Fixes Needed**

| Step | Issue | Status | Fix Required |
|------|-------|--------|--------------|
| **STEP 2** | Distance filter too relaxed | ❌ | Change to 1×ATR OR 0.3% |
| **STEP 3** | Exhaustion optional | ❌ | Make mandatory |
| **STEP 3C** | Small bodies detection | ⚠️ | Find largest range in 5-10 candles |
| **STEP 7** | Trade limit per session | ⚠️ | Clarify: per session or per day? |

---

## 🔧 **Fixes to Implement**

1. ✅ Fix distance filter (1×ATR OR 0.3%)
2. ✅ Make exhaustion mandatory
3. ✅ Fix small bodies detection (find largest range)
4. ⚠️ Clarify trade limits (per session or per day?)

