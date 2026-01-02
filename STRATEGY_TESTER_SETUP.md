# 🔧 Strategy Tester Setup Guide

## ❌ **Error: "set mode to math calculations or adjust testing dates"**

### **Problem:**
The Strategy Tester is showing date `2026.01.02` which is in the future. MT5 requires:
- **Past dates** for testing
- OR **"Every tick"** mode instead of "Math calculations"

---

## ✅ **Solution 1: Fix Testing Dates (Recommended)**

### **Steps:**
1. Open **Strategy Tester** (View → Strategy Tester or Ctrl+R)
2. Select your EA: **MeanReversionEA**
3. Set **Symbol**: Your trading pair (e.g., EURUSD)
4. Set **Period**: M5 (5 minutes)
5. **IMPORTANT - Set Dates:**
   - **From:** `2024.01.01` (or any past date)
   - **To:** `2024.12.31` (or current date, but must be in past)
6. Set **Mode**: 
   - **"Every tick"** (most accurate) OR
   - **"1 minute OHLC"** (faster, less accurate)
7. Click **Start**

---

## ✅ **Solution 2: Use "Every Tick" Mode**

If you want to test with current/future dates:

1. In Strategy Tester, set **Mode** to **"Every tick"**
2. This bypasses the date validation
3. More accurate but slower

---

## 📊 **Recommended Testing Settings**

### **For Initial Testing:**
- **Period:** M5 (5 minutes)
- **From:** `2024.01.01`
- **To:** `2024.12.31`
- **Mode:** `1 minute OHLC` (faster)
- **Optimization:** Disabled
- **Visual Mode:** Enabled (to see trades)

### **For Final Validation:**
- **Period:** M5 (5 minutes)
- **From:** `2024.01.01`
- **To:** `2024.12.31`
- **Mode:** `Every tick` (most accurate)
- **Visual Mode:** Enabled

---

## ⚠️ **Common Issues**

### **Issue 1: Future Dates**
- ❌ **Wrong:** From: `2026.01.01`, To: `2026.12.31`
- ✅ **Correct:** From: `2024.01.01`, To: `2024.12.31`

### **Issue 2: Wrong Mode**
- ❌ **Wrong:** "Math calculations" with future dates
- ✅ **Correct:** "Every tick" OR past dates

### **Issue 3: No Historical Data**
- If you get "no data" error:
  1. Go to **Tools → History Center**
  2. Download data for your symbol
  3. Select **M5** period
  4. Click **Download**

---

## 🎯 **Quick Fix Steps**

1. **Open Strategy Tester** (Ctrl+R)
2. **Select EA:** MeanReversionEA
3. **Set Symbol:** EURUSD (or your pair)
4. **Set Period:** M5
5. **Set Dates:**
   - From: `2024.01.01`
   - To: `2024.12.31`
6. **Set Mode:** `Every tick` or `1 minute OHLC`
7. **Click Start**

---

## ✅ **After Fixing Dates**

The EA should now:
- ✅ Compile successfully
- ✅ Run in Strategy Tester
- ✅ Show trades in visual mode
- ✅ Generate test results

---

## 📝 **Note**

The error is **NOT** a code issue - it's a **tester configuration issue**. The EA code is correct, you just need to set proper testing dates.

