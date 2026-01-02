//+------------------------------------------------------------------+
//| VWAPMagnetTrade.mqh                                               |
//| Strategy B: VWAP Magnet Trade - Fade extensions away from VWAP   |
//+------------------------------------------------------------------+
#include "Logger.mqh"
#include "MeanCalculator.mqh"

class CVWAPMagnetTrade
{
private:
   string m_Symbol;
   CLogger* m_Logger;
   CMeanCalculator* m_MeanCalculator;
   
   double m_VWAP;
   double m_LastVWAP;
   bool m_VWAPFlipped;
   datetime m_LastCheckTime;
   
   bool IsPriceExtendedFromVWAP(double currentPrice, double vwap);
   bool HasVWAPFlipped();
   
public:
   CVWAPMagnetTrade(string symbol, CLogger* logger, CMeanCalculator* meanCalculator);
   ~CVWAPMagnetTrade();
   
   bool CanEnterVWAPMagnetTrade(bool isLong, double currentPrice, double vwap);
   bool ShouldExitVWAPMagnetTrade(double currentPrice, double vwap);
   void OnNewBar();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CVWAPMagnetTrade::CVWAPMagnetTrade(string symbol, CLogger* logger, CMeanCalculator* meanCalculator)
{
   m_Symbol = symbol;
   m_Logger = logger;
   m_MeanCalculator = meanCalculator;
   m_VWAP = 0;
   m_LastVWAP = 0;
   m_VWAPFlipped = false;
   m_LastCheckTime = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CVWAPMagnetTrade::~CVWAPMagnetTrade()
{
}

//+------------------------------------------------------------------+
//| Called on new bar                                                |
//+------------------------------------------------------------------+
void CVWAPMagnetTrade::OnNewBar()
{
   // Check if VWAP flipped
   if(HasVWAPFlipped())
   {
      m_VWAPFlipped = true;
      (*m_Logger).LogWarning("VWAP flipped - exit VWAP magnet trade");
   }
   
   m_LastCheckTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Check if we can enter VWAP Magnet Trade                          |
//| Strategy: Fade extensions away from VWAP                         |
//+------------------------------------------------------------------+
bool CVWAPMagnetTrade::CanEnterVWAPMagnetTrade(bool isLong, double currentPrice, double vwap)
{
   if(vwap <= 0) return false;
   
   m_VWAP = vwap;
   
   // Check if price is extended away from VWAP
   if(!IsPriceExtendedFromVWAP(currentPrice, vwap))
   {
      return false;
   }
   
   // For long: price should be below VWAP (extended down)
   // For short: price should be above VWAP (extended up)
   if(isLong)
   {
      if(currentPrice >= vwap)
      {
         return false; // Price not extended below VWAP
      }
   }
   else
   {
      if(currentPrice <= vwap)
      {
         return false; // Price not extended above VWAP
      }
   }
   
   (*m_Logger).LogInfo(StringFormat("VWAP Magnet Trade setup: Price=%.5f, VWAP=%.5f, Direction=%s", 
                                    currentPrice, vwap, isLong ? "Long" : "Short"));
   return true;
}

//+------------------------------------------------------------------+
//| Check if price is extended from VWAP                             |
//| Extension = price is > 1.5× ATR away from VWAP                   |
//+------------------------------------------------------------------+
bool CVWAPMagnetTrade::IsPriceExtendedFromVWAP(double currentPrice, double vwap)
{
   // Get ATR for distance calculation
   int atrHandle = iATR(m_Symbol, PERIOD_M5, 14);
   if(atrHandle == INVALID_HANDLE) return false;
   
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0)
   {
      IndicatorRelease(atrHandle);
      return false;
   }
   
   IndicatorRelease(atrHandle);
   
   double distanceFromVWAP = MathAbs(currentPrice - vwap);
   double extensionThreshold = 1.5 * atr[0];
   
   return (distanceFromVWAP > extensionThreshold);
}

//+------------------------------------------------------------------+
//| Check if we should exit VWAP Magnet Trade                        |
//| Exit conditions:                                                 |
//| 1. Price reached VWAP (TP)                                       |
//| 2. VWAP flipped                                                   |
//+------------------------------------------------------------------+
bool CVWAPMagnetTrade::ShouldExitVWAPMagnetTrade(double currentPrice, double vwap)
{
   if(vwap <= 0) return false;
   
   // Check if VWAP flipped
   if(m_VWAPFlipped)
   {
      return true;
   }
   
   // Check if price reached VWAP (within 0.5× ATR)
   int atrHandle = iATR(m_Symbol, PERIOD_M5, 14);
   if(atrHandle == INVALID_HANDLE) return false;
   
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0)
   {
      IndicatorRelease(atrHandle);
      return false;
   }
   
   IndicatorRelease(atrHandle);
   
   double distanceToVWAP = MathAbs(currentPrice - vwap);
   double tpThreshold = 0.5 * atr[0];
   
   if(distanceToVWAP <= tpThreshold)
   {
      (*m_Logger).LogInfo("VWAP Magnet Trade: Target reached (price at VWAP)");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if VWAP flipped (changed direction significantly)          |
//+------------------------------------------------------------------+
bool CVWAPMagnetTrade::HasVWAPFlipped()
{
   if(m_MeanCalculator == NULL) return false;
   
   double currentVWAP = 0;
   currentVWAP = m_MeanCalculator->GetMean();
   
   if(m_LastVWAP > 0 && currentVWAP > 0)
   {
      // Check if VWAP moved significantly in opposite direction
      double vwapChange = currentVWAP - m_LastVWAP;
      double point = SymbolInfoDouble(m_Symbol, SYMBOL_POINT);
      
      // Significant flip = VWAP moved > 10 pips in opposite direction
      if(MathAbs(vwapChange) > 10 * point * 10)
      {
         m_LastVWAP = currentVWAP;
         return true;
      }
   }
   
   m_LastVWAP = currentVWAP;
   return false;
}

