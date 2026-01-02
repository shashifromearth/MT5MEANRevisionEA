//+------------------------------------------------------------------+
//| TimeManager.mqh                                                  |
//| Manages trading session time validation                         |
//+------------------------------------------------------------------+
#include "Logger.mqh"

class CTimeManager
{
private:
   int m_LondonStartHour;
   int m_LondonStartMinute;
   int m_LondonEndHour;
   int m_LondonEndMinute;
   int m_NYStartHour;
   int m_NYStartMinute;
   int m_NYEndHour;
   int m_NYEndMinute;
   CLogger* m_Logger;
   
   bool IsTimeInRange(int hour, int minute, int startHour, int startMinute, int endHour, int endMinute);
   
public:
   CTimeManager(int londonStartH, int londonStartM, int londonEndH, int londonEndM,
                int nyStartH, int nyStartM, int nyEndH, int nyEndM, CLogger* logger);
   ~CTimeManager();
   
   bool IsTradingSession();
   bool IsLondonSession();
   bool IsNewYorkSession();
   bool IsDeadZone();  // Dead zone: 05:00-07:00 UTC (10:30-12:30 IST)
   string GetCurrentSession();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTimeManager::CTimeManager(int londonStartH, int londonStartM, int londonEndH, int londonEndM,
                           int nyStartH, int nyStartM, int nyEndH, int nyEndM, CLogger* logger)
{
   m_LondonStartHour = londonStartH;
   m_LondonStartMinute = londonStartM;
   m_LondonEndHour = londonEndH;
   m_LondonEndMinute = londonEndM;
   m_NYStartHour = nyStartH;
   m_NYStartMinute = nyStartM;
   m_NYEndHour = nyEndH;
   m_NYEndMinute = nyEndM;
   m_Logger = logger;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTimeManager::~CTimeManager()
{
}

//+------------------------------------------------------------------+
//| Check if current time is within trading session                  |
//+------------------------------------------------------------------+
bool CTimeManager::IsTradingSession()
{
   // CRITICAL: Do NOT trade during dead zone
   if(IsDeadZone())
   {
      return false;
   }
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   int currentHour = dt.hour;
   int currentMinute = dt.min;
   
   // Check London session
   if(IsTimeInRange(currentHour, currentMinute, m_LondonStartHour, m_LondonStartMinute,
                    m_LondonEndHour, m_LondonEndMinute))
   {
      return true;
   }
   
   // Check New York session
   if(IsTimeInRange(currentHour, currentMinute, m_NYStartHour, m_NYStartMinute,
                    m_NYEndHour, m_NYEndMinute))
   {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if current time is London session                          |
//+------------------------------------------------------------------+
bool CTimeManager::IsLondonSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   return IsTimeInRange(dt.hour, dt.min, m_LondonStartHour, m_LondonStartMinute,
                        m_LondonEndHour, m_LondonEndMinute);
}

//+------------------------------------------------------------------+
//| Check if current time is New York session                        |
//+------------------------------------------------------------------+
bool CTimeManager::IsNewYorkSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   return IsTimeInRange(dt.hour, dt.min, m_NYStartHour, m_NYStartMinute,
                        m_NYEndHour, m_NYEndMinute);
}

//+------------------------------------------------------------------+
//| Check if current time is Dead Zone (05:00-07:00 UTC)            |
//| Dead Zone: 10:30-12:30 IST = 05:00-07:00 UTC                    |
//+------------------------------------------------------------------+
bool CTimeManager::IsDeadZone()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   int currentHour = dt.hour;
   int currentMinute = dt.min;
   int currentTime = currentHour * 60 + currentMinute;
   
   // Dead zone: 05:00-07:00 UTC (10:30-12:30 IST)
   int deadZoneStart = 5 * 60;   // 05:00 UTC
   int deadZoneEnd = 7 * 60;      // 07:00 UTC
   
   return (currentTime >= deadZoneStart && currentTime < deadZoneEnd);
}

//+------------------------------------------------------------------+
//| Get current session name                                         |
//+------------------------------------------------------------------+
string CTimeManager::GetCurrentSession()
{
   if(IsDeadZone()) return "Dead Zone";
   if(IsLondonSession()) return "London";
   if(IsNewYorkSession()) return "New York";
   return "None";
}

//+------------------------------------------------------------------+
//| Check if time is within specified range                          |
//+------------------------------------------------------------------+
bool CTimeManager::IsTimeInRange(int hour, int minute, int startHour, int startMinute, 
                                  int endHour, int endMinute)
{
   int currentTime = hour * 60 + minute;
   int startTime = startHour * 60 + startMinute;
   int endTime = endHour * 60 + endMinute;
   
   if(startTime <= endTime)
   {
      // Normal range (same day)
      return (currentTime >= startTime && currentTime <= endTime);
   }
   else
   {
      // Range spans midnight
      return (currentTime >= startTime || currentTime <= endTime);
   }
}

