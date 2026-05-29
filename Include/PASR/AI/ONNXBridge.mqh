//+------------------------------------------------------------------+
//| AI/ONNXBridge.mqh — v1.01                                        |
//| Optional ONNX Runtime bridge for MQL5.                            |
//| Native ONNX calls are disabled unless PASR_ENABLE_ONNX is defined |
//| by the compile target. This keeps PASR_MODULAR.mq5 compile-ready  |
//| on terminals/builds without ONNX support.                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __ONNX_BRIDGE_MQH__
#define __ONNX_BRIDGE_MQH__

#include "AITypes.mqh"

class CONNXBridge
  {
private:
   long     m_session;
   bool     m_loaded;
   string   m_model_path;
   int      m_input_size;
   int      m_output_size;
   string   m_input_name;
   string   m_output_name;

public:
   CONNXBridge()
      : m_session(INVALID_HANDLE), m_loaded(false),
        m_model_path(""), m_input_size(AI_FEATURE_DIM), m_output_size(1),
        m_input_name("input"), m_output_name("output")
     {}

   ~CONNXBridge() { Unload(); }

   bool Load(const string path)
     {
      Unload();
      m_model_path = path;
#ifdef PASR_ENABLE_ONNX
      m_session = OnnxCreate(path, ONNX_DEFAULT);
      if(m_session == INVALID_HANDLE)
        {
         PrintFormat("ONNXBridge: Failed to load '%s' (error=%d)", path, GetLastError());
         return false;
        }
      m_loaded = true;
      PrintFormat("ONNXBridge: Loaded '%s'", path);
      return true;
#else
      Print("ONNXBridge: PASR_ENABLE_ONNX not defined; ONNX disabled.");
      return false;
#endif
     }

   void Unload()
     {
#ifdef PASR_ENABLE_ONNX
      if(m_loaded && m_session != INVALID_HANDLE)
        {
         OnnxRelease(m_session);
         m_session = INVALID_HANDLE;
        }
#endif
      m_loaded = false;
     }

   bool Run(const double &features[], double &out_score)
     {
      out_score = 0.0;
      if(!m_loaded || m_session == INVALID_HANDLE) return false;
      if(ArraySize(features) < m_input_size) return false;

#ifdef PASR_ENABLE_ONNX
      float input_f[AI_FEATURE_DIM];
      for(int i=0; i<m_input_size; i++) input_f[i] = (float)features[i];
      float output_f[1];
      if(!OnnxRun(m_session, ONNX_DEFAULT, input_f, output_f))
        {
         PrintFormat("ONNXBridge: OnnxRun failed (error=%d)", GetLastError());
         return false;
        }
      out_score = (double)output_f[0];
      return true;
#else
      return false;
#endif
     }

   bool RunFV(const SAIFeatureVector &fv, double &out_score)
     {
      return Run(fv.features, out_score);
     }

   bool   IsLoaded()     const { return m_loaded;      }
   string GetModelPath() const { return m_model_path;  }
   long   GetSession()   const { return m_session;     }
   void   SetInputName(string n)  { m_input_name  = n; }
   void   SetOutputName(string n) { m_output_name = n; }
  };

#endif // __ONNX_BRIDGE_MQH__