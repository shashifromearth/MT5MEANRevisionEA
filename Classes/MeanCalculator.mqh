//+------------------------------------------------------------------+
//| MeanCalculator.mqh                                               |
//| Calculates mean using Asian Midpoint or Session VWAP             |
//+------------------------------------------------------------------+
#include "Enums.mqh"
#include "Logger.mqh"

class CMeanCalculator
{
private:
   MEAN_TYPE m_MeanMethod;
   string m_Symbol;
   CLogger* m_Logger;
   
   datetime m_LastResetDate;
   double m_CachedMean;
   datetime m_CachedMeanTime;
   
   // Asian Midpoint variables
   double m_AsianHigh;
   double m_AsianLow;
   datetime m_AsianStartTime;
   
   // Session VWAP variables
   double m_SessionVolume;
   double m_SessionPriceVolume;
   datetime m_SessionStartTime;
   string m_CurrentSession;
   
   // Asian VWAP variables
   double m_AsianVolume;
   double m_AsianPriceVolume;
   datetime m_AsianVWAPStartTime;
   double m_CachedAsianVWAP;
   datetime m_CachedAsianVWAPTime;
   
   // Last 24-hour (last day) variables
   double m_LastDayHigh;
   double m_LastDayLow;
   datetime m_LastDayResetTime;
   
   double CalculateAsianMidpoint();
   double CalculateSessionVWAP();
   double CalculateAsianVWAP();
   void ResetDaily();
   void CalculateLastDayRange();
   bool IsNewDay();
   bool IsNewSession();
   string GetCurrentSession();
   
public:
   CMeanCalculator(MEAN_TYPE method, string symbol, CLogger* logger);
   ~CMeanCalculator();
   
   double CalculateMean();
   void OnNewBar();
   double GetMean() { return m_CachedMean; }
   double GetAsianHigh() { return m_AsianHigh; }
   double GetAsianLow() { return m_AsianLow; }
   double GetAsianMid() { return (m_AsianHigh > 0 && m_AsianLow < DBL_MAX) ? (m_AsianHigh + m_AsianLow) / 2.0 : 0; }
   double GetAsianVWAP();
   bool IsAsianRangeValid() { return (m_AsianHigh > 0 && m_AsianLow < DBL_MAX); }
   
   // Last 24-hour (last day) calculations
   double GetLastDayHigh();
   double GetLastDayLow();
   double GetLastDayMid();
   bool IsLastDayRangeValid();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CMeanCalculator::CMeanCalculator(MEAN_TYPE method, string symbol, CLogger* logger)
{
   m_MeanMethod = method;
   m_Symbol = symbol;
   m_Logger = logger;
   m_LastResetDate = 0;
   m_CachedMean = 0;
   m_CachedMeanTime = 0;
   m_AsianHigh = 0;
   m_AsianLow = DBL_MAX;
   m_SessionVolume = 0;
   m_SessionPriceVolume = 0;
   m_SessionStartTime = 0;
   m_CurrentSession = "";
   m_AsianVolume = 0;
   m_AsianPriceVolume = 0;
   m_AsianVWAPStartTime = 0;
   m_CachedAsianVWAP = 0;
   m_CachedAsianVWAPTime = 0;
   m_LastDayHigh = 0;
   m_LastDayLow = DBL_MAX;
   m_LastDayResetTime = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CMeanCalculator::~CMeanCalculator()
{
}

//+------------------------------------------------------------------+
//| Calculate mean based on selected method                          |
//+------------------------------------------------------------------+
double CMeanCalculator::CalculateMean()
{
   // Check if we need to reset
   if(IsNewDay())
   {
      ResetDaily();
   }
   
   // Check if cached value is still valid (same bar)
   datetime currentBarTime = iTime(m_Symbol, PERIOD_M5, 0);
   if(m_CachedMeanTime == currentBarTime && m_CachedMean > 0)
   {
      return m_CachedMean;
   }
   
   double mean = 0;
   
   if(m_MeanMethod == ASIAN_MIDPOINT)
   {
      mean = CalculateAsianMidpoint();
   }
   else if(m_MeanMethod == SESSION_VWAP)
   {
      mean = CalculateSessionVWAP();
   }
   
   m_CachedMean = mean;
   m_CachedMeanTime = currentBarTime;
   
   return mean;
}

//+------------------------------------------------------------------+
//| Calculate Asian Midpoint (00:00-05:00 UTC)                      |
//+------------------------------------------------------------------+
double CMeanCalculator::CalculateAsianMidpoint()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Asian session: 00:00-05:00 UTC
   int currentHour = dt.hour;
   int currentMinute = dt.min;
   int currentTime = currentHour * 60 + currentMinute;
   int asianStart = 0;   // 00:00
   int asianEnd = 5 * 60; // 05:00
   
   // Check if we're in Asian session
   bool inAsianSession = (currentTime >= asianStart && currentTime <= asianEnd);
   
   if(inAsianSession)
   {
      // Update high/low during Asian session
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      
      if(CopyHigh(m_Symbol, PERIOD_M5, 0, 1, high) > 0 &&
         CopyLow(m_Symbol, PERIOD_M5, 0, 1, low) > 0)
      {
         if(high[0] > m_AsianHigh) m_AsianHigh = high[0];
         if(low[0] < m_AsianLow) m_AsianLow = low[0];
      }
   }
   
   // Calculate midpoint
   if(m_AsianHigh > 0 && m_AsianLow < DBL_MAX)
   {
      double midpoint = (m_AsianHigh + m_AsianLow) / 2.0;
      return midpoint;
   }
   
   // If Asian session hasn't completed yet, use previous day's values
   // or calculate from available data
   if(m_AsianHigh == 0 || m_AsianLow == DBL_MAX)
   {
      // Try to get last 5 hours of data
      int bars = iBars(m_Symbol, PERIOD_M5);
      int asianBars = 60; // 5 hours * 12 bars per hour
      if(bars < asianBars) asianBars = bars;
      
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      
      if(CopyHigh(m_Symbol, PERIOD_M5, 0, asianBars, high) > 0 &&
         CopyLow(m_Symbol, PERIOD_M5, 0, asianBars, low) > 0)
      {
         int maxIndex = ArrayMaximum(high, 0, asianBars);
         int minIndex = ArrayMinimum(low, 0, asianBars);
         
         if(maxIndex >= 0 && minIndex >= 0)
         {
            return (high[maxIndex] + low[minIndex]) / 2.0;
         }
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Calculate Session VWAP                                           |
//+------------------------------------------------------------------+
double CMeanCalculator::CalculateSessionVWAP()
{
   string currentSession = GetCurrentSession();
   
   // Check if session changed
   if(currentSession != m_CurrentSession || IsNewSession())
   {
      // Reset VWAP for new session
      m_SessionVolume = 0;
      m_SessionPriceVolume = 0;
      m_SessionStartTime = TimeCurrent();
      m_CurrentSession = currentSession;
   }
   
   // Get current bar data
   double open[], high[], low[], close[];
   long volume[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(volume, true);
   
   if(CopyOpen(m_Symbol, PERIOD_M5, 0, 1, open) <= 0 ||
      CopyHigh(m_Symbol, PERIOD_M5, 0, 1, high) <= 0 ||
      CopyLow(m_Symbol, PERIOD_M5, 0, 1, low) <= 0 ||
      CopyClose(m_Symbol, PERIOD_M5, 0, 1, close) <= 0 ||
      CopyTickVolume(m_Symbol, PERIOD_M5, 0, 1, volume) <= 0)
   {
      return 0;
   }
   
   // Typical price for VWAP
   double typicalPrice = (high[0] + low[0] + close[0]) / 3.0;
   
   // Update VWAP
   double volumeValue = (double)volume[0];
   m_SessionPriceVolume += typicalPrice * volumeValue;
   m_SessionVolume += volumeValue;
   
   if(m_SessionVolume > 0)
   {
      return m_SessionPriceVolume / m_SessionVolume;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Get current session name                                         |
//+------------------------------------------------------------------+
string CMeanCalculator::GetCurrentSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentHour = dt.hour;
   int currentMinute = dt.min;
   int currentTime = currentHour * 60 + currentMinute;
   
   // London: 07:00-08:30 UTC
   if(currentTime >= 7*60 && currentTime <= 8*60+30)
      return "London";
   
   // New York: 12:30-14:00 UTC
   if(currentTime >= 12*60+30 && currentTime <= 14*60)
      return "NewYork";
   
   return "Other";
}

//+------------------------------------------------------------------+
//| Check if it's a new day                                          |
//+------------------------------------------------------------------+
bool CMeanCalculator::IsNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   
   if(m_LastResetDate == 0 || currentDate > m_LastResetDate)
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if it's a new session                                      |
//+------------------------------------------------------------------+
bool CMeanCalculator::IsNewSession()
{
   string currentSession = GetCurrentSession();
   return (currentSession != m_CurrentSession);
}

//+------------------------------------------------------------------+
//| Reset daily values                                               |
//+------------------------------------------------------------------+
void CMeanCalculator::ResetDaily()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   m_LastResetDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   
   m_AsianHigh = 0;
   m_AsianLow = DBL_MAX;
   m_CachedMean = 0;
   m_CachedMeanTime = 0;
   m_AsianVolume = 0;
   m_AsianPriceVolume = 0;
   m_AsianVWAPStartTime = 0;
   m_CachedAsianVWAP = 0;
   m_CachedAsianVWAPTime = 0;
   
   (*m_Logger).LogInfo("Daily reset: Asian range reset for new day");
   
   // Calculate last day range
   CalculateLastDayRange();
}

//+------------------------------------------------------------------+
//| Calculate last 24-hour (last day) high, low, and mid             |
//+------------------------------------------------------------------+
void CMeanCalculator::CalculateLastDayRange()
{
   // Get all bars from last 24 hours (288 bars for M5 = 24 hours)
   int barsToCheck = 288; // 24 hours * 12 bars per hour
   int totalBars = iBars(m_Symbol, PERIOD_M5);
   if(barsToCheck > totalBars) barsToCheck = totalBars;
   
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, barsToCheck, high) > 0 &&
      CopyLow(m_Symbol, PERIOD_M5, 0, barsToCheck, low) > 0)
   {
      m_LastDayHigh = 0;
      m_LastDayLow = DBL_MAX;
      
      // Find high and low from last 24 hours
      for(int i = 0; i < barsToCheck; i++)
      {
         if(high[i] > m_LastDayHigh) m_LastDayHigh = high[i];
         if(low[i] < m_LastDayLow) m_LastDayLow = low[i];
      }
      
      m_LastDayResetTime = TimeCurrent();
      
      if(m_LastDayHigh > 0 && m_LastDayLow < DBL_MAX)
      {
         (*m_Logger).LogInfo(StringFormat("Last day range calculated: High=%.5f, Low=%.5f, Mid=%.5f", 
                                         m_LastDayHigh, m_LastDayLow, (m_LastDayHigh + m_LastDayLow) / 2.0));
      }
   }
}

//+------------------------------------------------------------------+
//| Get last day high                                                |
//+------------------------------------------------------------------+
double CMeanCalculator::GetLastDayHigh()
{
   // Recalculate if it's a new day or not initialized
   if(IsNewDay() || m_LastDayHigh == 0)
   {
      CalculateLastDayRange();
   }
   return m_LastDayHigh;
}

//+------------------------------------------------------------------+
//| Get last day low                                                 |
//+------------------------------------------------------------------+
double CMeanCalculator::GetLastDayLow()
{
   // Recalculate if it's a new day or not initialized
   if(IsNewDay() || m_LastDayLow == DBL_MAX)
   {
      CalculateLastDayRange();
   }
   return m_LastDayLow;
}

//+------------------------------------------------------------------+
//| Get last day mid (mean)                                          |
//+------------------------------------------------------------------+
double CMeanCalculator::GetLastDayMid()
{
   double high = GetLastDayHigh();
   double low = GetLastDayLow();
   
   if(high > 0 && low < DBL_MAX)
   {
      return (high + low) / 2.0;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Check if last day range is valid                                 |
//+------------------------------------------------------------------+
bool CMeanCalculator::IsLastDayRangeValid()
{
   return (m_LastDayHigh > 0 && m_LastDayLow < DBL_MAX);
}

//+------------------------------------------------------------------+
//| Calculate Asian VWAP (00:00-05:00 UTC)                           |
//+------------------------------------------------------------------+
double CMeanCalculator::CalculateAsianVWAP()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   int currentHour = dt.hour;
   int currentMinute = dt.min;
   int currentTime = currentHour * 60 + currentMinute;
   int asianStart = 0;   // 00:00 UTC
   int asianEnd = 5 * 60; // 05:00 UTC
   
   // Check if we're in Asian session
   bool inAsianSession = (currentTime >= asianStart && currentTime <= asianEnd);
   
   // Check if it's a new day - reset Asian VWAP
   if(IsNewDay())
   {
      m_AsianVolume = 0;
      m_AsianPriceVolume = 0;
      m_AsianVWAPStartTime = 0;
      m_CachedAsianVWAP = 0;
      m_CachedAsianVWAPTime = 0;
   }
   
   // Check if cached value is still valid (same bar)
   datetime currentBarTime = iTime(m_Symbol, PERIOD_M5, 0);
   if(m_CachedAsianVWAPTime == currentBarTime && m_CachedAsianVWAP > 0)
   {
      return m_CachedAsianVWAP;
   }
   
   if(inAsianSession)
   {
      // Update VWAP during Asian session
      if(m_AsianVWAPStartTime == 0)
      {
         m_AsianVWAPStartTime = TimeCurrent();
         m_AsianVolume = 0;
         m_AsianPriceVolume = 0;
      }
      
      // Get current bar data
      double open[], high[], low[], close[];
      long volume[];
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(volume, true);
      
      if(CopyOpen(m_Symbol, PERIOD_M5, 0, 1, open) <= 0 ||
         CopyHigh(m_Symbol, PERIOD_M5, 0, 1, high) <= 0 ||
         CopyLow(m_Symbol, PERIOD_M5, 0, 1, low) <= 0 ||
         CopyClose(m_Symbol, PERIOD_M5, 0, 1, close) <= 0 ||
         CopyTickVolume(m_Symbol, PERIOD_M5, 0, 1, volume) <= 0)
      {
         return (m_CachedAsianVWAP > 0) ? m_CachedAsianVWAP : 0;
      }
      
      // Typical price for VWAP
      double typicalPrice = (high[0] + low[0] + close[0]) / 3.0;
      
      // Update VWAP
      double volumeValue = (double)volume[0];
      m_AsianPriceVolume += typicalPrice * volumeValue;
      m_AsianVolume += volumeValue;
   }
   
   // Calculate VWAP
   if(m_AsianVolume > 0)
   {
      m_CachedAsianVWAP = m_AsianPriceVolume / m_AsianVolume;
      m_CachedAsianVWAPTime = currentBarTime;
      return m_CachedAsianVWAP;
   }
   
   // If Asian session hasn't completed, return cached value or calculate from historical data
   if(m_CachedAsianVWAP > 0)
   {
      return m_CachedAsianVWAP;
   }
   
   // Try to calculate from historical Asian session data
   int bars = iBars(m_Symbol, PERIOD_M5);
   int asianBars = 60; // 5 hours * 12 bars per hour
   if(bars < asianBars) asianBars = bars;
   
   double open[], high[], low[], close[];
   long volume[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(volume, true);
   
   if(CopyOpen(m_Symbol, PERIOD_M5, 0, asianBars, open) > 0 &&
      CopyHigh(m_Symbol, PERIOD_M5, 0, asianBars, high) > 0 &&
      CopyLow(m_Symbol, PERIOD_M5, 0, asianBars, low) > 0 &&
      CopyClose(m_Symbol, PERIOD_M5, 0, asianBars, close) > 0 &&
      CopyTickVolume(m_Symbol, PERIOD_M5, 0, asianBars, volume) > 0)
   {
      double totalVolume = 0;
      double totalPriceVolume = 0;
      
      for(int i = 0; i < asianBars; i++)
      {
         double typicalPrice = (high[i] + low[i] + close[i]) / 3.0;
         double volumeValue = (double)volume[i];
         totalPriceVolume += typicalPrice * volumeValue;
         totalVolume += volumeValue;
      }
      
      if(totalVolume > 0)
      {
         m_CachedAsianVWAP = totalPriceVolume / totalVolume;
         m_CachedAsianVWAPTime = currentBarTime;
         return m_CachedAsianVWAP;
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Get Asian VWAP                                                  |
//+------------------------------------------------------------------+
double CMeanCalculator::GetAsianVWAP()
{
   return CalculateAsianVWAP();
}

//+------------------------------------------------------------------+
//| Called on new bar                                                |
//+------------------------------------------------------------------+
void CMeanCalculator::OnNewBar()
{
   // Invalidate cache to force recalculation
   m_CachedMeanTime = 0;
}

