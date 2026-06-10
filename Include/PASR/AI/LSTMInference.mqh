//+------------------------------------------------------------------+
//| AI/LSTMInference.mqh — v1.01                                     |
//| LSTM-based inference engine for time series prediction           |
//| Replaces simple MLP with temporal modeling capability           |
//+------------------------------------------------------------------+
#property strict
#ifndef __AI_LSTM_INFERENCE_MQH__
#define __AI_LSTM_INFERENCE_MQH__

#include "AITypes.mqh"
#include "../Core/IManager.mqh"

#define LSTM_HIDDEN_SIZE 128
#define LSTM_SEQUENCE_LENGTH 50
#define LSTM_NUM_LAYERS 2

struct LSTMLayer
{
   double W_xh[][LSTM_HIDDEN_SIZE];  // Input to hidden weights
   double W_hh[][LSTM_HIDDEN_SIZE];  // Hidden to hidden weights  
   double W_xi[][LSTM_HIDDEN_SIZE];  // Input to input gate weights
   double W_hi[][LSTM_HIDDEN_SIZE];  // Hidden to input gate weights
   double W_xf[][LSTM_HIDDEN_SIZE];  // Input to forget gate weights
   double W_hf[][LSTM_HIDDEN_SIZE];  // Hidden to forget gate weights
   double W_xo[][LSTM_HIDDEN_SIZE];  // Input to output gate weights
   double W_ho[][LSTM_HIDDEN_SIZE];  // Hidden to output gate weights
   double b_i[LSTM_HIDDEN_SIZE];     // Input gate bias
   double b_f[LSTM_HIDDEN_SIZE];     // Forget gate bias
   double b_o[LSTM_HIDDEN_SIZE];     // Output gate bias
   double b_h[LSTM_HIDDEN_SIZE];     // Hidden bias
   
   double h[LSTM_HIDDEN_SIZE];       // Hidden state
   double c[LSTM_HIDDEN_SIZE];       // Cell state
   
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
   double ReLU(double x) { return MathMax(0.0, x); }
   
   void InitRandomWeights()
   {
      MathSrand(m_rand_seed);
      
      for(int layer = 0; layer < LSTM_NUM_LAYERS; layer++)
      {
         int input_sz = (layer == 0) ? AI_FEATURE_DIM : LSTM_HIDDEN_SIZE;
         double scale = MathSqrt(2.0 / (input_sz + LSTM_HIDDEN_SIZE));
         
         m_layers[layer].input_size = input_sz;
         m_layers[layer].hidden_size = LSTM_HIDDEN_SIZE;
         
         // Initialize gate weights with Xavier initialization
         ArrayResize(m_layers[layer].W_xh, input_sz);
         ArrayResize(m_layers[layer].W_hh, LSTM_HIDDEN_SIZE);
         ArrayResize(m_layers[layer].W_xi, input_sz);
         ArrayResize(m_layers[layer].W_hi, LSTM_HIDDEN_SIZE);
         ArrayResize(m_layers[layer].W_xf, input_sz);
         ArrayResize(m_layers[layer].W_hf, LSTM_HIDDEN_SIZE);
         ArrayResize(m_layers[layer].W_xo, input_sz);
         ArrayResize(m_layers[layer].W_ho, LSTM_HIDDEN_SIZE);
         
         for(int i = 0; i < input_sz; i++)
         {
            for(int j = 0; j < LSTM_HIDDEN_SIZE; j++)
            {
               m_layers[layer].W_xh[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale;
               m_layers[layer].W_xi[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale;
               m_layers[layer].W_xf[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale;
               m_layers[layer].W_xo[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale;
            }
         }
         
         for(int i = 0; i < LSTM_HIDDEN_SIZE; i++)
         {
            for(int j = 0; j < LSTM_HIDDEN_SIZE; j++)
            {
               m_layers[layer].W_hh[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale;
               m_layers[layer].W_hi[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale;
               m_layers[layer].W_hf[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale;
               m_layers[layer].W_ho[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale;
            }
            // FIX: bias init must use loop variable 'i', not out-of-scope 'j'
            m_layers[layer].b_i[i] = 0.0;
            m_layers[layer].b_f[i] = 0.0;
            m_layers[layer].b_o[i] = 0.0;
            m_layers[layer].b_h[i] = 0.0;
         }
      }
      
      // Output layer
      double out_scale = MathSqrt(2.0 / (LSTM_HIDDEN_SIZE + 1));
      for(int i = 0; i < LSTM_HIDDEN_SIZE; i++)
         m_output_weights[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * out_scale;
      m_output_bias = 0.0;
   }
   
   // FIX: remove 'const' from array parameter — MQL5 does not support const ref array params
   void LSTMForwardStep(LSTMLayer &layer, double &input[], double &output[])
   {
      double i_gate[LSTM_HIDDEN_SIZE];
      double f_gate[LSTM_HIDDEN_SIZE];
      double o_gate[LSTM_HIDDEN_SIZE];
      double g_gate[LSTM_HIDDEN_SIZE];
      
      for(int j = 0; j < LSTM_HIDDEN_SIZE; j++)
      {
         // Input gate
         double xi = layer.b_i[j];
         for(int i = 0; i < layer.input_size; i++) xi += input[i] * layer.W_xi[i][j];
         for(int i = 0; i < LSTM_HIDDEN_SIZE; i++) xi += layer.h[i] * layer.W_hi[i][j];
         i_gate[j] = Sigmoid(xi);
         
         // Forget gate
         double xf = layer.b_f[j];
         for(int i = 0; i < layer.input_size; i++) xf += input[i] * layer.W_xf[i][j];
         for(int i = 0; i < LSTM_HIDDEN_SIZE; i++) xf += layer.h[i] * layer.W_hf[i][j];
         f_gate[j] = Sigmoid(xf);
         
         // Output gate
         double xo = layer.b_o[j];
         for(int i = 0; i < layer.input_size; i++) xo += input[i] * layer.W_xo[i][j];
         for(int i = 0; i < LSTM_HIDDEN_SIZE; i++) xo += layer.h[i] * layer.W_ho[i][j];
         o_gate[j] = Sigmoid(xo);
         
         // Candidate gate
         double xg = layer.b_h[j];
         for(int i = 0; i < layer.input_size; i++) xg += input[i] * layer.W_xh[i][j];
         for(int i = 0; i < LSTM_HIDDEN_SIZE; i++) xg += layer.h[i] * layer.W_hh[i][j];
         g_gate[j] = Tanh(xg);
         
         // Update cell state
         layer.c[j] = f_gate[j] * layer.c[j] + i_gate[j] * g_gate[j];
         
         // Update hidden state
         layer.h[j] = o_gate[j] * Tanh(layer.c[j]);
         
         output[j] = layer.h[j];
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
         ArrayInitialize(m_sequence_buffer[i], 0.0);
   }
   
   virtual string HandlerName() const override { return "LSTMInference"; }
   
   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!IManager::Init(data, bus)) return false;
      InitRandomWeights();
      m_loaded = true;
      PrintFormat("[LSTMInference] LSTM %d-layer %d-hidden %d-seq ready", 
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
      
      // Add to sequence buffer
      if(!AddToSequence(features)) return false;
      
      // Wait until sequence is filled
      if(!m_sequence_filled) 
      {
         out_score = 0.0;
         return false;
      }
      
      // Get sequence
      double sequence[][AI_FEATURE_DIM];
      if(!GetSequence(sequence)) return false;
      
      // Reset LSTM states
      for(int layer = 0; layer < LSTM_NUM_LAYERS; layer++)
         m_layers[layer].Reset();
      
      // Process sequence through LSTM layers
      double layer_output[LSTM_HIDDEN_SIZE];
      double prev_output[LSTM_HIDDEN_SIZE];
      ArrayInitialize(prev_output, 0.0);
      
      for(int t = 0; t < m_sequence_length; t++)
      {
         double input[LSTM_HIDDEN_SIZE];
         
         // First layer
         if(t == 0)
         {
            for(int i = 0; i < LSTM_HIDDEN_SIZE; i++)
               input[i] = (i < AI_FEATURE_DIM) ? sequence[t][i] : 0.0;
         }
         else
         {
            for(int i = 0; i < LSTM_HIDDEN_SIZE; i++)
               input[i] = prev_output[i];
         }
         
         LSTMForwardStep(m_layers[0], sequence[t], layer_output);
         
         // Subsequent layers
         for(int layer = 1; layer < LSTM_NUM_LAYERS; layer++)
         {
            LSTMForwardStep(m_layers[layer], layer_output, layer_output);
         }
         
         for(int i = 0; i < LSTM_HIDDEN_SIZE; i++)
            prev_output[i] = layer_output[i];
      }
      
      // Output layer
      double sum = m_output_bias;
      for(int i = 0; i < LSTM_HIDDEN_SIZE; i++)
         sum += layer_output[i] * m_output_weights[i];
      
      out_score = Tanh(sum);
      return true;
   }
   
   bool ForwardFV(const SAIFeatureVector &fv, double &out_score)
   {
      return ForwardSequence(fv.features, out_score);
   }
   
   bool   IsLoaded() const { return m_loaded; }
   string GetModelId() const { return m_model_id; }
   int    GetSequenceLength() const { return m_sequence_length; }
   bool   IsSequenceFilled() const { return m_sequence_filled; }
   void   ResetSequence()
   {
      m_sequence_head = 0;
      m_sequence_filled = false;
      for(int i = 0; i < m_sequence_length; i++)
         ArrayInitialize(m_sequence_buffer[i], 0.0);
      for(int layer = 0; layer < LSTM_NUM_LAYERS; layer++)
         m_layers[layer].Reset();
   }
};

#endif // __AI_LSTM_INFERENCE_MQH__
