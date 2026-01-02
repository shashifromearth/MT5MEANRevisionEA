//+------------------------------------------------------------------+
//| DeadZoneManager.mqh                                               |
//| Manages dead zone break detection and London confirmation         |
//+------------------------------------------------------------------+
#include "Enums.mqh"
#include "Logger.mqh"
#include "TimeManager.mqh"

// Dead zone break status
enum DEAD_ZONE_BREAK_STATUS
{
   NO_BREAK,              // No break detected
   BREAK_BELOW_LOW,       // Price broke below Asian LOW
   BREAK_ABOVE_HIGH,      // Price broke above Asian HIGH
   BREAK_ACCEPTED,        // Break held (trend continuation)
   BREAK_REJECTED         // Break rejected (mean reversion)
};

// London confirmation pattern
enum LONDON_PATTERN
{
   NO_PATTERN,
   REJECTION_ENGULF,      // Engulfing pattern showing rejection
   STRONG_CLOSE_UP,       // Strong close up (for long entries)
   STRONG_CLOSE_DOWN,     // Strong close down (for short entries)
   CONTINUATION           // Break continues (invalid for mean reversion)
};

class CDeadZoneManager
{
private:
   string m_Symbol;
   CLogger* m_Logger;
   CTimeManager* m_TimeManager;
   
   // Dead zone break tracking
   DEAD_ZONE_BREAK_STATUS m_BreakStatus;
   double m_BreakPrice;
   datetime m_BreakTime;
   double m_AsianHigh;
   double m_AsianLow;
   
   // London confirmation tracking
   bool m_WaitingForLondon;
   datetime m_LondonOpenTime;
   
   // London sweep tracking
   bool m_SweepDetected;
   double m_SweepPrice;
   datetime m_SweepTime;
   bool m_SweepWasRejected;
   
   // Dead zone break weakness tracking
   bool m_DeadZoneBreakWeak;
   int m_DeadZoneBreakCandles;
   
   DEAD_ZONE_BREAK_STATUS DetectDeadZoneBreak(double currentPrice, double asianHigh, double asianLow);
   bool DetectLondonSweep(double currentPrice, double asianHigh, double asianLow);
   LONDON_PATTERN DetectLondonRejection(bool isLongSetup);
   bool IsStrongClose(bool isLong);
   bool IsEngulfingPattern(bool isLong);
   bool IsRejectionCandleValid(bool isLong, double asianHigh, double asianLow);
   bool IsBodyInsideBox(double asianHigh, double asianLow);
   bool NextCandleContinuesBreakout(bool isLong);
   
public:
   CDeadZoneManager(string symbol, CLogger* logger, CTimeManager* timeManager);
   ~CDeadZoneManager();
   
   void UpdateAsianRange(double asianHigh, double asianLow);
   bool CanEnterTrade(double currentPrice, bool isLongSetup);
   LONDON_PATTERN GetLondonConfirmation(bool isLongSetup);
   bool HasLondonSweep() { return m_SweepDetected; }
   bool IsSweepRejected() { return m_SweepWasRejected; }
   bool IsDeadZoneBreakWeak() { return m_DeadZoneBreakWeak; }
   int GetDeadZoneBreakCandles() { return m_DeadZoneBreakCandles; }
   bool IsEntryNearAsianLevel(bool isLong, double currentPrice, double asianHigh, double asianLow);
   void Reset();
   void OnNewBar();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CDeadZoneManager::CDeadZoneManager(string symbol, CLogger* logger, CTimeManager* timeManager)
{
   m_Symbol = symbol;
   m_Logger = logger;
   m_TimeManager = timeManager;
   m_BreakStatus = NO_BREAK;
   m_BreakPrice = 0;
   m_BreakTime = 0;
   m_AsianHigh = 0;
   m_AsianLow = 0;
   m_WaitingForLondon = false;
   m_LondonOpenTime = 0;
   m_SweepDetected = false;
   m_SweepPrice = 0;
   m_SweepTime = 0;
   m_SweepWasRejected = false;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CDeadZoneManager::~CDeadZoneManager()
{
}

//+------------------------------------------------------------------+
//| Update Asian range values                                        |
//+------------------------------------------------------------------+
void CDeadZoneManager::UpdateAsianRange(double asianHigh, double asianLow)
{
   m_AsianHigh = asianHigh;
   m_AsianLow = asianLow;
}

//+------------------------------------------------------------------+
//| Called on new bar                                                |
//+------------------------------------------------------------------+
void CDeadZoneManager::OnNewBar()
{
   // Check if we're in dead zone - monitor for breaks
   bool inDeadZone = false;
   if(m_TimeManager != NULL)
   {
      inDeadZone = m_TimeManager->IsDeadZone();
   }
   
   if(inDeadZone)
   {
      double currentPrice = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
      
      // Check for breaks during dead zone
      if(m_AsianHigh > 0 && m_AsianLow > 0 && m_AsianHigh > m_AsianLow)
      {
         DEAD_ZONE_BREAK_STATUS currentBreak = DetectDeadZoneBreak(currentPrice, m_AsianHigh, m_AsianLow);
         
         if(currentBreak == BREAK_BELOW_LOW || currentBreak == BREAK_ABOVE_HIGH)
         {
            if(m_BreakStatus == NO_BREAK)
            {
               m_BreakStatus = currentBreak;
               m_BreakPrice = currentPrice;
               m_BreakTime = TimeCurrent();
               m_WaitingForLondon = true;
               m_DeadZoneBreakWeak = true; // Dead zone breaks are ALWAYS weak (low volume)
               m_DeadZoneBreakCandles = 1;
               (*m_Logger).LogInfo(StringFormat("Dead zone break detected (WEAK): %s at %.5f - waiting for London confirmation", 
                                             (currentBreak == BREAK_BELOW_LOW) ? "BELOW_LOW" : "ABOVE_HIGH",
                                             currentPrice));
            }
            else
            {
               // Break continues - count candles
               m_DeadZoneBreakCandles++;
               // If 3-4 candles, it's a short-lived break (weak) - high probability reversal
               if(m_DeadZoneBreakCandles >= 3 && m_DeadZoneBreakCandles <= 4)
               {
                  (*m_Logger).LogInfo(StringFormat("Dead zone break: %d candles - Short-lived (WEAK break, expect reversal)", m_DeadZoneBreakCandles));
               }
            }
         }
         else
         {
            // Break ended - check if it was short-lived
            if(m_BreakStatus != NO_BREAK && m_DeadZoneBreakCandles > 0 && m_DeadZoneBreakCandles <= 4)
            {
               (*m_Logger).LogInfo("Dead zone break ended - Short-lived break confirms weakness");
            }
         }
      }
   }
   
   // Check if London just opened
   bool inLondonSession = false;
   if(m_TimeManager != NULL)
   {
      inLondonSession = m_TimeManager->IsLondonSession();
   }
   
   if(inLondonSession)
   {
      if(m_LondonOpenTime == 0)
      {
         m_LondonOpenTime = TimeCurrent();
         if(m_WaitingForLondon)
         {
            (*m_Logger).LogInfo("London session opened - checking for dead zone break confirmation");
         }
      }
      
      // Check for London sweep (touch Asian High/Low then reject)
      if(m_AsianHigh > 0 && m_AsianLow > 0 && m_AsianHigh > m_AsianLow)
      {
         double currentPrice = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
         if(DetectLondonSweep(currentPrice, m_AsianHigh, m_AsianLow))
         {
            m_SweepDetected = true;
            m_SweepPrice = currentPrice;
            m_SweepTime = TimeCurrent();
            (*m_Logger).LogInfo(StringFormat("London sweep detected at %.5f - monitoring for rejection", currentPrice));
         }
      }
   }
   else
   {
      // Reset London open time if not in London session
      bool notInLondon = false;
      if(m_TimeManager != NULL)
      {
         notInLondon = !m_TimeManager->IsLondonSession();
      }
      if(m_LondonOpenTime > 0 && notInLondon)
      {
         m_LondonOpenTime = 0;
      }
   }
   
   // Reset break status if we're past London session
   bool pastLondonSession = false;
   if(m_TimeManager != NULL)
   {
      bool notDeadZone = !m_TimeManager->IsDeadZone();
      bool notLondon = !m_TimeManager->IsLondonSession();
      pastLondonSession = (notDeadZone && notLondon);
   }
   
   if(pastLondonSession)
   {
      if(m_BreakStatus != NO_BREAK && m_BreakStatus != BREAK_ACCEPTED && m_BreakStatus != BREAK_REJECTED)
      {
         (*m_Logger).LogInfo("Resetting dead zone break status - past London session");
         m_BreakStatus = NO_BREAK;
         m_WaitingForLondon = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if we can enter trade based on dead zone break logic      |
//+------------------------------------------------------------------+
bool CDeadZoneManager::CanEnterTrade(double currentPrice, bool isLongSetup)
{
   // If not in London session, cannot enter
   if(m_TimeManager == NULL)
   {
      return false;
   }
   
   bool inLondonSession = m_TimeManager->IsLondonSession();
   if(!inLondonSession)
   {
      return false;
   }
   
   // If no Asian range, allow normal entry (fallback)
   if(m_AsianHigh <= 0 || m_AsianLow <= 0 || m_AsianHigh <= m_AsianLow)
   {
      return true;
   }
   
   // Check if we had a dead zone break (detected during dead zone or just now)
   if(m_BreakStatus == NO_BREAK)
   {
      // No break detected yet - check if price is currently outside Asian range
      DEAD_ZONE_BREAK_STATUS currentBreak = DetectDeadZoneBreak(currentPrice, m_AsianHigh, m_AsianLow);
      
      if(currentBreak == BREAK_BELOW_LOW || currentBreak == BREAK_ABOVE_HIGH)
      {
         // Price is outside range now - need London confirmation
         m_BreakStatus = currentBreak;
         m_BreakPrice = currentPrice;
         m_BreakTime = TimeCurrent();
         m_WaitingForLondon = true;
         (*m_Logger).LogInfo(StringFormat("Dead zone break detected at London open: %s at %.5f - waiting for confirmation", 
                                         (currentBreak == BREAK_BELOW_LOW) ? "BELOW_LOW" : "ABOVE_HIGH",
                                         currentPrice));
         return false; // Wait for London confirmation
      }
      
      // Price is within Asian range - normal mean reversion setup
      return true;
   }
   
   // We have a break or sweep - need London confirmation
   if(m_WaitingForLondon || m_SweepDetected)
   {
      // First check if rejection candle is valid (body inside box, next candle doesn't continue)
      if(m_SweepDetected && !IsRejectionCandleValid(isLongSetup, m_AsianHigh, m_AsianLow))
      {
         // Rejection candle not valid yet - wait
         return false;
      }
      
      LONDON_PATTERN pattern = GetLondonConfirmation(isLongSetup);
      
      if(pattern == REJECTION_ENGULF || pattern == STRONG_CLOSE_UP || pattern == STRONG_CLOSE_DOWN)
      {
         m_BreakStatus = BREAK_REJECTED;
         m_WaitingForLondon = false;
         if(m_SweepDetected)
         {
            m_SweepWasRejected = true;
            (*m_Logger).LogInfo("London sweep rejected - mean reversion entry allowed");
         }
         else
         {
            (*m_Logger).LogInfo("London confirmed rejection - mean reversion entry allowed");
         }
         return true;
      }
      else if(pattern == CONTINUATION)
      {
         m_BreakStatus = BREAK_ACCEPTED;
         m_WaitingForLondon = false;
         m_SweepDetected = false;
         (*m_Logger).LogWarning("London confirmed break continuation - mean reversion INVALID");
         return false;
      }
      
      // Still waiting for confirmation - check if enough time has passed
      if(m_LondonOpenTime > 0)
      {
         int minutesSinceLondon = (int)((TimeCurrent() - m_LondonOpenTime) / 60);
         if(minutesSinceLondon >= 2) // Give 2 minutes for London to show direction
         {
            // If no clear pattern after 2 minutes, allow entry if price is reverting
            double priceChange = currentPrice - m_BreakPrice;
            if((m_BreakStatus == BREAK_BELOW_LOW && priceChange > 0) || 
               (m_BreakStatus == BREAK_ABOVE_HIGH && priceChange < 0))
            {
               m_BreakStatus = BREAK_REJECTED;
               m_WaitingForLondon = false;
               (*m_Logger).LogInfo("Price reverting after dead zone break - mean reversion entry allowed");
               return true;
            }
         }
      }
      
      // Still waiting for confirmation
      return false;
   }
   
   // Break was already processed
   if(m_BreakStatus == BREAK_REJECTED)
   {
      return true; // Can enter mean reversion
   }
   else if(m_BreakStatus == BREAK_ACCEPTED)
   {
      return false; // Mean reversion invalid
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Detect dead zone break                                          |
//+------------------------------------------------------------------+
DEAD_ZONE_BREAK_STATUS CDeadZoneManager::DetectDeadZoneBreak(double currentPrice, double asianHigh, double asianLow)
{
   if(asianHigh <= 0 || asianLow <= 0 || asianHigh <= asianLow)
      return NO_BREAK;
   
   // Check if price broke below Asian LOW
   if(currentPrice < asianLow)
   {
      return BREAK_BELOW_LOW;
   }
   
   // Check if price broke above Asian HIGH
   if(currentPrice > asianHigh)
   {
      return BREAK_ABOVE_HIGH;
   }
   
   return NO_BREAK;
}

//+------------------------------------------------------------------+
//| Get London confirmation pattern                                  |
//+------------------------------------------------------------------+
LONDON_PATTERN CDeadZoneManager::GetLondonConfirmation(bool isLongSetup)
{
   // Check for engulfing pattern
   if(IsEngulfingPattern(isLongSetup))
   {
      return REJECTION_ENGULF;
   }
   
   // Check for strong close
   if(isLongSetup)
   {
      if(IsStrongClose(true))
      {
         return STRONG_CLOSE_UP;
      }
   }
   else
   {
      if(IsStrongClose(false))
      {
         return STRONG_CLOSE_DOWN;
      }
   }
   
   // Check if break is continuing (invalid for mean reversion)
   double currentPrice = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
   if(m_BreakStatus == BREAK_BELOW_LOW && currentPrice < m_BreakPrice)
   {
      return CONTINUATION; // Price continuing down
   }
   if(m_BreakStatus == BREAK_ABOVE_HIGH && currentPrice > m_BreakPrice)
   {
      return CONTINUATION; // Price continuing up
   }
   
   return NO_PATTERN;
}

//+------------------------------------------------------------------+
//| Detect strong close pattern                                      |
//+------------------------------------------------------------------+
bool CDeadZoneManager::IsStrongClose(bool isLong)
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
   
   if(isLong)
   {
      // Strong close up: close in upper 25% of range, body > 60% of range
      double bodySize = MathAbs(close[0] - open[0]);
      double closePosition = (close[0] - low[0]) / candleRange;
      return (closePosition > 0.75 && bodySize > 0.6 * candleRange);
   }
   else
   {
      // Strong close down: close in lower 25% of range, body > 60% of range
      double bodySize = MathAbs(close[0] - open[0]);
      double closePosition = (close[0] - low[0]) / candleRange;
      return (closePosition < 0.25 && bodySize > 0.6 * candleRange);
   }
}

//+------------------------------------------------------------------+
//| Detect engulfing pattern (rejection)                             |
//+------------------------------------------------------------------+
bool CDeadZoneManager::IsEngulfingPattern(bool isLong)
{
   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(CopyOpen(m_Symbol, PERIOD_M5, 0, 2, open) < 2 ||
      CopyHigh(m_Symbol, PERIOD_M5, 0, 2, high) < 2 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 2, low) < 2 ||
      CopyClose(m_Symbol, PERIOD_M5, 0, 2, close) < 2)
   {
      return false;
   }
   
   if(isLong)
   {
      // Bullish engulfing: current candle engulfs previous bearish candle
      bool prevBearish = (close[1] < open[1]);
      bool currentBullish = (close[0] > open[0]);
      bool engulfsHigh = (high[0] > high[1]);
      bool engulfsLow = (low[0] < low[1]);
      
      return (prevBearish && currentBullish && engulfsHigh && engulfsLow);
   }
   else
   {
      // Bearish engulfing: current candle engulfs previous bullish candle
      bool prevBullish = (close[1] > open[1]);
      bool currentBearish = (close[0] < open[0]);
      bool engulfsHigh = (high[0] > high[1]);
      bool engulfsLow = (low[0] < low[1]);
      
      return (prevBullish && currentBearish && engulfsHigh && engulfsLow);
   }
}

//+------------------------------------------------------------------+
//| Detect London sweep (touches Asian High/Low then rejects)        |
//+------------------------------------------------------------------+
bool CDeadZoneManager::DetectLondonSweep(double currentPrice, double asianHigh, double asianLow)
{
   if(asianHigh <= 0 || asianLow <= 0 || asianHigh <= asianLow)
      return false;
   
   // Get recent candles to check for sweep pattern
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 3, high) < 3 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 3, low) < 3 ||
      CopyClose(m_Symbol, PERIOD_M5, 0, 3, close) < 3)
   {
      return false;
   }
   
   // Check if price swept Asian High (touched then rejected)
   // Sweep = high touched Asian High, then closed back inside
   double tolerance = (asianHigh - asianLow) * 0.001; // 0.1% tolerance
   bool sweptHigh = (high[0] >= asianHigh - tolerance && high[0] <= asianHigh + tolerance) && 
                    (close[0] < asianHigh);
   
   // Check if price swept Asian Low (touched then rejected)
   // Sweep = low touched Asian Low, then closed back inside
   bool sweptLow = (low[0] <= asianLow + tolerance && low[0] >= asianLow - tolerance) && 
                   (close[0] > asianLow);
   
   return (sweptHigh || sweptLow);
}

//+------------------------------------------------------------------+
//| Validate rejection candle rules                                  |
//| 1. Long wick into liquidity                                      |
//| 2. Body closes inside box                                       |
//| 3. Next candle does not continue breakout                       |
//+------------------------------------------------------------------+
bool CDeadZoneManager::IsRejectionCandleValid(bool isLong, double asianHigh, double asianLow)
{
   // Check 1: Body closes inside box
   if(!IsBodyInsideBox(asianHigh, asianLow))
   {
      return false;
   }
   
   // Check 2: Next candle does not continue breakout
   if(NextCandleContinuesBreakout(isLong))
   {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if candle body closes inside Asian box                    |
//+------------------------------------------------------------------+
bool CDeadZoneManager::IsBodyInsideBox(double asianHigh, double asianLow)
{
   double open[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);
   
   if(CopyOpen(m_Symbol, PERIOD_M5, 0, 1, open) <= 0 ||
      CopyClose(m_Symbol, PERIOD_M5, 0, 1, close) <= 0)
   {
      return false;
   }
   
   double bodyHigh = MathMax(open[0], close[0]);
   double bodyLow = MathMin(open[0], close[0]);
   
   // Body must be inside Asian box
   return (bodyHigh <= asianHigh && bodyLow >= asianLow);
}

//+------------------------------------------------------------------+
//| Check if next candle continues breakout (invalid)                |
//+------------------------------------------------------------------+
bool CDeadZoneManager::NextCandleContinuesBreakout(bool isLong)
{
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 2, high) < 2 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 2, low) < 2 ||
      CopyClose(m_Symbol, PERIOD_M5, 0, 2, close) < 2)
   {
      return false;
   }
   
   // Check if we had a sweep
   if(m_SweepDetected && m_AsianHigh > 0 && m_AsianLow > 0)
   {
      // If sweep was above (touched high), check if next candle continues up
      if(m_SweepPrice >= m_AsianHigh * 0.999)
      {
         // Sweep was at high - check if next candle continues above
         if(close[1] > m_AsianHigh || high[1] > m_AsianHigh)
         {
            return true; // Continues breakout - invalid
         }
      }
      // If sweep was below (touched low), check if next candle continues down
      else if(m_SweepPrice <= m_AsianLow * 1.001)
      {
         // Sweep was at low - check if next candle continues below
         if(close[1] < m_AsianLow || low[1] < m_AsianLow)
         {
            return true; // Continues breakout - invalid
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if entry is near Asian level (preferred entry zone)       |
//| Entry near Asian Low after rejection = high probability         |
//+------------------------------------------------------------------+
bool CDeadZoneManager::IsEntryNearAsianLevel(bool isLong, double currentPrice, double asianHigh, double asianLow)
{
   if(asianHigh <= 0 || asianLow <= 0) return false;
   
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double tolerance = 10 * point * 10; // 10 pips tolerance
   
   if(isLong)
   {
      // For long: prefer entry near Asian Low (within 10 pips)
      return (currentPrice >= asianLow - tolerance && currentPrice <= asianLow + tolerance);
   }
   else
   {
      // For short: prefer entry near Asian High (within 10 pips)
      return (currentPrice >= asianHigh - tolerance && currentPrice <= asianHigh + tolerance);
   }
}

//+------------------------------------------------------------------+
//| Reset dead zone break status                                    |
//+------------------------------------------------------------------+
void CDeadZoneManager::Reset()
{
   m_BreakStatus = NO_BREAK;
   m_BreakPrice = 0;
   m_BreakTime = 0;
   m_WaitingForLondon = false;
   m_LondonOpenTime = 0;
   m_SweepDetected = false;
   m_SweepPrice = 0;
   m_SweepTime = 0;
   m_SweepWasRejected = false;
   m_DeadZoneBreakWeak = false;
   m_DeadZoneBreakCandles = 0;
}

