//+------------------------------------------------------------------+
//|                                          MeanReversionEA.mq5     |
//|                        Time-Boxed Mean Reversion Strategy EA      |
//|                        EURUSD & GBPUSD on M5 Timeframe           |
//+------------------------------------------------------------------+
#property copyright "MQL5 Expert Advisor"
#property version   "1.00"
#property strict

#include "Classes/Enums.mqh"
#include "Classes/TimeManager.mqh"
#include "Classes/MeanCalculator.mqh"
#include "Classes/ExhaustionDetector.mqh"
#include "Classes/RiskManager.mqh"
#include "Classes/SessionManager.mqh"
#include "Classes/ValidationChecker.mqh"
#include "Classes/TradeExecutor.mqh"
#include "Classes/BuyTrade.mqh"
#include "Classes/SellTrade.mqh"
#include "Classes/Logger.mqh"
#include "Classes/DeadZoneManager.mqh"
#include "Classes/PerformanceMetrics.mqh"
#include "Classes/MultipleTPManager.mqh"
#include "Classes/VWAPMagnetTrade.mqh"
#include "Classes/LiquidityMagnet.mqh"
#include "Classes/ProfessionalTradeManager.mqh"
#include "Classes/RejectionDetector.mqh"
#include "Classes/TelegramAlert.mqh"

//+------------------------------------------------------------------+
//| Input Parameters - Highly Customizable                          |
//+------------------------------------------------------------------+

//=== TRADE QUANTITY & POSITION SIZING ===
input group "=== Trade Quantity Settings ===";
input double   LotSize           = 0.10;   // Fixed lot size (0.10 = micro lot, recommended for $10K account)
input bool     UseMoneyManagement = false; // If true, use risk-based position sizing
input double   RiskPercentPerTrade = 0.75; // Risk % per trade (if UseMoneyManagement = true)

//=== DAILY TRADE LIMITS ===
input group "=== Daily Trade Limits ===";
input int      MaxTradesPerDay  = 3;      // Maximum trades per day (recommended: 2-5 for quality)
input double   MaxDailyLossUSD  = 100.0;  // Stop trading if daily loss exceeds this (USD)
input double   MaxSingleTradeLossUSD = 50.0; // Alert if single trade loss exceeds this (USD)

//=== BUY TRADE SETTINGS ===
input group "=== Buy (Long) Trade Settings ===";
input bool     EnableBuyTrades  = true;   // Enable/Disable buy trades
input double   BuyLotSize       = 0.10;   // Lot size for buy trades (0 = use default LotSize)
input bool     UseBuySpecificSL = false;  // Use specific SL for buy trades
input double   BuyStopLossPips  = 30;     // Stop loss in pips for buy trades

//=== SELL TRADE SETTINGS ===
input group "=== Sell (Short) Trade Settings ===";
input bool     EnableSellTrades = true;   // Enable/Disable sell trades
input double   SellLotSize      = 0.10;   // Lot size for sell trades (0 = use default LotSize)
input bool     UseSellSpecificSL = false; // Use specific SL for sell trades
input double   SellStopLossPips  = 30;     // Stop loss in pips for sell trades

//=== TIME & SESSION SETTINGS ===
input group "=== Trading Time Settings ===";
input bool     TradeAllDay      = false;  // If true, trade all day (ignore session limits)
input bool     TradeLondonSession = true; // Trade during London session (07:00-10:00 UTC)
input int      LondonStartHour   = 7;     // London session start hour (UTC)
input int      LondonStartMinute = 0;     // London session start minute
input int      LondonEndHour     = 10;    // London session end hour (UTC) - no entries after this
input int      TradeMaxDurationHours = 3; // Maximum trade duration (hours) before auto-close
input bool     NoFridayTrading  = true;   // Disable trading on Fridays

//=== MEAN CALCULATION SETTINGS ===
input group "=== Mean Calculation Settings ===";
input MEAN_TYPE MeanMethod       = ASIAN_MIDPOINT; // Mean calculation method
input bool     UseATRFilter      = true;  // Use ATR-based distance filter
input int      ATR_Period        = 14;   // ATR period for calculations

//=== ENTRY CONDITIONS ===
input group "=== Entry Condition Settings ===";
input bool     RequireExhaustion = false; // Require exhaustion pattern for entry (default: false for more trades)
input bool     RequireRejection  = false; // Require rejection pattern at key levels (default: false for more trades)
input bool     RequireVolumeConf = false; // Require volume confirmation
input int      MinCandleWickPct  = 40;    // Minimum wick % for pin bars (40% = strong rejection)

//=== EXIT & TAKE PROFIT SETTINGS ===
input group "=== Exit & Take Profit Settings ===";
input TP_METHOD TakeProfitMethod = TO_MEAN; // Take profit method
input bool     UseAutoCloseRule  = true;  // Auto-close if trade not moving toward target
input bool     UseTrailingStop   = true;  // Use trailing stop loss
input double   TrailingStopPips  = 20;    // Trailing stop distance (pips)
input double   TrailingActivationPips = 15; // Activate trailing after X pips profit

//=== TELEGRAM ALERT SETTINGS ===
input group "=== Telegram Alert Settings ===";
input string   TelegramToken     = "7481766478:AAE9SU9K15g09fTE3iAwQdQWz_5ADyvMoG4";
input string   ChatID            = "6583697962";
input bool     EnableTradeEntryAlert = true;  // Alert on trade entry
input bool     EnableTradeExitAlert = true;  // Alert on trade exit
input bool     EnableMarginAlert = true;      // Alert if margin exceeds limit
input bool     EnableLossAlert  = true;       // Alert if single trade loss exceeds limit
input double   MaxMarginUtilizedUSD = 2000.0; // Alert if margin > this amount (USD)
input bool     TelegramDebugMode = false;     // If true, log to file instead of sending

//=== LOGGING SETTINGS ===
input group "=== Logging Settings ===";
input bool     EnableDetailedLog = true;  // Enable detailed logging
input bool     EnableEmailAlerts = false;  // Enable email alerts (if supported)

//+------------------------------------------------------------------+
//| Global Objects                                                   |
//+------------------------------------------------------------------+
CTimeManager*         g_TimeManager;
CMeanCalculator*      g_MeanCalculator;
CExhaustionDetector*  g_ExhaustionDetector;
CRiskManager*         g_RiskManager;
CSessionManager*      g_SessionManager;
CValidationChecker*   g_ValidationChecker;
CTradeExecutor*       g_TradeExecutor;
CBuyTrade*            g_BuyTrade;
CSellTrade*           g_SellTrade;
CLogger*              g_Logger;
CDeadZoneManager*     g_DeadZoneManager;
CPerformanceMetrics*  g_PerformanceMetrics;
CMultipleTPManager*   g_MultipleTPManager;
CVWAPMagnetTrade*     g_VWAPMagnetTrade;
CLiquidityMagnet*      g_LiquidityMagnet;
CProfessionalTradeManager* g_ProfessionalTradeManager;
CRejectionDetector*    g_RejectionDetector;
CTelegramAlert*        g_TelegramAlert;

string g_CurrentSymbol;
datetime g_LastBarTime = 0;
int g_ATRHandle = INVALID_HANDLE;
const int EA_MAGIC_NUMBER = 123456;
ulong g_LastCloseAttemptTicket = 0; // Prevent multiple close attempts
datetime g_LastCloseAttemptTime = 0;

//+------------------------------------------------------------------+
//| Check if EA has an open position (with magic number filter)     |
//+------------------------------------------------------------------+
bool HasEAPosition(string symbol)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == EA_MAGIC_NUMBER)
            {
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get EA position ticket (with magic number filter)                |
//+------------------------------------------------------------------+
ulong GetEAPositionTicket(string symbol)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL) == symbol && 
               PositionGetInteger(POSITION_MAGIC) == EA_MAGIC_NUMBER)
            {
               return ticket;
            }
         }
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Get daily loss in USD                                            |
//+------------------------------------------------------------------+
double GetDailyLoss()
{
   double totalLoss = 0;
   datetime dayStart = TimeCurrent() - (TimeCurrent() % 86400);
   
   HistorySelect(dayStart, TimeCurrent());
   int total = HistoryDealsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket > 0)
      {
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == EA_MAGIC_NUMBER &&
            HistoryDealGetString(dealTicket, DEAL_SYMBOL) == g_CurrentSymbol)
         {
            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            
            totalLoss += profit + swap + commission;
         }
      }
   }
   
   return (totalLoss < 0) ? MathAbs(totalLoss) : 0;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize current symbol
   g_CurrentSymbol = _Symbol;
   
   // Initialize ATR indicator
   g_ATRHandle = iATR(g_CurrentSymbol, PERIOD_M5, 14);
   if(g_ATRHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create ATR indicator handle");
      return INIT_FAILED;
   }
   
   // Initialize all manager classes
   g_Logger = new CLogger(EnableDetailedLog, EnableEmailAlerts);
   // TimeManager: Use LondonEndHour as end, set NY session to 12:30-14:00 UTC
   g_TimeManager = new CTimeManager(LondonStartHour, LondonStartMinute, LondonEndHour, 0,
                                    12, 30, 14, 0, g_Logger);
   g_MeanCalculator = new CMeanCalculator(MeanMethod, g_CurrentSymbol, g_Logger);
   g_ExhaustionDetector = new CExhaustionDetector(g_CurrentSymbol, g_Logger);
   g_RiskManager = new CRiskManager(TakeProfitMethod, UseAutoCloseRule, g_ATRHandle, g_CurrentSymbol, g_Logger);
   g_SessionManager = new CSessionManager(MaxTradesPerDay, false, 0, g_Logger);
   g_ValidationChecker = new CValidationChecker(g_CurrentSymbol, g_ATRHandle, g_Logger);
   g_TradeExecutor = new CTradeExecutor(LotSize, UseMoneyManagement, RiskPercentPerTrade, g_CurrentSymbol, g_Logger);
   g_BuyTrade = new CBuyTrade(g_TradeExecutor, g_RiskManager, g_MeanCalculator, g_ExhaustionDetector,
                              g_ValidationChecker, g_CurrentSymbol, g_ATRHandle, g_Logger);
   g_SellTrade = new CSellTrade(g_TradeExecutor, g_RiskManager, g_MeanCalculator, g_ExhaustionDetector,
                                g_ValidationChecker, g_CurrentSymbol, g_ATRHandle, g_Logger);
   g_DeadZoneManager = new CDeadZoneManager(g_CurrentSymbol, g_Logger, g_TimeManager);
   g_PerformanceMetrics = new CPerformanceMetrics(g_Logger);
   g_MultipleTPManager = new CMultipleTPManager(g_CurrentSymbol, g_Logger, g_MeanCalculator);
   g_VWAPMagnetTrade = new CVWAPMagnetTrade(g_CurrentSymbol, g_Logger, g_MeanCalculator);
   g_LiquidityMagnet = new CLiquidityMagnet(g_CurrentSymbol, g_Logger);
   g_ProfessionalTradeManager = new CProfessionalTradeManager(g_CurrentSymbol, g_Logger, g_MeanCalculator);
   g_RejectionDetector = new CRejectionDetector(g_CurrentSymbol, g_Logger);
   g_TelegramAlert = new CTelegramAlert(TelegramToken, ChatID, EnableTradeEntryAlert, EnableTradeExitAlert,
                                        EnableMarginAlert, EnableLossAlert, MaxMarginUtilizedUSD, MaxSingleTradeLossUSD,
                                        TelegramDebugMode, g_Logger);
   
   g_Logger.LogInfo("Mean Reversion EA initialized successfully");
   g_Logger.LogInfo(StringFormat("Symbol: %s, Mean Method: %d, TP Method: %d", 
                                  g_CurrentSymbol, MeanMethod, TakeProfitMethod));
   g_Logger.LogInfo("Dead Zone: 05:00-07:00 UTC (10:30-12:30 IST) - Trading blocked");
   g_Logger.LogInfo("Risk:Reward validation: 1:0.5 to 1:1 required");
   g_Logger.LogInfo("Trade duration limit: 20 minutes");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up indicators
   if(g_ATRHandle != INVALID_HANDLE)
      IndicatorRelease(g_ATRHandle);
   
   // Delete all objects
   if(g_Logger != NULL) delete g_Logger;
   if(g_TimeManager != NULL) delete g_TimeManager;
   if(g_MeanCalculator != NULL) delete g_MeanCalculator;
   if(g_ExhaustionDetector != NULL) delete g_ExhaustionDetector;
   if(g_RiskManager != NULL) delete g_RiskManager;
   if(g_SessionManager != NULL) delete g_SessionManager;
   if(g_ValidationChecker != NULL) delete g_ValidationChecker;
   if(g_TradeExecutor != NULL) delete g_TradeExecutor;
   if(g_BuyTrade != NULL) delete g_BuyTrade;
   if(g_SellTrade != NULL) delete g_SellTrade;
   if(g_DeadZoneManager != NULL) delete g_DeadZoneManager;
   if(g_PerformanceMetrics != NULL) delete g_PerformanceMetrics;
   if(g_MultipleTPManager != NULL) delete g_MultipleTPManager;
   if(g_VWAPMagnetTrade != NULL) delete g_VWAPMagnetTrade;
   if(g_LiquidityMagnet != NULL) delete g_LiquidityMagnet;
   if(g_ProfessionalTradeManager != NULL) delete g_ProfessionalTradeManager;
   if(g_RejectionDetector != NULL) delete g_RejectionDetector;
   if(g_TelegramAlert != NULL) delete g_TelegramAlert;
   
   Print("Mean Reversion EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if new bar formed
   datetime currentBarTime = iTime(g_CurrentSymbol, PERIOD_M5, 0);
   bool isNewBar = (currentBarTime != g_LastBarTime);
   
   if(isNewBar)
   {
      g_LastBarTime = currentBarTime;
      g_MeanCalculator.OnNewBar();
      g_SessionManager.OnNewBar();
      g_DeadZoneManager.OnNewBar();
      g_PerformanceMetrics.OnNewBar();
      g_VWAPMagnetTrade.OnNewBar();
      g_ProfessionalTradeManager.OnNewBar();
      
      // Update Asian range in DeadZoneManager
      if(g_MeanCalculator.IsAsianRangeValid())
      {
         double asianHigh = g_MeanCalculator.GetAsianHigh();
         double asianLow = g_MeanCalculator.GetAsianLow();
         double asianMid = g_MeanCalculator.GetAsianMid();
         g_DeadZoneManager.UpdateAsianRange(asianHigh, asianLow);
         
         // Update liquidity magnet tracking
         double currentPrice = SymbolInfoDouble(g_CurrentSymbol, SYMBOL_BID);
         bool isDeadZone = g_TimeManager.IsDeadZone();
         g_LiquidityMagnet.OnNewBar(currentPrice, asianHigh, asianLow, asianMid, isDeadZone);
      }
   }
   
   // PROFESSIONAL TRADE MANAGEMENT - Always active (even outside sessions)
   if(HasEAPosition(g_CurrentSymbol))
   {
      ulong ticket = GetEAPositionTicket(g_CurrentSymbol);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         // Check for loss alert
         if(g_TelegramAlert != NULL)
         {
            g_TelegramAlert.CheckTradeLoss(ticket, g_CurrentSymbol);
         }
         
         g_ProfessionalTradeManager.ManageTrade();
         
         if(g_ProfessionalTradeManager.ShouldExitTrade())
         {
            bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            string exitReason = g_ProfessionalTradeManager.GetExitReason();
            double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_DEAL;
            request.symbol = g_CurrentSymbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = isLong ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.deviation = 10;
            request.magic = EA_MAGIC_NUMBER;
            request.comment = StringFormat("Professional exit: %s", exitReason);
            
            if(OrderSend(request, result))
            {
               g_Logger.LogInfo(StringFormat("Trade closed: %s", exitReason));
               
               // Send Telegram alert for trade exit
               if(g_TelegramAlert != NULL)
               {
                  double exitPrice = isLong ? SymbolInfoDouble(g_CurrentSymbol, SYMBOL_BID) : SymbolInfoDouble(g_CurrentSymbol, SYMBOL_ASK);
                  double profit = PositionGetDouble(POSITION_PROFIT);
                  double point = SymbolInfoDouble(g_CurrentSymbol, SYMBOL_POINT);
                  int digits = (int)SymbolInfoInteger(g_CurrentSymbol, SYMBOL_DIGITS);
                  double pipValue = (digits == 3 || digits == 5) ? point * 10 : point;
                  double profitPips = isLong ? 
                                     ((exitPrice - entryPrice) / pipValue) : 
                                     ((entryPrice - exitPrice) / pipValue);
                  
                  g_TelegramAlert.AlertTradeExit(isLong, exitPrice, profit, profitPips, g_CurrentSymbol, exitReason);
                  g_TelegramAlert.CheckMarginUtilization();
               }
            }
         }
      }
   }
   
   // CRITICAL: Check dead zone - do NOT trade during dead zone
   if(g_TimeManager.IsDeadZone())
   {
      // Only monitor existing positions, do not enter new trades
      g_RiskManager.MonitorPositions(g_MeanCalculator);
      return;
   }
   
   // Check if we're in a valid trading session
   if(!g_TimeManager.IsTradingSession())
   {
      // Monitor existing positions for auto-close rule
      g_RiskManager.MonitorPositions(g_MeanCalculator);
      return;
   }
   
   // Check session trade limits
   if(!g_SessionManager.CanTrade())
   {
      if(UseAutoCloseRule)
         g_RiskManager.MonitorPositions(g_MeanCalculator);
      return;
   }
   
   // CRITICAL: Check if we already have an open position (EA's position only)
   // This check MUST happen BEFORE any trade execution logic
   if(HasEAPosition(g_CurrentSymbol))
   {
      ulong ticket = GetEAPositionTicket(g_CurrentSymbol);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         // Monitor existing position ONLY - NO NEW TRADES
         bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         if(EnableDetailedLog)
         {
            g_Logger.LogInfo(StringFormat("Position exists (Ticket: %llu) - Monitoring only, NO NEW TRADE", ticket));
         }
         
         // PROFESSIONAL TRADE MANAGEMENT (Priority 1)
         g_ProfessionalTradeManager.ManageTrade();
         
         // Check if professional manager says to exit
         if(g_ProfessionalTradeManager.ShouldExitTrade())
         {
            // Prevent multiple close attempts for same position in same second
            datetime currentTime = TimeCurrent();
            if(g_LastCloseAttemptTicket == ticket && (currentTime - g_LastCloseAttemptTime) < 1)
            {
               return; // Already tried to close this position recently
            }
            
            g_LastCloseAttemptTicket = ticket;
            g_LastCloseAttemptTime = currentTime;
            
            string exitReason = g_ProfessionalTradeManager.GetExitReason();
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_DEAL;
            request.position = ticket; // CRITICAL: Specify which position to close
            request.symbol = g_CurrentSymbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = isLong ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.deviation = 10;
            request.magic = EA_MAGIC_NUMBER;
            request.comment = StringFormat("Professional exit: %s", exitReason);
            
            if(OrderSend(request, result))
            {
               g_Logger.LogInfo(StringFormat("Trade closed: %s", exitReason));
               g_LastCloseAttemptTicket = 0; // Reset on success
            }
            else
            {
               // If "No money" error, log and stop trying (prevent infinite loop)
               if(result.retcode == 10004 || result.retcode == 10019) // TRADE_RETCODE_NO_MONEY or TRADE_RETCODE_NOT_ENOUGH_MONEY
               {
                  g_Logger.LogWarning("Insufficient margin to close position - will retry when margin available");
                  // Don't reset ticket - prevent retry for 60 seconds
                  g_LastCloseAttemptTime = currentTime + 60;
               }
               else
               {
                  g_Logger.LogError(StringFormat("Failed to close position: %s (retcode: %d)", result.comment, result.retcode));
               }
            }
            return;
         }
         
         // Monitor multiple TPs (if not using professional manager)
         if(g_RiskManager.IsMultipleTPMethod() && !g_ProfessionalTradeManager.ShouldExitTrade())
         {
            g_MultipleTPManager.MonitorPosition(ticket);
         }
         
         // Monitor VWAP Magnet Trade exit
         double vwap = g_MeanCalculator.GetMean();
         if(vwap > 0)
         {
            double currentPrice = SymbolInfoDouble(g_CurrentSymbol, SYMBOL_ASK);
            if(!isLong) currentPrice = SymbolInfoDouble(g_CurrentSymbol, SYMBOL_BID);
            
            if(g_VWAPMagnetTrade.ShouldExitVWAPMagnetTrade(currentPrice, vwap))
            {
               // Close VWAP Magnet Trade
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               request.action = TRADE_ACTION_DEAL;
               request.position = ticket; // CRITICAL: Specify which position to close
               request.symbol = g_CurrentSymbol;
               request.volume = PositionGetDouble(POSITION_VOLUME);
               request.type = isLong ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
               request.deviation = 10;
               request.magic = EA_MAGIC_NUMBER;
               request.comment = "VWAP Magnet Trade exit";
               if(!OrderSend(request, result))
               {
                  // If "No money" error, stop trying (prevent infinite loop)
                  if(result.retcode == 10004 || result.retcode == 10019) // TRADE_RETCODE_NO_MONEY or TRADE_RETCODE_NOT_ENOUGH_MONEY
                  {
                     g_Logger.LogWarning("Insufficient margin to close VWAP Magnet Trade - will retry when margin available");
                  }
                  else
                  {
                     g_Logger.LogError(StringFormat("Failed to close VWAP Magnet Trade: %s (retcode: %d)", result.comment, result.retcode));
                  }
               }
            }
         }
         
         if(UseAutoCloseRule)
            g_RiskManager.MonitorPositions(g_MeanCalculator);
         
         // CRITICAL: Return here - NO NEW TRADE while position exists
         return;
      }
   }
   
   // NEW LOGIC: Last Day Mean Reversion (24-hour high/low/mid)
   // Check trading time settings
   if(!TradeAllDay)
   {
      if(TradeLondonSession && !g_TimeManager.IsLondonSession())
      {
         return; // Only trade during London session if enabled
      }
      else if(!TradeLondonSession)
      {
         return; // No trading sessions enabled
      }
   }
   
   // Check Friday trading restriction
   if(NoFridayTrading)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5) // Friday
      {
         if(EnableDetailedLog)
            g_Logger.LogInfo("Trading disabled on Friday");
         return;
      }
   }
   
   // Check daily trade limit
   if(!g_SessionManager.CanTrade())
   {
      if(EnableDetailedLog)
         g_Logger.LogInfo(StringFormat("Daily trade limit reached: %d/%d", 
                                      g_SessionManager.GetTradesToday(), MaxTradesPerDay));
      return;
   }
   
   // Check buy/sell trade enable flags
   if(!EnableBuyTrades && !EnableSellTrades)
   {
      return; // Both trade types disabled
   }
   
   // Get current market data
   double ask = SymbolInfoDouble(g_CurrentSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_CurrentSymbol, SYMBOL_BID);
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_ATRHandle, 0, 0, 1, atr) <= 0)
   {
      g_Logger.LogError("Failed to copy ATR buffer");
      return;
   }
   
   // Get last day (24-hour) high, low, and mid
   double lastDayHigh = g_MeanCalculator.GetLastDayHigh();
   double lastDayLow = g_MeanCalculator.GetLastDayLow();
   double lastDayMid = g_MeanCalculator.GetLastDayMid();
   
   if(!g_MeanCalculator.IsLastDayRangeValid())
   {
      if(EnableDetailedLog)
         g_Logger.LogWarning("Last day range not valid - waiting for data");
      return;
   }
   
   // Check daily loss limit
   if(MaxDailyLossUSD > 0 && g_TelegramAlert != NULL)
   {
      double dailyLoss = GetDailyLoss();
      if(dailyLoss >= MaxDailyLossUSD)
      {
         if(EnableDetailedLog)
            g_Logger.LogWarning(StringFormat("Daily loss limit reached: $%.2f (Max: $%.2f) - Trading stopped", 
                                            dailyLoss, MaxDailyLossUSD));
         return;
      }
   }
   
   // Check exhaustion requirement (if enabled)
   int exhaustionType = g_ExhaustionDetector.DetectExhaustion();
   bool hasExhaustion = (exhaustionType != EXHAUSTION_NONE);
   
   if(RequireExhaustion && !hasExhaustion)
   {
      if(EnableDetailedLog)
         g_Logger.LogWarning("Trade rejected: No exhaustion pattern (RequireExhaustion = true)");
      return;
   }
   
   double point = SymbolInfoDouble(g_CurrentSymbol, SYMBOL_POINT);
   // Increased tolerance: Use ATR-based or 0.3% of price, whichever is larger (was 15 pips)
   double atrTolerance = atr[0] * 0.5; // 50% of ATR
   double percentTolerance = ask * 0.003; // 0.3% of price
   double tolerance = MathMax(atrTolerance, percentTolerance); // Use larger tolerance
   
   // Determine which level price is near
   bool nearHigh = MathAbs(ask - lastDayHigh) <= tolerance;
   bool nearLow = MathAbs(ask - lastDayLow) <= tolerance;
   bool nearMid = MathAbs(ask - lastDayMid) <= tolerance;
   
   bool shouldTrade = false;
   bool isLongSetup = false;
   bool isShortSetup = false;
   double targetMean = 0;
   double distanceFromMean = 0;
   
   // Scenario 1: Price near last day HIGH + rejection → SHORT
   if(nearHigh)
   {
      // Check for rejection wick/candle at high
      if((!RequireRejection || g_RejectionDetector.DetectRejection(lastDayHigh, false))) // false = short (rejection at high)
      {
         isShortSetup = true;
         targetMean = lastDayMid; // Target mid
         distanceFromMean = ask - lastDayMid;
         shouldTrade = true;
         
         if(EnableDetailedLog)
            g_Logger.LogInfo(StringFormat("SHORT setup: Price near last day HIGH (%.5f) with rejection → Target MID (%.5f)", 
                                        lastDayHigh, lastDayMid));
      }
      else
      {
         // Wait for rejection candle - check for trend continuation
         // If price continues up (no rejection), don't trade
         if(EnableDetailedLog)
            g_Logger.LogInfo("Price near HIGH but no rejection yet - waiting for rejection confirmation");
         return;
      }
   }
   // Scenario 2: Price near last day LOW + rejection → LONG
   else if(nearLow)
   {
      // Check for rejection wick/candle at low
      if((!RequireRejection || g_RejectionDetector.DetectRejection(lastDayLow, true))) // true = long (rejection at low)
      {
         isLongSetup = true;
         targetMean = lastDayMid; // Target mid
         distanceFromMean = lastDayMid - ask;
         shouldTrade = true;
         
         if(EnableDetailedLog)
            g_Logger.LogInfo(StringFormat("LONG setup: Price near last day LOW (%.5f) with rejection → Target MID (%.5f)", 
                                        lastDayLow, lastDayMid));
      }
      else
      {
         // Wait for rejection candle - check for trend continuation
         // If price continues down (no rejection), don't trade
         if(EnableDetailedLog)
            g_Logger.LogInfo("Price near LOW but no rejection yet - waiting for rejection confirmation");
         return;
      }
   }
   // Scenario 3: Price near MID → monitor direction
   else if(nearMid)
   {
      // Detect which direction price will go from mid
      int midDirection = g_RejectionDetector.DetectMidDirection(lastDayMid, lastDayHigh, lastDayLow);
      
      if(midDirection == 1)
      {
         // Going to HIGH → SHORT from mid
         if(g_RejectionDetector.DetectRejection(lastDayMid, false))
         {
            isShortSetup = true;
            targetMean = lastDayHigh; // Target high
            distanceFromMean = ask - lastDayHigh;
            shouldTrade = true;
            
            if(EnableDetailedLog)
               g_Logger.LogInfo(StringFormat("SHORT setup: Price near MID (%.5f), rejected upward → Target HIGH (%.5f)", 
                                           lastDayMid, lastDayHigh));
         }
      }
      else if(midDirection == -1)
      {
         // Going to LOW → LONG from mid
         if((!RequireRejection || g_RejectionDetector.DetectRejection(lastDayMid, true)))
         {
            isLongSetup = true;
            targetMean = lastDayLow; // Target low
            distanceFromMean = lastDayLow - ask;
            shouldTrade = true;
            
            if(EnableDetailedLog)
               g_Logger.LogInfo(StringFormat("LONG setup: Price near MID (%.5f), rejected downward → Target LOW (%.5f)", 
                                           lastDayMid, lastDayLow));
         }
      }
      else
      {
         // Unclear direction - wait
         if(EnableDetailedLog)
            g_Logger.LogInfo("Price near MID but direction unclear - monitoring");
         return;
      }
   }
   else
   {
      // Price not near any key level
      if(EnableDetailedLog)
         g_Logger.LogInfo(StringFormat("Price not near key levels: Ask=%.5f, High=%.5f, Mid=%.5f, Low=%.5f", 
                                      ask, lastDayHigh, lastDayMid, lastDayLow));
      return;
   }
   
   if(!shouldTrade)
   {
      return;
   }
   
   // Validate setup
   if(!g_ValidationChecker.IsValidSetup(targetMean, ask, bid))
   {
      if(EnableDetailedLog)
         g_Logger.LogWarning("Setup validation failed - rejecting trade");
      return;
   }
   
   // Pre-calculate SL/TP to check RR
   double preStopLoss = 0;
   double preTakeProfit = 0;
   if(isLongSetup)
   {
      preStopLoss = g_RiskManager.GetStopLoss(true, ask, atr[0]);
      preTakeProfit = g_RiskManager.GetTakeProfit(true, ask, targetMean, distanceFromMean);
   }
   else if(isShortSetup)
   {
      preStopLoss = g_RiskManager.GetStopLoss(false, ask, atr[0]);
      preTakeProfit = g_RiskManager.GetTakeProfit(false, ask, targetMean, distanceFromMean);
   }
   
   // RR check
   if((isLongSetup || isShortSetup) && preStopLoss > 0 && preTakeProfit > 0)
   {
      if(!g_RiskManager.ValidateRiskReward(isLongSetup, ask, preStopLoss, preTakeProfit))
      {
         if(EnableDetailedLog)
            g_Logger.LogWarning("Trade rejected: Risk:reward ratio < 1:1");
         return;
      }
   }
   
   // VWAP Magnet Trade logic removed - using last day mean reversion instead
   
   // Wait for candle close to confirm rejection (entry timing)
   datetime currentTime = TimeCurrent();
   int secondsIntoBar = (int)(currentTime - currentBarTime);
   
   // Wait for candle close (if less than 4 minutes into 5-minute bar)
   if(secondsIntoBar < 240)
   {
      if(EnableDetailedLog)
         g_Logger.LogInfo("Waiting for rejection candle close before entry");
      return; // Wait for candle to close
   }
   
   // Log trade setup summary
   if(EnableDetailedLog)
   {
      string setupSummary = StringFormat("=== LAST DAY MEAN REVERSION SETUP ===\n" +
                                        "Direction: %s\n" +
                                        "Last Day High: %.5f\n" +
                                        "Last Day Mid: %.5f\n" +
                                        "Last Day Low: %.5f\n" +
                                        "Current Price: %.5f\n" +
                                        "Target: %.5f\n" +
                                        "Distance: %.5f",
                                        isLongSetup ? "LONG" : "SHORT",
                                        lastDayHigh, lastDayMid, lastDayLow,
                                        ask, targetMean, distanceFromMean);
      g_Logger.LogInfo(setupSummary);
   }
   
   // CRITICAL: Double-check position before execution (prevent race condition)
   if(HasEAPosition(g_CurrentSymbol))
   {
      if(EnableDetailedLog)
         g_Logger.LogWarning("Trade execution blocked: Position exists - preventing duplicate trade");
      return;
   }
   
   // Execute trade
   if(isLongSetup)
   {
      // TRIPLE-CHECK: Verify no position exists right before execution
      if(HasEAPosition(g_CurrentSymbol))
      {
         g_Logger.LogWarning("Trade execution blocked at final check: Position exists");
         return;
      }
      
      // Use targetMean instead of mean, and calculate distance filter
      double distanceFilter = g_ValidationChecker.CalculateDistanceFilter(ask, atr[0]);
      if(g_BuyTrade.ExecuteTrade(targetMean, distanceFilter, atr[0], EXHAUSTION_NONE))
      {
         // Count trade ONLY when we actually open a position
         g_SessionManager.OnTrade();
         g_PerformanceMetrics.OnTradeOpen();
         
         // Initialize professional trade manager
         if(HasEAPosition(g_CurrentSymbol))
         {
            ulong ticket = GetEAPositionTicket(g_CurrentSymbol);
            if(ticket > 0 && PositionSelectByTicket(ticket))
            {
               double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               double lotSize = PositionGetDouble(POSITION_VOLUME);
               double stopLoss = PositionGetDouble(POSITION_SL);
               double takeProfit = PositionGetDouble(POSITION_TP);
               
               // Send Telegram alert for trade entry
               if(g_TelegramAlert != NULL)
               {
                  g_TelegramAlert.AlertTradeEntry(true, entryPrice, lotSize, stopLoss, takeProfit, g_CurrentSymbol);
                  g_TelegramAlert.CheckMarginUtilization();
               }
               
               // Get London reaction levels (high/low from London session start)
               double londonReactionHigh = 0;
               double londonReactionLow = DBL_MAX;
               if(g_TimeManager.IsLondonSession())
               {
                  // Get London session candles
                  double high[], low[];
                  ArraySetAsSeries(high, true);
                  ArraySetAsSeries(low, true);
                  
                  // Get last 10 candles (London session)
                  if(CopyHigh(g_CurrentSymbol, PERIOD_M5, 0, 10, high) >= 10 &&
                     CopyLow(g_CurrentSymbol, PERIOD_M5, 0, 10, low) >= 10)
                  {
                     londonReactionHigh = high[ArrayMaximum(high, 0, 10)];
                     londonReactionLow = low[ArrayMinimum(low, 0, 10)];
                  }
               }
               
               double targetVWAP = g_MeanCalculator.GetLastDayMid(); // Use last day mid as VWAP
               if(targetVWAP <= 0) targetVWAP = targetMean;
               
               g_ProfessionalTradeManager.InitializeTrade(ticket, true, entryPrice, targetMean, targetVWAP, 
                                                          distanceFromMean, londonReactionHigh, londonReactionLow);
            }
         }
         
         // Set multiple TP targets if enabled (using last day levels)
         if(g_RiskManager.IsMultipleTPMethod() && g_MeanCalculator.IsLastDayRangeValid())
         {
            double lastDayHigh = g_MeanCalculator.GetLastDayHigh();
            double lastDayLow = g_MeanCalculator.GetLastDayLow();
            double lastDayMid = g_MeanCalculator.GetLastDayMid();
            double lastDayVWAP = lastDayMid; // Use mid as VWAP
            
            g_MultipleTPManager.SetTPTargets(true, ask, lastDayHigh, lastDayLow, lastDayMid, lastDayVWAP);
         }
      }
   }
   else if(isShortSetup)
   {
      // TRIPLE-CHECK: Verify no position exists right before execution
      if(HasEAPosition(g_CurrentSymbol))
      {
         g_Logger.LogWarning("Trade execution blocked at final check: Position exists");
         return;
      }
      
      // Use targetMean instead of mean, and calculate distance filter
      double distanceFilter = g_ValidationChecker.CalculateDistanceFilter(ask, atr[0]);
      if(g_SellTrade.ExecuteTrade(targetMean, distanceFilter, atr[0], EXHAUSTION_NONE))
      {
         // Count trade ONLY when we actually open a position
         g_SessionManager.OnTrade();
         g_PerformanceMetrics.OnTradeOpen();
         
         // Initialize professional trade manager
         // CRITICAL: Use HasEAPosition to filter by magic number
         if(HasEAPosition(g_CurrentSymbol))
         {
            ulong ticket = GetEAPositionTicket(g_CurrentSymbol);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
               return;
            double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double lotSize = PositionGetDouble(POSITION_VOLUME);
            double stopLoss = PositionGetDouble(POSITION_SL);
            double takeProfit = PositionGetDouble(POSITION_TP);
            
            // Get London reaction levels
            double londonReactionHigh = 0;
            double londonReactionLow = DBL_MAX;
            if(g_TimeManager.IsLondonSession())
            {
               double high[], low[];
               ArraySetAsSeries(high, true);
               ArraySetAsSeries(low, true);
               
               if(CopyHigh(g_CurrentSymbol, PERIOD_M5, 0, 10, high) >= 10 &&
                  CopyLow(g_CurrentSymbol, PERIOD_M5, 0, 10, low) >= 10)
               {
                  londonReactionHigh = high[ArrayMaximum(high, 0, 10)];
                  londonReactionLow = low[ArrayMinimum(low, 0, 10)];
               }
            }
            
            double targetVWAP = g_MeanCalculator.GetLastDayMid(); // Use last day mid as VWAP
            if(targetVWAP <= 0) targetVWAP = targetMean;
            
            g_ProfessionalTradeManager.InitializeTrade(ticket, false, entryPrice, targetMean, targetVWAP, 
                                                       distanceFromMean, londonReactionHigh, londonReactionLow);
            
            // Send Telegram alert for trade entry
            if(g_TelegramAlert != NULL)
            {
               g_TelegramAlert.AlertTradeEntry(false, entryPrice, lotSize, stopLoss, takeProfit, g_CurrentSymbol);
               g_TelegramAlert.CheckMarginUtilization();
            }
         }
         
         // Set multiple TP targets if enabled (using last day levels)
         if(g_RiskManager.IsMultipleTPMethod() && g_MeanCalculator.IsLastDayRangeValid())
         {
            double lastDayHigh = g_MeanCalculator.GetLastDayHigh();
            double lastDayLow = g_MeanCalculator.GetLastDayLow();
            double lastDayMid = g_MeanCalculator.GetLastDayMid();
            double lastDayVWAP = lastDayMid; // Use mid as VWAP
            
            g_MultipleTPManager.SetTPTargets(false, ask, lastDayHigh, lastDayLow, lastDayMid, lastDayVWAP);
         }
      }
   }
   
   // Monitor positions
   if(UseAutoCloseRule)
      g_RiskManager.MonitorPositions(g_MeanCalculator);
}

//+------------------------------------------------------------------+
//| Trade event handler                                              |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Check if we have an EA position (with magic number filter)
   if(HasEAPosition(g_CurrentSymbol))
   {
      // EA position exists - update risk manager (but DON'T count trade here)
      // Trade is counted when we actually execute it, not in OnTrade() event
      g_RiskManager.OnTrade();
   }
   else
   {
      // EA position was closed - check if it was a loss
      HistorySelect(TimeCurrent() - 86400, TimeCurrent()); // Last 24 hours
      int totalDeals = HistoryDealsTotal();
      
      if(totalDeals > 0)
      {
         // Find the most recent EA deal (magic number filter)
         ulong ticket = 0;
         for(int i = totalDeals - 1; i >= 0; i--)
         {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket > 0)
            {
               if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == EA_MAGIC_NUMBER &&
                  HistoryDealGetString(dealTicket, DEAL_SYMBOL) == g_CurrentSymbol)
               {
                  ticket = dealTicket;
                  break;
               }
            }
         }
         
         if(ticket > 0)
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
            double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            double totalProfit = profit + swap + commission;
            
            // Update performance metrics
            g_PerformanceMetrics.OnTradeClose(totalProfit);
            
            if(totalProfit < 0)
            {
               g_SessionManager.OnLoss();
               g_Logger.LogWarning(StringFormat("Trade closed with loss: %.2f (P: %.2f, S: %.2f, C: %.2f)", 
                                                 totalProfit, profit, swap, commission));
            }
            else
            {
               g_Logger.LogInfo(StringFormat("Trade closed with profit: %.2f (P: %.2f, S: %.2f, C: %.2f)", 
                                             totalProfit, profit, swap, commission));
            }
            
            // Log performance statistics
            g_PerformanceMetrics.LogStatistics();
         }
      }
   }
}

