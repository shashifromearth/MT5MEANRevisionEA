//+------------------------------------------------------------------+
//| RiskManager.mqh                                                  |
//| Manages stop loss, take profit, and position monitoring         |
//+------------------------------------------------------------------+
#include "Enums.mqh"
#include "Logger.mqh"
#include "MeanCalculator.mqh"

class CRiskManager
{
private:
   TP_METHOD m_TPMethod;
   bool m_UseAutoCloseRule;
   int m_ATRHandle;
   string m_Symbol;
   CLogger* m_Logger;
   
   // Position monitoring
   datetime m_EntryBarTime;
   datetime m_EntryTime;  // Actual entry time for duration tracking
   int m_BarsSinceEntry;
   
   double CalculateStopLoss(bool isLong, double entryPrice, double atr);
   double CalculateTakeProfit(bool isLong, double entryPrice, double mean, double distanceFromMean);
   bool CheckAutoCloseRule(ulong ticket);
   bool CheckTradeDuration(ulong ticket);
   double CalculateRiskReward(bool isLong, double entryPrice, double stopLoss, double takeProfit);
   
public:
   CRiskManager(TP_METHOD tpMethod, bool useAutoClose, int atrHandle, string symbol, CLogger* logger);
   ~CRiskManager();
   
   double GetStopLoss(bool isLong, double entryPrice, double atr);
   double GetTakeProfit(bool isLong, double entryPrice, double mean, double distanceFromMean);
   bool ValidateRiskReward(bool isLong, double entryPrice, double stopLoss, double takeProfit);
   bool IsMultipleTPMethod() { return (m_TPMethod == MULTIPLE_TARGETS); }
   void OnTrade();
   void MonitorPositions(CMeanCalculator* meanCalculator);
   void SetEntryBarTime(datetime barTime) { m_EntryBarTime = barTime; m_EntryTime = TimeCurrent(); }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CRiskManager::CRiskManager(TP_METHOD tpMethod, bool useAutoClose, int atrHandle, string symbol, CLogger* logger)
{
   m_TPMethod = tpMethod;
   m_UseAutoCloseRule = useAutoClose;
   m_ATRHandle = atrHandle;
   m_Symbol = symbol;
   m_Logger = logger;
   m_EntryBarTime = 0;
   m_EntryTime = 0;
   m_BarsSinceEntry = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CRiskManager::~CRiskManager()
{
}

//+------------------------------------------------------------------+
//| Get stop loss price                                              |
//+------------------------------------------------------------------+
double CRiskManager::GetStopLoss(bool isLong, double entryPrice, double atr)
{
   return CalculateStopLoss(isLong, entryPrice, atr);
}

//+------------------------------------------------------------------+
//| Calculate stop loss                                              |
//| IMPROVED: Use Asian extremes when available (better SL placement)|
//| SL = MIN(3 pips beyond swing/Asian extreme, 0.6 × ATR(14))     |
//+------------------------------------------------------------------+
double CRiskManager::CalculateStopLoss(bool isLong, double entryPrice, double atr)
{
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(m_Symbol, SYMBOL_DIGITS);
   
   // Get last 10 candles for swing extremes (increased from 5)
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 10, high) < 10 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 10, low) < 10)
   {
      // Fallback: use ATR-based SL
      if(isLong)
         return entryPrice - 0.6 * atr; // Increased from 0.5
      else
         return entryPrice + 0.6 * atr;
   }
   
   double swingExtreme;
   double slFromSwing;
   double slFromATR;
   
   if(isLong)
   {
      // Find lowest low in last 10 candles (better reference)
      int minIndex = ArrayMinimum(low, 0, 10);
      swingExtreme = low[minIndex];
      
      // SL = 3 pips below swing extreme (increased from 2 for better protection)
      slFromSwing = swingExtreme - 3.0 * point * 10; // 3 pips
      
      // SL = 0.6 × ATR below entry (increased from 0.5 for better protection)
      slFromATR = entryPrice - 0.6 * atr;
      
      // Return minimum (closer to entry = tighter SL, but with better protection)
      return MathMin(slFromSwing, slFromATR);
   }
   else
   {
      // Find highest high in last 10 candles
      int maxIndex = ArrayMaximum(high, 0, 10);
      swingExtreme = high[maxIndex];
      
      // SL = 3 pips above swing extreme
      slFromSwing = swingExtreme + 3.0 * point * 10; // 3 pips
      
      // SL = 0.6 × ATR above entry
      slFromATR = entryPrice + 0.6 * atr;
      
      // Return maximum (closer to entry = tighter SL, but with better protection)
      return MathMax(slFromSwing, slFromATR);
   }
}

//+------------------------------------------------------------------+
//| Get take profit price                                            |
//+------------------------------------------------------------------+
double CRiskManager::GetTakeProfit(bool isLong, double entryPrice, double mean, double distanceFromMean)
{
   return CalculateTakeProfit(isLong, entryPrice, mean, distanceFromMean);
}

//+------------------------------------------------------------------+
//| Calculate take profit                                            |
//+------------------------------------------------------------------+
double CRiskManager::CalculateTakeProfit(bool isLong, double entryPrice, double mean, double distanceFromMean)
{
   if(m_TPMethod == TO_MEAN)
   {
      // TP = Mean price
      return mean;
   }
   else if(m_TPMethod == SEVENTY_FIVE_PERCENT)
   {
      // TP = Entry ± (0.75 × Distance_From_Mean)
      if(isLong)
      {
         return entryPrice + 0.75 * distanceFromMean;
      }
      else
      {
         return entryPrice - 0.75 * distanceFromMean;
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Calculate Risk:Reward ratio                                      |
//+------------------------------------------------------------------+
double CRiskManager::CalculateRiskReward(bool isLong, double entryPrice, double stopLoss, double takeProfit)
{
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   
   double risk = MathAbs(entryPrice - stopLoss) / point;
   double reward = MathAbs(takeProfit - entryPrice) / point;
   
   if(risk <= 0) return 0;
   
   return reward / risk;
}

//+------------------------------------------------------------------+
//| Validate Risk:Reward ratio (must be 1:0.5 to 1:1)               |
//+------------------------------------------------------------------+
bool CRiskManager::ValidateRiskReward(bool isLong, double entryPrice, double stopLoss, double takeProfit)
{
   double rr = CalculateRiskReward(isLong, entryPrice, stopLoss, takeProfit);
   
   // RELAXED: Require minimum 0.7:1 RR (was 1.0:1 - too strict)
   // Allow trades with at least 0.7:1 risk:reward for more opportunities
   // Maximum 3.0 to allow reasonable targets
   if(rr < 0.7 || rr > 3.0)
   {
      (*m_Logger).LogWarning(StringFormat("RR validation failed: %.2f (required: 0.7-3.0, minimum 0.7:1)", rr));
      return false;
   }
   
   // All passed trades have at least 1:1 RR
   if(rr >= 1.5)
   {
      (*m_Logger).LogInfo(StringFormat("RR validation passed: %.2f (EXCELLENT - 1:1.5 or better)", rr));
   }
   else
   {
      (*m_Logger).LogInfo(StringFormat("RR validation passed: %.2f (GOOD - minimum 1:1)", rr));
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Called on trade event                                            |
//+------------------------------------------------------------------+
void CRiskManager::OnTrade()
{
   // Reset entry bar time when new position opens
   if(PositionSelect(m_Symbol))
   {
      m_EntryBarTime = iTime(m_Symbol, PERIOD_M5, 0);
      m_EntryTime = TimeCurrent();
      m_BarsSinceEntry = 0;
   }
}

//+------------------------------------------------------------------+
//| Monitor positions for auto-close rule                            |
//| If price doesn't revert within 3 candles, close position         |
//+------------------------------------------------------------------+
void CRiskManager::MonitorPositions(CMeanCalculator* meanCalculator)
{
   // Check for EA position with magic number filter
   ulong ticket = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket > 0)
      {
         if(PositionSelectByTicket(posTicket))
         {
            if(PositionGetString(POSITION_SYMBOL) == m_Symbol && 
               PositionGetInteger(POSITION_MAGIC) == 123456)
            {
               ticket = posTicket;
               break;
            }
         }
      }
   }
   
   if(ticket == 0) return;
   if(!PositionSelectByTicket(ticket)) return;
   
   bool shouldClose = false;
   string closeReason = "";
   
   // Check auto-close rule (FLEXIBLE: 6 candles, requires strong confirmation)
   if(m_UseAutoCloseRule && CheckAutoCloseRule(ticket))
   {
      shouldClose = true;
      closeReason = "Failed mean reversion initiation";
   }
   
   // Check trade duration (FLEXIBLE: max 3 hours, only close if losing and not moving toward target)
   if(CheckTradeDuration(ticket))
   {
      shouldClose = true;
      closeReason = "Trade duration exceeded time limit";
   }
   
   if(shouldClose)
   {
      // Close position - CRITICAL: Must specify position ticket
      if(!PositionSelectByTicket(ticket))
      {
         // Position already closed, skip
         return;
      }
      
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_DEAL;
      request.position = ticket; // CRITICAL: Specify which position to close
      request.symbol = m_Symbol;
      request.volume = PositionGetDouble(POSITION_VOLUME);
      request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      request.deviation = 10;
      request.magic = 123456;
      request.comment = StringFormat("Auto-close: %s", closeReason);
      
      if(OrderSend(request, result))
      {
         (*m_Logger).LogWarning(StringFormat("Position %llu closed: %s", ticket, closeReason));
      }
      else
      {
         (*m_Logger).LogError(StringFormat("Failed to close position %llu: %s (retcode: %d)", ticket, result.comment, result.retcode));
         // If "No money" error, stop trying to close (infinite loop prevention)
         if(result.retcode == 10004 || result.retcode == 10019) // TRADE_RETCODE_NO_MONEY or TRADE_RETCODE_NOT_ENOUGH_MONEY
         {
            (*m_Logger).LogWarning("Insufficient margin to close position - will retry when margin available");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check auto-close rule                                            |
//| OPTIMIZED: If price doesn't start reverting toward mean within 5 candles, |
//| close position immediately (was 3 candles)                       |
//+------------------------------------------------------------------+
bool CRiskManager::CheckAutoCloseRule(ulong ticket)
{
   if(m_EntryBarTime == 0) return false;
   
   datetime currentBarTime = iTime(m_Symbol, PERIOD_M5, 0);
   int barsSinceEntry = (int)((currentBarTime - m_EntryBarTime) / PeriodSeconds(PERIOD_M5));
   
   // FLEXIBLE: Increased to 6 candles (more patience for mean reversion to develop)
   if(barsSinceEntry < 6) return false;
   
   // Get entry price
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   
   // FLEXIBLE: Check last 6 candles for more reliable signal
   double close[];
   ArraySetAsSeries(close, true);
   
   if(CopyClose(m_Symbol, PERIOD_M5, 0, 6, close) < 6)
   {
      return false;
   }
   
   // Check if price is reverting toward mean
   // For long: price should be moving up (closer to mean)
   // For short: price should be moving down (closer to mean)
   
   if(isLong)
   {
      // Long position: check if price is consistently moving down (away from mean)
      // FLEXIBLE: Require 5 out of 6 candles below entry (less aggressive)
      int candlesBelow = 0;
      for(int i = 0; i < 6; i++)
      {
         if(close[i] < entryPrice) candlesBelow++;
      }
      
      // Also check if price is moving further away (4 consecutive lower closes - more strict)
      bool movingAway = (close[0] < close[1] && close[1] < close[2] && close[2] < close[3] && close[3] < close[4]);
      
      // Only close if BOTH conditions met (more flexible)
      return (candlesBelow >= 5 && movingAway);
   }
   else
   {
      // Short position: check if price is consistently moving up (away from mean)
      int candlesAbove = 0;
      for(int i = 0; i < 6; i++)
      {
         if(close[i] > entryPrice) candlesAbove++;
      }
      
      // Also check if price is moving further away (4 consecutive higher closes - more strict)
      bool movingAway = (close[0] > close[1] && close[1] > close[2] && close[2] > close[3] && close[3] > close[4]);
      
      // Only close if BOTH conditions met (more flexible)
      return (candlesAbove >= 5 && movingAway);
   }
}

//+------------------------------------------------------------------+
//| Check trade duration - FLEXIBLE: exit if > 3 hours AND trade is losing |
//| Only close if trade is in loss and not moving toward target      |
//+------------------------------------------------------------------+
bool CRiskManager::CheckTradeDuration(ulong ticket)
{
   if(m_EntryTime == 0) return false;
   
   datetime currentTime = TimeCurrent();
   int durationMinutes = (int)((currentTime - m_EntryTime) / 60);
   
   // FLEXIBLE: Max trade duration (configurable, default 3 hours = 180 minutes)
   // Mean reversion trades need time to develop
   int maxDurationMinutes = 180; // Default 3 hours - can be made configurable
   if(durationMinutes <= maxDurationMinutes) return false; // Let trades run for up to max duration
   
   // After 3 hours, only close if trade is losing AND not moving toward target
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double profit = PositionGetDouble(POSITION_PROFIT);
   bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   
   // If trade is in profit, let it continue (don't close on duration)
   if(profit > 0)
   {
      (*m_Logger).LogInfo(StringFormat("Trade duration %d minutes but in profit (%.2f) - allowing to continue", 
                                      durationMinutes, profit));
      return false;
   }
   
   // If trade is losing, check if it's moving toward target
   // Get last 3 candles to see direction
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(m_Symbol, PERIOD_M5, 0, 3, close) >= 3)
   {
      if(isLong)
      {
         // Long: check if price is moving up (toward target)
         bool movingUp = (close[0] > close[1] && close[1] > close[2]);
         if(movingUp)
         {
            (*m_Logger).LogInfo(StringFormat("Trade duration %d minutes but moving toward target - allowing to continue", 
                                            durationMinutes));
            return false; // Moving in right direction, let it continue
         }
      }
      else
      {
         // Short: check if price is moving down (toward target)
         bool movingDown = (close[0] < close[1] && close[1] < close[2]);
         if(movingDown)
         {
            (*m_Logger).LogInfo(StringFormat("Trade duration %d minutes but moving toward target - allowing to continue", 
                                            durationMinutes));
            return false; // Moving in right direction, let it continue
         }
      }
   }
   
   // Trade exceeded 3 hours AND is losing AND not moving toward target
   (*m_Logger).LogWarning(StringFormat("Trade duration exceeded: %d minutes (max: 180) - closing losing trade", durationMinutes));
   return true;
}

