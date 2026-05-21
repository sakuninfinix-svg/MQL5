//+------------------------------------------------------------------+
//| Signal/ISignalSource.mqh — v1.00                                 |
//| Interface for all signal source plugins.                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_ISIGNAL_SOURCE_MQH__
#define __SIGNAL_ISIGNAL_SOURCE_MQH__

enum ENUM_SIGNAL_DIR { SIGNAL_NONE=0, SIGNAL_BUY=1, SIGNAL_SELL=-1 };

struct SignalResult
  {
   ENUM_SIGNAL_DIR direction;
   double          confidence;  // 0.0-1.0
   string          reason;

   void Clear() { direction=SIGNAL_NONE; confidence=0.0; reason=""; }
  };

class ISignalSource
  {
public:
   virtual string Name()                    = 0;
   virtual bool   Evaluate(SignalResult &o) = 0;
  };

#endif
