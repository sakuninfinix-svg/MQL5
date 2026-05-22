//+------------------------------------------------------------------+
//| HealthMonitor.mqh                                                |
//| Copyright 2024, PASR Architecture                                |
//| Self-Healing & System Health Monitoring                          |
//+------------------------------------------------------------------+
#property copyright "2024, PASR Architecture"
#property link      "https://pasr.quant"
#property version   "1.00"

#include "../Core/EventBus.mqh"
#include "../Core/Config/SystemConfig.mqh"

//--- Constants
#define HEALTH_STATUS_OK        0
#define HEALTH_STATUS_WARNING   1
#define HEALTH_STATUS_CRITICAL  2
#define HEALTH_STATUS_DEAD      3

//--- Thresholds
#define MAX_LATENCY_MS          500       // Max acceptable pipeline latency
#define MAX_MEMORY_MB           256       // Max memory usage before warning
#define MAX_CONSECUTIVE_ERRORS  5         // Max errors before trigger recovery
#define HEARTBEAT_INTERVAL_SEC  5         // Check interval

//+------------------------------------------------------------------+
//| Class CHealthMonitor                                             |
//+------------------------------------------------------------------+
class CHealthMonitor
{
private:
   int                m_status;
   datetime           m_last_heartbeat;
   int                m_consecutive_errors;
   ulong              m_start_memory;
   ulong              m_current_memory;
   datetime           m_last_recovery_time;
   bool               m_is_recovering;
   
   // References (Weak pointers to avoid circular dep)
   EventBus          *m_bus;
   
   // Metrics
   int                m_latency_samples[];
   int                m_sample_index;
   
public:
   CHealthMonitor();
   ~CHealthMonitor();
   
   bool Initialize(EventBus *bus);
   void Shutdown();
   
   // Main health check routine
   void OnTick_HealthCheck();
   
   // Manual triggers
   void ReportError(int error_code);
   void ReportLatency(int latency_ms);
   
   // Recovery actions
   bool TriggerSoftRecovery();
   bool TriggerHardReset();
   
   // Getters
   int Status() const { return m_status; }
   bool IsHealthy() const { return m_status <= HEALTH_STATUS_WARNING; }
   
private:
   ulong GetMemoryUsage();
   void UpdateStatus(int new_status);
   void LogHealthEvent(string message, int level);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CHealthMonitor::CHealthMonitor()
{
   m_status = HEALTH_STATUS_OK;
   m_last_heartbeat = TimeCurrent();
   m_consecutive_errors = 0;
   m_start_memory = 0;
   m_current_memory = 0;
   m_last_recovery_time = 0;
   m_is_recovering = false;
   m_bus = NULL;
   m_sample_index = 0;
   ArrayResize(m_latency_samples, 60); // 1 minute history @ 1s
   ArrayInitialize(m_latency_samples, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CHealthMonitor::~CHealthMonitor()
{
   Shutdown();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CHealthMonitor::Initialize(EventBus *bus)
{
   if(bus == NULL) return false;
   m_bus = bus;
   m_start_memory = GetMemoryUsage();
   m_last_heartbeat = TimeCurrent();
   
   LogHealthEvent("HealthMonitor initialized. Base Memory: "+IntegerToString(m_start_memory), 0);
   return true;
}

//+------------------------------------------------------------------+
//| Shutdown                                                         |
//+------------------------------------------------------------------+
void CHealthMonitor::Shutdown()
{
   m_is_recovering = true;
   LogHealthEvent("HealthMonitor shutting down", 0);
}

//+------------------------------------------------------------------+
//| Main Health Check Routine                                        |
//+------------------------------------------------------------------+
void CHealthMonitor::OnTick_HealthCheck()
{
   if(m_is_recovering) return;
   
   datetime now = TimeCurrent();
   
   // 1. Heartbeat Check
   if(now - m_last_heartbeat > HEARTBEAT_INTERVAL_SEC)
   {
      ReportError(9999); // Internal heartbeat timeout
      return;
   }
   
   // 2. Memory Check
   m_current_memory = GetMemoryUsage();
   ulong mem_diff = (m_current_memory > m_start_memory) ? (m_current_memory - m_start_memory) : 0;
   
   if(mem_diff > MAX_MEMORY_MB * 1024 * 1024)
   {
      LogHealthEvent("Memory Leak Detected! Usage: "+IntegerToString(m_current_memory/1024/1024)+"MB", 2);
      UpdateStatus(HEALTH_STATUS_CRITICAL);
      if(!TriggerSoftRecovery())
         TriggerHardReset();
      return;
   }
   
   // 3. Error Rate Check
   if(m_consecutive_errors >= MAX_CONSECUTIVE_ERRORS)
   {
      LogHealthEvent("Consecutive Errors Threshold Reached: "+IntegerToString(m_consecutive_errors), 2);
      UpdateStatus(HEALTH_STATUS_CRITICAL);
      if(!TriggerSoftRecovery())
         TriggerHardReset();
      return;
   }
   
   // 4. Latency Check (Average of last 10 samples)
   if(m_sample_index > 10)
   {
      long sum = 0;
      for(int i = m_sample_index-10; i < m_sample_index; i++) sum += m_latency_samples[i % 60];
      int avg_latency = (int)(sum / 10);
      
      if(avg_latency > MAX_LATENCY_MS)
      {
         LogHealthEvent("High Latency Detected: Avg "+IntegerToString(avg_latency)+"ms", 1);
         UpdateStatus(HEALTH_STATUS_WARNING);
      }
      else if(m_status == HEALTH_STATUS_WARNING && avg_latency < MAX_LATENCY_MS/2)
      {
         UpdateStatus(HEALTH_STATUS_OK); // Recovered
      }
   }
   
   // Reset heartbeat
   m_last_heartbeat = now;
}

//+------------------------------------------------------------------+
//| Report Error                                                     |
//+------------------------------------------------------------------+
void CHealthMonitor::ReportError(int error_code)
{
   m_consecutive_errors++;
   LogHealthEvent("Error Reported: "+IntegerToString(error_code)+" (Total: "+IntegerToString(m_consecutive_errors)+")", 1);
   
   if(m_consecutive_errors >= MAX_CONSECUTIVE_ERRORS)
   {
      TriggerSoftRecovery();
   }
}

//+------------------------------------------------------------------+
//| Report Latency                                                   |
//+------------------------------------------------------------------+
void CHealthMonitor::ReportLatency(int latency_ms)
{
   m_latency_samples[m_sample_index % 60] = latency_ms;
   m_sample_index++;
}

//+------------------------------------------------------------------+
//| Trigger Soft Recovery                                            |
//+------------------------------------------------------------------+
bool CHealthMonitor::TriggerSoftRecovery()
{
   if(m_is_recovering) return false;
   
   datetime now = TimeCurrent();
   if(now - m_last_recovery_time < 300) // Cooldown 5 mins
   {
      LogHealthEvent("Recovery Cooldown Active. Skipping soft recovery.", 2);
      return false;
   }
   
   m_is_recovering = true;
   LogHealthEvent(">>> INITIATING SOFT RECOVERY <<<", 3);
   
   // Send Event to Orchestrator to pause trading and reset managers
   if(m_bus != NULL)
   {
      // Assume EVENT_ID_SYSTEM_RECOVER is defined in EventBus
      m_bus.SendEvent(EVENT_ID_SYSTEM_RECOVER, 0, 0, "SoftRecovery"); 
   }
   
   // Reset counters
   m_consecutive_errors = 0;
   m_last_recovery_time = now;
   m_is_recovering = false;
   
   UpdateStatus(HEALTH_STATUS_OK);
   return true;
}

//+------------------------------------------------------------------+
//| Trigger Hard Reset                                               |
//+------------------------------------------------------------------+
bool CHealthMonitor::TriggerHardReset()
{
   LogHealthEvent(">>> CRITICAL FAILURE: INITIATING HARD RESET <<<", 4);
   
   // In MQL5, we cannot force-restart the EA from within easily without external script
   // Best approach: Save state and request user intervention or stop trading completely
   if(m_bus != NULL)
   {
      m_bus.SendEvent(EVENT_ID_SYSTEM_HALT, 0, 0, "HardResetRequired");
   }
   
   m_status = HEALTH_STATUS_DEAD;
   return true;
}

//+------------------------------------------------------------------+
//| Get Memory Usage                                                 |
//+------------------------------------------------------------------+
ulong CHealthMonitor::GetMemoryUsage()
{
   // Approximation using MQL5 built-in (Note: MQL5 doesn't expose direct process memory easily)
   // We use a proxy based on global objects count or rely on OS if DLL allowed
   // For pure MQL5, we track array sizes manually in a real impl, here we simulate
   return (ulong)MemoryUsage(); 
}

//+------------------------------------------------------------------+
//| Update Status                                                    |
//+------------------------------------------------------------------+
void CHealthMonitor::UpdateStatus(int new_status)
{
   if(m_status != new_status)
   {
      int old = m_status;
      m_status = new_status;
      LogHealthEvent("Health Status Changed: "+IntegerToString(old)+" -> "+IntegerToString(new_status), 1);
   }
}

//+------------------------------------------------------------------+
//| Log Health Event                                                 |
//+------------------------------------------------------------------+
void CHealthMonitor::LogHealthEvent(string message, int level)
{
   string prefix = "";
   if(level == 0) prefix = "[INFO]";
   else if(level == 1) prefix = "[WARN]";
   else if(level == 2) prefix = "[ERROR]";
   else if(level == 3) prefix = "[RECOVERY]";
   else if(level == 4) prefix = "[CRITICAL]";
   
   Print("HEALTH:: ", prefix, " ", message);
   
   // Also send to EventBus for centralized logging
   if(m_bus != NULL)
   {
      m_bus.SendEvent(EVENT_ID_LOG_MESSAGE, level, 0, message);
   }
}

//+------------------------------------------------------------------+
//| Helper: MemoryUsage (Mock for compilation if not built-in)       |
//+------------------------------------------------------------------+
long MemoryUsage()
{
   // Placeholder: In real MQL5, use custom tracking or DLL
   return 0; 
}
