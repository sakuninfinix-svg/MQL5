//+------------------------------------------------------------------+
//| Analysis/CNNPatternRecognizer.mqh — v1.1                         |
//| 1D Convolutional Neural Network for candlestick pattern recognition|
//| Enhances rule-based patterns with learned spatial features       |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_CNN_PATTERN_RECOGNIZER_MQH__
#define __ANALYSIS_CNN_PATTERN_RECOGNIZER_MQH__

#include "../Core/IManager.mqh"
#include "Pattern/PatternTypes.mqh"

#define CNN_INPUT_SIZE 20        // 20 candles input
#define CNN_NUM_FEATURES 4       // OHLC
#define CNN_CONV1_FILTERS 16
#define CNN_CONV1_KERNEL 3
#define CNN_CONV2_FILTERS 32
#define CNN_CONV2_KERNEL 3
#define CNN_POOL_SIZE 2
#define CNN_DENSE_SIZE 64
#define CNN_OUTPUT_SIZE 6       // 6 pattern types

struct CNNLayer1D
{
   double weights[];
   double biases[];
   int input_size;
   int input_channels;
   int num_filters;
   int kernel_size;
   int weight_stride;

   void Reset()
   {
      ArrayInitialize(weights, 0.0);
      ArrayInitialize(biases, 0.0);
   }

   int WeightIndex(int channel, int k, int f) const
   {
      return (k * input_channels + channel) * num_filters + f;
   }
};

struct CNNDenseLayer
{
   double weights[];
   double biases[];
   int input_size;
   int output_size;

   void Reset()
   {
      ArrayInitialize(weights, 0.0);
      ArrayInitialize(biases, 0.0);
   }

   int WeightIndex(int i, int j) const
   {
      return i * output_size + j;
   }
};

struct CNNPatternOutput
{
   double pattern_scores[CNN_OUTPUT_SIZE];
   int dominant_pattern;
   double confidence;

   void Reset()
   {
      ArrayInitialize(pattern_scores, 0.0);
      dominant_pattern = -1;
      confidence = 0.0;
   }
};

class CCNNPatternRecognizer : public IManager
{
private:
   CNNLayer1D m_conv1;
   CNNLayer1D m_conv2;
   CNNDenseLayer m_dense1;
   double m_output_weights[CNN_DENSE_SIZE][CNN_OUTPUT_SIZE];
   double m_output_biases[CNN_OUTPUT_SIZE];
   bool m_initialized;
   int m_rand_seed;

   double m_input_buffer[CNN_INPUT_SIZE][CNN_NUM_FEATURES];
   int m_buffer_head;
   bool m_buffer_filled;

   double ReLU(double x) { return MathMax(0.0, x); }
   double Sigmoid(double x) { return 1.0 / (1.0 + MathExp(-x)); }
   double Tanh(double x)
   {
      x = MathMax(-500.0, MathMin(500.0, x));
      double e2 = MathExp(2.0 * x);
      return (e2 - 1.0) / (e2 + 1.0);
   }

    void InitializeWeights()
    {
       MathSrand(m_rand_seed);

       // Initialize Conv1: 20 candles x 4 OHLC channels -> 16 filters
       m_conv1.input_size = CNN_INPUT_SIZE;
       m_conv1.input_channels = CNN_NUM_FEATURES;
       m_conv1.num_filters = CNN_CONV1_FILTERS;
       m_conv1.kernel_size = CNN_CONV1_KERNEL;
       m_conv1.weight_stride = CNN_CONV1_KERNEL * CNN_NUM_FEATURES * CNN_CONV1_FILTERS;

       double scale1 = MathSqrt(2.0 / (CNN_NUM_FEATURES * CNN_CONV1_KERNEL));
       int conv1_weight_count = CNN_CONV1_KERNEL * CNN_NUM_FEATURES * CNN_CONV1_FILTERS;
       ArrayResize(m_conv1.weights, conv1_weight_count);
       ArrayResize(m_conv1.biases, CNN_CONV1_FILTERS);
       ArrayInitialize(m_conv1.weights, 0.0);
       ArrayInitialize(m_conv1.biases, 0.0);
       for(int i = 0; i < conv1_weight_count; i++)
          m_conv1.weights[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale1;

       // Initialize Conv2: conv1 channels -> 32 filters
       int conv1_output_size = CNN_INPUT_SIZE - CNN_CONV1_KERNEL + 1;
       m_conv2.input_size = conv1_output_size;
       m_conv2.input_channels = CNN_CONV1_FILTERS;
       m_conv2.num_filters = CNN_CONV2_FILTERS;
       m_conv2.kernel_size = CNN_CONV2_KERNEL;
       m_conv2.weight_stride = CNN_CONV2_KERNEL * CNN_CONV1_FILTERS * CNN_CONV2_FILTERS;

       double scale2 = MathSqrt(2.0 / (CNN_CONV1_FILTERS * CNN_CONV2_KERNEL));
       int conv2_weight_count = CNN_CONV2_KERNEL * CNN_CONV1_FILTERS * CNN_CONV2_FILTERS;
       ArrayResize(m_conv2.weights, conv2_weight_count);
       ArrayResize(m_conv2.biases, CNN_CONV2_FILTERS);
       ArrayInitialize(m_conv2.weights, 0.0);
       ArrayInitialize(m_conv2.biases, 0.0);
       for(int i = 0; i < conv2_weight_count; i++)
          m_conv2.weights[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale2;

       // Initialize Dense1
       int conv2_output_size = conv1_output_size - CNN_CONV2_KERNEL + 1;
       int pooled_size = conv2_output_size / CNN_POOL_SIZE;
       m_dense1.input_size = pooled_size * CNN_CONV2_FILTERS;
       m_dense1.output_size = CNN_DENSE_SIZE;

       double scale3 = MathSqrt(2.0 / (m_dense1.input_size + CNN_DENSE_SIZE));
       int dense1_weight_count = m_dense1.input_size * CNN_DENSE_SIZE;
       ArrayResize(m_dense1.weights, dense1_weight_count);
       ArrayResize(m_dense1.biases, CNN_DENSE_SIZE);
       ArrayInitialize(m_dense1.weights, 0.0);
       ArrayInitialize(m_dense1.biases, 0.0);
       for(int i = 0; i < dense1_weight_count; i++)
          m_dense1.weights[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale3;

       // Initialize multi-class output layer: dense_size x output_classes
       double scale4 = MathSqrt(2.0 / (CNN_DENSE_SIZE + CNN_OUTPUT_SIZE));
       for(int i = 0; i < CNN_DENSE_SIZE; i++)
          for(int j = 0; j < CNN_OUTPUT_SIZE; j++)
             m_output_weights[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale4;
       ArrayInitialize(m_output_biases, 0.0);
    }

    void Conv1D(double &input[], int input_size, CNNLayer1D &layer,
                double &output[], int &output_size)
    {
       output_size = input_size - layer.kernel_size + 1;
       if(output_size <= 0) return;

       ArrayResize(output, output_size * layer.num_filters);
       ArrayInitialize(output, 0.0);

       for(int f = 0; f < layer.num_filters; f++)
       {
          for(int i = 0; i < output_size; i++)
          {
             double sum = layer.biases[f];
             for(int k = 0; k < layer.kernel_size; k++)
             {
                int input_idx = i + k;
                if(input_idx < input_size)
                {
                   for(int channel = 0; channel < layer.input_channels; channel++)
                   {
                      int weight_idx = layer.WeightIndex(channel, k, f);
                      int input_flat_idx = input_idx * layer.input_channels + channel;
                      sum += input[input_flat_idx] * layer.weights[weight_idx];
                   }
                }
             }
             output[i * layer.num_filters + f] = ReLU(sum);
          }
       }
    }

    void MaxPool1D(double &input[], int input_size, int num_filters, int pool_size,
                   double &output[], int &output_size)
    {
       output_size = input_size / pool_size;
       if(output_size <= 0) return;

       ArrayResize(output, output_size * num_filters);
       ArrayInitialize(output, 0.0);

       for(int f = 0; f < num_filters; f++)
       {
          for(int i = 0; i < output_size; i++)
          {
             double max_val = -DBL_MAX;
             for(int k = 0; k < pool_size; k++)
             {
                int input_idx = (i * pool_size + k) * num_filters + f;
                if(input_idx < input_size * num_filters)
                   max_val = MathMax(max_val, input[input_idx]);
             }
             output[i * num_filters + f] = max_val;
          }
       }
    }

    void Dense(double &input[], CNNDenseLayer &layer,
               double &output[], bool use_relu = true)
    {
       ArrayResize(output, layer.output_size);
       ArrayInitialize(output, 0.0);

       for(int j = 0; j < layer.output_size; j++)
       {
          double sum = layer.biases[j];
          for(int i = 0; i < layer.input_size; i++)
             sum += input[i] * layer.weights[layer.WeightIndex(i, j)];
          output[j] = use_relu ? ReLU(sum) : sum;
       }
    }

    bool NormalizeInput(const MqlRates rates[], int start_idx, double &normalized[])
    {
       if(start_idx < 0) return false;
       if(start_idx + CNN_INPUT_SIZE > ArraySize(rates)) return false;

       ArrayResize(normalized, CNN_INPUT_SIZE * CNN_NUM_FEATURES);

       // Find min/max for normalization
       double min_price = DBL_MAX;
       double max_price = -DBL_MAX;
       for(int i = 0; i < CNN_INPUT_SIZE; i++)
       {
          min_price = MathMin(min_price, rates[start_idx + i].low);
          max_price = MathMax(max_price, rates[start_idx + i].high);
       }
       double price_range = max_price - min_price;
       if(price_range <= 0) price_range = 1.0;

       // Normalize OHLC to [0,1]
       for(int i = 0; i < CNN_INPUT_SIZE; i++)
       {
          MqlRates bar = rates[start_idx + i];
          int base_idx = i * CNN_NUM_FEATURES;

          normalized[base_idx + 0] = (bar.open - min_price) / price_range;  // Open
          normalized[base_idx + 1] = (bar.high - min_price) / price_range;  // High
          normalized[base_idx + 2] = (bar.low - min_price) / price_range;   // Low
          normalized[base_idx + 3] = (bar.close - min_price) / price_range; // Close
       }

       return true;
    }

    bool UpdateInputBuffer(const MqlRates rates[], int latest_idx)
    {
       // rates[] is expected as series. PatternManager passes the scan shift, so the
       // CNN window is [latest_idx .. latest_idx + 19], not a rolling single-bar append.
       double temp_buffer[];
       if(!NormalizeInput(rates, latest_idx, temp_buffer)) return false;
       
       for(int i = 0; i < CNN_INPUT_SIZE; i++)
          for(int f = 0; f < CNN_NUM_FEATURES; f++)
             m_input_buffer[i][f] = temp_buffer[i * CNN_NUM_FEATURES + f];

       m_buffer_head = 0;
       m_buffer_filled = true;
       return true;
    }

public:
   CCNNPatternRecognizer(int seed = 44)
      : IManager(), m_initialized(false), m_rand_seed(seed),
        m_buffer_head(0), m_buffer_filled(false)
   {
      for(int i = 0; i < CNN_INPUT_SIZE; i++)
         ArrayInitialize(m_input_buffer[i], 0.0);
      ArrayInitialize(m_output_biases, 0.0);
   }

   virtual string HandlerName() const override { return "CNNPatternRecognizer"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!IManager::Init(data, bus)) return false;
      InitializeWeights();
      m_initialized = true;
      PrintFormat("[CNNPatternRecognizer] 1D-CNN initialized: %d candles, %d conv1 filters, %d conv2 filters, %d classes",
                  CNN_INPUT_SIZE, CNN_CONV1_FILTERS, CNN_CONV2_FILTERS, CNN_OUTPUT_SIZE);
      return true;
   }

   virtual void Deinit() override
   {
      m_initialized = false;
      IManager::Deinit();
   }

   virtual void DeclareEvents() override {}
   virtual void OnEvent(const PASREvent &ev) override {}

   bool RecognizePattern(const MqlRates rates[], int latest_idx, CNNPatternOutput &output)
   {
      output.Reset();
      if(!m_initialized) return false;

      if(!UpdateInputBuffer(rates, latest_idx)) return false;
      if(!m_buffer_filled) return false;

      // Flatten input buffer
      double input[CNN_INPUT_SIZE * CNN_NUM_FEATURES];
      for(int i = 0; i < CNN_INPUT_SIZE; i++)
      {
         for(int f = 0; f < CNN_NUM_FEATURES; f++)
            input[i * CNN_NUM_FEATURES + f] = m_input_buffer[i][f];
      }

      // Conv1 over candle steps
      double conv1_out[];
      int conv1_size = 0;
      Conv1D(input, CNN_INPUT_SIZE, m_conv1, conv1_out, conv1_size);
      if(conv1_size <= 0) return false;

      // Conv2 over conv1 output steps
      double conv2_out[];
      int conv2_size = 0;
      Conv1D(conv1_out, conv1_size, m_conv2, conv2_out, conv2_size);
      if(conv2_size <= 0) return false;

      // Pooling
      double pooled_out[];
      int pooled_size = 0;
      MaxPool1D(conv2_out, conv2_size, CNN_CONV2_FILTERS, CNN_POOL_SIZE, pooled_out, pooled_size);
      if(pooled_size <= 0) return false;

      // Dense
      double dense_out[];
      Dense(pooled_out, m_dense1, dense_out, true);

      // Output layer
      double final_scores[CNN_OUTPUT_SIZE];
      for(int j = 0; j < CNN_OUTPUT_SIZE; j++)
      {
         double sum = m_output_biases[j];
         for(int i = 0; i < CNN_DENSE_SIZE; i++)
            sum += dense_out[i] * m_output_weights[i][j];
         final_scores[j] = Tanh(sum);
      }

      // Stable softmax
      double max_score = final_scores[0];
      for(int j = 1; j < CNN_OUTPUT_SIZE; j++)
         max_score = MathMax(max_score, final_scores[j]);

      double sum_exp = 0.0;
      for(int j = 0; j < CNN_OUTPUT_SIZE; j++)
         sum_exp += MathExp(final_scores[j] - max_score);

      if(sum_exp > 0.0)
      {
         for(int j = 0; j < CNN_OUTPUT_SIZE; j++)
            output.pattern_scores[j] = MathExp(final_scores[j] - max_score) / sum_exp;
      }

      // Find dominant pattern
      int best_idx = 0;
      double best_score = output.pattern_scores[0];
      for(int j = 1; j < CNN_OUTPUT_SIZE; j++)
      {
         if(output.pattern_scores[j] > best_score)
         {
            best_score = output.pattern_scores[j];
            best_idx = j;
         }
      }

      output.dominant_pattern = best_idx;
      output.confidence = best_score;

      return true;
   }

   bool RecognizePattern(const MqlRates rates[], CNNPatternOutput &output)
   {
      return RecognizePattern(rates, 0, output);
   }

   ENUM_PATTERN_TYPE GetPatternType(int cnn_output) const
   {
      switch(cnn_output)
      {
         case 0: return PATTERN_PINBAR;
         case 1: return PATTERN_ENGULFING;
         case 2: return PATTERN_INSIDE_BAR_BREAKOUT;
         case 3: return PATTERN_FAKEY;
         case 4: return PATTERN_BOTTOM;
         case 5: return PATTERN_NONE;
         default: return PATTERN_NONE;
      }
   }

   bool IsBufferFilled() const { return m_initialized; }
   void ResetBuffer()
   {
      m_buffer_head = 0;
      m_buffer_filled = false;
      for(int i = 0; i < CNN_INPUT_SIZE; i++)
         ArrayInitialize(m_input_buffer[i], 0.0);
   }
};

#endif // __ANALYSIS_CNN_PATTERN_RECOGNIZER_MQH__
