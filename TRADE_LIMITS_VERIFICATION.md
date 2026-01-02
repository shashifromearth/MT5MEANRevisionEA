# ✅ Trade Limits Verification & Updates

## 📋 **Requirements Check**

### **1. One Trade at a Time** ✅ **IMPLEMENTED**
**Status:** ✅ Already implemented

**Location:** `MeanReversionEA.mq5` line 253
```mql5
// Check if we already have an open position
if(PositionSelect(g_CurrentSymbol))
{
   // Monitor existing position only
   // NO NEW TRADE until existing one is closed
   return; // Exits early, prevents new trade
}
```

**How it works:**
- Checks if position exists on current symbol
- If position exists → monitors it only
- Returns early → **NO new trade can be opened**
- New trade only possible after existing position is closed

---

### **2. Exit Existing Before New Trade** ✅ **IMPLEMENTED**
**Status:** ✅ Already implemented (implicitly)

**How it works:**
- The check at line 253 prevents new trades if position exists
- Position must be closed (manually or by TP/SL) before new trade
- Professional trade manager can exit positions based on rules
- **No forced closure** - waits for natural exit or professional exit

**Note:** The EA doesn't force-close existing trades to open new ones. It waits for natural exit (TP/SL/professional exit), then allows new trade.

---

### **3. Default Lot Size = 1.0** ✅ **FIXED**
**Status:** ✅ Updated

**Change:**
- **Before:** `input double LotSize = 0.01;`
- **After:** `input double LotSize = 1.0;`

**Location:** `MeanReversionEA.mq5` line 32

---

### **4. Daily Trade Limit = 6** ✅ **FIXED**
**Status:** ✅ Updated

**Change:**
- **Before:** `input int MaxTradesPerSession = 2;`
- **After:** `input int MaxTradesPerDay = 6;`

**Location:** `MeanReversionEA.mq5` line 57

**Note:** The `SessionManager` already tracks daily trades (`m_TradesToday`), so this works correctly.

---

## ✅ **Summary of Changes**

| Requirement | Status | Change Made |
|------------|--------|-------------|
| **One trade at a time** | ✅ Already implemented | No change needed |
| **Exit existing before new** | ✅ Already implemented | No change needed |
| **Default lot size = 1.0** | ✅ Fixed | Changed from 0.01 to 1.0 |
| **Daily limit = 6** | ✅ Fixed | Changed from 2 to 6, renamed parameter |

---

## 🔍 **How It Works**

### **Trade Flow:**
1. ✅ Check if position exists → If YES, monitor only (no new trade)
2. ✅ Check daily trade limit → If reached (6 trades), block new trades
3. ✅ Check all entry conditions → If all pass, open trade
4. ✅ Monitor position → Professional management, TP/SL
5. ✅ Position closes → Reset, allow new trade (if under daily limit)

### **Daily Limit Logic:**
- Tracks trades per day (`m_TradesToday`)
- Resets at midnight (new day)
- Blocks new trades when limit reached (6 trades)
- Logs when limit is reached

### **One Trade at a Time Logic:**
- Checks `PositionSelect(g_CurrentSymbol)` before entry
- If position exists → returns early (no new trade)
- Only after position closes → new trade possible

---

## ✅ **All Requirements Met**

1. ✅ **One trade at a time** - Implemented (line 253)
2. ✅ **No new trade if existing** - Implemented (line 253)
3. ✅ **Default lot size = 1.0** - Fixed
4. ✅ **Daily limit = 6** - Fixed

**The EA is now configured as requested!** 🎯

