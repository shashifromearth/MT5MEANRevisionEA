//+------------------------------------------------------------------+
//| Logger.mqh                                                       |
//| Comprehensive logging and reporting system                       |
//+------------------------------------------------------------------+

class CLogger
{
private:
   bool m_EnableDetailedLog;
   bool m_EnableEmailAlerts;
   string m_LogFileName;
   int m_LogFileHandle;
   
   void WriteToFile(string message);
   void SendEmailAlert(string subject, string body);
   
public:
   CLogger(bool enableDetailedLog, bool enableEmail);
   ~CLogger();
   
   void LogInfo(string message);
   void LogWarning(string message);
   void LogError(string message);
   void LogTrade(string message);
   void LogViolation(string message);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CLogger::CLogger(bool enableDetailedLog, bool enableEmail)
{
   m_EnableDetailedLog = enableDetailedLog;
   m_EnableEmailAlerts = enableEmail;
   m_LogFileHandle = INVALID_HANDLE;
   
   // Create log file name with timestamp
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   m_LogFileName = StringFormat("MeanReversionEA_%04d%02d%02d.log", dt.year, dt.mon, dt.day);
   
   // Open log file
   m_LogFileHandle = FileOpen(m_LogFileName, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(m_LogFileHandle != INVALID_HANDLE)
   {
      FileWriteString(m_LogFileHandle, "=== Mean Reversion EA Log Started ===\n");
      FileFlush(m_LogFileHandle);
   }
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CLogger::~CLogger()
{
   if(m_LogFileHandle != INVALID_HANDLE)
   {
      FileWriteString(m_LogFileHandle, "=== Mean Reversion EA Log Ended ===\n");
      FileClose(m_LogFileHandle);
   }
}

//+------------------------------------------------------------------+
//| Log info message                                                 |
//+------------------------------------------------------------------+
void CLogger::LogInfo(string message)
{
   string fullMessage = StringFormat("[INFO] %s: %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), message);
   
   if(m_EnableDetailedLog)
   {
      Print(fullMessage);
   }
   
   WriteToFile(fullMessage);
}

//+------------------------------------------------------------------+
//| Log warning message                                              |
//+------------------------------------------------------------------+
void CLogger::LogWarning(string message)
{
   string fullMessage = StringFormat("[WARNING] %s: %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), message);
   
   Print(fullMessage);
   WriteToFile(fullMessage);
   
   if(m_EnableEmailAlerts)
   {
      SendEmailAlert("Mean Reversion EA Warning", fullMessage);
   }
}

//+------------------------------------------------------------------+
//| Log error message                                                |
//+------------------------------------------------------------------+
void CLogger::LogError(string message)
{
   string fullMessage = StringFormat("[ERROR] %s: %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), message);
   
   Print(fullMessage);
   WriteToFile(fullMessage);
   
   if(m_EnableEmailAlerts)
   {
      SendEmailAlert("Mean Reversion EA Error", fullMessage);
   }
}

//+------------------------------------------------------------------+
//| Log trade message                                                |
//+------------------------------------------------------------------+
void CLogger::LogTrade(string message)
{
   string fullMessage = StringFormat("[TRADE] %s: %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), message);
   
   Print(fullMessage);
   WriteToFile(fullMessage);
   
   if(m_EnableEmailAlerts)
   {
      SendEmailAlert("Mean Reversion EA Trade", fullMessage);
   }
}

//+------------------------------------------------------------------+
//| Log violation message                                            |
//+------------------------------------------------------------------+
void CLogger::LogViolation(string message)
{
   string fullMessage = StringFormat("[VIOLATION] %s: %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), message);
   
   Print(fullMessage);
   WriteToFile(fullMessage);
   
   if(m_EnableEmailAlerts)
   {
      SendEmailAlert("Mean Reversion EA Rule Violation", fullMessage);
   }
}

//+------------------------------------------------------------------+
//| Write message to file                                            |
//+------------------------------------------------------------------+
void CLogger::WriteToFile(string message)
{
   if(m_LogFileHandle != INVALID_HANDLE)
   {
      FileWriteString(m_LogFileHandle, message + "\n");
      FileFlush(m_LogFileHandle);
   }
}

//+------------------------------------------------------------------+
//| Send email alert                                                 |
//+------------------------------------------------------------------+
void CLogger::SendEmailAlert(string subject, string body)
{
   if(!m_EnableEmailAlerts) return;
   
   // Send email (requires email configuration in MT5)
   SendMail(subject, body);
}

