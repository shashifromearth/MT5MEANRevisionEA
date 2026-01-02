//+------------------------------------------------------------------+
//| MultipleTPManager.mqh                                            |
//| Manages multiple TP targets (Asian Mid, VWAP, Opposite side)    |
//+------------------------------------------------------------------+
#include "Logger.mqh"
#include "MeanCalculator.mqh"

class CMultipleTPManager
{
private:
   string m_Symbol;
   CLogger* m_Logger;
   CMeanCalculator* m_MeanCalculator;
   
   // TP levels
   double m_TP1_AsianMid;
   double m_TP2_VWAP;
   double m_TP3_OppositeSide;
   
   // Position tracking
   ulong m_PositionTicket;
   double m_OriginalVolume;
   double m_RemainingVolume;
   bool m_TP1_Hit;
   bool m_TP2_Hit;
   bool m_TP3_Hit;
   
   bool ClosePartialPosition(double volumePercent);
   
public:
   CMultipleTPManager(string symbol, CLogger* logger, CMeanCalculator* meanCalculator);
   ~CMultipleTPManager();
   
   void SetTPTargets(bool isLong, double entryPrice, double asianHigh, double asianLow, double asianMid, double vwap);
   void MonitorPosition(ulong ticket);
   void Reset();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CMultipleTPManager::CMultipleTPManager(string symbol, CLogger* logger, CMeanCalculator* meanCalculator)
{
   m_Symbol = symbol;
   m_Logger = logger;
   m_MeanCalculator = meanCalculator;
   m_PositionTicket = 0;
   m_OriginalVolume = 0;
   m_RemainingVolume = 0;
   m_TP1_Hit = false;
   m_TP2_Hit = false;
   m_TP3_Hit = false;
   m_TP1_AsianMid = 0;
   m_TP2_VWAP = 0;
   m_TP3_OppositeSide = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CMultipleTPManager::~CMultipleTPManager()
{
}

//+------------------------------------------------------------------+
//| Set multiple TP targets                                          |
//| TP1: Asian Mid (30% of position)                                 |
//| TP2: VWAP (40% of position)                                     |
//| TP3: Opposite side (30% of position)                             |
//+------------------------------------------------------------------+
void CMultipleTPManager::SetTPTargets(bool isLong, double entryPrice, double asianHigh, double asianLow, double asianMid, double vwap)
{
   m_TP1_AsianMid = asianMid;
   m_TP2_VWAP = vwap;
   
   // TP3: Opposite side (if momentum builds)
   if(isLong)
   {
      m_TP3_OppositeSide = asianHigh; // Target opposite side (high)
   }
   else
   {
      m_TP3_OppositeSide = asianLow; // Target opposite side (low)
   }
   
   m_TP1_Hit = false;
   m_TP2_Hit = false;
   m_TP3_Hit = false;
   
   (*m_Logger).LogInfo(StringFormat("Multiple TPs set: TP1=%.5f (Asian Mid), TP2=%.5f (VWAP), TP3=%.5f (Opposite)", 
                                    m_TP1_AsianMid, m_TP2_VWAP, m_TP3_OppositeSide));
}

//+------------------------------------------------------------------+
//| Monitor position and close partial lots at TP levels             |
//+------------------------------------------------------------------+
void CMultipleTPManager::MonitorPosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
   {
      Reset();
      return;
   }
   
   if(m_PositionTicket == 0)
   {
      m_PositionTicket = ticket;
      m_OriginalVolume = PositionGetDouble(POSITION_VOLUME);
      m_RemainingVolume = m_OriginalVolume;
   }
   
   double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(m_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(m_Symbol, SYMBOL_ASK);
   
   bool isLong = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double currentVolume = PositionGetDouble(POSITION_VOLUME);
   
   // Check TP1: Asian Mid (close 30%)
   if(!m_TP1_Hit && m_TP1_AsianMid > 0)
   {
      bool tp1Hit = (isLong && currentPrice >= m_TP1_AsianMid) || 
                    (!isLong && currentPrice <= m_TP1_AsianMid);
      
      if(tp1Hit)
      {
         double closeVolume = m_OriginalVolume * 0.30; // 30%
         if(closeVolume < currentVolume)
         {
            if(ClosePartialPosition(0.30))
            {
               m_TP1_Hit = true;
               m_RemainingVolume -= closeVolume;
               (*m_Logger).LogInfo(StringFormat("TP1 hit (Asian Mid): Closed 30%% at %.5f", m_TP1_AsianMid));
            }
         }
      }
   }
   
   // Check TP2: VWAP (close 40%)
   if(!m_TP2_Hit && m_TP2_VWAP > 0)
   {
      bool tp2Hit = (isLong && currentPrice >= m_TP2_VWAP) || 
                    (!isLong && currentPrice <= m_TP2_VWAP);
      
      if(tp2Hit)
      {
         double closeVolume = m_OriginalVolume * 0.40; // 40%
         if(closeVolume < currentVolume)
         {
            if(ClosePartialPosition(0.40))
            {
               m_TP2_Hit = true;
               m_RemainingVolume -= closeVolume;
               (*m_Logger).LogInfo(StringFormat("TP2 hit (VWAP): Closed 40%% at %.5f", m_TP2_VWAP));
            }
         }
      }
   }
   
   // Check TP3: Opposite side (close 30% if momentum builds)
   if(!m_TP3_Hit && m_TP3_OppositeSide > 0 && (m_TP1_Hit || m_TP2_Hit))
   {
      bool tp3Hit = (isLong && currentPrice >= m_TP3_OppositeSide) || 
                    (!isLong && currentPrice <= m_TP3_OppositeSide);
      
      if(tp3Hit)
      {
         double closeVolume = m_OriginalVolume * 0.30; // 30%
         if(closeVolume <= currentVolume)
         {
            if(ClosePartialPosition(0.30))
            {
               m_TP3_Hit = true;
               m_RemainingVolume -= closeVolume;
               (*m_Logger).LogInfo(StringFormat("TP3 hit (Opposite side): Closed 30%% at %.5f", m_TP3_OppositeSide));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close partial position                                           |
//+------------------------------------------------------------------+
bool CMultipleTPManager::ClosePartialPosition(double volumePercent)
{
   if(!PositionSelectByTicket(m_PositionTicket))
      return false;
   
   double currentVolume = PositionGetDouble(POSITION_VOLUME);
   double closeVolume = m_OriginalVolume * volumePercent;
   
   // Ensure we don't close more than available
   if(closeVolume > currentVolume)
      closeVolume = currentVolume;
   
   // Normalize volume to lot step
   double lotStep = SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_STEP);
   closeVolume = MathFloor(closeVolume / lotStep) * lotStep;
   
   if(closeVolume < SymbolInfoDouble(m_Symbol, SYMBOL_VOLUME_MIN))
      return false;
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = m_Symbol;
   request.volume = closeVolume;
   request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.position = m_PositionTicket;
   request.deviation = 10;
   request.magic = 123456;
   request.comment = StringFormat("Partial TP: %.0f%%", volumePercent * 100);
   
   if(OrderSend(request, result))
   {
      return true;
   }
   else
   {
      (*m_Logger).LogError(StringFormat("Failed to close partial position: %s", result.comment));
      return false;
   }
}

//+------------------------------------------------------------------+
//| Reset TP manager                                                 |
//+------------------------------------------------------------------+
void CMultipleTPManager::Reset()
{
   m_PositionTicket = 0;
   m_OriginalVolume = 0;
   m_RemainingVolume = 0;
   m_TP1_Hit = false;
   m_TP2_Hit = false;
   m_TP3_Hit = false;
   m_TP1_AsianMid = 0;
   m_TP2_VWAP = 0;
   m_TP3_OppositeSide = 0;
}

