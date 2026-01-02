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
   double m_PartialPercent; // 30-50%
   double m_PartialDistance; // 25-40% of distance to mean
   
   // Trend continuation tracking
   bool m_TrendContinuationDetected;
   datetime m_LastCheckTime;
   
   // VWAP tracking
   bool m_VWAPFirstTouch;
   bool m_VWAPRejected;
   double m_VWAPTouchPrice;
   
   bool TakePartialProfit(double percent);
   bool CheckStructureBreak();
   bool DetectTrendContinuation();
   bool CheckVWAPBehavior();
   double CalculatePartialDistance();
   bool IsStrongImpulsiveCandle(bool isLong);
   bool HasFollowThroughCandle(bool isLong);
   bool FailedToReclaimMidLevel(bool isLong, double midLevel);
   
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
   m_TrendContinuationDetected = false;
   m_LastCheckTime = 0;
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
   
   // Calculate partial distance (25-40% of distance to mean)
   m_PartialDistance = distanceToMean * 0.35; // 35% average
   m_PartialPercent = 0.40; // 40% of position
   
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
   
   // Layer 1: Partial Profit Rule (NON-NEGOTIABLE)
   if(!m_PartialTaken)
   {
      double priceMoved = m_IsLong ? (currentPrice - m_EntryPrice) : (m_EntryPrice - currentPrice);
      double partialTarget = m_IsLong ? 
                            (m_EntryPrice + m_PartialDistance) : 
                            (m_EntryPrice - m_PartialDistance);
      
      // Check if price reached 25-40% of distance to mean OR first opposing structure
      bool reachedPartialDistance = m_IsLong ? 
                                    (currentPrice >= partialTarget) : 
                                    (currentPrice <= partialTarget);
      
      // Check for first opposing structure (swing high/low)
      bool hitOpposingStructure = false;
      if(m_IsLong)
      {
         // For long: check if hit swing high (opposing structure)
         double high[];
         ArraySetAsSeries(high, true);
         if(CopyHigh(m_Symbol, PERIOD_M5, 0, 3, high) >= 3)
         {
            double recentHigh = high[ArrayMaximum(high, 0, 3)];
            if(currentPrice >= recentHigh * 0.999) // Within 0.1%
            {
               hitOpposingStructure = true;
            }
         }
      }
      else
      {
         // For short: check if hit swing low (opposing structure)
         double low[];
         ArraySetAsSeries(low, true);
         if(CopyLow(m_Symbol, PERIOD_M5, 0, 3, low) >= 3)
         {
            double recentLow = low[ArrayMinimum(low, 0, 3)];
            if(currentPrice <= recentLow * 1.001) // Within 0.1%
            {
               hitOpposingStructure = true;
            }
         }
      }
      
      if(reachedPartialDistance || hitOpposingStructure)
      {
         if(TakePartialProfit(m_PartialPercent))
         {
            m_PartialTaken = true;
            m_PartialPrice = currentPrice;
            m_State = TM_PARTIAL_TAKEN;
            (*m_Logger).LogInfo(StringFormat("✅ Partial profit taken: %.0f%% at %.5f - Green trade guaranteed", 
                                           m_PartialPercent * 100, currentPrice));
         }
      }
   }
   
   // Layer 2: Check structure break (invalidation-based exit)
   if(CheckStructureBreak())
   {
      m_State = TM_STRUCTURE_BROKEN;
      (*m_Logger).LogWarning("Structure broken - Exit signal");
      return;
   }
   
   // Layer 3: Check trend continuation (hard exit)
   if(DetectTrendContinuation())
   {
      m_State = TM_TREND_RESUMED;
      m_TrendContinuationDetected = true;
      (*m_Logger).LogWarning("Trend continuation detected - Exit immediately");
      return;
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
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::CheckStructureBreak()
{
   double currentPrice = m_IsLong ? 
                        SymbolInfoDouble(m_Symbol, SYMBOL_BID) : 
                        SymbolInfoDouble(m_Symbol, SYMBOL_ASK);
   
   // Get current candle close
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(m_Symbol, PERIOD_M5, 0, 1, close) < 1)
      return false;
   
   double candleClose = close[0];
   
   // Check if broke entry structure
   if(m_IsLong)
   {
      // Long: exit if closes below entry structure low
      if(candleClose < m_EntryStructureLow)
      {
         (*m_Logger).LogWarning(StringFormat("Structure break: Closed below entry structure (%.5f < %.5f)", 
                                           candleClose, m_EntryStructureLow));
         return true;
      }
      
      // Check if broke London reaction low
      if(m_LondonReactionLow > 0 && candleClose < m_LondonReactionLow)
      {
         (*m_Logger).LogWarning(StringFormat("Structure break: Closed below London reaction low (%.5f < %.5f)", 
                                           candleClose, m_LondonReactionLow));
         return true;
      }
   }
   else
   {
      // Short: exit if closes above entry structure high
      if(candleClose > m_EntryStructureHigh)
      {
         (*m_Logger).LogWarning(StringFormat("Structure break: Closed above entry structure (%.5f > %.5f)", 
                                           candleClose, m_EntryStructureHigh));
         return true;
      }
      
      // Check if broke London reaction high
      if(m_LondonReactionHigh > 0 && candleClose > m_LondonReactionHigh)
      {
         (*m_Logger).LogWarning(StringFormat("Structure break: Closed above London reaction high (%.5f > %.5f)", 
                                           candleClose, m_LondonReactionHigh));
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Detect trend continuation (hard exit)                            |
//+------------------------------------------------------------------+
bool CProfessionalTradeManager::DetectTrendContinuation()
{
   // Trend continuation = Strong impulsive candle + follow-through + failure to reclaim mid-level
   
   // Check 1: Strong impulsive candle with trend
   if(!IsStrongImpulsiveCandle(m_IsLong))
   {
      return false;
   }
   
   // Check 2: Follow-through candle
   if(!HasFollowThroughCandle(m_IsLong))
   {
      return false;
   }
   
   // Check 3: Failure to reclaim mid-level
   double midLevel = (m_EntryPrice + m_TargetMean) / 2.0;
   if(!FailedToReclaimMidLevel(m_IsLong, midLevel))
   {
      return false;
   }
   
   // All conditions met = trend resumed
   (*m_Logger).LogWarning("Trend continuation: Strong impulse + follow-through + failed to reclaim mid");
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
//| Reset trade manager                                              |
//+------------------------------------------------------------------+
void CProfessionalTradeManager::Reset()
{
   m_PositionTicket = 0;
   m_EntryPrice = 0;
   m_State = TM_NONE;
   m_PartialTaken = false;
   m_TrendContinuationDetected = false;
   m_VWAPFirstTouch = false;
   m_VWAPRejected = false;
}

