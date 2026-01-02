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
   int m_TradesThisSession;  // Trades in current session (London or NY)
   int m_LossesToday;
   int m_LossesThisSession;  // Losses in current session
   datetime m_LastTradeTime;
   datetime m_LastLossTime;
   datetime m_LastResetDate;
   string m_CurrentSession;
   string m_LastSession;
   
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
   m_TradesThisSession = 0;
   m_LossesToday = 0;
   m_LossesThisSession = 0;
   m_LastTradeTime = 0;
   m_LastLossTime = 0;
   m_LastResetDate = 0;
   m_CurrentSession = "";
   m_LastSession = "";
   
   // Initialize daily reset on startup
   ResetDaily();
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
   
   // Check session change and reset session counters
   string currentSession = GetCurrentSession();
   if(currentSession != m_CurrentSession && currentSession != "")
   {
      // New session started - reset session counters
      m_LastSession = m_CurrentSession;
      m_CurrentSession = currentSession;
      m_TradesThisSession = 0;
      m_LossesThisSession = 0;
      (*m_Logger).LogInfo(StringFormat("New session started: %s - Session counters reset", currentSession));
   }
   
   // Check max trades per session (2 trades per session)
   if(m_TradesThisSession >= m_MaxTradesPerSession)
   {
      (*m_Logger).LogInfo(StringFormat("Max trades per session reached: %d/%d (Session: %s)", 
                                      m_TradesThisSession, m_MaxTradesPerSession, m_CurrentSession));
      return false;
   }
   
   // Check loss cooldown (per session)
   if(m_EnableLossCoolDown && m_LossesThisSession > 0)
   {
      if(m_LossesThisSession >= 2)
      {
         (*m_Logger).LogWarning(StringFormat("2 losses in session (%s) - trading stopped for this session", m_CurrentSession));
         return false;
      }
      
      if(m_LastLossTime > 0)
      {
         datetime currentTime = TimeCurrent();
         int minutesSinceLoss = (int)((currentTime - m_LastLossTime) / 60);
         
         if(minutesSinceLoss < m_LossCoolDownMinutes)
         {
            (*m_Logger).LogInfo(StringFormat("In cooldown period: %d minutes remaining (Session: %s)", 
                                          m_LossCoolDownMinutes - minutesSinceLoss, m_CurrentSession));
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
   m_TradesThisSession++;
   m_LastTradeTime = TimeCurrent();
   
   (*m_Logger).LogInfo(StringFormat("Trade executed. Session: %s | Trades this session: %d/%d | Total today: %d", 
                                   m_CurrentSession, m_TradesThisSession, m_MaxTradesPerSession, m_TradesToday));
}

//+------------------------------------------------------------------+
//| Called when a trade results in a loss                            |
//+------------------------------------------------------------------+
void CSessionManager::OnLoss()
{
   m_LossesToday++;
   m_LossesThisSession++;
   m_LastLossTime = TimeCurrent();
   
   (*m_Logger).LogWarning(StringFormat("Trade loss recorded. Session: %s | Losses this session: %d | Total today: %d", 
                                       m_CurrentSession, m_LossesThisSession, m_LossesToday));
   
   if(m_LossesThisSession >= 2)
   {
      (*m_Logger).LogWarning(StringFormat("2 losses in session (%s) - trading stopped for this session", m_CurrentSession));
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
   m_TradesThisSession = 0;
   m_LossesToday = 0;
   m_LossesThisSession = 0;
   m_LastTradeTime = 0;
   m_LastLossTime = 0;
   m_CurrentSession = "";
   m_LastSession = "";
   
   (*m_Logger).LogInfo("Daily reset: All counters reset");
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

