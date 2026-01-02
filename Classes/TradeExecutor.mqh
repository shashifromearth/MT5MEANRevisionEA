//+------------------------------------------------------------------+
//| TradeExecutor.mqh                                                |
//| Handles order execution and position management                 |
//+------------------------------------------------------------------+
#include "Logger.mqh"

class CTradeExecutor
{
private:
   double m_LotSize;
   bool m_UseMoneyManagement;
   double m_RiskPercent;
   string m_Symbol;
   CLogger* m_Logger;
   
   double CalculateLotSize(double entryPrice, double stopLoss);
   
public:
   CTradeExecutor(double lotSize, bool useMM, double riskPercent, string symbol, CLogger* logger);
   ~CTradeExecutor();
   
   bool ExecuteBuy(double entryPrice, double stopLoss, double takeProfit, string comment);
   bool ExecuteSell(double entryPrice, double stopLoss, double takeProfit, string comment);
   double GetLotSize(double entryPrice, double stopLoss);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTradeExecutor::CTradeExecutor(double lotSize, bool useMM, double riskPercent, string symbol, CLogger* logger)
{
   m_LotSize = lotSize;
   m_UseMoneyManagement = useMM;
   m_RiskPercent = riskPercent;
   m_Symbol = symbol;
   m_Logger = logger;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTradeExecutor::~CTradeExecutor()
{
}

//+------------------------------------------------------------------+
//| Execute buy order                                                |
//+------------------------------------------------------------------+
bool CTradeExecutor::ExecuteBuy(double entryPrice, double stopLoss, double takeProfit, string comment)
{
   double lotSize = GetLotSize(entryPrice, stopLoss);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = m_Symbol;
   request.volume = lotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = SymbolInfoDouble(m_Symbol, SYMBOL_ASK);
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = 10;
   request.magic = 123456;
   request.comment = comment;
   request.type_filling = ORDER_FILLING_FOK;
   
   if(!OrderSend(request, result))
   {
      (*m_Logger).LogError(StringFormat("Buy order failed: %s (retcode: %d)", result.comment, result.retcode));
      return false;
   }
   
   (*m_Logger).LogInfo(StringFormat("Buy order executed: Ticket=%llu, Lot=%.2f, Entry=%.5f, SL=%.5f, TP=%.5f",
                                  result.order, lotSize, entryPrice, stopLoss, takeProfit));
   
   return true;
}

//+------------------------------------------------------------------+
//| Execute sell order                                               |
//+------------------------------------------------------------------+
bool CTradeExecutor::ExecuteSell(double entryPrice, double stopLoss, double takeProfit, string comment)
{
   double lotSize = GetLotSize(entryPrice, stopLoss);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = m_Symbol;
   request.volume = lotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = 10;
   request.magic = 123456;
   request.comment = comment;
   request.type_filling = ORDER_FILLING_FOK;
   
   if(!OrderSend(request, result))
   {
      (*m_Logger).LogError(StringFormat("Sell order failed: %s (retcode: %d)", result.comment, result.retcode));
      return false;
   }
   
   (*m_Logger).LogInfo(StringFormat("Sell order executed: Ticket=%llu, Lot=%.2f, Entry=%.5f, SL=%.5f, TP=%.5f",
                                  result.order, lotSize, entryPrice, stopLoss, takeProfit));
   
   return true;
}

//+------------------------------------------------------------------+
//| Get lot size (with or without money management)                  |
//+------------------------------------------------------------------+
double CTradeExecutor::GetLotSize(double entryPrice, double stopLoss)
{
   if(m_UseMoneyManagement)
   {
      return CalculateLotSize(entryPrice, stopLoss);
   }
   
   return m_LotSize;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                     |
//+------------------------------------------------------------------+
double CTradeExecutor::CalculateLotSize(double entryPrice, double stopLoss)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * m_RiskPercent / 100.0;
   
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(m_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(m_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   double stopLossPoints = MathAbs(entryPrice - stopLoss) / point;
   double stopLossValue = stopLossPoints * tickValue / tickSize;
   
   if(stopLossValue <= 0) return m_LotSize;
   
   double lotSize = riskAmount / stopLossValue;
   
   // Normalize lot size
   double minLot = SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
}

