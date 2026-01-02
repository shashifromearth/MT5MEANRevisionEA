# Strategy Tester Guide - Mean Reversion EA

## How to Test EA with Custom Settings in MT5 Strategy Tester

### Step 1: Open Strategy Tester
1. In MetaTrader 5, press **Ctrl+R** or go to **View → Strategy Tester**
2. The Strategy Tester window will open at the bottom of the terminal

### Step 2: Select Your EA
1. In the Strategy Tester, click the **Settings** tab
2. In the **Expert Advisor** dropdown, select: **MeanReversionEA**
3. Make sure **Symbol** is set to your desired pair (e.g., EURUSD, GBPUSD)
4. Set **Period** to **M5** (5-minute charts) - recommended for this EA

### Step 3: Configure Testing Parameters

#### **General Settings:**
- **Testing Mode**: Select **"Every tick"** (most accurate) or **"1 minute OHLC"** (faster)
- **Date Range**: 
  - **From**: Select start date (e.g., 2024.01.01)
  - **To**: Select end date (e.g., 2024.12.31)
- **Optimization**: Leave unchecked (unless optimizing)

#### **Input Parameters (Custom Settings):**

Click on **"Inputs"** tab to customize all EA settings:

##### **=== Trade Quantity Settings ===**
- `LotSize` = 0.10 (or your preferred lot size)
- `UseMoneyManagement` = false (or true if you want %-based sizing)
- `RiskPercentPerTrade` = 0.75 (0.75% risk per trade)

##### **=== Daily Trade Limits ===**
- `MaxTradesPerDay` = 3 (or higher for more trades)
- `MaxDailyLossUSD` = 100.00 (stop trading if daily loss exceeds this)
- `MaxSingleTradeLossUSD` = 50.00 (alert threshold)

##### **=== Buy/Sell Trade Settings ===**
- `EnableBuyTrades` = true (enable buy trades)
- `BuyLotSize` = 0.10
- `BuyStopLossPips` = 30
- `EnableSellTrades` = true (enable sell trades)
- `SellLotSize` = 0.10
- `SellStopLossPips` = 30

##### **=== Trading Time Settings ===**
- `TradeAllDay` = **true** (recommended for testing - trades all day)
  - OR `false` if you want to test only London session
- `TradeLondonSession` = true (if TradeAllDay = false)
- `LondonStartHour` = 7
- `LondonStartMinute` = 0
- `LondonEndHour` = 10
- `NoFridayTrading` = false (set to true to skip Fridays)

##### **=== Entry Condition Settings ===**
- `RequireExhaustion` = **false** (recommended - allows more trades)
- `RequireRejection` = **false** (recommended - allows more trades)
- `RequireVolumeConf` = false
- `MinCandleWickPct` = 40

##### **=== Exit & Take Profit Settings ===**
- `TakeProfitMethod` = TO_MEAN
- `UseAutoCloseRule` = true
- `UseTrailingStop` = true
- `TrailingStopPips` = 20
- `TrailingActivationPips` = 15

##### **=== Telegram Settings (Optional) ===**
- `TelegramToken` = "" (leave empty for testing)
- `TelegramChatID` = "" (leave empty for testing)
- `TelegramDebugMode` = **true** (logs to file in tester)
- `EnableTradeEntryAlert` = false (disable for testing)
- `EnableTradeExitAlert` = false (disable for testing)

##### **=== Logging ===**
- `EnableDetailedLog` = **true** (recommended - see why trades are rejected)
- `EnableEmailAlerts` = false

### Step 4: Run the Test

1. Click **Start** button (green play icon)
2. Watch the progress bar
3. Check the **Journal** tab for any errors
4. Check the **Log** tab for detailed trade information

### Step 5: Analyze Results

After test completes, check:

1. **Results Tab**: 
   - Total trades
   - Win rate
   - Profit factor
   - Max drawdown
   - Total profit/loss

2. **Graph Tab**: 
   - Equity curve
   - Balance curve
   - Drawdown chart

3. **Report Tab**: 
   - Detailed trade-by-trade analysis
   - Monthly/weekly breakdown

4. **Log Tab**: 
   - Detailed logs (if `EnableDetailedLog = true`)
   - See why trades were rejected
   - Entry/exit reasons

### Step 6: Optimize Settings (Optional)

If you want to find optimal parameters:

1. Click **Settings** tab
2. Check **Optimization** checkbox
3. Select parameters to optimize (e.g., `LotSize`, `MaxTradesPerDay`)
4. Set **Optimization Method**: Genetic Algorithm (recommended)
5. Set **Optimization Criterion**: Balance (or Custom max)
6. Click **Start**

### Important Notes:

1. **Testing Mode**: 
   - **"Every tick"** = Most accurate but slowest
   - **"1 minute OHLC"** = Faster but less accurate
   - **"Open prices only"** = Fastest but least accurate (not recommended)

2. **Date Range**: 
   - Test at least 3-6 months for reliable results
   - Avoid testing only trending or only ranging periods

3. **Symbol**: 
   - Make sure you have historical data for the symbol
   - Download data: Tools → History Center → Download

4. **Initial Deposit**: 
   - Set realistic starting balance (e.g., $10,000)
   - Check **Settings → Deposit** field

5. **Spread**: 
   - Set realistic spread (e.g., 2-3 pips for EURUSD)
   - Check **Settings → Spread** field

### Recommended Test Configuration:

```
Symbol: EURUSD
Period: M5
Date Range: 2024.01.01 to 2024.12.31
Testing Mode: Every tick
Initial Deposit: $10,000
Spread: 2 pips

Key Settings:
- TradeAllDay = true
- RequireExhaustion = false
- RequireRejection = false
- MaxTradesPerDay = 5
- EnableDetailedLog = true
- TelegramDebugMode = true
```

### Troubleshooting:

1. **"No trades taken"**: 
   - Check `EnableDetailedLog = true` and review logs
   - Verify `TradeAllDay = true` or session times are correct
   - Check if `MaxTradesPerDay` limit is reached

2. **"Insufficient money"**: 
   - Reduce `LotSize` or `RiskPercentPerTrade`
   - Increase initial deposit

3. **"Slow testing"**: 
   - Use "1 minute OHLC" mode instead of "Every tick"
   - Reduce date range
   - Disable detailed logging

4. **"Errors in Journal"**: 
   - Check if symbol data is available
   - Verify all input parameters are valid
   - Check Expert tab for compilation errors

### Export Results:

1. Right-click on **Report** tab
2. Select **Save Report** or **Save Detailed Report**
3. Choose location and save as HTML

---

**Happy Testing! 📊**

