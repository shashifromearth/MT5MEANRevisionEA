//+------------------------------------------------------------------+
//| Enums.mqh                                                        |
//| Enumeration definitions for Mean Reversion EA                    |
//+------------------------------------------------------------------+

// Mean calculation method
enum MEAN_TYPE
{
   ASIAN_MIDPOINT,    // Asian Range Midpoint (00:00-05:00 UTC)
   SESSION_VWAP       // Session VWAP
};

// Take profit method
enum TP_METHOD
{
   TO_MEAN,           // Return to mean
   SEVENTY_FIVE_PERCENT, // 75% of distance from mean
   MULTIPLE_TARGETS   // Multiple partial TPs (Asian Mid, VWAP, Opposite side)
};

// Exhaustion pattern types
enum EXHAUSTION_TYPE
{
   EXHAUSTION_NONE = 0,
   LONG_WICK,         // Wick >= 50% of candle range
   INSIDE_CANDLE,     // High/Low inside previous candle
   SMALL_BODIES       // Two consecutive small bodies
};

