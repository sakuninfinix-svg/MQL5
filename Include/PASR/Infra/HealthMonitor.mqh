//+------------------------------------------------------------------+
//| Infra/HealthMonitor.mqh — v2.01                                  |
//| Self-Healing & System Health Monitoring                          |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_HEALTH_MONITOR_MQH__
#define __INFRA_HEALTH_MONITOR_MQH__

#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"
#include "../Core/IManager.mqh"

#define HEALTH_STATUS_OK        0
#define HEALTH_STATUS_WARNING   1
#define HEALTH_STATUS_CRITICAL  2
#define HEALTH_STATUS_DEAD      3

#define MAX_LATENCY_MS          500
#define MAX_MEMORY_MB           256
#define MAX_CONSECUTIVE_ERRORS  5
#define HEARTBEAT_INTERVAL_SEC  5
#define RECOVERY_COOLDOWN_SEC   300

ulong PASR_MemoryUsage()
  {
   return (ulong)TerminalInfoInteger(TERMINAL_MEMORY_USED) * 1024;
  }

class CHealthMonitor : public IManager
  {
private:
   int               m_status;
   int               m_consecutive_errors;
   ulong             m_start_memory;
   datetime          m_last_recovery_time;
   datetime          m_last_heartbeat;
   bool              m_is_recovering;
   bool              m_shutting_down;
   int               m_latency_samples[60];
   int               m_sample_index;

public:
   CHealthMonitor()
      : IManager(), m_status(HEALTH_STATUS_OK), m_consecutive_errors(0),
        m_start_memory(0), m_last_recovery_time(0), m_last_heartbeat(0),
        m_is_recovering(false), m_shutting_down(false), m_sample_index(0)
     {
      ArrayInitialize(m_latency_samples, 0);
     }

   ~CHealthMonitor()
     { Deinit(); }

   virtual string HandlerName() const override { return "HealthMonitor"; }

   virtual void DeclareEvents() override
     { AddEvent(EVENT_ID_HEALTH_CHECK); }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      m_start_memory = PASR_MemoryUsage();
      m_last_heartbeat = TimeCurrent();
      m_shutting_down = false;
      LogHealth("Initialized. Base memory: " + IntegerToString((int)(m_start_memory / 1024)) + " KB", 0);
      return true;
     }

   virtual void Deinit() override
     {
      if(!m_initialized) return;
      m_shutting_down = true;
      LogHealth("Deinit requested.", 0);
      IManager::Deinit();
     }

   bool Initialize(IDataManager *data, CEventBus *bus) { return Init(data, bus); }
   void Shutdown() { Deinit(); }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(ev.id == EVENT_ID_HEALTH_CHECK)
         OnTick_HealthCheck();
     }

   void OnTick_HealthCheck()
     {
      if(m_shutting_down) return;
      if(m_is_recovering) return;

      datetime now     = TimeCurrent();
      datetime elapsed = now - m_last_heartbeat;
      m_last_heartbeat = now;

      if(m_sample_index > 0 && elapsed > HEARTBEAT_INTERVAL_SEC * 3)
        {
         LogHealth("Heartbeat gap: " + IntegerToString((int)elapsed) + "s", 1);
         ReportError(9999);
        }

      ulong cur_mem   = PASR_MemoryUsage();
      ulong mem_delta = (cur_mem > m_start_memory) ? (cur_mem - m_start_memory) : 0;
      if(mem_delta > (ulong)(MAX_MEMORY_MB) * 1024 * 1024)
        {
         LogHealth("Memory delta " + IntegerToString((int)(mem_delta/1024/1024)) + "MB exceeds limit", 2);
         UpdateStatus(HEALTH_STATUS_CRITICAL);
         if(!TriggerSoftRecovery()) TriggerHardReset();
         return;
        }

      if(m_consecutive_errors >= MAX_CONSECUTIVE_ERRORS)
        {
         LogHealth("Consecutive errors=" + IntegerToString(m_consecutive_errors), 2);
         UpdateStatus(HEALTH_STATUS_CRITICAL);
         if(!TriggerSoftRecovery()) TriggerHardReset();
         return;
        }

      if(m_sample_index >= 10)
        {
         long sum  = 0;
         int start = MathMax(0, m_sample_index - 10);
         for(int i = start; i < m_sample_index && i < start + 10; i++)
            sum += m_latency_samples[i % 60];
         int avg = (int)(sum / 10);
         if(avg > MAX_LATENCY_MS)
           {
            LogHealth("Avg latency " + IntegerToString(avg) + "ms > limit", 1);
            UpdateStatus(HEALTH_STATUS_WARNING);
           }
         else if(m_status == HEALTH_STATUS_WARNING && avg < MAX_LATENCY_MS / 2)
            UpdateStatus(HEALTH_STATUS_OK);
        }

      m_sample_index++;
     }

   void ReportError(int error_code)
     {
      m_consecutive_errors++;
      LogHealth("Error " + IntegerToString(error_code) +
                " | total=" + IntegerToString(m_consecutive_errors), 1);
      if(m_consecutive_errors >= MAX_CONSECUTIVE_ERRORS && !m_is_recovering)
         TriggerSoftRecovery();
     }

   void ReportLatency(int latency_ms)
     { m_latency_samples[m_sample_index % 60] = latency_ms; }

   void ResetRecoveryFlag() { m_is_recovering = false; }

   bool TriggerSoftRecovery()
     {
      if(m_is_recovering) return false;
      if(m_shutting_down) return false;
      datetime now = TimeCurrent();
      if(now - m_last_recovery_time < RECOVERY_COOLDOWN_SEC)
        {
         LogHealth("Recovery cooldown active — skip.", 2);
         return false;
        }
      m_is_recovering      = true;
      m_last_recovery_time = now;
      m_consecutive_errors = 0;
      LogHealth(">>> SOFT RECOVERY INITIATED <<<", 3);
      PushSystemEvent(EVENT_ID_SYSTEM_RECOVER, "SoftRecovery");
      UpdateStatus(HEALTH_STATUS_WARNING);
      return true;
     }

   bool TriggerHardReset()
     {
      LogHealth(">>> HARD RESET — TRADING HALTED <<<", 4);
      PushSystemEvent(EVENT_ID_SYSTEM_HALT, "HardResetRequired");
      m_status = HEALTH_STATUS_DEAD;
      return true;
     }

   int  Status() const { return m_status; }
   virtual bool IsHealthy() const override { return (m_initialized && m_status <= HEALTH_STATUS_WARNING); }
   bool IsDead() const { return (m_status == HEALTH_STATUS_DEAD); }

private:
   void UpdateStatus(int new_status)
     {
      if(m_status == new_status) return;
      LogHealth("Status: " + IntegerToString(m_status) + " → " + IntegerToString(new_status), 1);
      m_status = new_status;
     }

   void PushSystemEvent(ENUM_EVENT_ID event_id, const string comment)
     {
      if(m_bus == NULL) return;
      PASREvent ev;
      ev.id       = event_id;
      ev.priority = 1;
      ev.tag      = comment;
      m_bus.Push(ev);
     }

   void LogHealth(const string msg, int level) const
     {
      string prefix = "[INFO]";
      if(level == 1) prefix = "[WARN]";
      else if(level == 2) prefix = "[ERROR]";
      else if(level == 3) prefix = "[RECOVERY]";
      else if(level == 4) prefix = "[CRITICAL]";
      PrintFormat("[HEALTH]%s %s", prefix, msg);
     }
  };

#endif // __INFRA_HEALTH_MONITOR_MQH__
