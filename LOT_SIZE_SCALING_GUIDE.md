# Mandatory Changes When Scaling Lot Sizes - Complete Guide

## Overview: Scaling from 0.01 to 5.00 Lots

When increasing lot sizes, you **MUST** adjust multiple parameters to maintain proper risk management and avoid margin calls.

---

## Critical Changes Required

### 1. **Account Balance Requirements** ⚠️ CRITICAL

Different lot sizes require different minimum account balances to avoid margin calls.

#### Minimum Account Balance by Lot Size (EURUSD, 1:100 Leverage):

| Lot Size | Margin/Trade | Min Balance | Safe Balance | Recommended Balance |
|----------|--------------|-------------|--------------|---------------------|
| 0.01     | ~$10         | $500        | $1,000       | $2,000              |
| 0.10     | ~$100        | $1,000      | $5,000       | $10,000             |
| 1.00     | ~$1,000      | $5,000      | $20,000      | $50,000             |
| 2.00     | ~$2,000      | $10,000     | $40,000      | $100,000            |
| 3.00     | ~$3,000      | $15,000     | $60,000      | $150,000            |
| 4.00     | ~$4,000      | $20,000     | $80,000      | $200,000            |
| 5.00     | ~$5,000      | $25,000     | $100,000     | $250,000            |

**Formula**: 
```
Minimum Balance = (Lot Size × 100,000 × Margin%) / Leverage
Safe Balance = Minimum Balance × 4 (for drawdowns)
Recommended = Minimum Balance × 10 (for safety)
```

**⚠️ WARNING**: Trading with insufficient balance = **MARGIN CALL RISK!**

---

### 2. **MaxDailyLossUSD** - MUST INCREASE

This is the **most critical** setting to adjust!

#### Current Setting:
```mql5
MaxDailyLossUSD = 100.0  // Too small for larger lots!
```

#### Required Changes by Lot Size:

| Lot Size | Risk/Trade | Max Loss/Trade | Recommended MaxDailyLossUSD | Formula |
|----------|------------|---------------|----------------------------|---------|
| 0.01     | $0.30      | $0.30         | $5.00                      | 15-20 trades |
| 0.10     | $3.00      | $3.00         | $50.00                     | 15-20 trades |
| 1.00     | $30.00     | $30.00        | $500.00                    | 15-20 trades |
| 2.00     | $60.00     | $60.00        | $1,000.00                  | 15-20 trades |
| 3.00     | $90.00     | $90.00        | $1,500.00                  | 15-20 trades |
| 4.00     | $120.00    | $120.00       | $2,000.00                  | 15-20 trades |
| 5.00     | $150.00    | $150.00       | $2,500.00                  | 15-20 trades |

**Formula**:
```
MaxDailyLossUSD = (Lot Size × 30 pips × $1/pip) × 15-20 trades
```

**Example for 1.00 lot**:
```
MaxDailyLossUSD = (1.00 × 30 × $1) × 15 = $450
Recommended: $500 (round up for safety)
```

**⚠️ CRITICAL**: If `MaxDailyLossUSD` is too small, EA will stop trading after just 1-2 losses!

---

### 3. **MaxSingleTradeLossUSD** - MUST INCREASE

Alert threshold for individual trade losses.

#### Current Setting:
```mql5
MaxSingleTradeLossUSD = 50.0  // Too small for larger lots!
```

#### Required Changes by Lot Size:

| Lot Size | Max Loss/Trade | Recommended MaxSingleTradeLossUSD |
|----------|----------------|----------------------------------|
| 0.01     | $0.30          | $1.00                            |
| 0.10     | $3.00          | $10.00                           |
| 1.00     | $30.00         | $100.00                          |
| 2.00     | $60.00         | $200.00                          |
| 3.00     | $90.00         | $300.00                          |
| 4.00     | $120.00        | $400.00                          |
| 5.00     | $150.00        | $500.00                          |

**Formula**:
```
MaxSingleTradeLossUSD = (Lot Size × 30 pips × $1/pip) × 3-4
```

**⚠️ IMPORTANT**: This is an **alert threshold**, not a stop. Set it 3-4x the expected loss per trade.

---

### 4. **MaxMarginUtilizedUSD** - MUST INCREASE

Telegram alert for margin usage.

#### Current Setting:
```mql5
MaxMarginUtilizedUSD = 2000.0  // May be too small for larger lots
```

#### Required Changes by Lot Size:

| Lot Size | Margin/Trade | Max Trades | Total Margin | Recommended MaxMarginUtilizedUSD |
|----------|--------------|------------|--------------|--------------------------------|
| 0.01     | $10          | 3          | $30          | $100                            |
| 0.10     | $100         | 3          | $300         | $1,000                          |
| 1.00     | $1,000       | 3          | $3,000       | $10,000                         |
| 2.00     | $2,000       | 3          | $6,000       | $20,000                         |
| 3.00     | $3,000       | 3          | $9,000       | $30,000                         |
| 4.00     | $4,000       | 3          | $12,000      | $40,000                         |
| 5.00     | $5,000       | 3          | $15,000      | $50,000                         |

**Formula**:
```
MaxMarginUtilizedUSD = (Lot Size × 100,000 × Margin%) × MaxTradesPerDay × 3-5
```

**⚠️ IMPORTANT**: Keep margin usage **<20%** of account balance for safety.

---

### 5. **MaxTradesPerDay** - CONSIDER ADJUSTING

With larger lot sizes, you may want to **reduce** daily trades to manage risk.

#### Current Setting:
```mql5
MaxTradesPerDay = 3  // May be too many for larger lots
```

#### Recommended Adjustments:

| Lot Size | Current Max | Recommended Max | Reason |
|----------|-------------|-----------------|--------|
| 0.01     | 3           | 5-10            | Low risk, can trade more |
| 0.10     | 3           | 3-5             | Moderate risk |
| 1.00     | 3           | 2-3             | High risk, limit trades |
| 2.00     | 3           | 2               | Very high risk |
| 3.00+    | 3           | 1-2             | Extreme risk, be conservative |

**⚠️ RECOMMENDATION**: 
- **Small lots (0.01-0.10)**: Can trade more (5-10/day)
- **Medium lots (0.50-1.00)**: Moderate (3-5/day)
- **Large lots (2.00+)**: Conservative (1-2/day)

---

### 6. **RiskPercentPerTrade** - IF USING MONEY MANAGEMENT

If `UseMoneyManagement = true`, adjust risk percentage.

#### Current Setting:
```mql5
RiskPercentPerTrade = 0.75%  // May be too high for larger lots
```

#### Recommended Adjustments:

| Lot Size | Recommended Risk % | Reason |
|----------|-------------------|--------|
| 0.01-0.10 | 0.75% - 1.0%     | Low risk, can be aggressive |
| 0.50-1.00 | 0.5% - 0.75%     | Moderate risk |
| 2.00+     | 0.25% - 0.5%     | High risk, be conservative |

**⚠️ IMPORTANT**: Larger lots = **lower risk percentage** for safety!

---

### 7. **Stop Loss Pips** - CONSIDER ADJUSTING

Larger lot sizes may need **tighter stop losses** to control risk.

#### Current Settings:
```mql5
BuyStopLossPips = 30
SellStopLossPips = 30
```

#### Recommended Adjustments:

| Lot Size | Current SL | Recommended SL | Reason |
|----------|------------|---------------|--------|
| 0.01-0.10 | 30 pips    | 30-40 pips    | Low risk, can use wider stops |
| 0.50-1.00 | 30 pips    | 25-30 pips    | Moderate risk |
| 2.00+     | 30 pips    | 20-25 pips    | High risk, use tighter stops |

**⚠️ TRADE-OFF**: Tighter stops = more stop-outs, but smaller losses per trade.

---

## Complete Configuration Table

### For 0.01 Lot Size:
```mql5
LotSize = 0.01
MaxDailyLossUSD = 5.0
MaxSingleTradeLossUSD = 1.0
MaxMarginUtilizedUSD = 100.0
MaxTradesPerDay = 5-10
RiskPercentPerTrade = 1.0%
BuyStopLossPips = 30
SellStopLossPips = 30
Min Account Balance: $2,000
```

### For 0.10 Lot Size:
```mql5
LotSize = 0.10
MaxDailyLossUSD = 50.0
MaxSingleTradeLossUSD = 10.0
MaxMarginUtilizedUSD = 1,000.0
MaxTradesPerDay = 3-5
RiskPercentPerTrade = 0.75%
BuyStopLossPips = 30
SellStopLossPips = 30
Min Account Balance: $10,000
```

### For 1.00 Lot Size:
```mql5
LotSize = 1.00
MaxDailyLossUSD = 500.0
MaxSingleTradeLossUSD = 100.0
MaxMarginUtilizedUSD = 10,000.0
MaxTradesPerDay = 2-3
RiskPercentPerTrade = 0.5%
BuyStopLossPips = 25-30
SellStopLossPips = 25-30
Min Account Balance: $50,000
```

### For 2.00 Lot Size:
```mql5
LotSize = 2.00
MaxDailyLossUSD = 1,000.0
MaxSingleTradeLossUSD = 200.0
MaxMarginUtilizedUSD = 20,000.0
MaxTradesPerDay = 2
RiskPercentPerTrade = 0.5%
BuyStopLossPips = 20-25
SellStopLossPips = 20-25
Min Account Balance: $100,000
```

### For 3.00 Lot Size:
```mql5
LotSize = 3.00
MaxDailyLossUSD = 1,500.0
MaxSingleTradeLossUSD = 300.0
MaxMarginUtilizedUSD = 30,000.0
MaxTradesPerDay = 1-2
RiskPercentPerTrade = 0.25-0.5%
BuyStopLossPips = 20-25
SellStopLossPips = 20-25
Min Account Balance: $150,000
```

### For 4.00 Lot Size:
```mql5
LotSize = 4.00
MaxDailyLossUSD = 2,000.0
MaxSingleTradeLossUSD = 400.0
MaxMarginUtilizedUSD = 40,000.0
MaxTradesPerDay = 1-2
RiskPercentPerTrade = 0.25-0.5%
BuyStopLossPips = 20-25
SellStopLossPips = 20-25
Min Account Balance: $200,000
```

### For 5.00 Lot Size:
```mql5
LotSize = 5.00
MaxDailyLossUSD = 2,500.0
MaxSingleTradeLossUSD = 500.0
MaxMarginUtilizedUSD = 50,000.0
MaxTradesPerDay = 1-2
RiskPercentPerTrade = 0.25-0.5%
BuyStopLossPips = 20-25
SellStopLossPips = 20-25
Min Account Balance: $250,000
```

---

## Step-by-Step Scaling Process

### Phase 1: Start Small (0.01-0.10 lots)
1. ✅ Test with 0.01 lots first
2. ✅ Verify all settings work correctly
3. ✅ Build confidence and track performance
4. ✅ Scale to 0.10 after 1-3 months of profit

### Phase 2: Moderate Scaling (0.50-1.00 lots)
1. ✅ Ensure account balance ≥ $50,000
2. ✅ Adjust `MaxDailyLossUSD` to $500
3. ✅ Reduce `MaxTradesPerDay` to 2-3
4. ✅ Monitor margin usage closely
5. ✅ Scale gradually: 0.50 → 0.75 → 1.00

### Phase 3: Large Positions (2.00+ lots)
1. ✅ Ensure account balance ≥ $100,000
2. ✅ Adjust `MaxDailyLossUSD` proportionally
3. ✅ Reduce `MaxTradesPerDay` to 1-2
4. ✅ Use tighter stop losses (20-25 pips)
5. ✅ Lower risk percentage (0.25-0.5%)
6. ✅ Scale very gradually: 2.00 → 3.00 → 4.00 → 5.00

---

## Risk Management Rules

### Rule 1: Never Risk More Than You Can Afford to Lose
- **Small lots**: Can risk 1% per trade
- **Large lots**: Risk only 0.25-0.5% per trade

### Rule 2: Maintain Adequate Account Balance
- **Minimum**: 4x margin requirement
- **Recommended**: 10x margin requirement
- **Safe**: 20x margin requirement

### Rule 3: Scale Gradually
- **Never jump** from 0.10 to 5.00 directly!
- **Scale in steps**: 0.10 → 0.50 → 1.00 → 2.00 → 3.00 → 4.00 → 5.00
- **Wait 1-3 months** between scaling steps

### Rule 4: Adjust All Parameters Together
- **Don't just change lot size**
- **Adjust ALL risk parameters** simultaneously
- **Test thoroughly** before going live

### Rule 5: Monitor Margin Usage
- **Keep margin usage <20%** of account
- **Reserve 80%** for drawdowns and safety
- **Set alerts** for high margin usage

---

## Quick Reference: Formula Cheat Sheet

### MaxDailyLossUSD:
```
MaxDailyLossUSD = (Lot Size × 30 pips × $1/pip) × 15-20
```

### MaxSingleTradeLossUSD:
```
MaxSingleTradeLossUSD = (Lot Size × 30 pips × $1/pip) × 3-4
```

### MaxMarginUtilizedUSD:
```
MaxMarginUtilizedUSD = (Lot Size × 100,000 × 0.01) × MaxTradesPerDay × 3-5
```

### Minimum Account Balance:
```
Min Balance = (Lot Size × 100,000 × 0.01) × 10
Safe Balance = Min Balance × 2
Recommended Balance = Min Balance × 5
```

---

## ⚠️ CRITICAL WARNINGS

1. **Never scale without adjusting risk parameters!**
   - Changing lot size without adjusting `MaxDailyLossUSD` = **EA stops trading after 1-2 losses**

2. **Never trade with insufficient balance!**
   - Insufficient balance = **MARGIN CALL** = Account wiped out

3. **Never scale too quickly!**
   - Jumping from 0.10 to 5.00 = **EXTREME RISK** = Account destruction

4. **Always test first!**
   - Test new settings in Strategy Tester
   - Verify all parameters work correctly
   - Check margin usage and drawdowns

5. **Monitor closely!**
   - Watch margin usage daily
   - Check daily loss limits
   - Review trade performance weekly

---

## Recommended Scaling Strategy

### Conservative Approach (Recommended):
```
Month 1-3:  0.01 lots  → Build confidence
Month 4-6:  0.10 lots  → Prove profitability
Month 7-9:  0.50 lots  → Scale gradually
Month 10-12: 1.00 lots → Moderate scaling
Year 2:     2.00 lots  → If profitable
Year 3+:    3.00+ lots → Only if consistently profitable
```

### Aggressive Approach (Higher Risk):
```
Month 1:    0.10 lots
Month 2:    0.50 lots
Month 3:    1.00 lots
Month 4:    2.00 lots
Month 5+:   3.00+ lots (if profitable)
```

**⚠️ WARNING**: Aggressive scaling = Higher risk of account loss!

---

## Summary: Mandatory Changes Checklist

When scaling lot size, you **MUST** adjust:

- ✅ **MaxDailyLossUSD** (CRITICAL - most important!)
- ✅ **MaxSingleTradeLossUSD** (Important)
- ✅ **MaxMarginUtilizedUSD** (Important)
- ✅ **Account Balance** (CRITICAL - must be sufficient)
- ⚠️ **MaxTradesPerDay** (Consider reducing)
- ⚠️ **RiskPercentPerTrade** (Consider reducing for large lots)
- ⚠️ **Stop Loss Pips** (Consider tightening for large lots)

**Remember**: Scaling lot size = Scaling risk. Adjust ALL parameters proportionally! 🎯

