//+------------------------------------------------------------------+
//| TrailingStopManager.mqh                                         |
//| Manages trailing stop loss when trade moves in our direction    |
//+------------------------------------------------------------------+
#include "Logger.mqh"

class CTrailingStopManager
{
private:
   string m_Symbol;
   CLogger* m_Logger;
   ulong m_PositionTicket;
   bool m_IsLong;
   double m_EntryPrice;
   double m_InitialStopLoss;
   double m_TrailingStopPips;
   double m_ActivationPips; // Activate trailing after X pips profit
   bool m_TrailingActive;
   double m_HighestProfit;
   double m_BestPrice;
   
public:
   CTrailingStopManager(string symbol, CLogger* logger);
   ~CTrailingStopManager();
   
   void Initialize(ulong ticket, bool isLong, double entryPrice, double initialSL, double trailingPips, double activationPips);
   void Update();
   void Reset();
   bool IsActive() { return m_TrailingActive; }
   double GetCurrentStopLoss();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTrailingStopManager::CTrailingStopManager(string symbol, CLogger* logger)
{
   m_Symbol = symbol;
   m_Logger = logger;
   Reset();
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTrailingStopManager::~CTrailingStopManager()
{
}

//+------------------------------------------------------------------+
//| Initialize trailing stop                                         |
//+------------------------------------------------------------------+
void CTrailingStopManager::Initialize(ulong ticket, bool isLong, double entryPrice, double initialSL, double trailingPips, double activationPips)
{
   m_PositionTicket = ticket;
   m_IsLong = isLong;
   m_EntryPrice = entryPrice;
   m_InitialStopLoss = initialSL;
   m_TrailingStopPips = trailingPips;
   m_ActivationPips = activationPips;
   m_TrailingActive = false;
   m_HighestProfit = 0;
   m_BestPrice = entryPrice;
}

//+------------------------------------------------------------------+
//| Update trailing stop                                             |
//+------------------------------------------------------------------+
void CTrailingStopManager::Update()
{
   if(m_PositionTicket == 0) return;
   
   if(!PositionSelectByTicket(m_PositionTicket))
   {
      Reset();
      return;
   }
   
   double currentPrice = m_IsLong ? 
                        SymbolInfoDouble(m_Symbol, SYMBOL_BID) : 
                        SymbolInfoDouble(m_Symbol, SYMBOL_ASK);
   
   double profit = PositionGetDouble(POSITION_PROFIT);
   double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(m_Symbol, SYMBOL_DIGITS);
   double pipValue = (digits == 3 || digits == 5) ? point * 10 : point;
   
   // Calculate profit in pips
   double profitPips = m_IsLong ? 
                      ((currentPrice - m_EntryPrice) / pipValue) : 
                      ((m_EntryPrice - currentPrice) / pipValue);
   
   // Activate trailing stop after activation threshold
   if(!m_TrailingActive && profitPips >= m_ActivationPips)
   {
      m_TrailingActive = true;
      m_BestPrice = currentPrice;
      m_HighestProfit = profit;
      (*m_Logger).LogInfo(StringFormat("Trailing stop activated: %.1f pips profit", profitPips));
   }
   
   if(!m_TrailingActive) return;
   
   // Update best price (highest profit point)
   if(profit > m_HighestProfit)
   {
      m_HighestProfit = profit;
      m_BestPrice = currentPrice;
   }
   
   // Calculate new stop loss
   double newStopLoss = 0;
   if(m_IsLong)
   {
      newStopLoss = m_BestPrice - (m_TrailingStopPips * pipValue);
      // Don't move stop loss down
      if(newStopLoss > m_InitialStopLoss)
      {
         double currentSL = PositionGetDouble(POSITION_SL);
         if(newStopLoss > currentSL)
         {
            // Modify stop loss
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_SLTP;
            request.position = m_PositionTicket;
            request.symbol = m_Symbol;
            request.sl = newStopLoss;
            request.tp = PositionGetDouble(POSITION_TP);
            
            if(OrderSend(request, result))
            {
               (*m_Logger).LogInfo(StringFormat("Trailing stop updated: SL=%.5f (%.1f pips behind best price)", 
                                                newStopLoss, m_TrailingStopPips));
            }
         }
      }
   }
   else
   {
      newStopLoss = m_BestPrice + (m_TrailingStopPips * pipValue);
      // Don't move stop loss up
      if(newStopLoss < m_InitialStopLoss || m_InitialStopLoss == 0)
      {
         double currentSL = PositionGetDouble(POSITION_SL);
         if(newStopLoss < currentSL || currentSL == 0)
         {
            // Modify stop loss
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_SLTP;
            request.position = m_PositionTicket;
            request.symbol = m_Symbol;
            request.sl = newStopLoss;
            request.tp = PositionGetDouble(POSITION_TP);
            
            if(OrderSend(request, result))
            {
               (*m_Logger).LogInfo(StringFormat("Trailing stop updated: SL=%.5f (%.1f pips behind best price)", 
                                                newStopLoss, m_TrailingStopPips));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Reset trailing stop                                              |
//+------------------------------------------------------------------+
void CTrailingStopManager::Reset()
{
   m_PositionTicket = 0;
   m_IsLong = false;
   m_EntryPrice = 0;
   m_InitialStopLoss = 0;
   m_TrailingStopPips = 0;
   m_ActivationPips = 0;
   m_TrailingActive = false;
   m_HighestProfit = 0;
   m_BestPrice = 0;
}

//+------------------------------------------------------------------+
//| Get current stop loss                                            |
//+------------------------------------------------------------------+
double CTrailingStopManager::GetCurrentStopLoss()
{
   if(m_PositionTicket == 0) return 0;
   if(!PositionSelectByTicket(m_PositionTicket)) return 0;
   return PositionGetDouble(POSITION_SL);
}

