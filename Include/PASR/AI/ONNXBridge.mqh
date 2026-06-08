//+------------------------------------------------------------------+
//| AI/ONNXBridge.mqh — v2.00                                        |
//| Optional ONNX Runtime bridge for MQL5 flat + sequence tensors.   |
//| Native ONNX calls are disabled unless PASR_ENABLE_ONNX is defined|
//| by the compile target.                                            |
//+------------------------------------------------------------------+
#property strict
#ifndef __ONNX_BRIDGE_MQH__
#define __ONNX_BRIDGE_MQH__

#include "AITypes.mqh"

#define ONNX_BRIDGE_MAX_OUTPUTS 4

enum ENUM_ONNX_INPUT_MODE
  {
   ONNX_INPUT_NONE      = 0,
   ONNX_INPUT_FLAT      = 1,
   ONNX_INPUT_SEQUENCE  = 2
  };

class CONNXBridge
  {
private:
   long                 m_session;
   bool                 m_loaded;
   string               m_model_path;
   ENUM_ONNX_INPUT_MODE m_input_mode;
   int                  m_input_size;
   int                  m_seq_len;
   int                  m_feat_dim;
   int                  m_output_size;
   string               m_input_name;
   string               m_output_name;

   bool SetSequenceInputShape()
     {
#ifdef PASR_ENABLE_ONNX
      if(m_session == INVALID_HANDLE || m_input_mode != ONNX_INPUT_SEQUENCE)
         return false;
      long shape[3];
      shape[0] = 1;
      shape[1] = m_seq_len;
      shape[2] = m_feat_dim;
      if(!OnnxSetInputShape(m_session, 0, shape))
        {
         PrintFormat("ONNXBridge: OnnxSetInputShape failed (error=%d)", GetLastError());
         return false;
        }
      return true;
#else
      return false;
#endif
     }

public:
   CONNXBridge()
      : m_session(INVALID_HANDLE), m_loaded(false),
        m_model_path(""), m_input_mode(ONNX_INPUT_NONE),
        m_input_size(AI_FEATURE_DIM), m_seq_len(0), m_feat_dim(0),
        m_output_size(1), m_input_name("input"), m_output_name("output")
     {}

   ~CONNXBridge() { Unload(); }

   bool LoadFlat(const string path, const int input_size, const int output_size = 1)
     {
      Unload();
      m_model_path = path;
      m_input_mode = ONNX_INPUT_FLAT;
      m_input_size = MathMax(1, input_size);
      m_seq_len = 0;
      m_feat_dim = 0;
      m_output_size = MathMax(1, MathMin(ONNX_BRIDGE_MAX_OUTPUTS, output_size));

#ifdef PASR_ENABLE_ONNX
      m_session = OnnxCreate(path, ONNX_DEFAULT);
      if(m_session == INVALID_HANDLE)
        {
         PrintFormat("ONNXBridge: Failed to load flat model '%s' (error=%d)", path, GetLastError());
         return false;
        }
      m_loaded = true;
      PrintFormat("ONNXBridge: Loaded flat model '%s' in=%d out=%d", path, m_input_size, m_output_size);
      return true;
#else
      Print("ONNXBridge: PASR_ENABLE_ONNX not defined; ONNX disabled.");
      return false;
#endif
     }

   bool LoadSequence(const string path,
                     const int seq_len,
                     const int feat_dim,
                     const int output_size = 2)
     {
      Unload();
      m_model_path = path;
      m_input_mode = ONNX_INPUT_SEQUENCE;
      m_seq_len = MathMax(1, seq_len);
      m_feat_dim = MathMax(1, feat_dim);
      m_input_size = m_seq_len * m_feat_dim;
      m_output_size = MathMax(1, MathMin(ONNX_BRIDGE_MAX_OUTPUTS, output_size));

#ifdef PASR_ENABLE_ONNX
      m_session = OnnxCreate(path, ONNX_DEFAULT);
      if(m_session == INVALID_HANDLE)
        {
         PrintFormat("ONNXBridge: Failed to load sequence model '%s' (error=%d)", path, GetLastError());
         return false;
        }
      if(!SetSequenceInputShape())
        {
         Unload();
         return false;
        }
      m_loaded = true;
      PrintFormat("ONNXBridge: Loaded sequence model '%s' shape=[1,%d,%d] out=%d",
                  path, m_seq_len, m_feat_dim, m_output_size);
      return true;
#else
      Print("ONNXBridge: PASR_ENABLE_ONNX not defined; ONNX disabled.");
      return false;
#endif
     }

   bool Load(const string path)
     {
      return LoadFlat(path, AI_FEATURE_DIM, 1);
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
      m_input_mode = ONNX_INPUT_NONE;
     }

   bool Run(const double &features[], double &out_score)
     {
      out_score = 0.0;
      if(!m_loaded || m_session == INVALID_HANDLE || m_input_mode != ONNX_INPUT_FLAT)
         return false;
      if(ArraySize(features) < m_input_size)
         return false;

#ifdef PASR_ENABLE_ONNX
      float input_f[];
      ArrayResize(input_f, m_input_size);
      for(int i = 0; i < m_input_size; i++)
         input_f[i] = (float)features[i];

      float output_f[];
      ArrayResize(output_f, m_output_size);
      if(!OnnxRun(m_session, ONNX_DEFAULT, input_f, output_f))
        {
         PrintFormat("ONNXBridge: OnnxRun flat failed (error=%d)", GetLastError());
         return false;
        }
      out_score = (double)output_f[0];
      return true;
#else
      return false;
#endif
     }

   bool RunSequence(const float &input[],
                    const int seq_len,
                    const int feat_dim,
                    double &outputs[],
                    int &out_count)
     {
      out_count = 0;
      ArrayResize(outputs, 0);
      if(!m_loaded || m_session == INVALID_HANDLE || m_input_mode != ONNX_INPUT_SEQUENCE)
         return false;
      if(seq_len != m_seq_len || feat_dim != m_feat_dim)
         return false;

      const int expected = seq_len * feat_dim;
      if(ArraySize(input) < expected)
         return false;

#ifdef PASR_ENABLE_ONNX
      if(!SetSequenceInputShape())
         return false;

      float input_f[];
      ArrayResize(input_f, expected);
      for(int i = 0; i < expected; i++)
         input_f[i] = input[i];

      float output_f[];
      ArrayResize(output_f, m_output_size);
      if(!OnnxRun(m_session, ONNX_DEFAULT, input_f, output_f))
        {
         PrintFormat("ONNXBridge: OnnxRun sequence failed (error=%d)", GetLastError());
         return false;
        }

      out_count = m_output_size;
      ArrayResize(outputs, out_count);
      for(int i = 0; i < out_count; i++)
         outputs[i] = (double)output_f[i];
      return true;
#else
      return false;
#endif
     }

   bool RunSequenceTensor(const SAISequenceTensor &tensor, double &outputs[], int &out_count)
     {
      out_count = 0;
      if(!tensor.valid)
         return false;

      float input_f[];
      ArrayResize(input_f, AI_SEQ_TENSOR_SIZE);
      for(int i = 0; i < AI_SEQ_TENSOR_SIZE; i++)
         input_f[i] = (float)tensor.data[i];
      return RunSequence(input_f, tensor.seq_len, tensor.feat_dim, outputs, out_count);
     }

   bool RunFV(const SAIFeatureVector &fv, double &out_score)
     {
      return Run(fv.features, out_score);
     }

   bool   IsLoaded()        const { return m_loaded; }
   string GetModelPath()    const { return m_model_path; }
   long   GetSession()      const { return m_session; }
   ENUM_ONNX_INPUT_MODE GetInputMode() const { return m_input_mode; }
   int    GetSeqLen()       const { return m_seq_len; }
   int    GetFeatDim()      const { return m_feat_dim; }
   int    GetOutputSize()   const { return m_output_size; }
   void   SetInputName(string n)  { m_input_name  = n; }
   void   SetOutputName(string n) { m_output_name = n; }
  };

#endif // __ONNX_BRIDGE_MQH__
