# ✅ Cross-Session "One Trade at a Time" Verification

## 🔍 **Analysis**

### **Question:** Is "one trade at a time" enforced across multiple sessions?

### **Answer:** ✅ **YES - It's enforced globally across ALL sessions**

---

## 📊 **How It Works**

### **1. Position Check is Global (Not Session-Specific)**

**Function:** `HasEAPosition(string symbol)` (Lines 95-113)

```mql5
bool HasEAPosition(string symbol)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)  // ✅ Checks ALL broker positions
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol && 
            PositionGetInteger(POSITION_MAGIC) == EA_MAGIC_NUMBER)  // ✅ Filters by magic number
         {
            return true;  // ✅ Position exists
         }
      }
   }
   return false;  // ✅ No position exists
}
```

**Key Points:**
- ✅ Uses `PositionsTotal()` - checks **ALL broker positions** (not session variables)
- ✅ Filters by **symbol** AND **magic number** (EA_MAGIC_NUMBER = 123456)
- ✅ **Independent of sessions** - checks actual broker positions
- ✅ **Persists across sessions** - position exists until closed

---

### **2. Position Check Happens BEFORE Session Checks**

**Order in OnTick() (Lines 249-410):**

1. ✅ **Line 250:** Check position FIRST (before any session logic)
   ```mql5
   // PROFESSIONAL TRADE MANAGEMENT - Always active (even outside sessions)
   if(HasEAPosition(g_CurrentSymbol))
   {
      // Monitor existing position
      return;  // ✅ NO NEW TRADE
   }
   ```

2. ✅ **Line 280:** Check dead zone
3. ✅ **Line 289:** Check trading session
4. ✅ **Line 297:** Check session trade limits
5. ✅ **Line 306:** Check position AGAIN (double-check)

**Result:** Position check happens **BEFORE** session checks, so it's **independent** of sessions.

---

### **3. SessionManager Doesn't Affect Position Tracking**

**SessionManager Responsibilities:**
- ✅ Tracks **daily trade count** (6 trades per day)
- ✅ Tracks **loss cooldown** (15 minutes after loss)
- ✅ Resets **daily counters** at midnight
- ❌ **Does NOT** track positions
- ❌ **Does NOT** reset position tracking

**Position Tracking:**
- ✅ Done via **actual broker positions** (not variables)
- ✅ **Persists** across all sessions
- ✅ **Independent** of SessionManager

---

### **4. Position Check Works Across All Sessions**

**Scenario 1: Trade Opens in London Session**
```
London Session (07:00 UTC)
├─ Position opens
├─ HasEAPosition() = TRUE
└─ NO NEW TRADE (even if conditions met)
```

**Scenario 2: London Session Ends, NY Session Starts**
```
NY Session (12:30 UTC)
├─ Position still exists (not closed)
├─ HasEAPosition() = TRUE (still checking broker positions)
└─ NO NEW TRADE (position persists across sessions)
```

**Scenario 3: Position Closes in NY Session**
```
NY Session (12:30 UTC)
├─ Position closes (TP/SL/manual/professional exit)
├─ HasEAPosition() = FALSE (position no longer exists)
└─ NEW TRADE ALLOWED (if conditions met)
```

**Result:** ✅ Position check works **across all sessions** - London, NY, Dead Zone, etc.

---

## 🛡️ **Protection Layers**

### **Layer 1: Early Check (Line 250)**
- ✅ Checks position **before** any session logic
- ✅ Works **even outside trading sessions**
- ✅ **Global** - not session-specific

### **Layer 2: Pre-Execution Check (Line 306)**
- ✅ Checks position **before** trade execution
- ✅ **Double-check** to prevent race conditions
- ✅ **Global** - not session-specific

### **Layer 3: Final Check (Lines 651, 709)**
- ✅ Checks position **right before** ExecuteTrade()
- ✅ **Triple-check** for safety
- ✅ **Global** - not session-specific

### **Layer 4: ExecuteTrade Safety (BuyTrade/SellTrade)**
- ✅ Checks position **inside** ExecuteTrade()
- ✅ **Final safety net**
- ✅ **Global** - not session-specific

**All 4 layers check ACTUAL BROKER POSITIONS, not session variables!**

---

## ✅ **Verification**

### **Test Scenarios:**

1. **Trade Opens in London → NY Session Starts**
   - ✅ Position exists → NO NEW TRADE in NY session
   - ✅ Position persists across sessions

2. **Trade Opens in NY → London Session Next Day**
   - ✅ Position exists → NO NEW TRADE in next London session
   - ✅ Position persists until closed

3. **Position Closes → New Session Starts**
   - ✅ Position closed → NEW TRADE ALLOWED
   - ✅ Works in any session (London, NY, etc.)

4. **Daily Reset (Midnight)**
   - ✅ Daily trade counter resets (6 trades)
   - ✅ Position check **NOT affected** (still checks broker positions)
   - ✅ If position exists → NO NEW TRADE (even after daily reset)

---

## 📋 **Summary**

### **✅ "One Trade at a Time" is Enforced Globally:**

1. ✅ **Checks actual broker positions** (not session variables)
2. ✅ **Independent of sessions** (London, NY, Dead Zone)
3. ✅ **Persists across sessions** (position exists until closed)
4. ✅ **Magic number filtering** (only EA's positions)
5. ✅ **4 layers of protection** (all global, not session-specific)

### **❌ What Does NOT Reset:**
- ❌ Position tracking (checks broker positions)
- ❌ Position existence (until closed)
- ❌ "One trade at a time" policy (always enforced)

### **✅ What DOES Reset:**
- ✅ Daily trade counter (6 trades per day)
- ✅ Loss cooldown (15 minutes)
- ✅ Session-specific counters

---

## 🎯 **Conclusion**

**YES - "One Trade at a Time" is enforced across ALL sessions!**

The position check uses **actual broker positions** (via `PositionsTotal()` and magic number filtering), not session-specific variables. This means:

- ✅ Position opened in London → Blocks new trades in NY session
- ✅ Position opened in NY → Blocks new trades in next London session
- ✅ Position persists until closed (TP/SL/manual/professional exit)
- ✅ Works across all sessions: London, NY, Dead Zone, Asian, etc.

**The policy is GLOBAL and SESSION-INDEPENDENT!** 🔒

