//+------------------------------------------------------------------+
//|                                             TelemetryRecorder.mqh |
//|                                  Copyright 2024, PASR Architecture |
//|                                             https://pasr.quant.id |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, PASR Architecture"
#property link      "https://pasr.quant.id"
#property version   "1.00"
#property description "Centralized Telemetry & Metrics Export System (Fase 3)"

#include "../Core/EventBus.mqh"
#include "../Core/IManager.mqh"
#include <File.mqh>

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
   
   void Serialize(CFile &file)
   {
      file.WriteLong(timestamp);
      file.WriteString(metric_name);
      file.WriteDouble(value);
      file.WriteString(unit);
      file.WriteULong(stage_id);
      file.WriteString(symbol);
   }
};

//+------------------------------------------------------------------+
//| CTelemetryRecorder Class                                         |
//+------------------------------------------------------------------+
class CTelemetryRecorder : public IManager
{
private:
   string                     m_base_path;
   string                     m_current_file;
   CFile                      m_csv_file;
   bool                       m_is_open;
   datetime                   m_last_flush;
   int                        m_records_pending;
   
   // Buffer untuk write batching
   STelemetryMetric           m_buffer[];
   int                        m_buffer_size;
   const int                  MAX_BUFFER_SIZE = 100;
   
   // Metrics counters
   ulong                      m_total_records;
   ulong                      m_pipeline_ticks;
   ulong                      m_execution_lags;
   double                     m_avg_latency;
   double                     m_max_slippage;

public:
   CTelemetryRecorder() : m_is_open(false), m_last_flush(0), 
                          m_records_pending(0), m_buffer_size(0),
                          m_total_records(0), m_pipeline_ticks(0),
                          m_execution_lags(0), m_avg_latency(0), m_max_slippage(0)
   {
      m_buffer_size = ArrayResize(m_buffer, MAX_BUFFER_SIZE);
   }
   
   ~CTelemetryRecorder()
   {
      Flush();
      CloseFile();
   }
   
   //--- IManager Interface
   virtual bool Initialize() override
   {
      m_base_path = "\\MQL5\\Files\\PASR\\Telemetry\\";
      if(!DirectoryCreate(m_base_path))
         return false;
      
      OpenNewFile();
      WriteHeader();
      
      EventSubscribe(EVENT_ID_PIPELINE_STAGE_COMPLETE);
      EventSubscribe(EVENT_ID_ORDER_EXECUTED);
      EventSubscribe(EVENT_ID_SIGNAL_GENERATED);
      
      Print("[Telemetry] Initialized - Recording to: ", m_base_path);
      return true;
   }
   
   virtual void Shutdown() override
   {
      Flush();
      CloseFile();
      Print("[Telemetry] Shutdown complete. Total records: ", m_total_records);
   }
   
   virtual void OnEvent(const SEvent &event) override
   {
      switch(event.event_id)
      {
         case EVENT_ID_PIPELINE_STAGE_COMPLETE:
            RecordPipelineLatency(event);
            break;
            
         case EVENT_ID_ORDER_EXECUTED:
            RecordExecutionMetrics(event);
            break;
            
         case EVENT_ID_SIGNAL_GENERATED:
            RecordSignalMetrics(event);
            break;
      }
   }
   
   virtual string GetName() const override { return "TelemetryRecorder"; }
   
   //--- Public API
   void RecordMetric(const string name, double value, const string unit, ulong stage_id=0, const string symbol="")
   {
      if(m_buffer_size >= MAX_BUFFER_SIZE)
         Flush();
      
      STelemetryMetric &metric = m_buffer[m_buffer_size];
      metric.timestamp = TimeCurrent();
      metric.metric_name = name;
      metric.value = value;
      metric.unit = unit;
      metric.stage_id = stage_id;
      metric.symbol = symbol;
      
      m_buffer_size++;
      m_records_pending++;
      m_total_records++;
      
      // Auto-flush setiap 5 detik
      if(TimeCurrent() - m_last_flush > 5)
         Flush();
   }
   
   void Flush()
   {
      if(!m_is_open || m_buffer_size == 0)
         return;
      
      for(int i = 0; i < m_buffer_size; i++)
      {
         WriteRecord(m_buffer[i]);
      }
      
      m_buffer_size = 0;
      m_records_pending = 0;
      m_last_flush = TimeCurrent();
      
      m_csv_file.Flush();
   }
   
private:
   void OpenNewFile()
   {
      CloseFile();
      
      string filename = StringFormat("telemetry_%s_%d.csv", 
                                     TimeToString(TimeCurrent(), TIME_DATE), 
                                     TimeCurrent());
      m_current_file = m_base_path + filename;
      
      if(m_csv_file.Open(m_current_file, FILE_WRITE | FILE_CSV | FILE_ANSI))
      {
         m_is_open = true;
      }
      else
      {
         Print("[Telemetry ERROR] Cannot open file: ", m_current_file);
         m_is_open = false;
      }
   }
   
   void CloseFile()
   {
      if(m_is_open)
      {
         m_csv_file.Close();
         m_is_open = false;
      }
   }
   
   void WriteHeader()
   {
      if(!m_is_open) return;
      
      m_csv_file.WriteString("Timestamp");
      m_csv_file.WriteString(",MetricName");
      m_csv_file.WriteString(",Value");
      m_csv_file.WriteString(",Unit");
      m_csv_file.WriteString(",StageID");
      m_csv_file.WriteString(",Symbol");
      m_csv_file.WriteLine();
   }
   
   void WriteRecord(const STelemetryMetric &metric)
   {
      if(!m_is_open) return;
      
      m_csv_file.WriteString(TimeToString(metric.timestamp, TIME_DATE|TIME_SECONDS));
      m_csv_file.WriteString("," + metric.metric_name);
      m_csv_file.WriteString("," + DoubleToString(metric.value, 6));
      m_csv_file.WriteString("," + metric.unit);
      m_csv_file.WriteString("," + IntegerToString(metric.stage_id));
      m_csv_file.WriteString("," + metric.symbol);
      m_csv_file.WriteLine();
   }
   
   //--- Event Handlers
   void RecordPipelineLatency(const SEvent &event)
   {
      double latency_us = event.data.double_value;
      string stage_name = event.data.string_value;
      
      RecordMetric("Pipeline_Latency_" + stage_name, latency_us, "microseconds", event.stage_id);
      
      m_pipeline_ticks++;
      m_avg_latency = (m_avg_latency * (m_pipeline_ticks-1) + latency_us) / m_pipeline_ticks;
   }
   
   void RecordExecutionMetrics(const SEvent &event)
   {
      double slippage = event.data.double_value;
      string symbol = event.data.string_value;
      
      RecordMetric("Execution_Slippage", slippage, "points", 0, symbol);
      
      if(slippage > m_max_slippage)
         m_max_slippage = slippage;
      
      m_execution_lags++;
   }
   
   void RecordSignalMetrics(const SEvent &event)
   {
      double signal_strength = event.data.double_value;
      string symbol = event.data.string_value;
      
      RecordMetric("Signal_Strength", signal_strength, "normalized", 0, symbol);
   }
};
//+------------------------------------------------------------------+
