//+------------------------------------------------------------------+
//| SellTrade.mqh                                                    |
//| Handles short (sell) trade logic                                 |
//+------------------------------------------------------------------+
#include "Enums.mqh"
#include "TradeExecutor.mqh"
#include "RiskManager.mqh"
#include "MeanCalculator.mqh"
#include "ExhaustionDetector.mqh"
#include "ValidationChecker.mqh"
#include "Logger.mqh"

class CSellTrade
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
   CSellTrade(CTradeExecutor* executor, CRiskManager* riskMgr, CMeanCalculator* meanCalc,
              CExhaustionDetector* exhaustionDet, CValidationChecker* validator,
              string symbol, int atrHandle, CLogger* logger);
   ~CSellTrade();
   
   bool ExecuteTrade(double mean, double distanceFilter, double atr, int exhaustionType);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSellTrade::CSellTrade(CTradeExecutor* executor, CRiskManager* riskMgr, CMeanCalculator* meanCalc,
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
CSellTrade::~CSellTrade()
{
}

//+------------------------------------------------------------------+
//| Execute sell trade                                               |
//+------------------------------------------------------------------+
bool CSellTrade::ExecuteTrade(double mean, double distanceFilter, double atr, int exhaustionType)
{
   // Get current price
   double ask = SymbolInfoDouble(m_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(m_Symbol, SYMBOL_BID);
   
   // Verify short setup: Price > Mean + Distance_Filter
   double distanceFromMean = ask - mean;
   if(distanceFromMean < distanceFilter)
   {
      (*m_Logger).LogWarning("Sell trade rejected: Price not far enough above mean");
      return false;
   }
   
   // Get entry price: Low of exhaustion candle - 0.2 pip
   double entryPrice = GetEntryPrice(exhaustionType);
   if(entryPrice <= 0)
   {
      entryPrice = bid; // Fallback to current bid
   }
   
   // Calculate stop loss
   bool isLong = false;
   double stopLoss = (*m_RiskManager).GetStopLoss(isLong, entryPrice, atr);
   
   // Calculate take profit
   double takeProfit = (*m_RiskManager).GetTakeProfit(isLong, entryPrice, mean, distanceFromMean);
   
   // Validate Risk:Reward ratio (must be 1:0.5 to 1:1)
   if(!(*m_RiskManager).ValidateRiskReward(isLong, entryPrice, stopLoss, takeProfit))
   {
      (*m_Logger).LogWarning("Sell trade rejected: Risk:Reward ratio outside acceptable range (1:0.5 to 1:1)");
      return false;
   }
   
   // Execute trade
   string comment = StringFormat("Short: Mean=%.5f, Dist=%.5f, Exhaustion=%d", 
                                 mean, distanceFromMean, exhaustionType);
   
   bool result = (*m_TradeExecutor).ExecuteSell(entryPrice, stopLoss, takeProfit, comment);
   
   if(result)
   {
      // Set entry bar time for monitoring
      datetime barTime = iTime(m_Symbol, PERIOD_M5, 0);
      (*m_RiskManager).SetEntryBarTime(barTime);
      (*m_Logger).LogInfo(StringFormat("Sell trade executed: Entry=%.5f, SL=%.5f, TP=%.5f", 
                                    entryPrice, stopLoss, takeProfit));
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Get entry price based on exhaustion pattern                      |
//| Entry: Sell at (Low of exhaustion candle - 0.2 pip)            |
//+------------------------------------------------------------------+
double CSellTrade::GetEntryPrice(int exhaustionType)
{
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   double pipValue = point * 10; // For 5-digit brokers, 1 pip = 10 points
   
   double low[];
   ArraySetAsSeries(low, true);
   
   if(CopyLow(m_Symbol, PERIOD_M5, 0, 1, low) <= 0)
   {
      return 0;
   }
   
   // Entry = Low of exhaustion candle - 0.2 pip
   double entryPrice = low[0] - 0.2 * pipValue;
   
   return entryPrice;
}

