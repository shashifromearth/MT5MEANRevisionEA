//+------------------------------------------------------------------+
//| ValidationChecker.mqh                                            |
//| Validates trade setups and checks filters                        |
//+------------------------------------------------------------------+
#include "Logger.mqh"

class CValidationChecker
{
private:
   string m_Symbol;
   int m_ATRHandle;
   CLogger* m_Logger;
   
   bool CheckTrendFilter();
   bool CheckPriceCrossedMean(double mean);
   bool CheckNewsFilter();
   bool CheckMomentumCandles();
   
public:
   CValidationChecker(string symbol, int atrHandle, CLogger* logger);
   ~CValidationChecker();
   
   bool IsValidSetup(double mean, double ask, double bid);
   double CalculateDistanceFilter(double price, double atr);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CValidationChecker::CValidationChecker(string symbol, int atrHandle, CLogger* logger)
{
   m_Symbol = symbol;
   m_ATRHandle = atrHandle;
   m_Logger = logger;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CValidationChecker::~CValidationChecker()
{
}

//+------------------------------------------------------------------+
//| Calculate distance filter                                        |
//| Price must be ≥ 1 × ATR(14) OR ≥ 0.3% of price                  |
//| Use MINIMUM (whichever is smaller) - satisfies OR condition     |
//+------------------------------------------------------------------+
double CValidationChecker::CalculateDistanceFilter(double price, double atr)
{
   double atrDistance = atr; // 1 × ATR(14)
   double percentDistance = price * 0.003; // 0.3% of price
   
   // Use MathMin: Price must be at least the smaller requirement
   // This satisfies "≥ 1×ATR OR ≥ 0.3%" (if price meets smaller, it meets the OR condition)
   return MathMin(atrDistance, percentDistance);
}

//+------------------------------------------------------------------+
//| Validate trade setup                                             |
//+------------------------------------------------------------------+
bool CValidationChecker::IsValidSetup(double mean, double ask, double bid)
{
   // Check 1: Strong trend day (Higher Timeframe Break of Structure)
   if(!CheckTrendFilter())
   {
      (*m_Logger).LogWarning("Setup rejected: Strong trend detected on higher timeframe");
      return false;
   }
   
   // Check 2: Price already crossed mean in last 3 candles
   if(CheckPriceCrossedMean(mean))
   {
      (*m_Logger).LogWarning("Setup rejected: Price already crossed mean recently");
      return false;
   }
   
   // Check 3: High impact news within last 15 minutes
   if(CheckNewsFilter())
   {
      (*m_Logger).LogWarning("Setup rejected: High impact news detected");
      return false;
   }
   
   // Check 4: Large momentum candles after entry signal
   if(CheckMomentumCandles())
   {
      (*m_Logger).LogWarning("Setup rejected: Large momentum candles detected");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check trend filter (Higher Timeframe)                            |
//+------------------------------------------------------------------+
bool CValidationChecker::CheckTrendFilter()
{
   // Check H1 timeframe for strong trend
   double h1High[], h1Low[], h1Close[];
   ArraySetAsSeries(h1High, true);
   ArraySetAsSeries(h1Low, true);
   ArraySetAsSeries(h1Close, true);
   
   if(CopyHigh(m_Symbol, PERIOD_H1, 0, 20, h1High) < 20 ||
      CopyLow(m_Symbol, PERIOD_H1, 0, 20, h1Low) < 20 ||
      CopyClose(m_Symbol, PERIOD_H1, 0, 20, h1Close) < 20)
   {
      return true; // If can't get data, allow trade
   }
   
   // Check for break of structure (BOS)
   // Simple check: if price made new highs/lows consistently
   double recentHigh = h1High[ArrayMaximum(h1High, 0, 10)];
   double recentLow = h1Low[ArrayMinimum(h1Low, 0, 10)];
   double olderHigh = h1High[ArrayMaximum(h1High, 10, 10)];
   double olderLow = h1Low[ArrayMinimum(h1Low, 10, 10)];
   
   // Strong uptrend: recent high > older high AND recent low > older low
   bool strongUptrend = (recentHigh > olderHigh && recentLow > olderLow);
   
   // Strong downtrend: recent high < older high AND recent low < older low
   bool strongDowntrend = (recentHigh < olderHigh && recentLow < olderLow);
   
   // Reject if strong trend
   if(strongUptrend || strongDowntrend)
   {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if price crossed mean in last 3 candles                   |
//+------------------------------------------------------------------+
bool CValidationChecker::CheckPriceCrossedMean(double mean)
{
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 3, high) < 3 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 3, low) < 3)
   {
      return false;
   }
   
   // Check if any candle crossed the mean
   for(int i = 0; i < 3; i++)
   {
      if((high[i] > mean && low[i] < mean))
      {
         return true; // Price crossed mean
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for high impact news                                       |
//| Note: This is a placeholder - actual news integration requires    |
//| external service or calendar data                                |
//+------------------------------------------------------------------+
bool CValidationChecker::CheckNewsFilter()
{
   // Placeholder: In real implementation, this would check:
   // 1. Economic calendar for high-impact news
   // 2. Time since last news event
   // 3. News impact level
   
   // For now, return false (no news detected)
   // This should be implemented with actual news feed integration
   return false;
}

//+------------------------------------------------------------------+
//| Check for large momentum candles                                 |
//+------------------------------------------------------------------+
bool CValidationChecker::CheckMomentumCandles()
{
   double atr[];
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(m_ATRHandle, 0, 0, 1, atr) <= 0)
   {
      return false;
   }
   
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 2, high) < 2 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 2, low) < 2)
   {
      return false;
   }
   
   // Check if recent candle range > 2 × ATR (large momentum)
   double recentRange = high[0] - low[0];
   if(recentRange > 2.0 * atr[0])
   {
      return true;
   }
   
   return false;
}

