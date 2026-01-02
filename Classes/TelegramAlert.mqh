//+------------------------------------------------------------------+
//| TelegramAlert.mqh                                                |
//| Sends Telegram alerts for trades, margin, and losses             |
//+------------------------------------------------------------------+
#include "Logger.mqh"

class CTelegramAlert
{
private:
   string m_TelegramToken;
   string m_ChatID;
   bool m_EnableTradeEntry;
   bool m_EnableTradeExit;
   bool m_EnableMarginAlert;
   bool m_EnableLossAlert;
   double m_MaxMarginUtilized; // Maximum margin in USD before alert
   double m_MaxSingleTradeLoss; // Maximum single trade loss in USD before alert
   bool m_DebugMode;
   CLogger* m_Logger;
   string m_LogFileName;
   
   bool SendTelegramMessage(string message);
   string URLEncode(string str);
   void LogAlert(string message);
   double GetAccountMarginUtilized();
   double GetPositionLoss(ulong ticket, string symbol);
   
public:
   CTelegramAlert(string token, string chatID, bool enableEntry, bool enableExit, 
                  bool enableMargin, bool enableLoss, double maxMargin, double maxLoss,
                  bool debugMode, CLogger* logger);
   ~CTelegramAlert();
   
   // Trade alerts
   void AlertTradeEntry(bool isLong, double entryPrice, double lotSize, double stopLoss, double takeProfit, string symbol);
   void AlertTradeExit(bool isLong, double exitPrice, double profit, double profitPips, string symbol, string reason);
   
   // Margin and loss monitoring
   void CheckMarginUtilization();
   void CheckTradeLoss(ulong ticket, string symbol);
   
   // Utility
   void SetDebugMode(bool debug) { m_DebugMode = debug; }
   bool IsDebugMode() { return m_DebugMode; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTelegramAlert::CTelegramAlert(string token, string chatID, bool enableEntry, bool enableExit,
                               bool enableMargin, bool enableLoss, double maxMargin, double maxLoss,
                               bool debugMode, CLogger* logger)
{
   m_TelegramToken = token;
   m_ChatID = chatID;
   m_EnableTradeEntry = enableEntry;
   m_EnableTradeExit = enableExit;
   m_EnableMarginAlert = enableMargin;
   m_EnableLossAlert = enableLoss;
   m_MaxMarginUtilized = maxMargin;
   m_MaxSingleTradeLoss = maxLoss;
   m_DebugMode = debugMode;
   m_Logger = logger;
   
   // Create log file name with timestamp
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   m_LogFileName = StringFormat("TelegramAlerts_%04d%02d%02d.log", dt.year, dt.mon, dt.day);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTelegramAlert::~CTelegramAlert()
{
}

//+------------------------------------------------------------------+
//| Send Telegram message                                            |
//+------------------------------------------------------------------+
bool CTelegramAlert::SendTelegramMessage(string message)
{
   // Skip Telegram alerts in Strategy Tester or Debug Mode
   bool is_tester = MQLInfoInteger(MQL_TESTER);
   if(is_tester || m_DebugMode)
   {
      // Log to file instead of sending Telegram
      LogAlert("[TESTER/DEBUG MODE] " + message);
      return true; // Return true to indicate "processed"
   }
   
   // Validate token format
   if(StringLen(m_TelegramToken) < 10)
   {
      Print("Invalid Telegram token");
      return false;
   }
   
   // Send text message
   string url_message = URLEncode(message);
   string url = "https://api.telegram.org/bot" + m_TelegramToken + "/sendMessage";
   string data = "chat_id=" + m_ChatID + "&text=" + url_message + "&parse_mode=HTML";
   
   // Prepare POST data
   uchar post[], result[];
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   
   int data_size = StringToCharArray(data, post, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(post, data_size - 1);
   
   // Send request
   string response_headers = "";
   int timeout = 5000;
   int res = WebRequest("POST", url, headers, timeout, post, result, response_headers);
   
   if(res == 200)
   {
      // Log successful alert
      LogAlert(message);
      return true;
   }
   else
   {
      string error_msg = "❌ Telegram send failed. Error code: " + IntegerToString(res);
      Print(error_msg);
      
      if(res == -1)
      {
         int error = GetLastError();
         error_msg += " | WebRequest error: " + IntegerToString(error);
         Print("WebRequest error code: ", error);
         if(error == 4060)
         {
            string detail = "⚠️ ERROR: WebRequest not allowed! Configure in Tools→Options→Expert Advisors";
            Print(detail);
            error_msg += " | " + detail;
         }
         else if(error == 4014)
         {
            string detail = "⚠️ ERROR: WebRequest not available in Strategy Tester";
            Print(detail);
            error_msg += " | " + detail;
         }
      }
      else
      {
         string response = CharArrayToString(result);
         error_msg += " | Response: " + response;
         Print("HTTP Response: ", response);
         
         // Check for common Telegram API errors
         if(StringFind(response, "Unauthorized") >= 0)
         {
            string detail = "⚠️ Invalid Telegram Bot Token";
            Print(detail);
            error_msg += " | " + detail;
         }
         else if(StringFind(response, "chat not found") >= 0)
         {
            string detail = "⚠️ Invalid Chat ID";
            Print(detail);
            error_msg += " | " + detail;
         }
      }
      
      // Log failure to file
      LogAlert("[FAILED] " + message + " | " + error_msg);
      return false;
   }
}

//+------------------------------------------------------------------+
//| URL Encode string                                                |
//+------------------------------------------------------------------+
string CTelegramAlert::URLEncode(string str)
{
   string result = "";
   int len = StringLen(str);
   
   for(int i = 0; i < len; i++)
   {
      ushort ch = StringGetCharacter(str, i);
      
      if((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || 
         (ch >= '0' && ch <= '9') || ch == '-' || ch == '_' || ch == '.' || ch == '~')
      {
         result += ShortToString(ch);
      }
      else if(ch == ' ')
      {
         result += "+";
      }
      else
      {
         result += StringFormat("%%%02X", ch);
      }
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Log alert to file                                                |
//+------------------------------------------------------------------+
void CTelegramAlert::LogAlert(string message)
{
   string logPath = m_LogFileName;
   int fileHandle = FileOpen(logPath, FILE_WRITE | FILE_READ | FILE_TXT | FILE_COMMON);
   
   if(fileHandle != INVALID_HANDLE)
   {
      FileSeek(fileHandle, 0, SEEK_END);
      string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
      FileWriteString(fileHandle, timestamp + " | " + message + "\n");
      FileClose(fileHandle);
   }
   
   // Also log to logger if available
   if(m_Logger != NULL)
   {
      (*m_Logger).LogInfo("Telegram Alert: " + message);
   }
}

//+------------------------------------------------------------------+
//| Alert trade entry                                                |
//+------------------------------------------------------------------+
void CTelegramAlert::AlertTradeEntry(bool isLong, double entryPrice, double lotSize, double stopLoss, double takeProfit, string symbol)
{
   if(!m_EnableTradeEntry) return;
   
   string direction = isLong ? "🟢 LONG" : "🔴 SHORT";
   string emoji = isLong ? "📈" : "📉";
   
   string message = StringFormat(
      "%s <b>TRADE ENTRY</b> %s\n\n"
      "Symbol: <b>%s</b>\n"
      "Direction: %s\n"
      "Entry Price: <b>%.5f</b>\n"
      "Lot Size: <b>%.2f</b>\n"
      "Stop Loss: <b>%.5f</b>\n"
      "Take Profit: <b>%.5f</b>\n"
      "Time: %s",
      emoji, emoji,
      symbol,
      direction,
      entryPrice,
      lotSize,
      stopLoss,
      takeProfit,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)
   );
   
   SendTelegramMessage(message);
}

//+------------------------------------------------------------------+
//| Alert trade exit                                                 |
//+------------------------------------------------------------------+
void CTelegramAlert::AlertTradeExit(bool isLong, double exitPrice, double profit, double profitPips, string symbol, string reason)
{
   if(!m_EnableTradeExit) return;
   
   string direction = isLong ? "🟢 LONG" : "🔴 SHORT";
   string emoji = (profit >= 0) ? "✅" : "❌";
   string profitStr = (profit >= 0) ? 
      StringFormat("+$%.2f (+%.1f pips)", profit, profitPips) : 
      StringFormat("-$%.2f (-%.1f pips)", MathAbs(profit), MathAbs(profitPips));
   
   string message = StringFormat(
      "%s <b>TRADE EXIT</b> %s\n\n"
      "Symbol: <b>%s</b>\n"
      "Direction: %s\n"
      "Exit Price: <b>%.5f</b>\n"
      "Profit/Loss: <b>%s</b>\n"
      "Reason: %s\n"
      "Time: %s",
      emoji, emoji,
      symbol,
      direction,
      exitPrice,
      profitStr,
      reason,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)
   );
   
   SendTelegramMessage(message);
}

//+------------------------------------------------------------------+
//| Get account margin utilized in USD                              |
//+------------------------------------------------------------------+
double CTelegramAlert::GetAccountMarginUtilized()
{
   // Get margin used (in account currency)
   // ACCOUNT_MARGIN_USED = 6 in ENUM_ACCOUNT_INFO_DOUBLE
   // Use direct numeric cast to avoid enum conversion issues
   double marginUsed = AccountInfoDouble((ENUM_ACCOUNT_INFO_DOUBLE)6); // ACCOUNT_MARGIN_USED
   
   // For simplicity, return margin used directly
   // Currency conversion to USD would require additional logic
   // Most brokers show margin in account currency anyway
   return marginUsed;
}

//+------------------------------------------------------------------+
//| Get position loss in USD                                         |
//+------------------------------------------------------------------+
double CTelegramAlert::GetPositionLoss(ulong ticket, string symbol)
{
   if(!PositionSelectByTicket(ticket))
      return 0;
   
   double profit = PositionGetDouble(POSITION_PROFIT);
   double swap = PositionGetDouble(POSITION_SWAP);
   
   // Get commission from deal history (POSITION_COMMISSION is deprecated)
   double commission = 0;
   if(HistorySelect(PositionGetInteger(POSITION_TIME), TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket > 0)
         {
            // Get deal symbol using the string return version
            string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            long dealPositionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
            if(dealSymbol == symbol && dealPositionId == ticket)
            {
               if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
               {
                  commission += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
               }
            }
         }
      }
   }
   
   // Total loss (negative profit)
   double totalLoss = profit + swap + commission;
   
   return (totalLoss < 0) ? MathAbs(totalLoss) : 0;
}

//+------------------------------------------------------------------+
//| Check margin utilization and alert if exceeded                  |
//+------------------------------------------------------------------+
void CTelegramAlert::CheckMarginUtilization()
{
   if(!m_EnableMarginAlert) return;
   
   double marginUsed = GetAccountMarginUtilized();
   
   if(marginUsed > m_MaxMarginUtilized)
   {
      string message = StringFormat(
         "⚠️ <b>MARGIN ALERT</b> ⚠️\n\n"
         "Margin Utilized: <b>$%.2f</b>\n"
         "Maximum Allowed: <b>$%.2f</b>\n"
         "Excess: <b>$%.2f</b>\n"
         "Time: %s",
         marginUsed,
         m_MaxMarginUtilized,
         marginUsed - m_MaxMarginUtilized,
         TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)
      );
      
      SendTelegramMessage(message);
   }
}

//+------------------------------------------------------------------+
//| Check single trade loss and alert if exceeded                   |
//+------------------------------------------------------------------+
void CTelegramAlert::CheckTradeLoss(ulong ticket, string symbol)
{
   if(!m_EnableLossAlert) return;
   
   double loss = GetPositionLoss(ticket, symbol);
   
   if(loss > m_MaxSingleTradeLoss)
   {
      string message = StringFormat(
         "🚨 <b>LOSS ALERT</b> 🚨\n\n"
         "Symbol: <b>%s</b>\n"
         "Ticket: <b>%llu</b>\n"
         "Current Loss: <b>$%.2f</b>\n"
         "Maximum Allowed: <b>$%.2f</b>\n"
         "Excess: <b>$%.2f</b>\n"
         "Time: %s",
         symbol,
         ticket,
         loss,
         m_MaxSingleTradeLoss,
         loss - m_MaxSingleTradeLoss,
         TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)
      );
      
      SendTelegramMessage(message);
   }
}

