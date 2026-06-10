//+------------------------------------------------------------------+
//| Infra/AuditLogSystem.mqh — v1.01                                 |
//| High-performance, space-efficient audit logging system           |
//| Optimized for strategy testing with minimal disk footprint       |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_AUDIT_LOG_SYSTEM_MQH__
#define __INFRA_AUDIT_LOG_SYSTEM_MQH__

#include "../Core/IManager.mqh"
#include "../Core/Globals.mqh"
#include "../Core/Events.mqh"
#include "../Data/RegimeTypes.mqh"

// Configuration constants
#define AUDIT_MAX_BUFFER_SIZE     1000    // Circular buffer size (in-memory only)
#define AUDIT_FLUSH_THRESHOLD     100     // Flush to disk after N entries
#define AUDIT_COMPRESS_ENABLED    true    // Enable compression for old entries
#define AUDIT_ROTATION_MAX_SIZE   5242880 // 5MB max file size before rotation
#define AUDIT_RETENTION_DAYS      7       // Keep logs for N days
#define AUDIT_MINIMAL_MODE        false   // Set true during optimization runs

// Log level enum for filtering
enum ENUM_AUDIT_LEVEL
  {
   AUDIT_LEVEL_NONE = 0,      // No logging
   AUDIT_LEVEL_ERROR = 1,     // Errors only
   AUDIT_LEVEL_WARN = 2,      // Warnings + errors
   AUDIT_LEVEL_INFO = 3,      // Info + warnings + errors
   AUDIT_LEVEL_DEBUG = 4,     // Debug + all above
   AUDIT_LEVEL_TRACE = 5      // Full trace (most verbose)
  };

// Compact audit entry structure (optimized for memory)
struct AuditEntry
  {
   ulong    timestamp_ms;     // Milliseconds since epoch (compact)
   uint     sequence_id;      // Sequence number for ordering
   uchar    level;            // ENUM_AUDIT_LEVEL (1 byte)
   uchar    module_id;        // Module identifier (1 byte)
   ushort   event_code;       // Event type code (2 bytes)
   long     value_int;        // Integer value (for metrics)
   double   value_double;     // Double value (for metrics)
   ulong    ticket;           // Trade ticket (if applicable)
   
   void Clear()
     {
      timestamp_ms = 0;
      sequence_id = 0;
      level = 0;
      module_id = 0;
      event_code = 0;
      value_int = 0;
      value_double = 0.0;
      ticket = 0;
     }
  };

// Module ID mapping for compact storage
enum ENUM_AUDIT_MODULE
  {
   MODULE_CORE = 0,
   MODULE_INFRA = 1,
   MODULE_ANALYSIS = 2,
   MODULE_SIGNAL = 3,
   MODULE_AI = 4,
   MODULE_TRADE = 5,
   MODULE_RISK = 6,
   MODULE_ORCHESTRATION = 7
  };

// Event codes per module (compact representation)
enum ENUM_AUDIT_EVENT
  {
   // Core events (0-99)
   EVENT_INIT_START = 1,
   EVENT_INIT_COMPLETE = 2,
   EVENT_DEINIT_START = 3,
   EVENT_TIMER_TICK = 4,
   
   // Infra events (100-199)
   EVENT_DATA_LOAD = 100,
   EVENT_SNAPSHOT_SAVE = 101,
   EVENT_STATE_RESTORE = 102,
   EVENT_CONFIG_UPDATE = 103,
   
   // Analysis events (200-299)
   EVENT_SR_DETECT = 200,
   EVENT_ZONE_UPDATE = 201,
   EVENT_PATTERN_FOUND = 202,
   EVENT_REGIME_CHANGE = 203,
   
   // Signal events (300-399)
   EVENT_SIGNAL_GENERATE = 300,
   EVENT_SIGNAL_FILTER = 301,
   EVENT_SIGNAL_SCORE = 302,
   
   // AI events (400-499)
   EVENT_AI_INFERENCE = 400,
   EVENT_AI_TRAIN_START = 401,
   EVENT_AI_TRAIN_COMPLETE = 402,
   EVENT_AI_CONFIDENCE = 403,
   
   // Trade events (500-599)
   EVENT_ORDER_SEND = 500,
   EVENT_ORDER_FILL = 501,
   EVENT_ORDER_MODIFY = 502,
   EVENT_ORDER_CLOSE = 503,
   EVENT_POSITION_OPEN = 504,
   EVENT_POSITION_CLOSE = 505,
   
   // Risk events (600-699)
   EVENT_RISK_CHECK = 600,
   EVENT_RISK_VIOLATION = 601,
   EVENT_DRAWDOWN_LIMIT = 602,
   
   // Orchestration events (700-799)
   EVENT_PIPELINE_START = 700,
   EVENT_PIPELINE_COMPLETE = 701,
   EVENT_STAGE_EXECUTE = 702
  };

//+------------------------------------------------------------------+
//| CAuditLogSystem - Main audit log manager class                   |
//+------------------------------------------------------------------+
class CAuditLogSystem : public IManager
  {
private:
   // Circular buffer for in-memory storage
   AuditEntry      m_buffer[];
   int             m_buffer_size;
   int             m_buffer_head;
   int             m_buffer_count;
   uint            m_sequence_counter;
   
   // File handling
   int             m_file_handle;
   string          m_current_file;
   datetime        m_last_flush_time;
   int             m_entries_since_flush;
   long            m_current_file_size;
   
   // Configuration
   ENUM_AUDIT_LEVEL m_log_level;
   bool            m_enabled;
   bool            m_minimal_mode;
   bool            m_compression_enabled;
   int             m_rotation_max_size;
   int             m_retention_days;
   
   // Statistics
   ulong           m_total_entries;
   ulong           m_flushed_entries;
   ulong           m_dropped_entries;
   datetime        m_start_time;
   
   // Module name mapping
   string          m_module_names[];
   
   // NOTE: m_initialized is inherited from IManager — do NOT redeclare here

private:
   // Internal helpers
   string GenerateFilename();
   void   RotateFileIfNeeded();
   void   CleanupOldFiles();
   string EntryToCSV(const AuditEntry &entry);
   string EntryToCompact(const AuditEntry &entry);
   void   InitModuleNames();
   uchar  GetModuleID(const string module_name);
   
public:
   // Constructor/Destructor
                     CAuditLogSystem();
                    ~CAuditLogSystem();
   
   // IManager interface — signatures must match IManager exactly
   virtual bool      Init(IDataManager *data, CEventBus *bus) override;
   virtual void      Deinit() override;
   virtual string    HandlerName() const override { return "AuditLogSystem"; }
   virtual bool      IsHealthy() const override { return m_initialized && m_enabled; }
   virtual void      DeclareEvents() override {}
   virtual void      OnEvent(const PASREvent &ev) override {}
   
   // Logging methods
   void              Log(ENUM_AUDIT_LEVEL level, ENUM_AUDIT_MODULE module, 
                         ENUM_AUDIT_EVENT event, const string details = "",
                         long int_val = 0, double dbl_val = 0.0, ulong ticket = 0);
   
   void              LogError(ENUM_AUDIT_MODULE module, ENUM_AUDIT_EVENT event,
                              const string details = "", long int_val = 0);
   void              LogWarn(ENUM_AUDIT_MODULE module, ENUM_AUDIT_EVENT event,
                             const string details = "");
   void              LogInfo(ENUM_AUDIT_MODULE module, ENUM_AUDIT_EVENT event,
                             const string details = "", double dbl_val = 0.0);
   void              LogDebug(ENUM_AUDIT_MODULE module, ENUM_AUDIT_EVENT event,
                              const string details = "");
   void              LogTrade(ulong ticket, ENUM_AUDIT_EVENT event,
                              const string details = "", double dbl_val = 0.0);
   
   // Flush control
   void              Flush();
   void              FlushAndClose();
   
   // Configuration
   void              SetLogLevel(ENUM_AUDIT_LEVEL level) { m_log_level = level; }
   void              SetEnabled(bool enabled) { m_enabled = enabled; }
   void              SetMinimalMode(bool minimal) { m_minimal_mode = minimal; }
   void              SetCompressionEnabled(bool enabled) { m_compression_enabled = enabled; }
   
   // Query methods
   ENUM_AUDIT_LEVEL  GetLogLevel() const { return m_log_level; }
   bool              IsEnabled() const { return m_enabled; }
   bool              IsMinimalMode() const { return m_minimal_mode; }
   ulong             GetTotalEntries() const { return m_total_entries; }
   ulong             GetFlushedEntries() const { return m_flushed_entries; }
   ulong             GetDroppedEntries() const { return m_dropped_entries; }
   
   // Get recent entries from buffer
   int               GetRecentEntries(AuditEntry &out_array[], int max_count);
   
   // Export methods
   bool              ExportToCSV(const string filename, datetime from_time, datetime to_time);
   bool              ExportSummary(const string filename);
  };

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CAuditLogSystem::CAuditLogSystem()
  {
   m_buffer_size = 0;
   m_buffer_head = 0;
   m_buffer_count = 0;
   m_sequence_counter = 0;
   m_file_handle = INVALID_HANDLE;
   m_last_flush_time = 0;
   m_entries_since_flush = 0;
   m_current_file_size = 0;
   m_log_level = AUDIT_LEVEL_INFO;
   m_enabled = true;
   m_minimal_mode = false;
   m_compression_enabled = AUDIT_COMPRESS_ENABLED;
   m_rotation_max_size = AUDIT_ROTATION_MAX_SIZE;
   m_retention_days = AUDIT_RETENTION_DAYS;
   m_total_entries = 0;
   m_flushed_entries = 0;
   m_dropped_entries = 0;
   m_start_time = 0;
   // m_initialized is set by IManager base constructor
   
   ArrayResize(m_buffer, AUDIT_MAX_BUFFER_SIZE);
   // struct array: clear each element individually (ArrayInitialize tidak support struct)
   for(int i = 0; i < AUDIT_MAX_BUFFER_SIZE; i++)
      m_buffer[i].Clear();
   InitModuleNames();
  }

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CAuditLogSystem::~CAuditLogSystem()
  {
   Deinit();
  }

//+------------------------------------------------------------------+
//| Initialize module name mapping                                   |
//+------------------------------------------------------------------+
void CAuditLogSystem::InitModuleNames()
  {
   ArrayResize(m_module_names, 8);
   m_module_names[MODULE_CORE] = "CORE";
   m_module_names[MODULE_INFRA] = "INFRA";
   m_module_names[MODULE_ANALYSIS] = "ANALYSIS";
   m_module_names[MODULE_SIGNAL] = "SIGNAL";
   m_module_names[MODULE_AI] = "AI";
   m_module_names[MODULE_TRADE] = "TRADE";
   m_module_names[MODULE_RISK] = "RISK";
   m_module_names[MODULE_ORCHESTRATION] = "ORCH";
  }

//+------------------------------------------------------------------+
//| Get module ID from name                                          |
//+------------------------------------------------------------------+
uchar CAuditLogSystem::GetModuleID(const string module_name)
  {
   for(int i = 0; i < ArraySize(m_module_names); i++)
     {
      if(StringFind(module_name, m_module_names[i]) >= 0)
         return (uchar)i;
     }
   return MODULE_CORE;
  }

//+------------------------------------------------------------------+
//| Initialize the audit log system                                  |
//+------------------------------------------------------------------+
bool CAuditLogSystem::Init(IDataManager *data, CEventBus *bus)
  {
   if(!IManager::Init(data, bus)) return false;
   if(m_initialized) return true;
   
   m_start_time = TimeCurrent();
   m_sequence_counter = 0;
   m_entries_since_flush = 0;
   
   // Check if we're in optimization mode
   if(MQLInfoInteger(MQL_OPTIMIZATION))
     {
      m_minimal_mode = true;
      m_log_level = AUDIT_LEVEL_WARN;
      PASRLogInfo("AuditLog", "Optimization mode detected - minimal logging enabled");
     }
   
   // In minimal mode, disable file logging entirely
   if(m_minimal_mode)
     {
      m_enabled = false;
      PASRLogInfo("AuditLog", "Minimal mode - file logging disabled");
      m_initialized = true;
      return true;
     }
   
   // Generate filename and open file
   m_current_file = GenerateFilename();
   
   bool new_file = !FileIsExist(m_current_file, FILE_COMMON);
   m_file_handle = FileOpen(m_current_file, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   
   if(m_file_handle == INVALID_HANDLE)
     {
      PASRLogError("AuditLog", "Failed to open log file: " + IntegerToString(GetLastError()));
      m_enabled = false;
      m_initialized = true;
      return false;
     }
   
   // Write header if new file
   if(new_file || FileSize(m_file_handle) == 0)
     {
      string header = "Timestamp,SeqID,Level,Module,Event,ValueInt,ValueDouble,Ticket,Details\r\n";
      FileWriteString(m_file_handle, header);
     }
   
   m_current_file_size = (long)FileSize(m_file_handle);
   FileSeek(m_file_handle, 0, SEEK_END);
   
   m_initialized = true;
   PASRLogInfo("AuditLog", "Audit system initialized - Level: " + EnumToString(m_log_level));
   
   return true;
  }

//+------------------------------------------------------------------+
//| Deinitialize the audit log system                                |
//+------------------------------------------------------------------+
void CAuditLogSystem::Deinit()
  {
   if(!m_initialized) return;
   
   FlushAndClose();
   CleanupOldFiles();
   
   m_initialized = false;
   PASRLogInfo("AuditLog", "Audit system shutdown - Total: " + IntegerToString((long)m_total_entries) + 
               ", Flushed: " + IntegerToString((long)m_flushed_entries));
   IManager::Deinit();
  }

//+------------------------------------------------------------------+
//| Generate log filename with date                                  |
//+------------------------------------------------------------------+
string CAuditLogSystem::GenerateFilename()
  {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   // StringReplace works in-place; do not use return value as string
   string symbol_clean = _Symbol;
   StringReplace(symbol_clean, "/", "_");
   return StringFormat("PASR_Audit_%s_%04d%02d%02d.csv", 
                       symbol_clean, dt.year, dt.mon, dt.day);
  }

//+------------------------------------------------------------------+
//| Rotate file if size exceeds limit                                |
//+------------------------------------------------------------------+
void CAuditLogSystem::RotateFileIfNeeded()
  {
   if(m_current_file_size < m_rotation_max_size) return;
   
   FileClose(m_file_handle);
   
   // Rename current file with timestamp
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   // StringReplace works in-place
   string archive_name = m_current_file;
   StringReplace(archive_name, ".csv",
                 StringFormat("_%02d%02d%02d.csv", dt.hour, dt.min, dt.sec));
   // FileMove: 4 params (src, src_flags, dst, dst_flags)
   FileMove(m_current_file, FILE_COMMON, archive_name, FILE_COMMON);
   
   // Create new file
   m_current_file = GenerateFilename();
   m_file_handle = FileOpen(m_current_file, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   
   if(m_file_handle != INVALID_HANDLE)
     {
      string header = "Timestamp,SeqID,Level,Module,Event,ValueInt,ValueDouble,Ticket,Details\r\n";
      FileWriteString(m_file_handle, header);
      m_current_file_size = (long)FileSize(m_file_handle);
      FileSeek(m_file_handle, 0, SEEK_END);
     }
   
   PASRLogInfo("AuditLog", "Log file rotated");
  }

//+------------------------------------------------------------------+
//| Clean up old log files                                           |
//+------------------------------------------------------------------+
void CAuditLogSystem::CleanupOldFiles()
  {
   if(m_retention_days <= 0) return;
   
   // Note: MQL5 doesn't have direct directory listing, so this is a placeholder
   PASRLogDebug("AuditLog", "Cleanup scheduled for files older than " +
                IntegerToString(m_retention_days) + " days");
  }

//+------------------------------------------------------------------+
//| Main logging method                                              |
//+------------------------------------------------------------------+
void CAuditLogSystem::Log(ENUM_AUDIT_LEVEL level, ENUM_AUDIT_MODULE module, 
                          ENUM_AUDIT_EVENT event, const string details = "",
                          long int_val = 0, double dbl_val = 0.0, ulong ticket = 0)
  {
   if(!m_initialized || !m_enabled) return;
   if(level > m_log_level) return;
   
   // Create entry
   AuditEntry entry;
   entry.Clear();
   // GetTickCount64() % 1000 gives sub-second ms component
   entry.timestamp_ms = (ulong)TimeCurrent() * 1000ULL + (GetTickCount64() % 1000ULL);
   entry.sequence_id = m_sequence_counter++;
   entry.level = (uchar)level;
   entry.module_id = (uchar)module;
   entry.event_code = (ushort)event;
   entry.value_int = int_val;
   entry.value_double = dbl_val;
   entry.ticket = ticket;
   
   m_total_entries++;
   
   // Add to circular buffer
   if(m_buffer_count < m_buffer_size)
     {
      m_buffer[m_buffer_count] = entry;
      m_buffer_count++;
     }
   else
     {
      // Overwrite oldest entry
      m_buffer[m_buffer_head] = entry;
      m_buffer_head = (m_buffer_head + 1) % m_buffer_size;
      m_dropped_entries++;
     }
   
   // Write to file if not in minimal mode
   if(!m_minimal_mode && m_file_handle != INVALID_HANDLE)
     {
      string line = EntryToCSV(entry);
      if(details != "") line += "," + details;
      line += "\r\n";
      
      FileWriteString(m_file_handle, line);
      m_current_file_size += StringLen(line);
      m_entries_since_flush++;
      
      // Flush periodically
      if(m_entries_since_flush >= AUDIT_FLUSH_THRESHOLD)
         Flush();
      
      // Check rotation
      RotateFileIfNeeded();
     }
  }

//+------------------------------------------------------------------+
//| Convert entry to CSV format                                      |
//+------------------------------------------------------------------+
string CAuditLogSystem::EntryToCSV(const AuditEntry &entry)
  {
   MqlDateTime dt;
   TimeToStruct((datetime)(entry.timestamp_ms / 1000), dt);
   
   string timestamp = StringFormat("%04d.%02d.%02d %02d:%02d:%02d.%03d",
                                   dt.year, dt.mon, dt.day,
                                   dt.hour, dt.min, dt.sec,
                                   (int)(entry.timestamp_ms % 1000));
   
   return StringFormat("%s,%u,%u,%u,%u,%I64d,%.8f,%I64u",
                       timestamp,
                       entry.sequence_id,
                       entry.level,
                       entry.module_id,
                       entry.event_code,
                       entry.value_int,
                       entry.value_double,
                       entry.ticket);
  }

//+------------------------------------------------------------------+
//| Convenience logging methods                                      |
//+------------------------------------------------------------------+
void CAuditLogSystem::LogError(ENUM_AUDIT_MODULE module, ENUM_AUDIT_EVENT event,
                               const string details = "", long int_val = 0)
  {
   Log(AUDIT_LEVEL_ERROR, module, event, details, int_val, 0.0, 0);
  }

void CAuditLogSystem::LogWarn(ENUM_AUDIT_MODULE module, ENUM_AUDIT_EVENT event,
                              const string details = "")
  {
   Log(AUDIT_LEVEL_WARN, module, event, details, 0, 0.0, 0);
  }

void CAuditLogSystem::LogInfo(ENUM_AUDIT_MODULE module, ENUM_AUDIT_EVENT event,
                              const string details = "", double dbl_val = 0.0)
  {
   Log(AUDIT_LEVEL_INFO, module, event, details, 0, dbl_val, 0);
  }

void CAuditLogSystem::LogDebug(ENUM_AUDIT_MODULE module, ENUM_AUDIT_EVENT event,
                               const string details = "")
  {
   Log(AUDIT_LEVEL_DEBUG, module, event, details, 0, 0.0, 0);
  }

void CAuditLogSystem::LogTrade(ulong ticket, ENUM_AUDIT_EVENT event,
                               const string details = "", double dbl_val = 0.0)
  {
   Log(AUDIT_LEVEL_INFO, MODULE_TRADE, event, details, 0, dbl_val, ticket);
  }

//+------------------------------------------------------------------+
//| Flush buffer to disk                                             |
//+------------------------------------------------------------------+
void CAuditLogSystem::Flush()
  {
   if(m_file_handle == INVALID_HANDLE) return;
   
   int flushed = m_entries_since_flush;
   FileFlush(m_file_handle);
   m_flushed_entries += flushed;
   m_entries_since_flush = 0;
  }

//+------------------------------------------------------------------+
//| Flush and close file                                             |
//+------------------------------------------------------------------+
void CAuditLogSystem::FlushAndClose()
  {
   if(m_file_handle == INVALID_HANDLE) return;
   
   Flush();
   FileClose(m_file_handle);
   m_file_handle = INVALID_HANDLE;
  }

//+------------------------------------------------------------------+
//| Get recent entries from buffer                                   |
//+------------------------------------------------------------------+
int CAuditLogSystem::GetRecentEntries(AuditEntry &out_array[], int max_count)
  {
   if(m_buffer_count == 0) return 0;
   
   int count = MathMin(max_count, m_buffer_count);
   ArrayResize(out_array, count);
   
   int idx = 0;
   int start = (m_buffer_count < m_buffer_size) ? 0 : m_buffer_head;
   
   for(int i = 0; i < count; i++)
     {
      int pos = (start + i) % m_buffer_size;
      out_array[idx] = m_buffer[pos];
      idx++;
     }
   
   return count;
  }

//+------------------------------------------------------------------+
//| Export entries to CSV file                                       |
//+------------------------------------------------------------------+
bool CAuditLogSystem::ExportToCSV(const string filename, datetime from_time, datetime to_time)
  {
   if(m_buffer_count == 0) return false;
   
   int h = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(h == INVALID_HANDLE) return false;
   
   FileWriteString(h, "Timestamp,SeqID,Level,Module,Event,ValueInt,ValueDouble,Ticket,Details\r\n");
   
   for(int i = 0; i < m_buffer_count; i++)
     {
      datetime entry_time = (datetime)(m_buffer[i].timestamp_ms / 1000);
      if(entry_time >= from_time && entry_time <= to_time)
        {
         string line = EntryToCSV(m_buffer[i]) + "\r\n";
         FileWriteString(h, line);
        }
     }
   
   FileClose(h);
   return true;
  }

//+------------------------------------------------------------------+
//| Export summary statistics                                        |
//+------------------------------------------------------------------+
bool CAuditLogSystem::ExportSummary(const string filename)
  {
   int h = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(h == INVALID_HANDLE) return false;
   
   string summary = "=== PASR Audit Log Summary ===\r\n";
   summary += "Start Time: " + TimeToString(m_start_time) + "\r\n";
   summary += "End Time: " + TimeToString(TimeCurrent()) + "\r\n";
   summary += "Total Entries: " + IntegerToString((long)m_total_entries) + "\r\n";
   summary += "Flushed Entries: " + IntegerToString((long)m_flushed_entries) + "\r\n";
   summary += "Dropped Entries: " + IntegerToString((long)m_dropped_entries) + "\r\n";
   summary += "Log Level: " + EnumToString(m_log_level) + "\r\n";
   summary += "Minimal Mode: " + (m_minimal_mode ? "Yes" : "No") + "\r\n";
   
   FileWriteString(h, summary);
   FileClose(h);
   
   return true;
  }

#endif // __INFRA_AUDIT_LOG_SYSTEM_MQH__
