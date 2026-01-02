//+------------------------------------------------------------------+
//| LiquidityMagnet.mqh                                               |
//| Tracks multiple touches of Asian High/Low (liquidity magnets)    |
//| Detects oscillations and consolidation boxes                     |
//+------------------------------------------------------------------+
#include "Logger.mqh"

// Touch type
enum TOUCH_TYPE
{
   TOUCH_NONE,
   TOUCH_ASIAN_HIGH,
   TOUCH_ASIAN_LOW,
   TOUCH_DAY_HIGH,
   TOUCH_DAY_LOW
};

class CLiquidityMagnet
{
private:
   string m_Symbol;
   CLogger* m_Logger;
   
   // Asian level touches
   int m_AsianHighTouches;
   int m_AsianLowTouches;
   datetime m_LastAsianHighTouch;
   datetime m_LastAsianLowTouch;
   double m_LastTouchPrice;
   
   // Day level tracking
   double m_DayHigh;
   double m_DayLow;
   datetime m_DayStartTime;
   int m_DayHighTouches;
   int m_DayLowTouches;
   
   // Oscillation tracking
   bool m_InOscillation;
   int m_OscillationCount; // Number of swings between levels
   double m_OscillationHigh;
   double m_OscillationLow;
   datetime m_OscillationStartTime;
   
   // Break tracking
   struct BreakInfo
   {
      bool active;
      double breakPrice;
      datetime breakTime;
      int candleCount;
      bool isDeadZoneBreak;
   };
   BreakInfo m_CurrentBreak;
   
   TOUCH_TYPE DetectTouch(double currentPrice, double asianHigh, double asianLow);
   bool IsShortLivedBreak(int candleCount);
   bool DetectOscillation(double currentPrice, double asianHigh, double asianLow, double asianMid);
   
public:
   CLiquidityMagnet(string symbol, CLogger* logger);
   ~CLiquidityMagnet();
   
   void OnNewBar(double currentPrice, double asianHigh, double asianLow, double asianMid, bool isDeadZone);
   bool IsLiquidityMagnetActive(bool isLong); // Asian Low for long, High for short
   int GetTouchCount(bool isLong); // Returns touch count for entry level
   bool IsInConsolidationBox();
   bool IsShortLivedBreakout(); // 3-4 candle break
   bool IsRangeActive(); // Range vs trend
   double GetDayLow() { return m_DayLow; }
   double GetDayHigh() { return m_DayHigh; }
   void ResetDaily();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CLiquidityMagnet::CLiquidityMagnet(string symbol, CLogger* logger)
{
   m_Symbol = symbol;
   m_Logger = logger;
   m_AsianHighTouches = 0;
   m_AsianLowTouches = 0;
   m_LastAsianHighTouch = 0;
   m_LastAsianLowTouch = 0;
   m_LastTouchPrice = 0;
   m_DayHigh = 0;
   m_DayLow = DBL_MAX;
   m_DayStartTime = 0;
   m_DayHighTouches = 0;
   m_DayLowTouches = 0;
   m_InOscillation = false;
   m_OscillationCount = 0;
   m_OscillationHigh = 0;
   m_OscillationLow = DBL_MAX;
   m_OscillationStartTime = 0;
   m_CurrentBreak.active = false;
   m_CurrentBreak.breakPrice = 0;
   m_CurrentBreak.breakTime = 0;
   m_CurrentBreak.candleCount = 0;
   m_CurrentBreak.isDeadZoneBreak = false;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CLiquidityMagnet::~CLiquidityMagnet()
{
}

//+------------------------------------------------------------------+
//| Called on new bar                                                |
//+------------------------------------------------------------------+
void CLiquidityMagnet::OnNewBar(double currentPrice, double asianHigh, double asianLow, double asianMid, bool isDeadZone)
{
   // Reset daily if new day
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   datetime dayStart = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
   
   if(m_DayStartTime == 0 || currentDate > m_DayStartTime)
   {
      ResetDaily();
      m_DayStartTime = dayStart;
   }
   
   // Update day high/low
   if(currentPrice > m_DayHigh) m_DayHigh = currentPrice;
   if(currentPrice < m_DayLow) m_DayLow = currentPrice;
   
   // Detect touches
   TOUCH_TYPE touch = DetectTouch(currentPrice, asianHigh, asianLow);
   
   if(touch == TOUCH_ASIAN_HIGH)
   {
      datetime currentTime = TimeCurrent();
      // Only count if it's been at least 1 bar since last touch
      if(currentTime - m_LastAsianHighTouch > PeriodSeconds(PERIOD_M5))
      {
         m_AsianHighTouches++;
         m_LastAsianHighTouch = currentTime;
         m_LastTouchPrice = currentPrice;
         (*m_Logger).LogInfo(StringFormat("Asian High touched (Count: %d) - Liquidity magnet strengthening", m_AsianHighTouches));
      }
   }
   else if(touch == TOUCH_ASIAN_LOW)
   {
      datetime currentTime = TimeCurrent();
      // Only count if it's been at least 1 bar since last touch
      if(currentTime - m_LastAsianLowTouch > PeriodSeconds(PERIOD_M5))
      {
         m_AsianLowTouches++;
         m_LastAsianLowTouch = currentTime;
         m_LastTouchPrice = currentPrice;
         (*m_Logger).LogInfo(StringFormat("Asian Low touched (Count: %d) - Liquidity magnet strengthening", m_AsianLowTouches));
      }
   }
   
   // Track breaks
   if(asianHigh > 0 && asianLow > 0)
   {
      bool brokeHigh = (currentPrice > asianHigh);
      bool brokeLow = (currentPrice < asianLow);
      
      if(brokeHigh || brokeLow)
      {
         if(!m_CurrentBreak.active)
         {
            m_CurrentBreak.active = true;
            m_CurrentBreak.breakPrice = currentPrice;
            m_CurrentBreak.breakTime = TimeCurrent();
            m_CurrentBreak.candleCount = 1;
            m_CurrentBreak.isDeadZoneBreak = isDeadZone;
         }
         else
         {
            m_CurrentBreak.candleCount++;
         }
      }
      else
      {
         // Break ended - check if it was short-lived
         if(m_CurrentBreak.active)
         {
            if(IsShortLivedBreak(m_CurrentBreak.candleCount))
            {
               (*m_Logger).LogInfo(StringFormat("Short-lived break detected (%d candles) - Likely stop hunt", m_CurrentBreak.candleCount));
            }
            m_CurrentBreak.active = false;
            m_CurrentBreak.candleCount = 0;
         }
      }
   }
   
   // Detect oscillations
   if(asianMid > 0)
   {
      DetectOscillation(currentPrice, asianHigh, asianLow, asianMid);
   }
}

//+------------------------------------------------------------------+
//| Detect touch of Asian levels                                     |
//+------------------------------------------------------------------+
TOUCH_TYPE CLiquidityMagnet::DetectTouch(double currentPrice, double asianHigh, double asianLow)
{
   if(asianHigh <= 0 || asianLow <= 0) return TOUCH_NONE;
   
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double tolerance = 5 * point * 10; // 5 pips tolerance
   
   // Get recent candles to check for touch
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 2, high) < 2 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 2, low) < 2)
   {
      return TOUCH_NONE;
   }
   
   // Check if touched Asian High (within 5 pips)
   if(MathAbs(high[0] - asianHigh) <= tolerance || MathAbs(high[1] - asianHigh) <= tolerance)
   {
      return TOUCH_ASIAN_HIGH;
   }
   
   // Check if touched Asian Low (within 5 pips)
   if(MathAbs(low[0] - asianLow) <= tolerance || MathAbs(low[1] - asianLow) <= tolerance)
   {
      return TOUCH_ASIAN_LOW;
   }
   
   return TOUCH_NONE;
}

//+------------------------------------------------------------------+
//| Check if break is short-lived (3-4 candles)                     |
//+------------------------------------------------------------------+
bool CLiquidityMagnet::IsShortLivedBreak(int candleCount)
{
   return (candleCount >= 3 && candleCount <= 4);
}

//+------------------------------------------------------------------+
//| Detect oscillation between Asian Low and Mean                   |
//+------------------------------------------------------------------+
bool CLiquidityMagnet::DetectOscillation(double currentPrice, double asianHigh, double asianLow, double asianMid)
{
   // Oscillation = price swings between Asian Low and Mean repeatedly
   double boxRange = asianHigh - asianLow;
   if(boxRange <= 0) return false;
   
   // Check if price is oscillating (swinging between low and mid)
   bool nearLow = (currentPrice >= asianLow && currentPrice <= asianLow + 0.3 * boxRange);
   bool nearMid = (currentPrice >= asianMid - 0.2 * boxRange && currentPrice <= asianMid + 0.2 * boxRange);
   
   if(!m_InOscillation)
   {
      if(nearLow)
      {
         m_InOscillation = true;
         m_OscillationStartTime = TimeCurrent();
         m_OscillationLow = currentPrice;
         m_OscillationHigh = asianMid;
         m_OscillationCount = 1;
         (*m_Logger).LogInfo("Oscillation detected: Price swinging between Asian Low and Mean");
      }
   }
   else
   {
      // Track oscillation swings
      if(nearLow && currentPrice < m_OscillationLow)
      {
         m_OscillationLow = currentPrice;
         m_OscillationCount++;
      }
      else if(nearMid && currentPrice > m_OscillationHigh)
      {
         m_OscillationHigh = currentPrice;
         m_OscillationCount++;
      }
      
      // If price moves significantly away, oscillation ended
      if(currentPrice > asianMid + 0.3 * boxRange || currentPrice < asianLow - 0.1 * boxRange)
      {
         m_InOscillation = false;
         (*m_Logger).LogInfo(StringFormat("Oscillation ended after %d swings", m_OscillationCount));
      }
   }
   
   return m_InOscillation;
}

//+------------------------------------------------------------------+
//| Check if liquidity magnet is active (multiple touches)          |
//+------------------------------------------------------------------+
bool CLiquidityMagnet::IsLiquidityMagnetActive(bool isLong)
{
   // For long: Asian Low is liquidity magnet
   // For short: Asian High is liquidity magnet
   if(isLong)
   {
      return (m_AsianLowTouches >= 2); // 2+ touches = strong magnet
   }
   else
   {
      return (m_AsianHighTouches >= 2); // 2+ touches = strong magnet
   }
}

//+------------------------------------------------------------------+
//| Get touch count for entry level                                  |
//+------------------------------------------------------------------+
int CLiquidityMagnet::GetTouchCount(bool isLong)
{
   return isLong ? m_AsianLowTouches : m_AsianHighTouches;
}

//+------------------------------------------------------------------+
//| Check if price is in consolidation box                           |
//+------------------------------------------------------------------+
bool CLiquidityMagnet::IsInConsolidationBox()
{
   // Consolidation = oscillation with 3+ swings
   return (m_InOscillation && m_OscillationCount >= 3);
}

//+------------------------------------------------------------------+
//| Check if current break is short-lived                            |
//+------------------------------------------------------------------+
bool CLiquidityMagnet::IsShortLivedBreakout()
{
   return (m_CurrentBreak.active && IsShortLivedBreak(m_CurrentBreak.candleCount));
}

//+------------------------------------------------------------------+
//| Check if range is still active (vs trend)                       |
//+------------------------------------------------------------------+
bool CLiquidityMagnet::IsRangeActive()
{
   // Range is active if:
   // 1. We're in oscillation
   // 2. Multiple touches of Asian levels
   // 3. No strong trend breakout
   
   bool hasMultipleTouches = (m_AsianHighTouches >= 2 || m_AsianLowTouches >= 2);
   bool inOscillation = m_InOscillation;
   bool shortBreak = IsShortLivedBreakout();
   
   // Range active if oscillating OR multiple touches OR short breaks
   return (inOscillation || hasMultipleTouches || shortBreak);
}

//+------------------------------------------------------------------+
//| Reset daily values                                               |
//+------------------------------------------------------------------+
void CLiquidityMagnet::ResetDaily()
{
   m_AsianHighTouches = 0;
   m_AsianLowTouches = 0;
   m_LastAsianHighTouch = 0;
   m_LastAsianLowTouch = 0;
   m_DayHigh = 0;
   m_DayLow = DBL_MAX;
   m_DayHighTouches = 0;
   m_DayLowTouches = 0;
   m_InOscillation = false;
   m_OscillationCount = 0;
   m_OscillationHigh = 0;
   m_OscillationLow = DBL_MAX;
   m_CurrentBreak.active = false;
   m_CurrentBreak.candleCount = 0;
   
   (*m_Logger).LogInfo("Daily reset: Liquidity magnet tracking reset");
}

