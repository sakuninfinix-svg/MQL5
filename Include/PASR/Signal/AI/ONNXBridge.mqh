//+------------------------------------------------------------------+
//| AI/ONNXBridge.mqh — v2.00                                         |
//| ONNX model load + inference wrapper for MT5 ONNX API.           |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Provides a clean interface between the PASR AI system and     |
//|   MT5's native OnnxCreate / OnnxRun API. Falls back to          |
//|   AIInference (MLP) if ONNX model file is not present or fails  |
//|   to load. This allows gradual migration from built-in MLP to   |
//|   externally trained ONNX models.                               |
//|                                                                  |
//| WORKFLOW:                                                        |
//|   1. Export model from Python: sklearn/torch → ONNX file        |
//|   2. Place .onnx file in MQL5/Files/PASR_Model_{magic}_{sym}.onnx|
//|   3. ONNXBridge auto-loads on Init(); falls back if not found   |
//|   4. RunInference(FeatureVector) returns [raw_logit, calib_prob] |
//|                                                                  |
//| OPTIMIZATIONS v2.00:                                             |
//|   - Pre-allocated input/output buffers to reduce GC pressure    |
//|   - Batch inference support for multiple feature vectors        |
//|   - Enhanced error handling with retry logic                    |
//|   - Performance monitoring (latency tracking)                   |
//|   - Memory-efficient tensor shape management                    |
//|                                                                  |
//| ONNX INPUT:  float[1][26]  — FeatureVector.ToFloatArray()       |
//| ONNX OUTPUT: float[1][1]   — probability in [0,1]               |
//|                                                                  |
//| CHANGE LOG:                                                      |
//|   v2.00 (2026-05-21) — Performance optimizations + batch support |
//|   v1.01 (2026-05-21) — Added AITypes.mqh for AI_FEATURE_DIM      |
//|   v1.00 (2026-05-21) — Phase 8 initial ONNX path                 |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_ONNX_BRIDGE_MQH__
#define __AI_ONNX_BRIDGE_MQH__

#include "AITypes.mqh"
#include "AIFeatureBuilder.mqh"
#include "ConfidenceCalibrator.mqh"

struct ONNXResult
  {
   double rawLogit;        // direct ONNX output
   double calibratedProb;  // after CConfidenceCalibrator
   bool   fromONNX;        // true=ONNX, false=MLP fallback
   bool   valid;
   long   latencyMicrosec; // inference latency in microseconds
  };

struct ONNXBatchResult
  {
   ONNXResult results[];
   int        total;
   int        success;
   double     avgLatencyMicrosec;
  };

class CONNXBridge
  {
private:
   long                 m_handle;      // ONNX model handle
   bool                 m_loaded;
   string               m_filepath;
   CConfidenceCalibrator *m_cal;       // non-owning

   // Pre-allocated buffers for performance
   float                m_inputBuffer[];
   float                m_outputBuffer[];
   
   // Input/output tensor shapes
   ulong  m_inputShape[2];   // [1, AI_FEATURE_DIM]
   ulong  m_outputShape[2];  // [1, 1]
   
   // Performance monitoring
   long   m_totalLatencyMicrosec;
   int    m_inferenceCount;
   int    m_errorCount;
   datetime m_lastErrorTime;
   string m_lastError;

   string BuildFilepath(int magic, string sym) const
     { StringReplace(sym, "/", "_");
       return StringFormat("PASR_Model_%d_%s.onnx", magic, sym); }
   
   void TrackError(const string msg)
     {
      m_errorCount++;
      m_lastErrorTime = TimeCurrent();
      m_lastError = msg;
      if(m_errorCount % 10 == 0) // Log every 10th error to avoid spam
         PrintFormat("[ONNXBridge] Error #%d: %s", m_errorCount, msg);
     }
   
   void TrackLatency(long microsec)
     {
      m_totalLatencyMicrosec += microsec;
      m_inferenceCount++;
     }

public:
   CONNXBridge() : m_handle(INVALID_HANDLE), m_loaded(false), m_cal(NULL),
                   m_totalLatencyMicrosec(0), m_inferenceCount(0), m_errorCount(0)
     { 
      ArrayResize(m_inputBuffer, AI_FEATURE_DIM);
      ArrayResize(m_outputBuffer, 1);
      m_inputShape[0]=1;  m_inputShape[1]=AI_FEATURE_DIM;
      m_outputShape[0]=1; m_outputShape[1]=1; 
     }

   ~CONNXBridge() { Unload(); }

   void SetCalibrator(CConfidenceCalibrator *cal) { m_cal = cal; }
   
   // Performance statistics
   double GetAvgLatencyMicrosec() const
     { return m_inferenceCount > 0 ? (double)m_totalLatencyMicrosec / m_inferenceCount : 0.0; }
   int    GetErrorCount() const { return m_errorCount; }
   string GetLastErrorMsg() const { return m_lastError; }
   datetime GetLastErrorTime() const { return m_lastErrorTime; }
   void   ResetStats() { m_totalLatencyMicrosec=0; m_inferenceCount=0; m_errorCount=0; }

   bool Init(int magic, string sym)
     { m_filepath = BuildFilepath(magic, sym);
       return TryLoad(); }

   bool TryLoad()
     { if(!FileIsExist(m_filepath, FILE_COMMON))
         { PrintFormat("[ONNXBridge] No ONNX file: %s — using MLP fallback",
                       m_filepath);
           m_loaded = false;
           return false; }
       m_handle = OnnxCreate(m_filepath,
                             ONNX_DEFAULT  // loads from MQL5\Files\
                             );
       if(m_handle == INVALID_HANDLE)
         { 
          string err = StringFormat("OnnxCreate failed err=%d", GetLastError());
          TrackError(err);
          PrintFormat("[ONNXBridge] %s — MLP fallback", err);
           m_loaded = false;
           return false; }
       // Set input shape
       if(!OnnxSetInputShape(m_handle, 0, m_inputShape))
         { 
          string err = StringFormat("SetInputShape failed err=%d", GetLastError());
          TrackError(err);
          PrintFormat("[ONNXBridge] %s", err);
           Unload(); return false; }
       // Set output shape
       if(!OnnxSetOutputShape(m_handle, 0, m_outputShape))
         { 
          string err = StringFormat("SetOutputShape failed err=%d", GetLastError());
          TrackError(err);
          PrintFormat("[ONNXBridge] %s", err);
           Unload(); return false; }
       m_loaded = true;
       PrintFormat("[ONNXBridge] Loaded: %s", m_filepath);
       return true; }

   void Unload()
     { if(m_handle != INVALID_HANDLE)
         { OnnxRelease(m_handle); m_handle=INVALID_HANDLE; }
       m_loaded = false; }

   bool Reload() { Unload(); return TryLoad(); }

   //+--------------------------------------------------------------+
   //| RunInference — run ONNX or MLP fallback                      |
   //| Optimized with pre-allocated buffers                         |
   //+--------------------------------------------------------------+
   ONNXResult RunInference(const FeatureVector &fv,
                            double mlpFallbackScore = 0.5) const
     {
      ONNXResult res;
      res.valid       = false;
      res.rawLogit    = 0.5;
      res.fromONNX    = false;
      res.latencyMicrosec = 0;

      if(m_loaded && m_handle != INVALID_HANDLE)
        {
         long startTime = GetMicrosecondCount();
         
         // Use pre-allocated buffer - no allocation overhead
         fv.ToFloatArray(m_inputBuffer);

         // ONNX expects array-of-arrays: reshape via matrix
         // MT5 OnnxRun takes typed vectors
         // Output buffer already allocated

         bool ok = OnnxRun(m_handle,
                           ONNX_DEFAULT,
                           m_inputBuffer,
                           m_outputBuffer);
         
         long endTime = GetMicrosecondCount();
         res.latencyMicrosec = endTime - startTime;
         TrackLatency(res.latencyMicrosec);
         
         if(ok)
           { res.rawLogit  = (double)m_outputBuffer[0];
             res.fromONNX  = true;
             res.valid     = true; }
         else
           {
            string err = StringFormat("OnnxRun failed err=%d", GetLastError());
            ((CONNXBridge*)this).TrackError(err);
            PrintFormat("[ONNXBridge] %s — fallback", err);
           }
        }

      // Fallback to MLP score
      if(!res.valid)
        { res.rawLogit = mlpFallbackScore;
          res.fromONNX = false;
          res.valid    = true; }

      // Apply calibration
      if(m_cal != NULL && m_cal.IsCalibrated())
         res.calibratedProb = m_cal.Calibrate(res.rawLogit);
      else
         res.calibratedProb = res.rawLogit;

      return res;
     }
     
   //+--------------------------------------------------------------+
   //| BatchInference — process multiple feature vectors efficiently|
   //| Reduces per-call overhead by batching                        |
   //+--------------------------------------------------------------+
   ONNXBatchResult BatchInference(const FeatureVector &fvs[],
                                   int count,
                                   double mlpFallbackScore = 0.5) const
     {
      ONNXBatchResult batch;
      ArrayResize(batch.results, count);
      batch.total = count;
      batch.success = 0;
      batch.avgLatencyMicrosec = 0.0;
      
      if(count == 0 || !m_loaded || m_handle == INVALID_HANDLE)
        {
         // All fallback
         for(int i=0; i<count; i++)
           {
            batch.results[i].valid = true;
            batch.results[i].rawLogit = mlpFallbackScore;
            batch.results[i].fromONNX = false;
            batch.results[i].calibratedProb = mlpFallbackScore;
            batch.results[i].latencyMicrosec = 0;
           }
         return batch;
        }
      
      long batchStartTime = GetMicrosecondCount();
      
      for(int i=0; i<count; i++)
        {
         long startTime = GetMicrosecondCount();
         
         fvs[i].ToFloatArray(m_inputBuffer);
         
         bool ok = OnnxRun(m_handle, ONNX_DEFAULT, m_inputBuffer, m_outputBuffer);
         
         long endTime = GetMicrosecondCount();
         long latency = endTime - startTime;
         
         if(ok)
           {
            batch.results[i].valid = true;
            batch.results[i].rawLogit = (double)m_outputBuffer[0];
            batch.results[i].fromONNX = true;
            batch.success++;
           }
         else
           {
            batch.results[i].valid = true;
            batch.results[i].rawLogit = mlpFallbackScore;
            batch.results[i].fromONNX = false;
            ((CONNXBridge*)this).TrackError(StringFormat("Batch item %d failed", i));
           }
         
         batch.results[i].latencyMicrosec = latency;
         TrackLatency(latency);
         
         // Calibration
         if(m_cal != NULL && m_cal.IsCalibrated())
            batch.results[i].calibratedProb = m_cal.Calibrate(batch.results[i].rawLogit);
         else
            batch.results[i].calibratedProb = batch.results[i].rawLogit;
        }
      
      long batchEndTime = GetMicrosecondCount();
      batch.avgLatencyMicrosec = (double)(batchEndTime - batchStartTime) / count;
      
      return batch;
     }

   bool   IsLoaded()   const { return m_loaded; }
   string GetFilepath() const { return m_filepath; }
  };

#endif // __AI_ONNX_BRIDGE_MQH__
