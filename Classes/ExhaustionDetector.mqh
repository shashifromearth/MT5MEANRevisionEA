//+------------------------------------------------------------------+
//| ExhaustionDetector.mqh                                           |
//| Detects exhaustion patterns for mean reversion entries           |
//+------------------------------------------------------------------+
#include "Enums.mqh"
#include "Logger.mqh"

class CExhaustionDetector
{
private:
   string m_Symbol;
   CLogger* m_Logger;
   
   bool DetectLongWick();
   bool DetectInsideCandle();
   bool DetectSmallBodies();
   
public:
   CExhaustionDetector(string symbol, CLogger* logger);
   ~CExhaustionDetector();
   
   int DetectExhaustion();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CExhaustionDetector::CExhaustionDetector(string symbol, CLogger* logger)
{
   m_Symbol = symbol;
   m_Logger = logger;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CExhaustionDetector::~CExhaustionDetector()
{
}

//+------------------------------------------------------------------+
//| Detect exhaustion pattern                                        |
//+------------------------------------------------------------------+
int CExhaustionDetector::DetectExhaustion()
{
   // Check all three patterns
   if(DetectLongWick())
   {
      (*m_Logger).LogInfo("Exhaustion pattern detected: LONG_WICK");
      return LONG_WICK;
   }
   
   if(DetectInsideCandle())
   {
      (*m_Logger).LogInfo("Exhaustion pattern detected: INSIDE_CANDLE");
      return INSIDE_CANDLE;
   }
   
   if(DetectSmallBodies())
   {
      (*m_Logger).LogInfo("Exhaustion pattern detected: SMALL_BODIES");
      return SMALL_BODIES;
   }
   
   return EXHAUSTION_NONE;
}

//+------------------------------------------------------------------+
//| Detect long wick pattern                                          |
//| Wick >= 50% of candle range, close not at extreme               |
//+------------------------------------------------------------------+
bool CExhaustionDetector::DetectLongWick()
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
   
   double upperWick = high[0] - MathMax(open[0], close[0]);
   double lowerWick = MathMin(open[0], close[0]) - low[0];
   
   // Check if wick is >= 50% of range
   bool longUpperWick = (upperWick >= 0.5 * candleRange);
   bool longLowerWick = (lowerWick >= 0.5 * candleRange);
   
   if(longUpperWick || longLowerWick)
   {
      // Check if close is not at extreme (not at high or low)
      double closePosition = (close[0] - low[0]) / candleRange;
      bool notAtExtreme = (closePosition > 0.1 && closePosition < 0.9);
      
      return notAtExtreme;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Detect inside candle pattern                                     |
//| High/Low inside previous candle                                  |
//+------------------------------------------------------------------+
bool CExhaustionDetector::DetectInsideCandle()
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 2, high) < 2 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 2, low) < 2)
   {
      return false;
   }
   
   // Current candle (index 0) is inside previous candle (index 1)
   bool isInside = (high[0] < high[1] && low[0] > low[1]);
   
   return isInside;
}

//+------------------------------------------------------------------+
//| Detect small bodies pattern                                      |
//| Two consecutive candles with bodies < 40% of prior impulse      |
//| Prior impulse = largest range in last 5-10 candles              |
//+------------------------------------------------------------------+
bool CExhaustionDetector::DetectSmallBodies()
{
   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   // Need at least 10 candles to find largest range
   if(CopyOpen(m_Symbol, PERIOD_M5, 0, 10, open) < 10 ||
      CopyHigh(m_Symbol, PERIOD_M5, 0, 10, high) < 10 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 10, low) < 10 ||
      CopyClose(m_Symbol, PERIOD_M5, 0, 10, close) < 10)
   {
      return false;
   }
   
   // Find prior impulse: largest range in last 5-10 candles (indices 2-9)
   double maxRange = 0;
   for(int i = 2; i < 10; i++)
   {
      double range = high[i] - low[i];
      if(range > maxRange)
      {
         maxRange = range;
      }
   }
   
   if(maxRange <= 0) return false;
   
   // Calculate body sizes for last two candles (indices 0 and 1)
   double body1 = MathAbs(close[0] - open[0]);
   double body2 = MathAbs(close[1] - open[1]);
   
   // Check if both bodies are < 40% of prior impulse range
   bool smallBody1 = (body1 < 0.4 * maxRange);
   bool smallBody2 = (body2 < 0.4 * maxRange);
   
   return (smallBody1 && smallBody2);
}

