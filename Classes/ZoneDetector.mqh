//+------------------------------------------------------------------+
//| ZoneDetector.mqh                                                  |
//| Detects price position relative to previous day's key levels     |
//+------------------------------------------------------------------+
#include "Enums.mqh"
#include "Logger.mqh"

enum ZONE_TYPE
{
   ZONE_NONE = 0,      // Not near any key level
   ZONE_NEAR_HIGH = 1, // Near Previous Day High
   ZONE_NEAR_LOW = -1, // Near Previous Day Low
   ZONE_NEAR_MID = 0   // Near Previous Day Mid
};

class CZoneDetector
{
private:
   string m_Symbol;
   CLogger* m_Logger;
   double m_ZonePercent; // Zone width as % of daily range
   bool m_UseDynamicZones;
   int m_ATRPeriod;
   int m_ATRHandle;
   
   double CalculateZoneWidth(double dailyHigh, double dailyLow, double atr);
   
public:
   CZoneDetector(string symbol, double zonePercent, bool useDynamic, int atrPeriod, int atrHandle, CLogger* logger);
   ~CZoneDetector();
   
   // Detect which zone price is currently in
   ZONE_TYPE DetectPriceZone(double currentPrice, double prevDayHigh, double prevDayLow, double prevDayMid, double atr);
   
   // Check if price is within zone
   bool IsInZone(double price, double level, double zoneWidth);
   
   // Get zone boundaries
   void GetZoneBoundaries(double level, double zoneWidth, double &upperBound, double &lowerBound);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CZoneDetector::CZoneDetector(string symbol, double zonePercent, bool useDynamic, int atrPeriod, int atrHandle, CLogger* logger)
{
   m_Symbol = symbol;
   m_ZonePercent = zonePercent;
   m_UseDynamicZones = useDynamic;
   m_ATRPeriod = atrPeriod;
   m_ATRHandle = atrHandle;
   m_Logger = logger;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CZoneDetector::~CZoneDetector()
{
}

//+------------------------------------------------------------------+
//| Calculate zone width based on daily range or ATR                |
//+------------------------------------------------------------------+
double CZoneDetector::CalculateZoneWidth(double dailyHigh, double dailyLow, double atr)
{
   double dailyRange = dailyHigh - dailyLow;
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(m_Symbol, SYMBOL_DIGITS);
   
   if(m_UseDynamicZones && atr > 0)
   {
      // Use ATR-based zone: 0.5 × ATR (more adaptive to volatility)
      return atr * 0.5;
   }
   else
   {
      // Use percentage of daily range
      return dailyRange * (m_ZonePercent / 100.0);
   }
}

//+------------------------------------------------------------------+
//| Detect which zone price is currently in                         |
//+------------------------------------------------------------------+
ZONE_TYPE CZoneDetector::DetectPriceZone(double currentPrice, double prevDayHigh, double prevDayLow, double prevDayMid, double atr)
{
   if(prevDayHigh <= 0 || prevDayLow >= DBL_MAX || prevDayMid <= 0)
   {
      return ZONE_NONE;
   }
   
   double zoneWidth = CalculateZoneWidth(prevDayHigh, prevDayLow, atr);
   
   // Check if price is near High
   if(IsInZone(currentPrice, prevDayHigh, zoneWidth))
   {
      (*m_Logger).LogInfo(StringFormat("Price in NEAR HIGH zone: %.5f (High: %.5f, Zone: ±%.5f)", 
                                       currentPrice, prevDayHigh, zoneWidth));
      return ZONE_NEAR_HIGH;
   }
   
   // Check if price is near Low
   if(IsInZone(currentPrice, prevDayLow, zoneWidth))
   {
      (*m_Logger).LogInfo(StringFormat("Price in NEAR LOW zone: %.5f (Low: %.5f, Zone: ±%.5f)", 
                                       currentPrice, prevDayLow, zoneWidth));
      return ZONE_NEAR_LOW;
   }
   
   // Check if price is near Mid
   if(IsInZone(currentPrice, prevDayMid, zoneWidth))
   {
      (*m_Logger).LogInfo(StringFormat("Price in NEAR MID zone: %.5f (Mid: %.5f, Zone: ±%.5f)", 
                                       currentPrice, prevDayMid, zoneWidth));
      return ZONE_NEAR_MID;
   }
   
   return ZONE_NONE;
}

//+------------------------------------------------------------------+
//| Check if price is within zone of a level                        |
//+------------------------------------------------------------------+
bool CZoneDetector::IsInZone(double price, double level, double zoneWidth)
{
   return (MathAbs(price - level) <= zoneWidth);
}

//+------------------------------------------------------------------+
//| Get zone boundaries                                              |
//+------------------------------------------------------------------+
void CZoneDetector::GetZoneBoundaries(double level, double zoneWidth, double &upperBound, double &lowerBound)
{
   upperBound = level + zoneWidth;
   lowerBound = level - zoneWidth;
}

