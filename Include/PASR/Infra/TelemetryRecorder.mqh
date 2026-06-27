//+------------------------------------------------------------------+
//| Infra/TelemetryRecorder.mqh — v3.01 Optimized                    |
//| High-performance telemetry with auto-optimization mode detection |
//| Saves disk space during strategy optimization runs               |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_TELEMETRY_RECORDER_MQH__
#define __INFRA_TELEMETRY_RECORDER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"
#include "../Core/Globals.mqh"
#include "../Observability/ObservabilityTypes.mqh"

// Optimized buffer sizes
#define PASR_TELEMETRY_MAX_BUFFER       500     // Increased for better batching
#define PASR_TELEMETRY_OPT_BUFFER       50      // Reduced buffer for optimization mode
#define PASR_TELEMETRY_FLUSH_INTERVAL   10      // Seconds between automatic flushes
#define PASR_TELEMETRY_MIN_FLUSH_INT    2       // Minimum flush interval in optimization
#define PASR_TELEMETRY_FILE_MAX_SIZE    5242880 // 5MB max file size before rotation
#define PASR_TELEMETRY_RETENTION_DAYS   7       // Keep logs for 7 days
#define PASR_TELEMETRY_SAMPLE_RATE      10      // Sample rate in optimization (1 of N)

struct STelemetryMetric
  {
   ulong    timestamp_ms;     // Milliseconds for higher precision
   string   metric_name;
   double   value;
   string   unit;
   ulong    stage_id;
   string   symbol;

   void Clear()
     {
      timestamp_ms = 0;
      metric_name = "";
      value = 0.0;
      unit = "";
      stage_id = 0;
      symbol = "";
     }
  };

struct TelemetrySnapshot
  {
   bool   isOpen;
   int    bufferCount;
   int    recordsPending;
   ulong  totalRecords;
   ulong  pipelineTicks;
   ulong  executionLags;
   double avgLatency;
   double maxSlippage;
   string currentFile;
   bool   isOptimizationMode;
   int    sampleRate;

   void Clear()
     {
      isOpen = false;
      bufferCount = 0;
      recordsPending = 0;
      totalRecords = 0;
      pipelineTicks = 0;
      executionLags = 0;
      avgLatency = 0.0;
      maxSlippage = 0.0;
      currentFile = "";
      isOptimizationMode = false;
      sampleRate = 1;
     }
  };

class CTelemetryRecorder : public IManager
  {
private:
   string            m_base_path;
   string            m_current_file;
   int               m_file_handle;
   bool              m_is_open;
   datetime          m_last_flush;
   int               m_records_pending;
   STelemetryMetric  m_buffer[];
   int               m_buffer_count;
   int               m_buffer_max;
   ulong             m_total_records;
   ulong             m_pipeline_ticks;
   ulong             m_execution_lags;
   double            m_avg_latency;
   double            m_max_slippage;
   string            m_last_observability;
   bool              m_optimization_mode;
   bool              m_tester_mode;
   int               m_sample_counter;
   int               m_sample_rate;
   datetime          m_last_rotation;
   long              m_current_file_size;
   
   // Statistics for optimization reporting
   ulong             m_sampled_records;
   ulong             m_skipped_records;

public:
   CTelemetryRecorder()
      : IManager(), m_base_path(""), m_current_file(""), m_file_handle(INVALID_HANDLE),
        m_is_open(false), m_last_flush(0), m_records_pending(0),
        m_buffer_count(0), m_buffer_max(PASR_TELEMETRY_MAX_BUFFER),
        m_total_records(0), m_pipeline_ticks(0),
        m_execution_lags(0), m_avg_latency(0.0), m_max_slippage(0.0),
        m_last_observability(""), m_optimization_mode(false), m_tester_mode(false),
        m_sample_counter(0), m_sample_rate(1), m_last_rotation(0),
        m_current_file_size(0), m_sampled_records(0), m_skipped_records(0)
     {
      ArrayResize(m_buffer, m_buffer_max);
      // struct array: clear each element individually
      for(int i = 0; i < m_buffer_max; i++)
         m_buffer[i].Clear();
     }

   ~CTelemetryRecorder()
     { Deinit(); }

   virtual string HandlerName() const override { return "TelemetryRecorder"; }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_PIPELINE_STAGE_COMPLETE);
      AddEvent(EVENT_ID_ORDER_EXECUTED);
      AddEvent(EVENT_SIGNAL_GENERATED);
     }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      
      // Avoid large telemetry CSV output during Strategy Tester runs.
      m_tester_mode = (MQLInfoInteger(MQL_TESTER) != 0);
      if(m_tester_mode)
        {
         PASRLogInfo("Telemetry", "Tester mode detected - CSV telemetry disabled");
         return true;
        }

      // Detect optimization mode automatically
      m_optimization_mode = (MQLInfoInteger(MQL_OPTIMIZATION) != 0);
      
      if(m_optimization_mode)
        {
         m_buffer_max = PASR_TELEMETRY_OPT_BUFFER;
         ArrayResize(m_buffer, m_buffer_max);
         m_sample_rate = PASR_TELEMETRY_SAMPLE_RATE;
         PASRLogInfo("Telemetry", "Optimization mode detected - sampling 1/" + IntegerToString(m_sample_rate));
        }
      
      m_base_path = "PASR\\Telemetry\\";
      OpenNewFile();
      WriteHeader();
      
      string mode = m_optimization_mode ? "OPTIMIZATION" : "NORMAL";
      PASRLogInfo("Telemetry", "v3.01 Initialized [" + mode + "] - recording to: " + m_base_path);
      return true;
     }

   virtual void Deinit() override
     {
      if(!m_initialized) return;
      if(!m_tester_mode)
        {
         Flush();
         CloseFile();
        }
      
      string summary = StringFormat("Shutdown. Total=%I64u Sampled=%I64u Skipped=%I64u",
                                    m_total_records, m_sampled_records, m_skipped_records);
      if(m_optimization_mode)
         summary += " [Optimization Mode]";
      if(m_tester_mode)
         summary += " [Tester CSV Disabled]";
      
      PASRLogInfo("Telemetry", summary);
      IManager::Deinit();
     }

   void Shutdown() { Deinit(); }
   
   // Query optimization mode
   bool IsOptimizationMode() const { return m_optimization_mode; }
   int GetSampleRate() const { return m_sample_rate; }
   ulong GetSampledRecords() const { return m_sampled_records; }
   ulong GetSkippedRecords() const { return m_skipped_records; }

   virtual void OnEvent(const PASREvent &event) override
     {
      switch(event.id)
        {
         case EVENT_ID_PIPELINE_STAGE_COMPLETE: RecordPipelineLatency(event); break;
         case EVENT_ID_ORDER_EXECUTED:          RecordExecutionMetrics(event); break;
         case EVENT_SIGNAL_GENERATED:           RecordSignalMetrics(event);   break;
         default: break;
        }
     }

   void RecordMetric(const string name, double value,
                     const string unit, ulong stage_id=0, const string symbol="")
     {
      // In optimization mode, apply sampling to reduce disk I/O
      if(m_tester_mode)
        {
         m_skipped_records++;
         m_total_records++;
         return;
        }

      // In optimization mode, apply sampling to reduce disk I/O
      if(m_optimization_mode)
        {
         m_sample_counter++;
         if(m_sample_counter % m_sample_rate != 0)
           {
            m_skipped_records++;
            m_total_records++;
            return; // Skip this record
           }
         m_sampled_records++;
        }
      
      if(m_buffer_count >= m_buffer_max) Flush();
      if(m_buffer_count < 0 || m_buffer_count >= m_buffer_max) return;

      // GetTickCount64() % 1000 provides sub-second ms component
      m_buffer[m_buffer_count].timestamp_ms = (ulong)TimeCurrent() * 1000ULL + (GetTickCount64() % 1000ULL);
      m_buffer[m_buffer_count].metric_name  = name;
      m_buffer[m_buffer_count].value        = value;
      m_buffer[m_buffer_count].unit         = unit;
      m_buffer[m_buffer_count].stage_id     = stage_id;
      m_buffer[m_buffer_count].symbol       = (symbol == "") ? _Symbol : symbol;
      m_buffer_count++;
      m_records_pending++;
      m_total_records++;
      
      // Adaptive flush interval based on mode
      int flush_interval = m_optimization_mode ? PASR_TELEMETRY_MIN_FLUSH_INT : PASR_TELEMETRY_FLUSH_INTERVAL;
      if(TimeCurrent() - m_last_flush > flush_interval) Flush();
     }

   void RecordObservabilityMetric(const string name, double value, const string unit=PASR_UNIT_VALUE)
     {
      RecordMetric(PASR_OBS_PREFIX + name, value, unit, 0, _Symbol);
     }

   void RecordNamedObservabilityMetric(const string metricName, double value, const string unit=PASR_UNIT_VALUE)
     {
      RecordMetric(metricName, value, unit, 0, _Symbol);
     }

   void RecordObservabilityText(const string text)
     {
      m_last_observability = text;
      RecordMetric(PASR_OBS_TEXT_LENGTH, (double)StringLen(text), PASR_UNIT_CHARS, 0, _Symbol);
      if(m_debugMode && text != "")
         PASRLogInfo("Telemetry", "OBS " + text);
     }

   string GetLastObservabilityText() const { return m_last_observability; }

   TelemetrySnapshot GetSnapshot() const
     {
      TelemetrySnapshot s;
      s.Clear();
      s.isOpen = m_is_open;
      s.bufferCount = m_buffer_count;
      s.recordsPending = m_records_pending;
      s.totalRecords = m_total_records;
      s.pipelineTicks = m_pipeline_ticks;
      s.executionLags = m_execution_lags;
      s.avgLatency = m_avg_latency;
      s.maxSlippage = m_max_slippage;
      s.currentFile = m_current_file;
      s.isOptimizationMode = m_optimization_mode;
      s.sampleRate = m_sample_rate;
      return s;
     }

   void PrintDiagnostics() const
     {
      string mode = m_optimization_mode ? "OPT" : "NRM";
      PrintFormat("[TelemetryDiag] mode=%s open=%s buffer=%d pending=%d total=%I64u sampled=%I64u skipped=%I64u ticks=%I64u exec=%I64u avgLat=%.2f maxSlip=%.2f file=%s obs=%s",
                  mode,
                  m_is_open ? "true" : "false",
                  m_buffer_count,
                  m_records_pending,
                  m_total_records,
                  m_sampled_records,
                  m_skipped_records,
                  m_pipeline_ticks,
                  m_execution_lags,
                  m_avg_latency,
                  m_max_slippage,
                  m_current_file,
                  m_last_observability);
     }

   void Flush()
     {
      if(!m_is_open || m_buffer_count == 0) return;
      for(int i = 0; i < m_buffer_count; i++)
         WriteRecord(m_buffer[i]);
      m_buffer_count = 0;
      m_records_pending = 0;
      m_last_flush = TimeCurrent();
      FileFlush(m_file_handle);
     }

private:
   void OpenNewFile()
     {
      CloseFile();
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      
      // Different filename pattern for optimization mode
      string mode_prefix = m_optimization_mode ? "opt_" : "";
      m_current_file = StringFormat("%s%s telemetry_%04d%02d%02d_%d.csv",
                                    m_base_path, mode_prefix, dt.year, dt.mon, dt.day,
                                    (int)TimeCurrent());
      m_file_handle = FileOpen(m_current_file, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON);
      if(m_file_handle == INVALID_HANDLE)
        {
         PASRLogError("Telemetry", "Cannot open file: " + m_current_file + " err=" + IntegerToString(GetLastError()));
         m_is_open = false;
        }
      else 
        {
         m_is_open = true;
         m_current_file_size = 0;
        }
     }

   void CloseFile()
     {
      if(m_is_open && m_file_handle != INVALID_HANDLE)
        {
         FileClose(m_file_handle);
         m_file_handle = INVALID_HANDLE;
         m_is_open = false;
        }
     }

   void WriteHeader()
     {
      if(!m_is_open) return;
      FileWrite(m_file_handle, "Timestamp", "MetricName", "Value", "Unit", "StageID", "Symbol");
      m_current_file_size += 50; // Approximate header size
     }

   void WriteRecord(const STelemetryMetric &metric)
     {
      if(!m_is_open) return;
      
      string line = StringFormat("%s,%s,%.6f,%s,%I64u,%s",
                TimeToString((datetime)(metric.timestamp_ms / 1000), TIME_DATE|TIME_SECONDS),
                metric.metric_name,
                metric.value,
                metric.unit,
                metric.stage_id,
                metric.symbol);
      
      FileWriteString(m_file_handle, line + "\r\n");
      m_current_file_size += StringLen(line) + 2;
      
      // Check for rotation after each write in normal mode
      if(!m_optimization_mode && m_current_file_size > PASR_TELEMETRY_FILE_MAX_SIZE)
         RotateFile();
     }
   
   void RotateFile()
     {
      if(!m_is_open) return;
      
      FileClose(m_file_handle);
      
      // Archive current file with timestamp — StringReplace in-place
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      string archive_name = m_current_file;
      StringReplace(archive_name, ".csv",
                    StringFormat("_arch_%02d%02d.csv", dt.hour, dt.min));
      // FileMove: 4 params (src, src_flags, dst, dst_flags)
      FileMove(m_current_file, FILE_COMMON, archive_name, FILE_COMMON);
      
      // Open new file
      m_current_file = StringFormat("%s telemetry_%04d%02d%02d_%d_rot.csv",
                                    m_base_path, dt.year, dt.mon, dt.day,
                                    (int)TimeCurrent());
      m_file_handle = FileOpen(m_current_file, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON);
      if(m_file_handle != INVALID_HANDLE)
        {
         WriteHeader();
         m_current_file_size = 0;
         m_last_rotation = TimeCurrent();
         PASRLogInfo("Telemetry", "File rotated due to size limit");
        }
      else
        {
         // Reopen original file if rotation fails
         m_file_handle = FileOpen(m_current_file, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON);
         m_is_open = (m_file_handle != INVALID_HANDLE);
        }
     }

   void RecordPipelineLatency(const PASREvent &event)
     {
      double latency_us = event.data1;
      string stage_name = event.tag;
      ulong stage_id = event.ticket;
      RecordMetric(PASR_METRIC_PIPELINE_LATENCY_PREFIX + stage_name, latency_us, PASR_UNIT_MICROSECONDS, stage_id);
      m_pipeline_ticks++;
      if(m_pipeline_ticks > 0)
         m_avg_latency = (m_avg_latency * (m_pipeline_ticks-1) + latency_us) / m_pipeline_ticks;
     }

   void RecordExecutionMetrics(const PASREvent &event)
     {
      double slippage = event.data1;
      string sym = (event.tag == "") ? _Symbol : event.tag;
      RecordMetric(PASR_METRIC_EXECUTION_SLIPPAGE, slippage, PASR_UNIT_POINTS, event.ticket, sym);
      if(slippage > m_max_slippage) m_max_slippage = slippage;
      m_execution_lags++;
     }

   void RecordSignalMetrics(const PASREvent &event)
     {
      double strength = event.data1;
      string sym = (event.tag == "") ? _Symbol : event.tag;
      RecordMetric(PASR_METRIC_SIGNAL_STRENGTH, strength, PASR_UNIT_NORMALIZED, event.ticket, sym);
     }
  };

#endif // __INFRA_TELEMETRY_RECORDER_MQH__
