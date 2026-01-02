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

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input string   TRADE_SETTINGS    = "--- Trade Settings ---";
input double   LotSize           = 1.0;
input bool     UseMoneyManagement = false;
input double   RiskPercent       = 1.0;
input string   Symbol1           = "EURUSD";
input string   Symbol2           = "GBPUSD";

input string   MEAN_SETTINGS     = "--- Mean Calculation ---";
input MEAN_TYPE MeanMethod       = ASIAN_MIDPOINT;
input bool     UseATRFilter      = true;

input string   EXIT_SETTINGS     = "--- Exit Settings ---";
input TP_METHOD TakeProfitMethod = TO_MEAN;
input bool     UseAutoCloseRule  = true;

input string   SESSION_SETTINGS  = "--- Session Times (UTC) ---";
input int      LondonStartHour   = 7;
input int      LondonStartMinute = 0;
input int      LondonEndHour     = 8;
input int      LondonEndMinute   = 30;
input int      NYStartHour       = 12;
input int      NYStartMinute     = 30;
input int      NYEndHour         = 14;
input int      NYEndMinute       = 0;

input string   RISK_SETTINGS     = "--- Risk Management ---";
input int      MaxTradesPerDay = 2; // Max 2 trades per session (London or NY)
input bool     EnableLossCoolDown = true;
input int      LossCoolDownMinutes = 15;

input string   LOG_SETTINGS      = "--- Logging ---";
input bool     EnableDetailedLog = true;
input bool     EnableEmailAlerts = false;

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
   g_TimeManager = new CTimeManager(LondonStartHour, LondonStartMinute, LondonEndHour, LondonEndMinute,
                                    NYStartHour, NYStartMinute, NYEndHour, NYEndMinute, g_Logger);
   g_MeanCalculator = new CMeanCalculator(MeanMethod, g_CurrentSymbol, g_Logger);
   g_ExhaustionDetector = new CExhaustionDetector(g_CurrentSymbol, g_Logger);
   g_RiskManager = new CRiskManager(TakeProfitMethod, UseAutoCloseRule, g_ATRHandle, g_CurrentSymbol, g_Logger);
   g_SessionManager = new CSessionManager(MaxTradesPerDay, EnableLossCoolDown, LossCoolDownMinutes, g_Logger);
   g_ValidationChecker = new CValidationChecker(g_CurrentSymbol, g_ATRHandle, g_Logger);
   g_TradeExecutor = new CTradeExecutor(LotSize, UseMoneyManagement, RiskPercent, g_CurrentSymbol, g_Logger);
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
         g_ProfessionalTradeManager.ManageTrade();
         
         if(g_ProfessionalTradeManager.ShouldExitTrade())
         {
            bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
            string exitReason = g_ProfessionalTradeManager.GetExitReason();
            
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
   
   // Calculate mean
   double mean = g_MeanCalculator.CalculateMean();
   if(mean <= 0)
   {
      g_Logger.LogWarning("Mean calculation returned invalid value");
      return;
   }
   
   // Check distance filter
   double distanceFilter = g_ValidationChecker.CalculateDistanceFilter(ask, atr[0]);
   double distanceFromMean = MathAbs(ask - mean);
   
   if(distanceFromMean < distanceFilter)
   {
      // Price too close to mean, reject trade
      if(EnableDetailedLog)
         g_Logger.LogInfo(StringFormat("Trade rejected: Distance from mean (%.5f) < filter (%.5f)", distanceFromMean, distanceFilter));
      return;
   }
   
   // CRITICAL: Exhaustion confirmation is MANDATORY (no exhaustion → no entry)
   int exhaustionType = g_ExhaustionDetector.DetectExhaustion();
   bool hasExhaustion = (exhaustionType != EXHAUSTION_NONE);
   
   if(!hasExhaustion)
   {
      if(EnableDetailedLog)
         g_Logger.LogWarning("Trade rejected: No exhaustion pattern detected - exhaustion is mandatory");
      return; // NO TRADE without exhaustion
   }
   
   // ENHANCEMENT: Prevent mid-box entries (only enter near extremes after sweep)
   // RELAXED: Only reject if no exhaustion AND no sweep rejection
   if(g_MeanCalculator.IsAsianRangeValid())
   {
      double asianHigh = g_MeanCalculator.GetAsianHigh();
      double asianLow = g_MeanCalculator.GetAsianLow();
      double asianMid = g_MeanCalculator.GetAsianMid();
      double boxRange = asianHigh - asianLow;
      
      if(boxRange > 0)
      {
         // Check if price is in middle 40% of box (mid-box)
         double pricePosition = (ask - asianLow) / boxRange;
         bool isMidBox = (pricePosition > 0.30 && pricePosition < 0.70);
         
         // Only reject mid-box entry if NO exhaustion AND NO sweep rejection
         if(isMidBox && !hasExhaustion && !g_DeadZoneManager.IsSweepRejected())
         {
            if(EnableDetailedLog)
               g_Logger.LogInfo("Trade rejected: Mid-box entry without exhaustion or sweep rejection");
            return;
         }
         else if(isMidBox && (hasExhaustion || g_DeadZoneManager.IsSweepRejected()))
         {
            if(EnableDetailedLog)
               g_Logger.LogInfo("Mid-box entry allowed: Exhaustion or sweep rejection present");
         }
      }
   }
   
   // Validate setup
   if(!g_ValidationChecker.IsValidSetup(mean, ask, bid))
   {
      if(EnableDetailedLog)
         g_Logger.LogWarning("Setup validation failed - rejecting trade (check trend/news/momentum filters)");
      return;
   }
   
   // Determine trade direction
   bool isLongSetup = (ask < mean - distanceFilter);
   bool isShortSetup = (ask > mean + distanceFilter);
   
   // ENHANCEMENT: Check liquidity magnet (multiple touches = stronger signal)
   if(g_MeanCalculator.IsAsianRangeValid())
   {
      double asianHigh = g_MeanCalculator.GetAsianHigh();
      double asianLow = g_MeanCalculator.GetAsianLow();
      
      // Prefer entries near Asian Low/High after multiple touches (liquidity magnet)
      bool nearAsianLevel = g_DeadZoneManager.IsEntryNearAsianLevel(isLongSetup, ask, asianHigh, asianLow);
      bool liquidityMagnetActive = g_LiquidityMagnet.IsLiquidityMagnetActive(isLongSetup);
      int touchCount = g_LiquidityMagnet.GetTouchCount(isLongSetup);
      
      if(liquidityMagnetActive && nearAsianLevel)
      {
         g_Logger.LogInfo(StringFormat("Liquidity magnet active: %d touches at Asian level - High probability setup", touchCount));
      }
      
      // Check if in consolidation box (oscillation) - treat as range continuation
      if(g_LiquidityMagnet.IsInConsolidationBox())
      {
         g_Logger.LogInfo("Price in consolidation box (oscillation) - Range active, mean reversion valid");
      }
      
      // Check if range is still active (vs trend)
      if(!g_LiquidityMagnet.IsRangeActive())
      {
         g_Logger.LogWarning("Range not active - Possible trend developing, mean reversion may be invalid");
         // Could add logic here to reduce position size or skip trade
      }
      
      // Check for short-lived break (3-4 candles) - high probability reversal
      if(g_LiquidityMagnet.IsShortLivedBreakout())
      {
         g_Logger.LogInfo("Short-lived break detected (3-4 candles) - High probability mean reversion");
      }
   }
   
   // RELAXED: Check dead zone break confirmation (London only) - prefer but don't require
   bool londonConfirmationPassed = true;
   if(g_TimeManager.IsLondonSession())
   {
      // Update Asian range before checking
      if(g_MeanCalculator.IsAsianRangeValid())
      {
         g_DeadZoneManager.UpdateAsianRange(g_MeanCalculator.GetAsianHigh(), g_MeanCalculator.GetAsianLow());
      }
      
      // Check if we can enter based on dead zone break logic
      if(isLongSetup)
      {
         londonConfirmationPassed = g_DeadZoneManager.CanEnterTrade(ask, true);
         if(!londonConfirmationPassed)
         {
            // RELAXED: If we have exhaustion or price is far from mean, allow trade anyway
            if(hasExhaustion || distanceFromMean > distanceFilter * 1.5)
            {
               if(EnableDetailedLog)
                  g_Logger.LogInfo("Long setup: London confirmation pending but allowing due to exhaustion or strong distance");
               londonConfirmationPassed = true; // Override
            }
            else
            {
               if(EnableDetailedLog)
                  g_Logger.LogInfo("Long setup rejected: Waiting for London confirmation of dead zone break");
               return;
            }
         }
      }
      else if(isShortSetup)
      {
         londonConfirmationPassed = g_DeadZoneManager.CanEnterTrade(ask, false);
         if(!londonConfirmationPassed)
         {
            // RELAXED: If we have exhaustion or price is far from mean, allow trade anyway
            if(hasExhaustion || distanceFromMean > distanceFilter * 1.5)
            {
               if(EnableDetailedLog)
                  g_Logger.LogInfo("Short setup: London confirmation pending but allowing due to exhaustion or strong distance");
               londonConfirmationPassed = true; // Override
            }
            else
            {
               if(EnableDetailedLog)
                  g_Logger.LogInfo("Short setup rejected: Waiting for London confirmation of dead zone break");
               return;
            }
         }
      }
   }
   
   // ENHANCEMENT: Check for VWAP Magnet Trade (Strategy B)
   double vwap = 0;
   if(g_MeanCalculator.GetMean() > 0)
   {
      // Try to get VWAP if using VWAP method
      // For now, use mean as VWAP proxy if SESSION_VWAP
      vwap = mean;
   }
   
   bool useVWAPMagnet = false;
   if(vwap > 0)
   {
      if(isLongSetup && g_VWAPMagnetTrade.CanEnterVWAPMagnetTrade(true, ask, vwap))
      {
         useVWAPMagnet = true;
         g_Logger.LogInfo("VWAP Magnet Trade setup detected (Long)");
      }
      else if(isShortSetup && g_VWAPMagnetTrade.CanEnterVWAPMagnetTrade(false, ask, vwap))
      {
         useVWAPMagnet = true;
         g_Logger.LogInfo("VWAP Magnet Trade setup detected (Short)");
      }
   }
   
   // ENHANCEMENT: Wait for candle close if we're waiting for rejection confirmation
   // This ensures we enter on rejection candle close, not mid-candle
   bool waitForClose = false;
   if(g_TimeManager.IsLondonSession() && g_DeadZoneManager.HasLondonSweep())
   {
      // Check if current candle is still forming
      datetime currentBarTime = iTime(g_CurrentSymbol, PERIOD_M5, 0);
      datetime currentTime = TimeCurrent();
      int secondsIntoBar = (int)(currentTime - currentBarTime);
      
      // If less than 4 minutes into 5-minute bar, wait for close
      if(secondsIntoBar < 240)
      {
         waitForClose = true;
         g_Logger.LogInfo("Waiting for rejection candle close before entry");
      }
   }
   
   if(waitForClose)
   {
      return; // Wait for candle to close
   }
   
   // Log trade setup summary
   if(EnableDetailedLog)
   {
      string setupSummary = StringFormat("=== TRADE SETUP SUMMARY ===\n" +
                                        "Direction: %s\n" +
                                        "Distance from Mean: %.5f (Filter: %.5f)\n" +
                                        "Exhaustion: %s\n" +
                                        "London Confirmation: %s\n" +
                                        "Mid-Box: %s\n" +
                                        "Mean: %.5f | Ask: %.5f",
                                        isLongSetup ? "LONG" : "SHORT",
                                        distanceFromMean, distanceFilter,
                                        hasExhaustion ? "YES" : "NO",
                                        londonConfirmationPassed ? "YES" : "NO",
                                        g_MeanCalculator.IsAsianRangeValid() ? "CHECKED" : "N/A",
                                        mean, ask);
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
      
      if(g_BuyTrade.ExecuteTrade(mean, distanceFilter, atr[0], exhaustionType))
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
               
               double targetVWAP = g_MeanCalculator.GetAsianVWAP();
               if(targetVWAP <= 0) targetVWAP = mean;
               
               g_ProfessionalTradeManager.InitializeTrade(ticket, true, entryPrice, mean, targetVWAP, 
                                                          distanceFromMean, londonReactionHigh, londonReactionLow);
            }
         }
         
         // Set multiple TP targets if enabled (fallback)
         if(g_RiskManager.IsMultipleTPMethod() && g_MeanCalculator.IsAsianRangeValid())
         {
            double asianHigh = g_MeanCalculator.GetAsianHigh();
            double asianLow = g_MeanCalculator.GetAsianLow();
            double asianMid = g_MeanCalculator.GetAsianMid();
            double asianVWAP = g_MeanCalculator.GetAsianVWAP();
            
            if(asianVWAP <= 0) asianVWAP = mean;
            if(asianMid <= 0) asianMid = (asianHigh + asianLow) / 2.0;
            
            g_MultipleTPManager.SetTPTargets(true, ask, asianHigh, asianLow, asianMid, asianVWAP);
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
      
      if(g_SellTrade.ExecuteTrade(mean, distanceFilter, atr[0], exhaustionType))
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
            
            double targetVWAP = g_MeanCalculator.GetAsianVWAP();
            if(targetVWAP <= 0) targetVWAP = mean;
            
            g_ProfessionalTradeManager.InitializeTrade(ticket, false, entryPrice, mean, targetVWAP, 
                                                       distanceFromMean, londonReactionHigh, londonReactionLow);
         }
         
         // Set multiple TP targets if enabled (fallback)
         if(g_RiskManager.IsMultipleTPMethod() && g_MeanCalculator.IsAsianRangeValid())
         {
            double asianHigh = g_MeanCalculator.GetAsianHigh();
            double asianLow = g_MeanCalculator.GetAsianLow();
            double asianMid = g_MeanCalculator.GetAsianMid();
            double asianVWAP = g_MeanCalculator.GetAsianVWAP();
            
            if(asianVWAP <= 0) asianVWAP = mean;
            if(asianMid <= 0) asianMid = (asianHigh + asianLow) / 2.0;
            
            g_MultipleTPManager.SetTPTargets(false, ask, asianHigh, asianLow, asianMid, asianVWAP);
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

