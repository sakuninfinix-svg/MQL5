//+------------------------------------------------------------------+
//| AI/ONNXBridge.mqh — v1.01                                         |
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
//| ONNX INPUT:  float[1][26]  — FeatureVector.ToFloatArray()       |
//| ONNX OUTPUT: float[1][1]   — probability in [0,1]               |
//|                                                                  |
//| CHANGE LOG:                                                      |
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
  };

class CONNXBridge
  {
private:
   long                 m_handle;      // ONNX model handle
   bool                 m_loaded;
   string               m_filepath;
   CConfidenceCalibrator *m_cal;       // non-owning

   // Input/output tensor shapes
   ulong  m_inputShape[2];   // [1, AI_FEATURE_DIM]
   ulong  m_outputShape[2];  // [1, 1]

   string BuildFilepath(int magic, string sym) const
     { StringReplace(sym, "/", "_");
       return StringFormat("PASR_Model_%d_%s.onnx", magic, sym); }

public:
   CONNXBridge() : m_handle(INVALID_HANDLE), m_loaded(false), m_cal(NULL)
     { m_inputShape[0]=1;  m_inputShape[1]=AI_FEATURE_DIM;
       m_outputShape[0]=1; m_outputShape[1]=1; }

   ~CONNXBridge() { Unload(); }

   void SetCalibrator(CConfidenceCalibrator *cal) { m_cal = cal; }

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
         { PrintFormat("[ONNXBridge] OnnxCreate failed err=%d — MLP fallback",
                       GetLastError());
           m_loaded = false;
           return false; }
       // Set input shape
       if(!OnnxSetInputShape(m_handle, 0, m_inputShape))
         { PrintFormat("[ONNXBridge] SetInputShape failed err=%d",
                       GetLastError());
           Unload(); return false; }
       // Set output shape
       if(!OnnxSetOutputShape(m_handle, 0, m_outputShape))
         { PrintFormat("[ONNXBridge] SetOutputShape failed err=%d",
                       GetLastError());
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
   //+--------------------------------------------------------------+
   ONNXResult RunInference(const FeatureVector &fv,
                            double mlpFallbackScore = 0.5) const
     {
      ONNXResult res;
      res.valid       = false;
      res.rawLogit    = 0.5;
      res.fromONNX    = false;

      if(m_loaded && m_handle != INVALID_HANDLE)
        {
         float inputData[AI_FEATURE_DIM];
         fv.ToFloatArray(inputData);

         // ONNX expects array-of-arrays: reshape via matrix
         // MT5 OnnxRun takes typed vectors
         float outputData[1];

         bool ok = OnnxRun(m_handle,
                           ONNX_DEFAULT,
                           inputData,
                           outputData);
         if(ok)
           { res.rawLogit  = (double)outputData[0];
             res.fromONNX  = true;
             res.valid     = true; }
         else
            PrintFormat("[ONNXBridge] OnnxRun failed err=%d — fallback",
                        GetLastError());
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

   bool   IsLoaded()   const { return m_loaded; }
   string GetFilepath() const { return m_filepath; }
  };

#endif // __AI_ONNX_BRIDGE_MQH__
