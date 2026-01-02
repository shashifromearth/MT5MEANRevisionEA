//+------------------------------------------------------------------+
//| RejectionDetector.mqh                                            |
//| Detects rejection patterns at key levels (high, low, mid)        |
//+------------------------------------------------------------------+
#include "Enums.mqh"
#include "Logger.mqh"

class CRejectionDetector
{
private:
   string m_Symbol;
   CLogger* m_Logger;
   
   bool HasRejectionWick(double level, bool isLong);
   bool HasRejectionCandle(double level, bool isLong);
   
public:
   CRejectionDetector(string symbol, CLogger* logger);
   ~CRejectionDetector();
   
   // Detect rejection at level (for long: rejection above, for short: rejection below)
   bool DetectRejection(double level, bool isLong);
   
   // Detect which direction price will go from mid
   // Returns: 1 = going to high, -1 = going to low, 0 = unclear
   int DetectMidDirection(double midLevel, double lastDayHigh, double lastDayLow);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CRejectionDetector::CRejectionDetector(string symbol, CLogger* logger)
{
   m_Symbol = symbol;
   m_Logger = logger;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CRejectionDetector::~CRejectionDetector()
{
}

//+------------------------------------------------------------------+
//| Detect rejection at level                                       |
//+------------------------------------------------------------------+
bool CRejectionDetector::DetectRejection(double level, bool isLong)
{
   // Check for rejection wick
   if(HasRejectionWick(level, isLong))
   {
      return true;
   }
   
   // Check for rejection candle
   if(HasRejectionCandle(level, isLong))
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for rejection wick                                         |
//+------------------------------------------------------------------+
bool CRejectionDetector::HasRejectionWick(double level, bool isLong)
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
   
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double tolerance = 10 * point * 10; // 10 pips tolerance
   
   if(isLong)
   {
      // For long: rejection at low level = long wick below, close above
      // Check if price touched level and rejected down
      if(MathAbs(low[0] - level) <= tolerance || MathAbs(low[1] - level) <= tolerance)
      {
         // Check for long lower wick (rejection)
         double candleRange = high[0] - low[0];
         double lowerWick = MathMin(open[0], close[0]) - low[0];
         double wickPercent = (candleRange > 0) ? (lowerWick / candleRange) : 0;
         
         // Long wick = rejection (wick > 40% of range)
         if(wickPercent > 0.40 && close[0] > level)
         {
            (*m_Logger).LogInfo(StringFormat("Rejection detected at level %.5f: Long lower wick (%.1f%%)", level, wickPercent * 100));
            return true;
         }
      }
   }
   else
   {
      // For short: rejection at high level = long wick above, close below
      // Check if price touched level and rejected up
      if(MathAbs(high[0] - level) <= tolerance || MathAbs(high[1] - level) <= tolerance)
      {
         // Check for long upper wick (rejection)
         double candleRange = high[0] - low[0];
         double upperWick = high[0] - MathMax(open[0], close[0]);
         double wickPercent = (candleRange > 0) ? (upperWick / candleRange) : 0;
         
         // Long wick = rejection (wick > 40% of range)
         if(wickPercent > 0.40 && close[0] < level)
         {
            (*m_Logger).LogInfo(StringFormat("Rejection detected at level %.5f: Long upper wick (%.1f%%)", level, wickPercent * 100));
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for rejection candle                                       |
//+------------------------------------------------------------------+
bool CRejectionDetector::HasRejectionCandle(double level, bool isLong)
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
   
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double tolerance = 10 * point * 10; // 10 pips tolerance
   
   if(isLong)
   {
      // For long: rejection = price touched level, then closed above with strong body
      if(MathAbs(low[0] - level) <= tolerance || MathAbs(low[1] - level) <= tolerance)
      {
         // Strong bullish close after touching level
         bool strongClose = (close[0] > open[0] && close[0] > level);
         bool bodySize = MathAbs(close[0] - open[0]) > (high[0] - low[0]) * 0.5;
         
         if(strongClose && bodySize)
         {
            (*m_Logger).LogInfo(StringFormat("Rejection candle detected at level %.5f: Strong bullish close", level));
            return true;
         }
      }
   }
   else
   {
      // For short: rejection = price touched level, then closed below with strong body
      if(MathAbs(high[0] - level) <= tolerance || MathAbs(high[1] - level) <= tolerance)
      {
         // Strong bearish close after touching level
         bool strongClose = (close[0] < open[0] && close[0] < level);
         bool bodySize = MathAbs(close[0] - open[0]) > (high[0] - low[0]) * 0.5;
         
         if(strongClose && bodySize)
         {
            (*m_Logger).LogInfo(StringFormat("Rejection candle detected at level %.5f: Strong bearish close", level));
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Detect which direction price will go from mid                    |
//+------------------------------------------------------------------+
int CRejectionDetector::DetectMidDirection(double midLevel, double lastDayHigh, double lastDayLow)
{
   double close[];
   ArraySetAsSeries(close, true);
   
   if(CopyClose(m_Symbol, PERIOD_M5, 0, 5, close) < 5)
   {
      return 0; // Unclear
   }
   
   // Check recent price action
   double currentPrice = close[0];
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double tolerance = 15 * point * 10; // 15 pips tolerance for "near mid"
   
   // Check if price is near mid
   if(MathAbs(currentPrice - midLevel) > tolerance)
   {
      return 0; // Not near mid
   }
   
   // Check for rejection from mid
   // If rejected upward → going to high
   // If rejected downward → going to low
   
   double high[], low[], open[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(open, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 3, high) < 3 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 3, low) < 3 ||
      CopyOpen(m_Symbol, PERIOD_M5, 0, 3, open) < 3)
   {
      return 0;
   }
   
   // Check last 3 candles for direction
   int upCandles = 0;
   int downCandles = 0;
   
   for(int i = 0; i < 3; i++)
   {
      if(close[i] > open[i]) upCandles++;
      if(close[i] < open[i]) downCandles++;
   }
   
   // Check for rejection wick
   // Upper wick rejection = going down (to low)
   // Lower wick rejection = going up (to high)
   double candleRange = high[0] - low[0];
   if(candleRange > 0)
   {
      double upperWick = high[0] - MathMax(open[0], close[0]);
      double lowerWick = MathMin(open[0], close[0]) - low[0];
      double upperWickPercent = upperWick / candleRange;
      double lowerWickPercent = lowerWick / candleRange;
      
      // Strong upper wick rejection = going to low
      if(upperWickPercent > 0.40 && close[0] < midLevel)
      {
         (*m_Logger).LogInfo("Mid direction: Rejection upward → Going to LOW");
         return -1; // Going to low
      }
      
      // Strong lower wick rejection = going to high
      if(lowerWickPercent > 0.40 && close[0] > midLevel)
      {
         (*m_Logger).LogInfo("Mid direction: Rejection downward → Going to HIGH");
         return 1; // Going to high
      }
   }
   
   // If no clear rejection, use momentum
   if(upCandles >= 2)
   {
      (*m_Logger).LogInfo("Mid direction: Momentum up → Going to HIGH");
      return 1; // Going to high
   }
   else if(downCandles >= 2)
   {
      (*m_Logger).LogInfo("Mid direction: Momentum down → Going to LOW");
      return -1; // Going to low
   }
   
   return 0; // Unclear
}

