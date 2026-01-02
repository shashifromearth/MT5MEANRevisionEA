# Mean Reversion Expert Advisor (MQL5)

A comprehensive, time-boxed mean reversion trading system for EURUSD and GBPUSD on 5-minute timeframe.

## Architecture

This EA is built using Object-Oriented Programming (OOP) principles with a multi-file structure:

### Main File
- **MeanReversionEA.mq5** - Entry point, handles OnInit, OnTick, OnTrade events

### Core Classes (in `Classes/` directory)

1. **TimeManager.mqh** - Manages trading session time validation
   - London Session: 07:00-08:30 UTC
   - New York Session: 12:30-14:00 UTC
   - Strict time filtering with server time checking

2. **MeanCalculator.mqh** - Calculates mean using two methods:
   - **Asian Midpoint**: (Highest High + Lowest Low) / 2 from 00:00-05:00 UTC
   - **Session VWAP**: Volume-Weighted Average Price for current session

3. **ExhaustionDetector.mqh** - Detects three exhaustion patterns:
   - **Long Wick**: Wick ≥ 50% of candle range, close not at extreme
   - **Inside Candle**: High/Low inside previous candle
   - **Small Bodies**: Two consecutive candles with bodies < 40% of prior impulse

4. **RiskManager.mqh** - Manages risk parameters:
   - Stop Loss: MIN(2 pips beyond swing extreme, 0.5 × ATR(14))
   - Take Profit: TO_MEAN or 75% of distance from mean
   - Auto-close monitoring: Closes if no reversion within 3 candles

5. **SessionManager.mqh** - Manages session trade limits:
   - Maximum 2 trades per session
   - 15-minute cooldown after 1 loss
   - Stop trading after 2 losses in session
   - Daily reset at 00:00 UTC

6. **ValidationChecker.mqh** - Validates trade setups:
   - Higher timeframe trend filter
   - Price crossed mean check
   - News filter (placeholder for integration)
   - Momentum candle detection

7. **TradeExecutor.mqh** - Handles order execution:
   - Fixed lot size or money management
   - Risk percentage calculation
   - Order placement with SL/TP

8. **BuyTrade.mqh** - Long trade logic:
   - Entry: High of exhaustion candle + 0.2 pip
   - Validates price < Mean - Distance_Filter

9. **SellTrade.mqh** - Short trade logic:
   - Entry: Low of exhaustion candle - 0.2 pip
   - Validates price > Mean + Distance_Filter

10. **Logger.mqh** - Comprehensive logging:
    - File logging with daily rotation
    - Email alerts (optional)
    - Trade, warning, error, and violation logging

## Key Features

### Trading Rules

1. **Time Restrictions**: Trades only during London (07:00-08:30 UTC) and New York (12:30-14:00 UTC) sessions

2. **Distance Filter**: Minimum distance from mean = MAX(1 × ATR(14), 0.3% of current price)

3. **Exhaustion Patterns**: Requires one of three patterns before entry

4. **Entry Rules**:
   - **Long**: Price < Mean - Distance_Filter + exhaustion pattern
   - **Short**: Price > Mean + Distance_Filter + exhaustion pattern

5. **Risk Management**:
   - Stop Loss: Never moved after placement
   - Take Profit: Configurable (to mean or 75% of distance)
   - Auto-close: If no reversion within 3 candles

6. **Session Management**:
   - Max 2 trades per session
   - Cooldown after losses
   - Automatic session reset

### Input Parameters

```
Trade Settings:
- LotSize: Fixed lot size (default: 0.01)
- UseMoneyManagement: Enable money management (default: false)
- RiskPercent: Risk percentage for MM (default: 1.0%)

Mean Calculation:
- MeanMethod: ASIAN_MIDPOINT or SESSION_VWAP
- UseATRFilter: Enable ATR-based distance filter

Exit Settings:
- TakeProfitMethod: TO_MEAN or SEVENTY_FIVE_PERCENT
- UseAutoCloseRule: Enable auto-close on failed reversion

Session Times (UTC):
- LondonStartHour/Minute: 7:00
- LondonEndHour/Minute: 8:30
- NYStartHour/Minute: 12:30
- NYEndHour/Minute: 14:00

Risk Management:
- MaxTradesPerSession: 2
- EnableLossCoolDown: true
- LossCoolDownMinutes: 15

Logging:
- EnableDetailedLog: true
- EnableEmailAlerts: false
```

## Installation

1. Copy all files to your MetaTrader 5 `MQL5/Experts/` directory
2. Ensure the `Classes/` folder is in the same directory as `MeanReversionEA.mq5`
3. Compile the EA in MetaEditor
4. Attach to EURUSD or GBPUSD chart with M5 timeframe

## Usage

1. **Backtesting**: Use Strategy Tester with:
   - Symbol: EURUSD or GBPUSD
   - Period: M5 (5 minutes)
   - Date range: Include London and NY sessions
   - Model: Every tick

2. **Live Trading**:
   - Ensure server time is set to UTC
   - Verify time synchronization
   - Start with minimum lot size
   - Monitor logs for rule violations

## Optimization Goals

- **Win Rate**: 63-70%
- **Risk-Reward**: 1:0.5 to 1:1
- **Maximum Drawdown**: <8%
- **Average Trade Duration**: 5-20 minutes

## Important Notes

1. **Server Time**: The EA uses server time (TimeCurrent()). Ensure your broker's server time is UTC or adjust session times accordingly.

2. **News Filter**: The news filter is a placeholder. For production use, integrate with an economic calendar API.

3. **Auto-Close Rule**: This is a critical safety feature. If price doesn't start reverting within 3 candles, the position is closed automatically.

4. **Session Reset**: Daily reset occurs at 00:00 UTC. All counters reset at this time.

5. **Position Monitoring**: The EA monitors positions continuously and enforces the auto-close rule even outside trading sessions.

## Logging

Logs are written to:
- Terminal: All messages (if detailed logging enabled)
- File: `MeanReversionEA_YYYYMMDD.log` in `MQL5/Files/Common/`
- Email: Alerts sent if enabled (requires email configuration in MT5)

## Safety Features

- Strict time filtering (no trades outside sessions)
- Distance filter validation
- Trend filter (rejects strong trend days)
- Session trade limits
- Loss cooldown periods
- Auto-close on failed reversion
- Comprehensive validation checks

## Disclaimer

This EA is for educational purposes. Always test thoroughly in demo accounts before live trading. Past performance does not guarantee future results. Use at your own risk.

