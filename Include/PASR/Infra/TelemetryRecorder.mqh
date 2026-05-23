//+------------------------------------------------------------------+
//|                                             TelemetryRecorder.mqh |
//|                                  Copyright 2024, PASR Architecture |
//|                                             https://pasr.quant.id |
//+------------------------------------------------------------------+
//| v2.00 (2026-05-24) — Sprint 20                                    |
//|   TEL-001: Initialize() → Init(IDataManager*, CEventBus*) override|
//|   TEL-002: EventSubscribe() → m_bus->Subscribe() via IManager     |
//|   TEL-003: CFile object methods → FileWrite*() built-in functions  |
//|   TEL-004: m_buffer_size init to 0, not MAX_BUFFER_SIZE           |
//+------------------------------------------------------------------+
#property strict
#ifndef __INFRA_TELEMETRY_RECORDER_MQH__
#define __INFRA_TELEMETRY_RECORDER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/EventBus.mqh"
#include "../Core/Events.mqh"
#include "../Core/Globals.mqh"

//+------------------------------------------------------------------+
//| Telemetry Metrics Structure                                      |
//+------------------------------------------------------------------+
struct STelemetryMetric
{
   datetime         timestamp;
   string           metric_name;
   double           value;
   string           unit;
   ulong            stage_id;
   string           symbol;
};

//+------------------------------------------------------------------+
//| CTelemetryRecorder — v2.00                                       |
//+------------------------------------------------------------------+
class CTelemetryRecorder : public IManager
{
private:
   string            m_base_path;
   string            m_current_file;
   int               m_file_handle;        // TEL-003: int handle, not CFile object
   bool              m_is_open;
   datetime          m_last_flush;
   int               m_records_pending;

   // TEL-004: buffer — m_buffer_count starts at 0 (items filled), not capacity
   static const int  MAX_BUFFER      = 100;
   STelemetryMetric  m_buffer[100];
   int               m_buffer_count;       // 0..MAX_BUFFER-1 items currently stored

   // Metrics counters
   ulong             m_total_records;
   ulong             m_pipeline_ticks;
   ulong             m_execution_lags;
   double            m_avg_latency;
   double            m_max_slippage;

public:
   CTelemetryRecorder()
      : m_is_open(false), m_last_flush(0), m_records_pending(0),
        m_buffer_count(0),                 // TEL-004 FIX: start empty
        m_total_records(0), m_pipeline_ticks(0),
        m_execution_lags(0), m_avg_latency(0.0), m_max_slippage(0.0),
        m_file_handle(INVALID_HANDLE)      // TEL-003 FIX: int handle
   {}

   ~CTelemetryRecorder()
   {
      Flush();
      CloseFile();
   }

   //--- IManager Interface — TEL-001 FIX: correct override signature
   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!IManager::Init(data, bus)) return false;

      m_base_path = "PASR\\Telemetry\\";

      OpenNewFile();
      WriteHeader();

      // TEL-002 FIX: subscribe via EventBus, not phantom EventSubscribe()
      if(m_bus != NULL)
      {
         m_bus.Subscribe(this, EVENT_ID_PIPELINE_STAGE_COMPLETE);
         m_bus.Subscribe(this, EVENT_ID_ORDER_EXECUTED);
         m_bus.Subscribe(this, EVENT_ID_SIGNAL_GENERATED);
      }

      PASRLogInfo("[Telemetry] v2.00 Initialized — recording to: " + m_base_path);
      return true;
   }

   virtual void Shutdown() override
   {
      Flush();
      CloseFile();
      PASRLogInfo("[Telemetry] Shutdown. Total records: " + IntegerToString((long)m_total_records));
   }

   virtual void OnEvent(const PASREvent &event) override
   {
      switch(event.id)
      {
         case EVENT_ID_PIPELINE_STAGE_COMPLETE: RecordPipelineLatency(event); break;
         case EVENT_ID_ORDER_EXECUTED:          RecordExecutionMetrics(event); break;
         case EVENT_ID_SIGNAL_GENERATED:        RecordSignalMetrics(event);   break;
      }
   }

   virtual string GetName() const override { return "TelemetryRecorder"; }

   //--- Public API
   void RecordMetric(const string name, double value,
                     const string unit, ulong stage_id=0, const string symbol="")
   {
      // TEL-004 FIX: flush when buffer FULL (count == MAX), not always
      if(m_buffer_count >= MAX_BUFFER)
         Flush();

      STelemetryMetric &m = m_buffer[m_buffer_count];
      m.timestamp   = TimeCurrent();
      m.metric_name = name;
      m.value       = value;
      m.unit        = unit;
      m.stage_id    = stage_id;
      m.symbol      = (symbol == "") ? _Symbol : symbol;

      m_buffer_count++;
      m_records_pending++;
      m_total_records++;

      // Auto-flush every 5 seconds
      if(TimeCurrent() - m_last_flush > 5)
         Flush();
   }

   void Flush()
   {
      if(!m_is_open || m_buffer_count == 0) return;

      for(int i = 0; i < m_buffer_count; i++)
         WriteRecord(m_buffer[i]);

      m_buffer_count    = 0;            // TEL-004 FIX: reset item count
      m_records_pending = 0;
      m_last_flush      = TimeCurrent();

      FileFlush(m_file_handle);         // TEL-003 FIX: built-in FileFlush
   }

private:
   void OpenNewFile()
   {
      CloseFile();

      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      m_current_file = StringFormat("%stelemetry_%04d%02d%02d_%d.csv",
                                    m_base_path, dt.year, dt.mon, dt.day,
                                    (int)TimeCurrent());

      // TEL-003 FIX: FileOpen returns int handle
      m_file_handle = FileOpen(m_current_file, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON);
      if(m_file_handle == INVALID_HANDLE)
      {
         PASRLogError("[Telemetry] Cannot open file: " + m_current_file
                      + " err=" + IntegerToString(GetLastError()));
         m_is_open = false;
      }
      else
         m_is_open = true;
   }

   void CloseFile()
   {
      if(m_is_open && m_file_handle != INVALID_HANDLE)
      {
         FileClose(m_file_handle);      // TEL-003 FIX
         m_file_handle = INVALID_HANDLE;
         m_is_open     = false;
      }
   }

   void WriteHeader()
   {
      if(!m_is_open) return;
      // TEL-003 FIX: FileWrite with comma-separated CSV
      FileWrite(m_file_handle, "Timestamp", "MetricName", "Value", "Unit", "StageID", "Symbol");
   }

   void WriteRecord(const STelemetryMetric &m)
   {
      if(!m_is_open) return;
      // TEL-003 FIX: FileWrite (CSV mode) handles delimiter automatically
      FileWrite(m_file_handle,
                TimeToString(m.timestamp, TIME_DATE|TIME_SECONDS),
                m.metric_name,
                DoubleToString(m.value, 6),
                m.unit,
                IntegerToString((long)m.stage_id),
                m.symbol);
   }

   void RecordPipelineLatency(const PASREvent &event)
   {
      double latency_us = event.double_value;
      string stage_name = event.tag;
      RecordMetric("Pipeline_Latency_" + stage_name, latency_us, "microseconds", event.stage_id);
      m_pipeline_ticks++;
      if(m_pipeline_ticks > 0)
         m_avg_latency = (m_avg_latency * (m_pipeline_ticks-1) + latency_us) / m_pipeline_ticks;
   }

   void RecordExecutionMetrics(const PASREvent &event)
   {
      double slippage = event.double_value;
      string sym      = event.tag;
      RecordMetric("Execution_Slippage", slippage, "points", 0, sym);
      if(slippage > m_max_slippage) m_max_slippage = slippage;
      m_execution_lags++;
   }

   void RecordSignalMetrics(const PASREvent &event)
   {
      double strength = event.double_value;
      string sym      = event.tag;
      RecordMetric("Signal_Strength", strength, "normalized", 0, sym);
   }
};

#endif // __INFRA_TELEMETRY_RECORDER_MQH__
//+------------------------------------------------------------------+
