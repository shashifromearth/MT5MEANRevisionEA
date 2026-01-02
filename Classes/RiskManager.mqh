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
//| SL = MIN(2 pips beyond swing extreme, 0.5 × ATR(14))           |
//+------------------------------------------------------------------+
double CRiskManager::CalculateStopLoss(bool isLong, double entryPrice, double atr)
{
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(m_Symbol, SYMBOL_DIGITS);
   
   // Get last 5 candles for swing extremes
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 5, high) < 5 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 5, low) < 5)
   {
      // Fallback: use ATR-based SL
      if(isLong)
         return entryPrice - 0.5 * atr;
      else
         return entryPrice + 0.5 * atr;
   }
   
   double swingExtreme;
   double slFromSwing;
   double slFromATR;
   
   if(isLong)
   {
      // Find lowest low in last 5 candles
      int minIndex = ArrayMinimum(low, 0, 5);
      swingExtreme = low[minIndex];
      
      // SL = 2 pips below swing extreme
      slFromSwing = swingExtreme - 2.0 * point * 10; // 2 pips
      
      // SL = 0.5 × ATR below entry
      slFromATR = entryPrice - 0.5 * atr;
      
      // Return minimum (closer to entry = tighter SL)
      return MathMin(slFromSwing, slFromATR);
   }
   else
   {
      // Find highest high in last 5 candles
      int maxIndex = ArrayMaximum(high, 0, 5);
      swingExtreme = high[maxIndex];
      
      // SL = 2 pips above swing extreme
      slFromSwing = swingExtreme + 2.0 * point * 10; // 2 pips
      
      // SL = 0.5 × ATR above entry
      slFromATR = entryPrice + 0.5 * atr;
      
      // Return maximum (closer to entry = tighter SL)
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
   
   // RR must be between 0.5 and 1.0 (1:0.5 to 1:1)
   if(rr < 0.5 || rr > 1.0)
   {
      (*m_Logger).LogWarning(StringFormat("RR validation failed: %.2f (required: 0.5-1.0)", rr));
      return false;
   }
   
   (*m_Logger).LogInfo(StringFormat("RR validation passed: %.2f", rr));
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
   if(!PositionSelect(m_Symbol)) return;
   
   ulong ticket = PositionGetInteger(POSITION_TICKET);
   if(ticket == 0) return;
   
   bool shouldClose = false;
   string closeReason = "";
   
   // Check auto-close rule (3 candles)
   if(m_UseAutoCloseRule && CheckAutoCloseRule(ticket))
   {
      shouldClose = true;
      closeReason = "Failed mean reversion initiation";
   }
   
   // Check trade duration (max 20 minutes = 4 M5 candles)
   if(CheckTradeDuration(ticket))
   {
      shouldClose = true;
      closeReason = "Trade duration exceeded 20 minutes";
   }
   
   if(shouldClose)
   {
      // Close position
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_DEAL;
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
         (*m_Logger).LogError(StringFormat("Failed to close position %llu: %s", ticket, result.comment));
      }
   }
}

//+------------------------------------------------------------------+
//| Check auto-close rule                                            |
//| If price doesn't start reverting toward mean within 3 candles,  |
//| close position immediately                                        |
//+------------------------------------------------------------------+
bool CRiskManager::CheckAutoCloseRule(ulong ticket)
{
   if(m_EntryBarTime == 0) return false;
   
   datetime currentBarTime = iTime(m_Symbol, PERIOD_M5, 0);
   int barsSinceEntry = (int)((currentBarTime - m_EntryBarTime) / PeriodSeconds(PERIOD_M5));
   
   if(barsSinceEntry < 3) return false;
   
   // Get entry price
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   
   // Get close prices for last 3 candles
   double close[];
   ArraySetAsSeries(close, true);
   
   if(CopyClose(m_Symbol, PERIOD_M5, 0, 3, close) < 3)
   {
      return false;
   }
   
   // Check if price is reverting toward mean
   // For long: price should be moving up (closer to mean)
   // For short: price should be moving down (closer to mean)
   
   if(isLong)
   {
      // Long position: check if price is consistently moving down (away from mean)
      // This indicates failed reversion
      bool notReverting = (close[0] < entryPrice && close[1] < entryPrice && close[2] < entryPrice);
      
      // Also check if price is moving further away
      bool movingAway = (close[0] < close[1] && close[1] < close[2]);
      
      return (notReverting || movingAway);
   }
   else
   {
      // Short position: check if price is consistently moving up (away from mean)
      bool notReverting = (close[0] > entryPrice && close[1] > entryPrice && close[2] > entryPrice);
      
      // Also check if price is moving further away
      bool movingAway = (close[0] > close[1] && close[1] > close[2]);
      
      return (notReverting || movingAway);
   }
}

//+------------------------------------------------------------------+
//| Check trade duration - exit if > 20 minutes                     |
//+------------------------------------------------------------------+
bool CRiskManager::CheckTradeDuration(ulong ticket)
{
   if(m_EntryTime == 0) return false;
   
   datetime currentTime = TimeCurrent();
   int durationMinutes = (int)((currentTime - m_EntryTime) / 60);
   
   // Max trade duration: 20 minutes
   if(durationMinutes > 20)
   {
      (*m_Logger).LogWarning(StringFormat("Trade duration exceeded: %d minutes (max: 20)", durationMinutes));
      return true;
   }
   
   return false;
}

