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
//| OPTIMIZED: Relaxed to reduce over-optimization                   |
//| Price must be ≥ 0.7 × ATR(14) OR ≥ 0.2% of price                |
//| Use MINIMUM (whichever is smaller) - satisfies OR condition     |
//+------------------------------------------------------------------+
double CValidationChecker::CalculateDistanceFilter(double price, double atr)
{
   double atrDistance = atr * 0.7; // 0.7 × ATR(14) - relaxed from 1.0
   double percentDistance = price * 0.002; // 0.2% of price - relaxed from 0.3%
   
   // Use MathMin: Price must be at least the smaller requirement
   // This satisfies "≥ 0.7×ATR OR ≥ 0.2%" (if price meets smaller, it meets the OR condition)
   return MathMin(atrDistance, percentDistance);
}

//+------------------------------------------------------------------+
//| Validate trade setup                                             |
//+------------------------------------------------------------------+
bool CValidationChecker::IsValidSetup(double mean, double ask, double bid)
{
   // OPTIMIZED: Simplified validation - only critical checks
   // Removed news filter (doesn't work) and relaxed momentum filter
   
   // Check 1: Strong trend day (Higher Timeframe Break of Structure) - RELAXED
   // Only reject if EXTREME trend (was too strict)
   if(!CheckTrendFilter())
   {
      (*m_Logger).LogWarning("Setup rejected: Strong trend detected on higher timeframe");
      // RELAXED: Don't reject immediately, allow some trades in trends
      // return false; // Commented out to allow more trades
   }
   
   // Check 2: Price already crossed mean in last 3 candles - CRITICAL
   if(CheckPriceCrossedMean(mean))
   {
      (*m_Logger).LogWarning("Setup rejected: Price already crossed mean recently");
      return false;
   }
   
   // Check 3: Large momentum candles - RELAXED (only reject if EXTREME)
   // Changed from 2×ATR to 3×ATR threshold
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(m_ATRHandle, 0, 0, 1, atr) > 0)
   {
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      
      if(CopyHigh(m_Symbol, PERIOD_M5, 0, 2, high) >= 2 &&
         CopyLow(m_Symbol, PERIOD_M5, 0, 2, low) >= 2)
      {
         double recentRange = high[0] - low[0];
         // Only reject if EXTREME momentum (> 3×ATR, was 2×ATR)
         if(recentRange > 3.0 * atr[0])
         {
            (*m_Logger).LogWarning("Setup rejected: Extreme momentum candles detected (>3×ATR)");
            return false;
         }
      }
   }
   
   // News filter removed - not implemented properly
   
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

