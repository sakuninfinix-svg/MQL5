//+------------------------------------------------------------------+
//| PASR/AI/AIRetrainTrigger.mqh                                      |
//| Auto-learning trigger system for PASR EA                         |
//|                                                                   |
//| Standalone module — does NOT require CAIInference.                |
//| Tracks trade count and writes retrain_trigger.flag when           |
//| threshold reached. Also detects weights file changes.             |
//|                                                                   |
//| Usage in EA:                                                     |
//|   #include <PASR/AI/AIRetrainTrigger.mqh>                        |
//|                                                                   |
//|   CAIRetrainTrigger g_retrain;                                    |
//|                                                                   |
//|   OnInit():                                                       |
//|     g_retrain.Init("PASR_mlp_m0.bin", 200);                      |
//|                                                                   |
//|   OnTimer():                                                      |
//|     g_retrain.Check();                                            |
//|                                                                   |
//|   OnTradeTransaction():                                           |
//|     if(trans.type == TRADE_TRANSACTION_DEAL_ADD)                 |
//|       g_retrain.OnTradeClosed();                                  |
//+------------------------------------------------------------------+
#ifndef __AI_RETRAIN_TRIGGER_MQH__
#define __AI_RETRAIN_TRIGGER_MQH__

class CAIRetrainTrigger
  {
private:
   string   m_weights_file;
   int      m_retrain_threshold;
   int      m_trades_since_retrain;
   int      m_last_history_total;
   datetime m_last_check_time;
   datetime m_weights_file_time;
   bool     m_enabled;
   bool     m_weights_changed;

   void WriteTriggerFlag()
     {
      int handle = FileOpen("retrain_trigger.flag", FILE_WRITE | FILE_TXT);
      if(handle != INVALID_HANDLE)
        {
         FileWrite(handle, StringFormat("trade_count=%d", m_trades_since_retrain));
         FileWrite(handle, StringFormat("timestamp=%s",
                     TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)));
         FileClose(handle);
         PrintFormat("[RetrainTrigger] Trigger flag written (%d trades)",
                     m_trades_since_retrain);
        }
      else
         Print("[RetrainTrigger] ERROR: Could not write trigger flag");
     }

   bool CheckWeightsChanged()
     {
      if(StringLen(m_weights_file) == 0) return false;

      datetime mod_time = (datetime)FileGetInteger(m_weights_file, FILE_MODIFY_DATE, false);
      if(mod_time == 0) return false;

      if(mod_time > m_weights_file_time)
        {
         m_weights_file_time = mod_time;
         return true;
        }
      return false;
     }

   int CountClosedDeals()
     {
      HistorySelect(0, TimeCurrent());
      return HistoryDealsTotal();
     }

public:
   CAIRetrainTrigger()
      : m_weights_file(""), m_retrain_threshold(200),
        m_trades_since_retrain(0), m_last_history_total(0),
        m_last_check_time(0), m_weights_file_time(0),
        m_enabled(true), m_weights_changed(false) {}

   bool Init(string weights_file, int threshold = 200)
     {
      m_weights_file = weights_file;
      m_retrain_threshold = MathMax(threshold, 50);

      m_last_history_total = CountClosedDeals();

      datetime mod_time = (datetime)FileGetInteger(m_weights_file, FILE_MODIFY_DATE, false);
      m_weights_file_time = (mod_time > 0) ? mod_time : TimeCurrent();

      PrintFormat("[RetrainTrigger] Initialized: weights='%s', threshold=%d, "
                  "existing_deals=%d",
                  m_weights_file, m_retrain_threshold, m_last_history_total);
      return true;
     }

   void SetEnabled(bool enabled) { m_enabled = enabled; }
   bool IsEnabled() const { return m_enabled; }
   int  GetTradesSinceRetrain() const { return m_trades_since_retrain; }
   int  GetThreshold() const { return m_retrain_threshold; }
   bool IsWeightsChanged() const { return m_weights_changed; }
   void ClearWeightsChanged() { m_weights_changed = false; }

   void Check()
     {
      if(!m_enabled) return;

      datetime now = TimeCurrent();
      if(now - m_last_check_time < 60) return;
      m_last_check_time = now;

      int current_deals = CountClosedDeals();
      int new_deals = current_deals - m_last_history_total;

      if(new_deals > 0)
        {
         m_trades_since_retrain += new_deals;
         m_last_history_total = current_deals;
        }

      if(CheckWeightsChanged())
        {
         m_weights_changed = true;
         Print("[RetrainTrigger] Weights file changed — kernel should reload");
        }

      if(m_trades_since_retrain >= m_retrain_threshold)
        {
         PrintFormat("[RetrainTrigger] Threshold reached: %d >= %d trades",
                     m_trades_since_retrain, m_retrain_threshold);
         WriteTriggerFlag();
        }
     }

   void OnTradeClosed()
     {
      if(!m_enabled) return;
      m_trades_since_retrain++;

      if(m_trades_since_retrain >= m_retrain_threshold)
        {
         PrintFormat("[RetrainTrigger] Threshold reached on trade close: %d trades",
                     m_trades_since_retrain);
         WriteTriggerFlag();
        }
     }

   void ResetCounter()
     {
      m_trades_since_retrain = 0;
      m_last_history_total = CountClosedDeals();
     }
  };

#endif // __AI_RETRAIN_TRIGGER_MQH__
