//+------------------------------------------------------------------+
//| Infra/HealthMonitor.mqh — v2.00 (Sprint 7 — State Ownership)    |
//| Self-Healing & System Health Monitoring                          |
//|                                                                  |
//| STATE OWNERSHIP (Sprint 7 contract):                             |
//|   OWNS  : m_status, m_consecutive_errors, m_latency_samples      |
//|            m_last_recovery_time                                  |
//|   READS : CEventBus (via Push only, no SendEvent)                |
//|   WRITES: EVENT_ID_SYSTEM_RECOVER, EVENT_ID_SYSTEM_HALT via bus  |
//|                                                                  |
//| CHANGELOG:                                                       |
//|   v2.00 (2026-05-23) Sprint 7 — 6 bug fixes:                    |
//|     - BUG-H1: EventBus* → CEventBus* (type mismatch fixed)      |
//|     - BUG-H2: SendEvent() → Push() (method tidak ada di CEventBus)|
//|     - BUG-H3: MemoryUsage() renamed → PASR_MemoryUsage()        |
//|     - BUG-H4: TriggerSoftRecovery() flag tidak di-reset internal |
//|               → flag hanya di-reset via ResetRecoveryFlag()      |
//|     - BUG-H5: m_is_recovering pisah jadi m_shutting_down +      |
//|               m_is_recovering (dual-purpose flag dihapus)        |
//|     - BUG-H6: Heartbeat false alarm startup fixed —             |
//|               m_last_heartbeat di-reset di AWAL OnTick, bukan akhir|
//|   v1.00 — Initial implementation                                 |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_HEALTH_MONITOR_MQH__
#define __INFRA_HEALTH_MONITOR_MQH__

#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"
#include "../Core/IManager.mqh"

//--- Health status codes
#define HEALTH_STATUS_OK        0
#define HEALTH_STATUS_WARNING   1
#define HEALTH_STATUS_CRITICAL  2
#define HEALTH_STATUS_DEAD      3

//--- Thresholds
#define MAX_LATENCY_MS          500
#define MAX_MEMORY_MB           256
#define MAX_CONSECUTIVE_ERRORS  5
#define HEARTBEAT_INTERVAL_SEC  5
#define RECOVERY_COOLDOWN_SEC   300

//+------------------------------------------------------------------+
//| BUG-H3 FIX: Renamed from MemoryUsage() to avoid clash with      |
//| any MQL5 built-in. Returns bytes used by terminal process.       |
//+------------------------------------------------------------------+
ulong PASR_MemoryUsage()
  {
   return (ulong)TerminalInfoInteger(TERMINAL_MEMORY_USED) * 1024;
  }

//+------------------------------------------------------------------+
//| CHealthMonitor — IManager-derived (Sprint 7)                     |
//+------------------------------------------------------------------+
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
   CEventBus        *m_bus;

public:
                     CHealthMonitor();
                    ~CHealthMonitor();

   virtual bool      Initialize(CEventBus *bus) override;
   virtual void      Shutdown() override;
   virtual void      OnEvent(const PASREvent &ev) override { }
   virtual string    Name() const override { return "CHealthMonitor"; }

   void              OnTick_HealthCheck();
   void              ReportError(int error_code);
   void              ReportLatency(int latency_ms);
   void              ResetRecoveryFlag() { m_is_recovering = false; }
   bool              TriggerSoftRecovery();
   bool              TriggerHardReset();

   int               Status()    const { return m_status; }
   bool              IsHealthy() const { return (m_status <= HEALTH_STATUS_WARNING); }
   bool              IsDead()    const { return (m_status == HEALTH_STATUS_DEAD); }

private:
   void              UpdateStatus(int new_status);
   void              LogHealth(const string msg, int level) const;
   void              PushSystemEvent(int event_id, const string comment);
  };

CHealthMonitor::CHealthMonitor()
  : m_status(HEALTH_STATUS_OK),
    m_consecutive_errors(0),
    m_start_memory(0),
    m_last_recovery_time(0),
    m_last_heartbeat(0),
    m_is_recovering(false),
    m_shutting_down(false),
    m_sample_index(0),
    m_bus(NULL)
  {
   ArrayInitialize(m_latency_samples, 0);
  }

CHealthMonitor::~CHealthMonitor()
  {
   if(!m_shutting_down) Shutdown();
  }

bool CHealthMonitor::Initialize(CEventBus *bus)
  {
   if(CheckPointer(bus) == POINTER_INVALID)
     {
      Print("[HealthMonitor][ERROR] NULL bus passed to Initialize()");
      return false;
     }
   m_bus          = bus;
   m_start_memory = PASR_MemoryUsage();
   m_last_heartbeat = TimeCurrent();
   LogHealth("Initialized. Base memory: " +
             IntegerToString((int)(m_start_memory / 1024)) + " KB", 0);
   return true;
  }

void CHealthMonitor::Shutdown()
  {
   m_shutting_down = true;
   LogHealth("Shutdown requested.", 0);
  }

void CHealthMonitor::OnTick_HealthCheck()
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

void CHealthMonitor::ReportError(int error_code)
  {
   m_consecutive_errors++;
   LogHealth("Error " + IntegerToString(error_code) +
             " | total=" + IntegerToString(m_consecutive_errors), 1);
   if(m_consecutive_errors >= MAX_CONSECUTIVE_ERRORS && !m_is_recovering)
      TriggerSoftRecovery();
  }

void CHealthMonitor::ReportLatency(int latency_ms)
  {
   m_latency_samples[m_sample_index % 60] = latency_ms;
  }

bool CHealthMonitor::TriggerSoftRecovery()
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

bool CHealthMonitor::TriggerHardReset()
  {
   LogHealth(">>> HARD RESET — TRADING HALTED <<<", 4);
   PushSystemEvent(EVENT_ID_SYSTEM_HALT, "HardResetRequired");
   m_status = HEALTH_STATUS_DEAD;
   return true;
  }

void CHealthMonitor::UpdateStatus(int new_status)
  {
   if(m_status == new_status) return;
   LogHealth("Status: " + IntegerToString(m_status) +
             " → " + IntegerToString(new_status), 1);
   m_status = new_status;
  }

void CHealthMonitor::PushSystemEvent(int event_id, const string comment)
  {
   if(CheckPointer(m_bus) == POINTER_INVALID) return;
   PASREvent ev;
   ev.id       = event_id;
   ev.priority = 255;
   ev.comment  = comment;
   m_bus.Push(ev);
  }

void CHealthMonitor::LogHealth(const string msg, int level) const
  {
   string prefix = "[INFO]";
   if(level == 1) prefix = "[WARN]";
   else if(level == 2) prefix = "[ERROR]";
   else if(level == 3) prefix = "[RECOVERY]";
   else if(level == 4) prefix = "[CRITICAL]";
   PrintFormat("[HEALTH]%s %s", prefix, msg);
  }

#endif // __INFRA_HEALTH_MONITOR_MQH__
