//+------------------------------------------------------------------+
//| AI/LSTMInference.mqh — v1.03                                     |
//| LSTM-based inference engine for time series prediction           |
//| FIX v1.03: LSTMForwardStep explicit int param to match 4-arg     |
//|            call sites; all 'input' array params without 'const'  |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_LSTM_INFERENCE_MQH__
#define __AI_LSTM_INFERENCE_MQH__

#include "AITypes.mqh"
#include "../Core/IManager.mqh"

#define LSTM_HIDDEN_SIZE    128
#define LSTM_SEQUENCE_LENGTH 50
#define LSTM_NUM_LAYERS       2

struct LSTMLayer
  {
   double W_xh[][LSTM_HIDDEN_SIZE];
   double W_hh[][LSTM_HIDDEN_SIZE];
   double W_xi[][LSTM_HIDDEN_SIZE];
   double W_hi[][LSTM_HIDDEN_SIZE];
   double W_xf[][LSTM_HIDDEN_SIZE];
   double W_hf[][LSTM_HIDDEN_SIZE];
   double W_xo[][LSTM_HIDDEN_SIZE];
   double W_ho[][LSTM_HIDDEN_SIZE];
   double b_i[LSTM_HIDDEN_SIZE];
   double b_f[LSTM_HIDDEN_SIZE];
   double b_o[LSTM_HIDDEN_SIZE];
   double b_h[LSTM_HIDDEN_SIZE];
   double h[LSTM_HIDDEN_SIZE];
   double c[LSTM_HIDDEN_SIZE];
   int input_size;
   int hidden_size;

   void Reset()
     {
      ArrayInitialize(h, 0.0);
      ArrayInitialize(c, 0.0);
     }
  };

class CLSTMInference : public IManager
  {
private:
   LSTMLayer m_layers[LSTM_NUM_LAYERS];
   double    m_output_weights[LSTM_HIDDEN_SIZE];
   double    m_output_bias;
   bool      m_loaded;
   string    m_model_id;
   int       m_sequence_length;
   int       m_feature_dim;
   double    m_sequence_buffer[][AI_FEATURE_DIM];
   int       m_sequence_head;
   bool      m_sequence_filled;
   int       m_rand_seed;

   double Sigmoid(double x) { return 1.0 / (1.0 + MathExp(-x)); }
   double Tanh(double x)
     {
      double e2 = MathExp(2.0 * x);
      return (e2 - 1.0) / (e2 + 1.0);
     }

   void InitRandomWeights()
     {
      MathSrand(m_rand_seed);
      for(int layer = 0; layer < LSTM_NUM_LAYERS; layer++)
        {
         int input_sz = (layer == 0) ? AI_FEATURE_DIM : LSTM_HIDDEN_SIZE;
         double scale = MathSqrt(2.0 / (input_sz + LSTM_HIDDEN_SIZE));
         m_layers[layer].input_size  = input_sz;
         m_layers[layer].hidden_size = LSTM_HIDDEN_SIZE;

         ArrayResize(m_layers[layer].W_xh, input_sz);
         ArrayResize(m_layers[layer].W_hh, LSTM_HIDDEN_SIZE);
         ArrayResize(m_layers[layer].W_xi, input_sz);
         ArrayResize(m_layers[layer].W_hi, LSTM_HIDDEN_SIZE);
         ArrayResize(m_layers[layer].W_xf, input_sz);
         ArrayResize(m_layers[layer].W_hf, LSTM_HIDDEN_SIZE);
         ArrayResize(m_layers[layer].W_xo, input_sz);
         ArrayResize(m_layers[layer].W_ho, LSTM_HIDDEN_SIZE);

         for(int i = 0; i < input_sz; i++)
            for(int j = 0; j < LSTM_HIDDEN_SIZE; j++)
              {
               m_layers[layer].W_xh[i][j] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
               m_layers[layer].W_xi[i][j] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
               m_layers[layer].W_xf[i][j] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
               m_layers[layer].W_xo[i][j] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
              }

         for(int i = 0; i < LSTM_HIDDEN_SIZE; i++)
           {
            for(int j = 0; j < LSTM_HIDDEN_SIZE; j++)
              {
               m_layers[layer].W_hh[i][j] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
               m_layers[layer].W_hi[i][j] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
               m_layers[layer].W_hf[i][j] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
               m_layers[layer].W_ho[i][j] = ((double)MathRand()/32767.0-0.5)*2.0*scale;
              }
            m_layers[layer].b_i[i] = 0.0;
            m_layers[layer].b_f[i] = 0.0;
            m_layers[layer].b_o[i] = 0.0;
            m_layers[layer].b_h[i] = 0.0;
           }
        }
      double out_scale = MathSqrt(2.0 / (LSTM_HIDDEN_SIZE + 1));
      for(int i = 0; i < LSTM_HIDDEN_SIZE; i++)
         m_output_weights[i] = ((double)MathRand()/32767.0-0.5)*2.0*out_scale;
      m_output_bias = 0.0;
     }

   // FIX v1.03: explicit int input_size param — no more 'input comma expected'
   void LSTMForwardStep(LSTMLayer &layer, double &input[], int input_size, double &output[])
     {
      double i_gate[LSTM_HIDDEN_SIZE];
      double f_gate[LSTM_HIDDEN_SIZE];
      double o_gate[LSTM_HIDDEN_SIZE];
      double g_gate[LSTM_HIDDEN_SIZE];

      for(int j = 0; j < LSTM_HIDDEN_SIZE; j++)
        {
         double xi = layer.b_i[j];
         for(int i = 0; i < input_size;        i++) xi += input[i]    * layer.W_xi[i][j];
         for(int i = 0; i < LSTM_HIDDEN_SIZE;  i++) xi += layer.h[i]  * layer.W_hi[i][j];
         i_gate[j] = Sigmoid(xi);

         double xf = layer.b_f[j];
         for(int i = 0; i < input_size;        i++) xf += input[i]    * layer.W_xf[i][j];
         for(int i = 0; i < LSTM_HIDDEN_SIZE;  i++) xf += layer.h[i]  * layer.W_hf[i][j];
         f_gate[j] = Sigmoid(xf);

         double xo = layer.b_o[j];
         for(int i = 0; i < input_size;        i++) xo += input[i]    * layer.W_xo[i][j];
         for(int i = 0; i < LSTM_HIDDEN_SIZE;  i++) xo += layer.h[i]  * layer.W_ho[i][j];
         o_gate[j] = Sigmoid(xo);

         double xg = layer.b_h[j];
         for(int i = 0; i < input_size;        i++) xg += input[i]    * layer.W_xh[i][j];
         for(int i = 0; i < LSTM_HIDDEN_SIZE;  i++) xg += layer.h[i]  * layer.W_hh[i][j];
         g_gate[j] = Tanh(xg);

         layer.c[j] = f_gate[j] * layer.c[j] + i_gate[j] * g_gate[j];
         layer.h[j] = o_gate[j] * Tanh(layer.c[j]);
         output[j]  = layer.h[j];
        }
     }

   bool AddToSequence(const double &features[])
     {
      if(ArraySize(features) < AI_FEATURE_DIM) return false;
      for(int i = 0; i < AI_FEATURE_DIM; i++)
         m_sequence_buffer[m_sequence_head][i] = features[i];
      m_sequence_head = (m_sequence_head + 1) % m_sequence_length;
      if(!m_sequence_filled && m_sequence_head == 0)
         m_sequence_filled = true;
      return true;
     }

   bool GetSequence(double &sequence[][AI_FEATURE_DIM])
     {
      if(!m_sequence_filled) return false;
      ArrayResize(sequence, m_sequence_length);
      for(int t = 0; t < m_sequence_length; t++)
        {
         int idx = (m_sequence_head + t) % m_sequence_length;
         for(int i = 0; i < AI_FEATURE_DIM; i++)
            sequence[t][i] = m_sequence_buffer[idx][i];
        }
      return true;
     }

public:
   CLSTMInference(int seed = 42)
      : IManager(), m_loaded(false), m_model_id("lstm_v1_50seq_128hid_2layer"),
        m_sequence_length(LSTM_SEQUENCE_LENGTH), m_feature_dim(AI_FEATURE_DIM),
        m_sequence_head(0), m_sequence_filled(false), m_rand_seed(seed), m_output_bias(0.0)
     {
      ArrayResize(m_sequence_buffer, m_sequence_length);
      for(int i = 0; i < m_sequence_length; i++)
         for(int f = 0; f < AI_FEATURE_DIM; f++)
            m_sequence_buffer[i][f] = 0.0;
     }

   virtual string HandlerName() const override { return "LSTMInference"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      InitRandomWeights();
      m_loaded = true;
      PrintFormat("[LSTMInference] %d-layer %d-hidden %d-seq ready",
                  LSTM_NUM_LAYERS, LSTM_HIDDEN_SIZE, LSTM_SEQUENCE_LENGTH);
      return true;
     }

   virtual void Deinit() override
     {
      m_loaded = false;
      IManager::Deinit();
     }

   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   bool ForwardSequence(const double &features[], double &out_score)
     {
      out_score = 0.0;
      if(!m_loaded) return false;
      if(ArraySize(features) < AI_FEATURE_DIM) return false;
      if(!AddToSequence(features)) return false;
      if(!m_sequence_filled) return false;

      double sequence[][AI_FEATURE_DIM];
      if(!GetSequence(sequence)) return false;

      for(int layer = 0; layer < LSTM_NUM_LAYERS; layer++)
         m_layers[layer].Reset();

      double layer_output[LSTM_HIDDEN_SIZE];
      ArrayInitialize(layer_output, 0.0);

      for(int t = 0; t < m_sequence_length; t++)
        {
         // copy 2D row to temp 1D array
         double row_in[AI_FEATURE_DIM];
         for(int k = 0; k < AI_FEATURE_DIM; k++)
            row_in[k] = sequence[t][k];

         double temp_out[LSTM_HIDDEN_SIZE];
         // FIX v1.03: 4-arg call — pass explicit AI_FEATURE_DIM
         LSTMForwardStep(m_layers[0], row_in, AI_FEATURE_DIM, temp_out);
         for(int k = 0; k < LSTM_HIDDEN_SIZE; k++) layer_output[k] = temp_out[k];

         for(int lyr = 1; lyr < LSTM_NUM_LAYERS; lyr++)
           {
            double inter_out[LSTM_HIDDEN_SIZE];
            LSTMForwardStep(m_layers[lyr], layer_output, LSTM_HIDDEN_SIZE, inter_out);
            for(int k = 0; k < LSTM_HIDDEN_SIZE; k++) layer_output[k] = inter_out[k];
           }
        }

      double raw = m_output_bias;
      for(int i = 0; i < LSTM_HIDDEN_SIZE; i++)
         raw += layer_output[i] * m_output_weights[i];

      out_score = 1.0 / (1.0 + MathExp(-raw));
      return true;
     }

   bool   IsLoaded()  const { return m_loaded; }
   string ModelId()   const { return m_model_id; }
  };

#endif // __AI_LSTM_INFERENCE_MQH__
