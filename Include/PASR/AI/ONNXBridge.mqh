//+------------------------------------------------------------------+
//| AI/ONNXBridge.mqh                                                |
//| ONNX Runtime bridge for MQL5 — loads .onnx model and runs       |
//| inference via OnnxRun()                                          |
//+------------------------------------------------------------------+
#property strict
#ifndef __ONNX_BRIDGE_MQH__
#define __ONNX_BRIDGE_MQH__

#include "AITypes.mqh"

//+------------------------------------------------------------------+
//| CONNXBridge                                                      |
//| Wraps MQL5 built-in ONNX API (OnnxCreate/OnnxRun/OnnxRelease)   |
//+------------------------------------------------------------------+
class CONNXBridge
{
private:
   long     m_session;      // ONNX session handle
   bool     m_loaded;
   string   m_model_path;
   int      m_input_size;   // expected feature dimension
   int      m_output_size;  // expected output dimension
   string   m_input_name;
   string   m_output_name;
   
public:
   CONNXBridge()
      : m_session(INVALID_HANDLE), m_loaded(false),
        m_model_path(""), m_input_size(AI_FEATURE_DIM), m_output_size(1),
        m_input_name("input"), m_output_name("output")
   {}
   
   ~CONNXBridge() { Unload(); }
   
   //--- Load ONNX model from file
   bool Load(const string path)
   {
      Unload();
      m_model_path = path;
      
      // MQL5 ONNX API
      m_session = OnnxCreate(path, ONNX_DEFAULT);
      if(m_session == INVALID_HANDLE)
      {
         PrintFormat("ONNXBridge: Failed to load '%s' (error=%d)", path, GetLastError());
         return false;
      }
      
      m_loaded = true;
      PrintFormat("ONNXBridge: Loaded '%s'", path);
      return true;
   }
   
   //--- Unload session
   void Unload()
   {
      if(m_loaded && m_session != INVALID_HANDLE)
      {
         OnnxRelease(m_session);
         m_session = INVALID_HANDLE;
      }
      m_loaded = false;
   }
   
   //--- Run inference
   //    features: AI_FEATURE_DIM float input
   //    out:      scalar output
   bool Run(const double &features[], double &out_score)
   {
      out_score = 0.0;
      if(!m_loaded || m_session == INVALID_HANDLE) return false;
      if(ArraySize(features) < m_input_size) return false;
      
      // Convert double[] to float[] for ONNX
      float input_f[AI_FEATURE_DIM];
      for(int i=0; i<m_input_size; i++) input_f[i] = (float)features[i];
      
      float output_f[1];
      
      // OnnxRun signature: OnnxRun(session, in_names, in_data, out_names, out_data)
      if(!OnnxRun(m_session,
                  ONNX_DEFAULT,
                  input_f,
                  output_f))
      {
         PrintFormat("ONNXBridge: OnnxRun failed (error=%d)", GetLastError());
         return false;
      }
      
      out_score = (double)output_f[0];
      return true;
   }
   
   //--- Struct-based run
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
