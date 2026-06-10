//+------------------------------------------------------------------+
//| ONNXBridge.mqh                                                   |
//| Wrapper for MQL5 ONNX runtime — scalar and sequence inference    |
//+------------------------------------------------------------------+
#pragma once
#include "../Core/AITypes.mqh"

#ifdef PASR_ENABLE_ONNX
#include <Math/Stat/Normal.mqh>
#endif

enum ENUM_ONNX_INPUT_MODE
  {
   ONNX_INPUT_SCALAR   = 0,
   ONNX_INPUT_SEQUENCE = 1
  };

class CONNXBridge
  {
private:
   long              m_session;
   bool              m_loaded;
   string            m_model_path;
   ENUM_ONNX_INPUT_MODE m_input_mode;
   int               m_input_size;
   int               m_output_size;
   int               m_seq_len;
   int               m_feat_dim;

   bool SetSequenceInputShape()
     {
#ifdef PASR_ENABLE_ONNX
      long input_shape[] = {1, m_seq_len, m_feat_dim};
      return OnnxSetInputShape(m_session, 0, input_shape);
#else
      return false;
#endif
     }

public:
   CONNXBridge() : m_session(INVALID_HANDLE), m_loaded(false), m_model_path(""),
                   m_input_mode(ONNX_INPUT_SCALAR), m_input_size(AI_FEATURE_DIM),
                   m_output_size(1), m_seq_len(AI_SEQUENCE_LEN), m_feat_dim(AI_FEATURE_DIM) {}

  ~CONNXBridge() { Unload(); }

   bool Load(const string path, const ENUM_ONNX_INPUT_MODE mode = ONNX_INPUT_SCALAR,
             const int seq_len = AI_SEQUENCE_LEN, const int feat_dim = AI_FEATURE_DIM,
             const int output_size = 1)
     {
      Unload();
      m_model_path  = path;
      m_input_mode  = mode;
      m_seq_len     = seq_len;
      m_feat_dim    = feat_dim;
      m_output_size = output_size;
      m_input_size  = (mode == ONNX_INPUT_SEQUENCE) ? seq_len * feat_dim : feat_dim;
#ifdef PASR_ENABLE_ONNX
      m_session = OnnxCreate(path, ONNX_DEFAULT);
      m_loaded  = (m_session != INVALID_HANDLE);
      if(!m_loaded)
         PrintFormat("ONNXBridge: Failed to load '%s' (error=%d)", path, GetLastError());
#else
      m_loaded = false;
#endif
      return m_loaded;
     }

   void Unload()
     {
#ifdef PASR_ENABLE_ONNX
      if(m_session != INVALID_HANDLE) { OnnxRelease(m_session); m_session = INVALID_HANDLE; }
#endif
      m_loaded = false;
     }

   bool Run(float &features[], double &out_score)
     {
      out_score = 0.0;
      if(!m_loaded || m_session == INVALID_HANDLE || m_input_mode != ONNX_INPUT_SCALAR)
         return false;
#ifdef PASR_ENABLE_ONNX
      float output_f[];
      ArrayResize(output_f, m_output_size);
      if(!OnnxRun(m_session, ONNX_DEFAULT, features, output_f))
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

   bool RunSequence(float &input[],
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
      return Run((float&)fv.features, out_score);
     }

   bool   IsLoaded()        const { return m_loaded; }
   string GetModelPath()    const { return m_model_path; }
   long   GetSession()      const { return m_session; }
   ENUM_ONNX_INPUT_MODE GetInputMode() const { return m_input_mode; }
   int    GetSeqLen()       const { return m_seq_len; }
   int    GetFeatDim()      const { return m_feat_dim; }
  };
