//+------------------------------------------------------------------+
//| ProfessionalTradeManager.mqh                                     |
//| Professional trade management: Partial profits, invalidation,     |
//| trend continuation detection                                      |
//+------------------------------------------------------------------+
#include "Logger.mqh"
#include "MeanCalculator.mqh"

// Trade management state
enum TRADE_MANAGEMENT_STATE
{
   TM_NONE,
   TM_PARTIAL_TAKEN,      // Partial profit taken
   TM_WAITING_FOR_MEAN,   // Waiting for mean target
   TM_PULLBACK,           // Price pulling back
   TM_STRUCTURE_BROKEN,    // Structure broken - exit
   TM_TREND_RESUMED       // Trend resumed - exit
};

// Structure break type
enum STRUCTURE_BREAK_TYPE
{
   STRUCTURE_NO_BREAK,
   BREAK_ENTRY_STRUCTURE,  // Broke entry structure
   BREAK_LONDON_REACTION   // Broke London reaction low/high
};

class CProfessionalTradeManager
{
private:
   string m_Symbol;
   CLogger* m_Logger;
   CMeanCalculator* m_MeanCalculator;
   
   // Position tracking
   ulong m_PositionTicket;
   double m_EntryPrice;
   double m_EntryStructureHigh;  // Entry structure high
   double m_EntryStructureLow;   // Entry structure low
   double m_LondonReactionHigh;  // London reaction high
   double m_LondonReactionLow;    // London reaction low
   bool m_IsLong;
   double m_TargetMean;
   double m_TargetVWAP;
   double m_DistanceToMean;
   
   // Trade management state
   TRADE_MANAGEMENT_STATE m_State;
   bool m_PartialTaken;
   double m_PartialPrice;
   double m_PartialPercent; // 25-30% (reduced from 40%)
   double m_PartialDistance; // 50-60% of distance to mean (increased from 35%)
   
   // Multiple partial levels
   bool m_Partial1Taken;  // First partial (25% at 50% distance)
   bool m_Partial2Taken;  // Second partial (25% at 75% distance)
   double m_Partial1Price;
   double m_Partial2Price;
   
   // Trailing stop
   bool m_TrailingStopActive;
   double m_TrailingStopPrice;
   double m_HighestProfit;  // Track highest profit for trailing
   
   // Breakeven stop
   bool m_BreakevenSet;
   double m_StopLossPrice;
   
   // Structure break confirmation
   int m_StructureBreakCandles;  // Count candles beyond structure
   
   // Trend continuation tracking
   bool m_TrendContinuationDetected;
   datetime m_LastCheckTime;
   int m_StrongImpulseCount;  // Count strong impulses (require 2-3)
   
   // VWAP tracking
   bool m_VWAPFirstTouch;
   bool m_VWAPRejected;
   double m_VWAPTouchPrice;
   
   bool TakePartialProfit(double percent);
   bool CheckStructureBreak();
   bool CheckMajorStructureBreak();  // More aggressive check before partial
   bool DetectTrendContinuation();
   bool CheckVWAPBehavior();
   double CalculatePartialDistance();
   bool IsStrongImpulsiveCandle(bool isLong);
   bool HasFollowThroughCandle(bool isLong);
   bool FailedToReclaimMidLevel(bool isLong, double midLevel);
   bool FailedToReclaimMidLevelExtended(bool isLong, double midLevel);  // Extended check (5 candles)
   void UpdateTrailingStop(double currentPrice);
   void SetBreakevenStop();
   bool CheckMultiplePartials(double currentPrice);
   
public:
   CProfessionalTradeManager(string symbol, CLogger* logger, CMeanCalculator* meanCalculator);
   ~CProfessionalTradeManager();
   
   void InitializeTrade(ulong ticket, bool isLong, double entryPrice, double targetMean, 
                       double targetVWAP, double distanceToMean, double londonReactionHigh, 
                       double londonReactionLow);
   void ManageTrade();
   void OnNewBar();
   bool ShouldExitTrade();
   string GetExitReason();
   void Reset();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CProfessionalTradeManager::CProfessionalTradeManager(string symbol, CLogger* logger, CMeanCalculator* meanCalculator)
{
   m_Symbol = symbol;
   m_Logger = logger;
   m_MeanCalculator = meanCalculator;
   m_PositionTicket = 0;
   m_EntryPrice = 0;
   m_EntryStructureHigh = 0;
   m_EntryStructureLow = 0;
   m_LondonReactionHigh = 0;
   m_LondonReactionLow = 0;
   m_IsLong = false;
   m_TargetMean = 0;
   m_TargetVWAP = 0;
   m_DistanceToMean = 0;
   m_State = TM_NONE;
   m_PartialTaken = false;
   m_PartialPrice = 0;
   m_PartialPercent = 0;
   m_PartialDistance = 0;
   m_Partial1Taken = false;
   m_Partial2Taken = false;
   m_Partial1Price = 0;
   m_Partial2Price = 0;
   m_TrailingStopActive = false;
   m_TrailingStopPrice = 0;
   m_HighestProfit = 0;
   m_BreakevenSet = false;
   m_StopLossPrice = 0;
   m_StructureBreakCandles = 0;
   m_TrendContinuationDetected = false;
   m_LastCheckTime = 0;
   m_StrongImpulseCount = 0;
   m_VWAPFirstTouch = false;
   m_VWAPRejected = false;
   m_VWAPTouchPrice = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CProfessionalTradeManager::~CProfessionalTradeManager()
{
}

//+------------------------------------------------------------------+
//| Initialize trade for management                                  |
//+------------------------------------------------------------------+
void CProfessionalTradeManager::InitializeTrade(ulong ticket, bool isLong, double entryPrice, 
                                                double targetMean, double targetVWAP, 
                                                double distanceToMean, double londonReactionHigh, 
                                                double londonReactionLow)
{
   m_PositionTicket = ticket;
   m_EntryPrice = entryPrice;
   m_IsLong = isLong;
   m_TargetMean = targetMean;
   m_TargetVWAP = targetVWAP;
   m_DistanceToMean = distanceToMean;
   m_LondonReactionHigh = londonReactionHigh;
   m_LondonReactionLow = londonReactionLow;
   m_State = TM_WAITING_FOR_MEAN;
   m_PartialTaken = false;
   m_TrendContinuationDetected = false;
   m_VWAPFirstTouch = false;
   m_VWAPRejected = false;
   
   // Calculate entry structure (last 5 candles high/low)
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 5, high) >= 5 &&
      CopyLow(m_Symbol, PERIOD_M5, 0, 5, low) >= 5)
   {
      m_EntryStructureHigh = high[ArrayMaximum(high, 0, 5)];
      m_EntryStructureLow = low[ArrayMinimum(low, 0, 5)];
   }
   else
   {
      m_EntryStructureHigh = entryPrice + distanceToMean * 0.1;
      m_EntryStructureLow = entryPrice - distanceToMean * 0.1;
   }
   
   // OPTIMIZED: Delay partial profit to let winners run longer
   // Increased from 55% to 60% to reduce over-optimization
   m_PartialDistance = distanceToMean * 0.60; // 60% (increased from 55%)
   m_PartialPercent = 0.20; // 20% of position (reduced from 25% to keep more for bigger wins)
   
   // Initialize multiple partial levels
   m_Partial1Taken = false;
   m_Partial2Taken = false;
   m_TrailingStopActive = false;
   m_BreakevenSet = false;
   m_StructureBreakCandles = 0;
   m_StrongImpulseCount = 0;
   
   // Get initial stop loss
   if(PositionSelectByTicket(ticket))
   {
      m_StopLossPrice = PositionGetDouble(POSITION_SL);
   }
   
   (*m_Logger).LogInfo(StringFormat("Trade initialized: Entry=%.5f, Target=%.5f, Partial at %.5f (%.0f%% of distance)", 
                                    entryPrice, targetMean, entryPrice + (isLong ? m_PartialDistance : -m_PartialDistance),
                                    (m_PartialDistance / distanceToMean) * 100));
}

//+------------------------------------------------------------------+
//| Manage open trade                                                |
//+------------------------------------------------------------------+
void CProfessionalTradeManager::ManageTrade()
{
   if(m_PositionTicket == 0)
      return;
      
   if(!PositionSelectByTicket(m_PositionTicket))
   {
      Reset();
      return;
   }
   
   double currentPrice = m_IsLong ? 
                         SymbolInfoDouble(m_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(m_Symbol, SYMBOL_ASK);
   
   // IMPROVED Layer 1: Multiple Partial Profit Levels (Scale Out)
   // Check multiple partial levels: 25% at 50%, 25% at 75%, 50% at mean
   CheckMultiplePartials(currentPrice);
   
   // Update trailing stop if partial taken
   if(m_PartialTaken || m_Partial1Taken)
   {
      UpdateTrailingStop(currentPrice);
      if(!m_BreakevenSet)
      {
         SetBreakevenStop();
      }
   }
   
   // OPTIMIZED: Delay exit checks until trade develops significantly
   // Calculate how far price has moved toward mean
   double priceMoved = m_IsLong ? (currentPrice - m_EntryPrice) : (m_EntryPrice - currentPrice);
   double distancePercent = (m_DistanceToMean > 0) ? (priceMoved / m_DistanceToMean) : 0;
   
   // Only check structure break/trend continuation after 75% distance reached
   // This lets trades develop fully before applying strict exit rules
   if(distancePercent >= 0.75 || m_PartialTaken || m_Partial1Taken)
   {
      // Layer 2: Check structure break (invalidation-based exit) - ONLY after 75% distance
      if(CheckStructureBreak())
      {
         m_State = TM_STRUCTURE_BROKEN;
         (*m_Logger).LogWarning("Structure broken - Exit signal (after 75% distance or partial)");
         return;
      }
      
      // Layer 3: Check trend continuation (hard exit) - ONLY after 75% distance
      if(DetectTrendContinuation())
      {
         m_State = TM_TREND_RESUMED;
         m_TrendContinuationDetected = true;
         (*m_Logger).LogWarning("Trend continuation detected - Exit immediately (after 75% distance or partial)");
         return;
      }
   }
   else
   {
      // Before 75% distance: Only exit on MAJOR structure break (4+ candles, larger buffer)
      // This allows normal pullbacks without exiting
      if(CheckMajorStructureBreak())
      {
         m_State = TM_STRUCTURE_BROKEN;
         (*m_Logger).LogWarning("Major structure break - Exit signal (before 75% distance)");
         return;
      }
   }
   
   // VWAP-specific rule
   if(m_TargetVWAP > 0)
   {
      CheckVWAPBehavior();
   }
   
   // Check for pullback (normal, not exit signal)
   if(m_PartialTaken)
   {
      double priceFromPartial = m_IsLong ? 
                               (currentPrice - m_PartialPrice) : 
                               (m_PartialPrice - currentPrice);
      
      if(priceFromPartial < 0) // Price pulled back from partial
      {
         m_State = TM_PULLBACK;
         // Pullback is normal - only exit if structure breaks
      }
   }
}

//+------------------------------------------------------------------+
//| Take partial profit                                              |
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::TakePartialProfit(double percent)
{
   if(!PositionSelectByTicket(m_PositionTicket))
      return false;
   
   double currentVolume = PositionGetDouble(POSITION_VOLUME);
   double closeVolume = currentVolume * percent;
   
   // Normalize volume
   double lotStep = SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_STEP);
   closeVolume = MathFloor(closeVolume / lotStep) * lotStep;
   
   if(closeVolume < SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_MIN))
      return false;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = m_Symbol;
   request.volume = closeVolume;
   request.type = m_IsLong ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.position = m_PositionTicket;
   request.deviation = 10;
   request.magic = 123456;
   request.comment = StringFormat("Partial profit: %.0f%%", percent * 100);
   
   if(OrderSend(request, result))
   {
      return true;
   }
   else
   {
      (*m_Logger).LogError(StringFormat("Failed to take partial profit: %s", result.comment));
      return false;
   }
}

//+------------------------------------------------------------------+
//| Check structure break (invalidation-based exit)                   |
//| IMPROVED: Requires 3 candles + buffer zone (much less aggressive)|
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::CheckStructureBreak()
{
   double currentPrice = m_IsLong ? 
                        SymbolInfoDouble(m_Symbol, SYMBOL_BID) : 
                        SymbolInfoDouble(m_Symbol, SYMBOL_ASK);
   
   // Get last 3 candle closes for stronger confirmation
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(m_Symbol, PERIOD_M5, 0, 3, close) < 3)
      return false;
   
   double candleClose0 = close[0]; // Current candle
   double candleClose1 = close[1]; // Previous candle
   double candleClose2 = close[2]; // 2 candles ago
   
   // Add buffer zone (5-10 pips) to avoid false exits on normal pullbacks
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double buffer = 10 * point * 10; // 10 pips buffer
   
   bool brokeStructure = false;
   
   // Check if broke entry structure (require 3 candles + buffer)
   if(m_IsLong)
   {
      // Long: exit if 3 candles close below entry structure low WITH buffer
      double structureLowWithBuffer = m_EntryStructureLow - buffer;
      if(candleClose0 < structureLowWithBuffer && 
         candleClose1 < structureLowWithBuffer && 
         candleClose2 < structureLowWithBuffer)
      {
         brokeStructure = true;
         (*m_Logger).LogWarning("Structure break (confirmed): 3 candles below entry structure with buffer");
      }
      
      // Check if broke London reaction low (require 3 candles + buffer)
      if(m_LondonReactionLow > 0)
      {
         double londonLowWithBuffer = m_LondonReactionLow - buffer;
         if(candleClose0 < londonLowWithBuffer && 
            candleClose1 < londonLowWithBuffer && 
            candleClose2 < londonLowWithBuffer)
         {
            brokeStructure = true;
            (*m_Logger).LogWarning("Structure break (confirmed): 3 candles below London reaction low with buffer");
         }
      }
   }
   else
   {
      // Short: exit if 3 candles close above entry structure high WITH buffer
      double structureHighWithBuffer = m_EntryStructureHigh + buffer;
      if(candleClose0 > structureHighWithBuffer && 
         candleClose1 > structureHighWithBuffer && 
         candleClose2 > structureHighWithBuffer)
      {
         brokeStructure = true;
         (*m_Logger).LogWarning("Structure break (confirmed): 3 candles above entry structure with buffer");
      }
      
      // Check if broke London reaction high (require 3 candles + buffer)
      if(m_LondonReactionHigh > 0)
      {
         double londonHighWithBuffer = m_LondonReactionHigh + buffer;
         if(candleClose0 > londonHighWithBuffer && 
            candleClose1 > londonHighWithBuffer && 
            candleClose2 > londonHighWithBuffer)
         {
            brokeStructure = true;
            (*m_Logger).LogWarning("Structure break (confirmed): 3 candles above London reaction high with buffer");
         }
      }
   }
   
   return brokeStructure;
}

//+------------------------------------------------------------------+
//| Check major structure break (before partial profit)               |
//| Even more aggressive - requires 4 candles + larger buffer        |
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::CheckMajorStructureBreak()
{
   double currentPrice = m_IsLong ? 
                        SymbolInfoDouble(m_Symbol, SYMBOL_BID) : 
                        SymbolInfoDouble(m_Symbol, SYMBOL_ASK);
   
   // Get last 4 candle closes for very strong confirmation
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(m_Symbol, PERIOD_M5, 0, 4, close) < 4)
      return false;
   
   // Larger buffer zone (15-20 pips) before partial profit
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double buffer = 20 * point * 10; // 20 pips buffer
   
   bool brokeStructure = false;
   
   // Check if broke entry structure (require 4 candles + larger buffer)
   if(m_IsLong)
   {
      double structureLowWithBuffer = m_EntryStructureLow - buffer;
      if(close[0] < structureLowWithBuffer && 
         close[1] < structureLowWithBuffer && 
         close[2] < structureLowWithBuffer &&
         close[3] < structureLowWithBuffer)
      {
         brokeStructure = true;
         (*m_Logger).LogWarning("Major structure break: 4 candles below entry structure (before partial)");
      }
   }
   else
   {
      double structureHighWithBuffer = m_EntryStructureHigh + buffer;
      if(close[0] > structureHighWithBuffer && 
         close[1] > structureHighWithBuffer && 
         close[2] > structureHighWithBuffer &&
         close[3] > structureHighWithBuffer)
      {
         brokeStructure = true;
         (*m_Logger).LogWarning("Major structure break: 4 candles above entry structure (before partial)");
      }
   }
   
   return brokeStructure;
}

//+------------------------------------------------------------------+
//| Detect trend continuation (hard exit)                            |
//| IMPROVED: Requires 3-4 strong impulses + stronger confirmation   |
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::DetectTrendContinuation()
{
   // IMPROVED: Require 3-4 strong impulses (was 2) - much less aggressive
   // This significantly reduces false exits during normal retracements
   
   // Check 1: Strong impulsive candle with trend
   if(IsStrongImpulsiveCandle(m_IsLong))
   {
      m_StrongImpulseCount++;
   }
   else
   {
      // Slowly decay count (allows some retracements without resetting)
      if(m_StrongImpulseCount > 0)
         m_StrongImpulseCount = MathMax(0, m_StrongImpulseCount - 1);
   }
   
   // Require at least 3 strong impulses (increased from 2)
   if(m_StrongImpulseCount < 3)
   {
      return false;
   }
   
   // Check 2: Follow-through candle (require 2 consecutive follow-throughs)
   if(!HasFollowThroughCandle(m_IsLong))
   {
      return false;
   }
   
   // Additional check: Require 2 consecutive follow-through candles
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(m_Symbol, PERIOD_M5, 0, 3, close) >= 3)
   {
      bool hasDoubleFollowThrough = false;
      if(m_IsLong)
      {
         // For long: 2 consecutive lower closes
         hasDoubleFollowThrough = (close[0] < close[1] && close[1] < close[2]);
      }
      else
      {
         // For short: 2 consecutive higher closes
         hasDoubleFollowThrough = (close[0] > close[1] && close[1] > close[2]);
      }
      
      if(!hasDoubleFollowThrough)
      {
         return false;
      }
   }
   
   // Check 3: Failure to reclaim mid-level (require 5 candles, not 3)
   double midLevel = (m_EntryPrice + m_TargetMean) / 2.0;
   if(!FailedToReclaimMidLevelExtended(m_IsLong, midLevel))
   {
      return false;
   }
   
   // All conditions met = trend resumed
   (*m_Logger).LogWarning(StringFormat("Trend continuation: %d strong impulses + double follow-through + extended mid-level failure", 
                                      m_StrongImpulseCount));
   return true;
}

//+------------------------------------------------------------------+
//| Check if candle is strong impulsive (trend direction)            |
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::IsStrongImpulsiveCandle(bool isLong)
{
   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(CopyOpen(m_Symbol, PERIOD_M5, 0, 1, open) <= 0 ||
      CopyHigh(m_Symbol, PERIOD_M5, 0, 1, high) <= 0 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 1, low) <= 0 ||
      CopyClose(m_Symbol, PERIOD_M5, 0, 1, close) <= 0)
   {
      return false;
   }
   
   double candleRange = high[0] - low[0];
   if(candleRange <= 0) return false;
   
   double bodySize = MathAbs(close[0] - open[0]);
   double bodyPercent = bodySize / candleRange;
   
   // Strong impulsive = body > 70% of range, in trend direction
   if(isLong)
   {
      // For long position: strong bearish candle = trend continuation down
      bool strongBearish = (close[0] < open[0]) && (bodyPercent > 0.70);
      return strongBearish;
   }
   else
   {
      // For short position: strong bullish candle = trend continuation up
      bool strongBullish = (close[0] > open[0]) && (bodyPercent > 0.70);
      return strongBullish;
   }
}

//+------------------------------------------------------------------+
//| Check for follow-through candle                                  |
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::HasFollowThroughCandle(bool isLong)
{
   double close[];
   ArraySetAsSeries(close, true);
   
   if(CopyClose(m_Symbol, PERIOD_M5, 0, 2, close) < 2)
      return false;
   
   // Follow-through = next candle continues in same direction
   if(isLong)
   {
      // For long: bearish candle followed by lower close
      return (close[0] < close[1]);
   }
   else
   {
      // For short: bullish candle followed by higher close
      return (close[0] > close[1]);
   }
}

//+------------------------------------------------------------------+
//| Check if failed to reclaim mid-level                             |
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::FailedToReclaimMidLevel(bool isLong, double midLevel)
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 3, high) < 3 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 3, low) < 3)
      return false;
   
   // Check last 3 candles - did price fail to reclaim mid-level?
   if(isLong)
   {
      // For long: price should reclaim mid-level (go above)
      // Failure = all 3 candles closed below mid-level
      bool allBelow = (high[0] < midLevel) && (high[1] < midLevel) && (high[2] < midLevel);
      return allBelow;
   }
   else
   {
      // For short: price should reclaim mid-level (go below)
      // Failure = all 3 candles closed above mid-level
      bool allAbove = (low[0] > midLevel) && (low[1] > midLevel) && (low[2] > midLevel);
      return allAbove;
   }
}

//+------------------------------------------------------------------+
//| Check if failed to reclaim mid-level (extended - 5 candles)      |
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::FailedToReclaimMidLevelExtended(bool isLong, double midLevel)
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 5, high) < 5 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 5, low) < 5)
      return false;
   
   // Check last 5 candles - did price fail to reclaim mid-level?
   if(isLong)
   {
      // For long: price should reclaim mid-level (go above)
      // Failure = all 5 candles closed below mid-level
      bool allBelow = (high[0] < midLevel) && (high[1] < midLevel) && (high[2] < midLevel) &&
                      (high[3] < midLevel) && (high[4] < midLevel);
      return allBelow;
   }
   else
   {
      // For short: price should reclaim mid-level (go below)
      // Failure = all 5 candles closed above mid-level
      bool allAbove = (low[0] > midLevel) && (low[1] > midLevel) && (low[2] > midLevel) &&
                      (low[3] > midLevel) && (low[4] > midLevel);
      return allAbove;
   }
}

//+------------------------------------------------------------------+
//| Check VWAP behavior                                              |
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::CheckVWAPBehavior()
{
   if(m_TargetVWAP <= 0) return false;
   
   double currentPrice = m_IsLong ? 
                        SymbolInfoDouble(m_Symbol, SYMBOL_BID) : 
                        SymbolInfoDouble(m_Symbol, SYMBOL_ASK);
   
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double tolerance = 5 * point * 10; // 5 pips tolerance
   
   // Check if price touched VWAP for first time
   if(!m_VWAPFirstTouch)
   {
      bool touchedVWAP = MathAbs(currentPrice - m_TargetVWAP) <= tolerance;
      
      if(touchedVWAP)
      {
         m_VWAPFirstTouch = true;
         m_VWAPTouchPrice = currentPrice;
         (*m_Logger).LogInfo("VWAP first touch - Monitoring for rejection");
      }
   }
   
   // If VWAP touched, check for rejection
   if(m_VWAPFirstTouch && !m_VWAPRejected)
   {
      // Check if price rejected VWAP (moved away)
      double distanceFromVWAP = MathAbs(currentPrice - m_TargetVWAP);
      
      if(distanceFromVWAP > tolerance * 2) // Moved 10+ pips away
      {
         // Check if rejection is in wrong direction (against our trade)
         bool rejectedAgainstUs = false;
         
         if(m_IsLong)
         {
            // For long: rejection = price moved below VWAP
            rejectedAgainstUs = (currentPrice < m_TargetVWAP);
         }
         else
         {
            // For short: rejection = price moved above VWAP
            rejectedAgainstUs = (currentPrice > m_TargetVWAP);
         }
         
         if(rejectedAgainstUs)
         {
            m_VWAPRejected = true;
            (*m_Logger).LogWarning("VWAP rejected against trade - Exit bias");
            return true; // Exit signal
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Called on new bar                                                |
//+------------------------------------------------------------------+
void CProfessionalTradeManager::OnNewBar()
{
   if(m_PositionTicket == 0) return;
   
   ManageTrade();
   m_LastCheckTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Check if should exit trade                                       |
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::ShouldExitTrade()
{
   return (m_State == TM_STRUCTURE_BROKEN || 
           m_State == TM_TREND_RESUMED || 
           m_VWAPRejected);
}

//+------------------------------------------------------------------+
//| Get exit reason                                                  |
//+------------------------------------------------------------------+
string CProfessionalTradeManager::GetExitReason()
{
   if(m_State == TM_STRUCTURE_BROKEN)
      return "Structure break";
   else if(m_State == TM_TREND_RESUMED)
      return "Trend continuation";
   else if(m_VWAPRejected)
      return "VWAP rejected";
   else
      return "Unknown";
}

//+------------------------------------------------------------------+
//| Check multiple partial profit levels (scale out)                 |
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::CheckMultiplePartials(double currentPrice)
{
   double priceMoved = m_IsLong ? (currentPrice - m_EntryPrice) : (m_EntryPrice - currentPrice);
   double distancePercent = (m_DistanceToMean > 0) ? (priceMoved / m_DistanceToMean) : 0;
   
   // OPTIMIZED: Delayed partial profits to let winners run
   // Partial 1: 20% at 60% of distance to mean (was 25% at 50%)
   if(!m_Partial1Taken && distancePercent >= 0.60)
   {
      if(TakePartialProfit(0.20))
      {
         m_Partial1Taken = true;
         m_Partial1Price = currentPrice;
         m_PartialTaken = true; // Mark as partial taken
         m_State = TM_PARTIAL_TAKEN;
         (*m_Logger).LogInfo(StringFormat("✅ Partial 1 taken: 20%% at 60%% distance (%.5f)", currentPrice));
      }
   }
   
   // Partial 2: 20% at 80% of distance to mean (was 25% at 75%)
   if(m_Partial1Taken && !m_Partial2Taken && distancePercent >= 0.80)
   {
      if(TakePartialProfit(0.20))
      {
         m_Partial2Taken = true;
         m_Partial2Price = currentPrice;
         (*m_Logger).LogInfo(StringFormat("✅ Partial 2 taken: 20%% at 80%% distance (%.5f)", currentPrice));
      }
   }
   
   // Final: Remaining 50% at mean (target)
   if(m_Partial1Taken && m_Partial2Taken && distancePercent >= 0.95)
   {
      // Close remaining position at mean
      if(PositionSelectByTicket(m_PositionTicket))
      {
         double remainingVolume = PositionGetDouble(POSITION_VOLUME);
         if(remainingVolume > 0)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_DEAL;
            request.symbol = m_Symbol;
            request.volume = remainingVolume;
            request.type = m_IsLong ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.position = m_PositionTicket;
            request.deviation = 10;
            request.magic = 123456;
            request.comment = "Final exit at mean target";
            
            if(OrderSend(request, result))
            {
               (*m_Logger).LogInfo(StringFormat("✅ Final exit: 50%% at mean target (%.5f)", currentPrice));
               return true;
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Update trailing stop                                              |
//+------------------------------------------------------------------+
void CProfessionalTradeManager::UpdateTrailingStop(double currentPrice)
{
   if(!PositionSelectByTicket(m_PositionTicket))
      return;
   
   double currentProfit = m_IsLong ? 
                         (currentPrice - m_EntryPrice) : 
                         (m_EntryPrice - currentPrice);
   
   // Track highest profit
   if(currentProfit > m_HighestProfit)
   {
      m_HighestProfit = currentProfit;
   }
   
   // Activate trailing stop if profit > 20 pips
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double minProfit = 20 * point * 10; // 20 pips
   
   if(m_HighestProfit > minProfit)
   {
      // Calculate trailing stop: 25-30 pips behind highest profit
      double trailDistance = 25 * point * 10; // 25 pips
      double newStopLoss = 0;
      
      if(m_IsLong)
      {
         newStopLoss = currentPrice - trailDistance;
         // Only move stop up, never down
         if(newStopLoss > m_TrailingStopPrice || m_TrailingStopPrice == 0)
         {
            m_TrailingStopPrice = newStopLoss;
            // Update position stop loss
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_SLTP;
            request.symbol = m_Symbol;
            request.position = m_PositionTicket;
            request.sl = m_TrailingStopPrice;
            request.tp = PositionGetDouble(POSITION_TP);
            request.magic = 123456;
            
            if(OrderSend(request, result))
            {
               m_TrailingStopActive = true;
            }
         }
      }
      else
      {
         newStopLoss = currentPrice + trailDistance;
         // Only move stop down, never up
         if(newStopLoss < m_TrailingStopPrice || m_TrailingStopPrice == 0)
         {
            m_TrailingStopPrice = newStopLoss;
            // Update position stop loss
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_SLTP;
            request.symbol = m_Symbol;
            request.position = m_PositionTicket;
            request.sl = m_TrailingStopPrice;
            request.tp = PositionGetDouble(POSITION_TP);
            request.magic = 123456;
            
            if(OrderSend(request, result))
            {
               m_TrailingStopActive = true;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Set breakeven stop (eliminate risk after partial)                |
//+------------------------------------------------------------------+
void CProfessionalTradeManager::SetBreakevenStop()
{
   if(!PositionSelectByTicket(m_PositionTicket))
      return;
   
   double currentPrice = m_IsLong ? 
                        SymbolInfoDouble(m_Symbol, SYMBOL_BID) : 
                        SymbolInfoDouble(m_Symbol, SYMBOL_ASK);
   
   // Check if price moved enough to set breakeven (10-15 pips profit)
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double minProfit = 10 * point * 10; // 10 pips
   double priceMoved = m_IsLong ? (currentPrice - m_EntryPrice) : (m_EntryPrice - currentPrice);
   
   if(priceMoved >= minProfit)
   {
      // Set stop loss to entry price (breakeven)
      double breakevenSL = m_EntryPrice;
      
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      request.action = TRADE_ACTION_SLTP;
      request.symbol = m_Symbol;
      request.position = m_PositionTicket;
      request.sl = breakevenSL;
      request.tp = PositionGetDouble(POSITION_TP);
      request.magic = 123456;
      
      if(OrderSend(request, result))
      {
         m_BreakevenSet = true;
         (*m_Logger).LogInfo("✅ Breakeven stop set - Risk eliminated");
      }
   }
}

//+------------------------------------------------------------------+
//| Reset trade manager                                              |
//+------------------------------------------------------------------+
void CProfessionalTradeManager::Reset()
{
   m_PositionTicket = 0;
   m_EntryPrice = 0;
   m_State = TM_NONE;
   m_PartialTaken = false;
   m_Partial1Taken = false;
   m_Partial2Taken = false;
   m_Partial1Price = 0;
   m_Partial2Price = 0;
   m_TrailingStopActive = false;
   m_TrailingStopPrice = 0;
   m_HighestProfit = 0;
   m_BreakevenSet = false;
   m_StopLossPrice = 0;
   m_StructureBreakCandles = 0;
   m_TrendContinuationDetected = false;
   m_StrongImpulseCount = 0;
   m_VWAPFirstTouch = false;
   m_VWAPRejected = false;
}

