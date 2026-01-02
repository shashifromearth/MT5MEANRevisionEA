//+------------------------------------------------------------------+
//| BuyTrade.mqh                                                     |
//| Handles long (buy) trade logic                                   |
//+------------------------------------------------------------------+
#include "Enums.mqh"
#include "TradeExecutor.mqh"
#include "RiskManager.mqh"
#include "MeanCalculator.mqh"
#include "ExhaustionDetector.mqh"
#include "ValidationChecker.mqh"
#include "Logger.mqh"

class CBuyTrade
{
private:
   CTradeExecutor* m_TradeExecutor;
   CRiskManager* m_RiskManager;
   CMeanCalculator* m_MeanCalculator;
   CExhaustionDetector* m_ExhaustionDetector;
   CValidationChecker* m_ValidationChecker;
   string m_Symbol;
   int m_ATRHandle;
   CLogger* m_Logger;
   
   double GetEntryPrice(int exhaustionType);
   
public:
   CBuyTrade(CTradeExecutor* executor, CRiskManager* riskMgr, CMeanCalculator* meanCalc,
             CExhaustionDetector* exhaustionDet, CValidationChecker* validator,
             string symbol, int atrHandle, CLogger* logger);
   ~CBuyTrade();
   
   bool ExecuteTrade(double mean, double distanceFilter, double atr, int exhaustionType);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CBuyTrade::CBuyTrade(CTradeExecutor* executor, CRiskManager* riskMgr, CMeanCalculator* meanCalc,
                     CExhaustionDetector* exhaustionDet, CValidationChecker* validator,
                     string symbol, int atrHandle, CLogger* logger)
{
   m_TradeExecutor = executor;
   m_RiskManager = riskMgr;
   m_MeanCalculator = meanCalc;
   m_ExhaustionDetector = exhaustionDet;
   m_ValidationChecker = validator;
   m_Symbol = symbol;
   m_ATRHandle = atrHandle;
   m_Logger = logger;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CBuyTrade::~CBuyTrade()
{
}

//+------------------------------------------------------------------+
//| Execute buy trade                                                |
//+------------------------------------------------------------------+
bool CBuyTrade::ExecuteTrade(double mean, double distanceFilter, double atr, int exhaustionType)
{
   // CRITICAL SAFETY CHECK: Verify no position exists before execution
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == m_Symbol && 
            PositionGetInteger(POSITION_MAGIC) == 123456) // EA_MAGIC_NUMBER
         {
            (*m_Logger).LogWarning("Buy trade blocked: Position already exists (safety check)");
            return false;
         }
      }
   }
   
   // Get current price
   double ask = SymbolInfoDouble(m_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
   
   // Verify long setup: Price < Mean - Distance_Filter
   double distanceFromMean = mean - ask;
   if(distanceFromMean < distanceFilter)
   {
      (*m_Logger).LogWarning("Buy trade rejected: Price not far enough below mean");
      return false;
   }
   
   // Get entry price: High of exhaustion candle + 0.2 pip
   double entryPrice = GetEntryPrice(exhaustionType);
   if(entryPrice <= 0)
   {
      entryPrice = ask; // Fallback to current ask
   }
   
   // Calculate stop loss
   bool isLong = true;
   double stopLoss = (*m_RiskManager).GetStopLoss(isLong, entryPrice, atr);
   
   // Calculate take profit
   double takeProfit = (*m_RiskManager).GetTakeProfit(isLong, entryPrice, mean, distanceFromMean);
   
   // Validate Risk:Reward ratio (must be 1:0.5 to 1:1)
   if(!(*m_RiskManager).ValidateRiskReward(isLong, entryPrice, stopLoss, takeProfit))
   {
      (*m_Logger).LogWarning("Buy trade rejected: Risk:Reward ratio outside acceptable range (1:0.5 to 1:1)");
      return false;
   }
   
   // Execute trade
   string comment = StringFormat("Long: Mean=%.5f, Dist=%.5f, Exhaustion=%d", 
                                 mean, distanceFromMean, exhaustionType);
   
   bool result = (*m_TradeExecutor).ExecuteBuy(entryPrice, stopLoss, takeProfit, comment);
   
   if(result)
   {
      // Set entry bar time for monitoring
      datetime barTime = iTime(m_Symbol, PERIOD_M5, 0);
      (*m_RiskManager).SetEntryBarTime(barTime);
      (*m_Logger).LogInfo(StringFormat("Buy trade executed: Entry=%.5f, SL=%.5f, TP=%.5f", 
                                    entryPrice, stopLoss, takeProfit));
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Get entry price based on exhaustion pattern                      |
//| Entry: Buy at (High of exhaustion candle + 0.2 pip)            |
//+------------------------------------------------------------------+
double CBuyTrade::GetEntryPrice(int exhaustionType)
{
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double pipValue = point * 10; // For 5-digit brokers, 1 pip = 10 points
   
   double high[];
   ArraySetAsSeries(high, true);
   
   if(CopyHigh(m_Symbol, PERIOD_M5, 0, 1, high) <= 0)
   {
      return 0;
   }
   
   // Entry = High of exhaustion candle + 0.2 pip
   double entryPrice = high[0] + 0.2 * pipValue;
   
   return entryPrice;
}

