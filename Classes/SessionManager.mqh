//+------------------------------------------------------------------+
//| SessionManager.mqh                                                |
//| Manages session trade limits and cooldown periods               |
//+------------------------------------------------------------------+
#include "Logger.mqh"

class CSessionManager
{
private:
   int m_MaxTradesPerSession;
   bool m_EnableLossCoolDown;
   int m_LossCoolDownMinutes;
   CLogger* m_Logger;
   
   int m_TradesToday;
   int m_LossesToday;
   datetime m_LastTradeTime;
   datetime m_LastLossTime;
   datetime m_LastResetDate;
   string m_CurrentSession;
   
   bool IsNewDay();
   void ResetDaily();
   string GetCurrentSession();
   
public:
   CSessionManager(int maxTrades, bool enableCooldown, int cooldownMinutes, CLogger* logger);
   ~CSessionManager();
   
   bool CanTrade();
   void OnTrade();
   void OnLoss();
   void OnNewBar();
   int GetTradesToday() { return m_TradesToday; }
   int GetLossesToday() { return m_LossesToday; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSessionManager::CSessionManager(int maxTrades, bool enableCooldown, int cooldownMinutes, CLogger* logger)
{
   m_MaxTradesPerSession = maxTrades;
   m_EnableLossCoolDown = enableCooldown;
   m_LossCoolDownMinutes = cooldownMinutes;
   m_Logger = logger;
   m_TradesToday = 0;
   m_LossesToday = 0;
   m_LastTradeTime = 0;
   m_LastLossTime = 0;
   m_LastResetDate = 0;
   m_CurrentSession = "";
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSessionManager::~CSessionManager()
{
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool CSessionManager::CanTrade()
{
   // Check daily reset
   if(IsNewDay())
   {
      ResetDaily();
   }
   
   // Check max trades per session
   if(m_TradesToday >= m_MaxTradesPerSession)
   {
      (*m_Logger).LogInfo(StringFormat("Max trades per session reached: %d", m_TradesToday));
      return false;
   }
   
   // Check loss cooldown
   if(m_EnableLossCoolDown && m_LossesToday > 0)
   {
      if(m_LossesToday >= 2)
      {
         (*m_Logger).LogWarning("2 losses in session - trading stopped for this session");
         return false;
      }
      
      if(m_LastLossTime > 0)
      {
         datetime currentTime = TimeCurrent();
         int minutesSinceLoss = (int)((currentTime - m_LastLossTime) / 60);
         
         if(minutesSinceLoss < m_LossCoolDownMinutes)
         {
            (*m_Logger).LogInfo(StringFormat("In cooldown period: %d minutes remaining", 
                                          m_LossCoolDownMinutes - minutesSinceLoss));
            return false;
         }
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Called when a trade is executed                                  |
//+------------------------------------------------------------------+
void CSessionManager::OnTrade()
{
   m_TradesToday++;
   m_LastTradeTime = TimeCurrent();
   
   (*m_Logger).LogInfo(StringFormat("Trade executed. Total trades today: %d", m_TradesToday));
}

//+------------------------------------------------------------------+
//| Called when a trade results in a loss                            |
//+------------------------------------------------------------------+
void CSessionManager::OnLoss()
{
   m_LossesToday++;
   m_LastLossTime = TimeCurrent();
   
   (*m_Logger).LogWarning(StringFormat("Trade loss recorded. Total losses today: %d", m_LossesToday));
   
   if(m_LossesToday >= 2)
   {
      (*m_Logger).LogWarning("2 losses reached - trading stopped for this session");
   }
}

//+------------------------------------------------------------------+
//| Called on new bar                                                |
//+------------------------------------------------------------------+
void CSessionManager::OnNewBar()
{
   // Check for session change or daily reset
   string currentSession = GetCurrentSession();
   if(currentSession != m_CurrentSession)
   {
      m_CurrentSession = currentSession;
      // Reset session-specific counters if needed
   }
}

//+------------------------------------------------------------------+
//| Check if it's a new day                                          |
//+------------------------------------------------------------------+
bool CSessionManager::IsNewDay()
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
//| Reset daily counters                                             |
//+------------------------------------------------------------------+
void CSessionManager::ResetDaily()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   m_LastResetDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   
   m_TradesToday = 0;
   m_LossesToday = 0;
   m_LastTradeTime = 0;
   m_LastLossTime = 0;
   
   (*m_Logger).LogInfo("Daily reset: Session counters reset");
}

//+------------------------------------------------------------------+
//| Get current session name                                         |
//+------------------------------------------------------------------+
string CSessionManager::GetCurrentSession()
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

