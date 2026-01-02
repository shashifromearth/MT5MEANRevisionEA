//+------------------------------------------------------------------+
//| PerformanceMetrics.mqh                                           |
//| Tracks win rate, drawdown, and other performance metrics          |
//+------------------------------------------------------------------+
#include "Logger.mqh"

class CPerformanceMetrics
{
private:
   CLogger* m_Logger;
   
   // Trade statistics
   int m_TotalTrades;
   int m_WinningTrades;
   int m_LosingTrades;
   double m_TotalProfit;
   double m_TotalLoss;
   
   // Drawdown tracking
   double m_PeakBalance;
   double m_CurrentDrawdown;
   double m_MaxDrawdown;
   datetime m_LastResetDate;
   
   // Session statistics
   int m_SessionTrades;
   int m_SessionWins;
   double m_SessionProfit;
   
   void UpdateDrawdown();
   void ResetDaily();
   bool IsNewDay();
   
public:
   CPerformanceMetrics(CLogger* logger);
   ~CPerformanceMetrics();
   
   void OnTradeOpen();
   void OnTradeClose(double profit);
   void OnNewBar();
   double GetWinRate();
   double GetCurrentDrawdown();
   double GetMaxDrawdown();
   void LogStatistics();
   void ResetSession();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPerformanceMetrics::CPerformanceMetrics(CLogger* logger)
{
   m_Logger = logger;
   m_TotalTrades = 0;
   m_WinningTrades = 0;
   m_LosingTrades = 0;
   m_TotalProfit = 0;
   m_TotalLoss = 0;
   m_PeakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_CurrentDrawdown = 0;
   m_MaxDrawdown = 0;
   m_LastResetDate = 0;
   m_SessionTrades = 0;
   m_SessionWins = 0;
   m_SessionProfit = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPerformanceMetrics::~CPerformanceMetrics()
{
}

//+------------------------------------------------------------------+
//| Called on new bar                                                |
//+------------------------------------------------------------------+
void CPerformanceMetrics::OnNewBar()
{
   if(IsNewDay())
   {
      ResetDaily();
   }
   
   UpdateDrawdown();
}

//+------------------------------------------------------------------+
//| Check if it's a new day                                          |
//+------------------------------------------------------------------+
bool CPerformanceMetrics::IsNewDay()
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
//| Reset daily statistics                                           |
//+------------------------------------------------------------------+
void CPerformanceMetrics::ResetDaily()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   m_LastResetDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   
   // Log daily statistics before reset
   LogStatistics();
   
   // Reset session stats (not total stats)
   ResetSession();
   
   (*m_Logger).LogInfo("Daily reset: Performance metrics updated");
}

//+------------------------------------------------------------------+
//| Reset session statistics                                         |
//+------------------------------------------------------------------+
void CPerformanceMetrics::ResetSession()
{
   m_SessionTrades = 0;
   m_SessionWins = 0;
   m_SessionProfit = 0;
}

//+------------------------------------------------------------------+
//| Called when trade opens                                          |
//+------------------------------------------------------------------+
void CPerformanceMetrics::OnTradeOpen()
{
   m_SessionTrades++;
   UpdateDrawdown();
}

//+------------------------------------------------------------------+
//| Called when trade closes                                         |
//+------------------------------------------------------------------+
void CPerformanceMetrics::OnTradeClose(double profit)
{
   m_TotalTrades++;
   m_SessionTrades++;
   
   if(profit > 0)
   {
      m_WinningTrades++;
      m_TotalProfit += profit;
      m_SessionWins++;
      m_SessionProfit += profit;
   }
   else if(profit < 0)
   {
      m_LosingTrades++;
      m_TotalLoss += MathAbs(profit);
      m_SessionProfit += profit;
   }
   
   UpdateDrawdown();
   
   // Log if win rate or drawdown exceeds targets
   double winRate = GetWinRate();
   if(winRate > 0 && (winRate < 0.63 || winRate > 0.70))
   {
      (*m_Logger).LogWarning(StringFormat("Win rate outside target range: %.2f%% (target: 63-70%%)", winRate * 100));
   }
   
   double currentDD = GetCurrentDrawdown();
   if(currentDD > 0.08) // 8%
   {
      (*m_Logger).LogWarning(StringFormat("Drawdown exceeds target: %.2f%% (target: <8%%)", currentDD * 100));
   }
}

//+------------------------------------------------------------------+
//| Update drawdown calculation                                      |
//+------------------------------------------------------------------+
void CPerformanceMetrics::UpdateDrawdown()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Update peak balance
   if(currentBalance > m_PeakBalance)
   {
      m_PeakBalance = currentBalance;
      m_CurrentDrawdown = 0;
   }
   else
   {
      // Calculate current drawdown
      m_CurrentDrawdown = (m_PeakBalance - currentBalance) / m_PeakBalance;
      
      // Update max drawdown
      if(m_CurrentDrawdown > m_MaxDrawdown)
      {
         m_MaxDrawdown = m_CurrentDrawdown;
      }
   }
}

//+------------------------------------------------------------------+
//| Get win rate (0.0 to 1.0)                                        |
//+------------------------------------------------------------------+
double CPerformanceMetrics::GetWinRate()
{
   if(m_TotalTrades == 0) return 0;
   return (double)m_WinningTrades / (double)m_TotalTrades;
}

//+------------------------------------------------------------------+
//| Get current drawdown (0.0 to 1.0)                                |
//+------------------------------------------------------------------+
double CPerformanceMetrics::GetCurrentDrawdown()
{
   return m_CurrentDrawdown;
}

//+------------------------------------------------------------------+
//| Get max drawdown (0.0 to 1.0)                                    |
//+------------------------------------------------------------------+
double CPerformanceMetrics::GetMaxDrawdown()
{
   return m_MaxDrawdown;
}

//+------------------------------------------------------------------+
//| Log performance statistics                                       |
//+------------------------------------------------------------------+
void CPerformanceMetrics::LogStatistics()
{
   double winRate = GetWinRate();
   double currentDD = GetCurrentDrawdown();
   double maxDD = GetMaxDrawdown();
   
   string stats = StringFormat(
      "Performance Stats - Total Trades: %d | Wins: %d | Losses: %d | Win Rate: %.2f%% | " +
      "Current DD: %.2f%% | Max DD: %.2f%% | Session Trades: %d | Session Win Rate: %.2f%%",
      m_TotalTrades,
      m_WinningTrades,
      m_LosingTrades,
      winRate * 100,
      currentDD * 100,
      maxDD * 100,
      m_SessionTrades,
      (m_SessionTrades > 0) ? ((double)m_SessionWins / (double)m_SessionTrades * 100) : 0
   );
   
   (*m_Logger).LogInfo(stats);
}

