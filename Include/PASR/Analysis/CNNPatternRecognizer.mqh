//+------------------------------------------------------------------+
//| Analysis/CNNPatternRecognizer.mqh — v1.0                         |
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
   double weights[][CNN_CONV1_FILTERS];
   double biases[CNN_CONV1_FILTERS];
   int input_size;
   int num_filters;
   int kernel_size;

   void Reset()
   {
      ArrayInitialize(weights, 0.0);
      ArrayInitialize(biases, 0.0);
   }
};

struct CNNDenseLayer
{
   double weights[][CNN_DENSE_SIZE];
   double biases[CNN_DENSE_SIZE];
   int input_size;
   int output_size;

   void Reset()
   {
      ArrayInitialize(weights, 0.0);
      ArrayInitialize(biases, 0.0);
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
   double m_output_weights[CNN_DENSE_SIZE];
   double m_output_bias;
   bool m_initialized;
   int m_rand_seed;

   double m_input_buffer[CNN_INPUT_SIZE][CNN_NUM_FEATURES];
   int m_buffer_head;
   bool m_buffer_filled;

   double ReLU(double x) { return MathMax(0.0, x); }
   double Sigmoid(double x) { return 1.0 / (1.0 + MathExp(-x)); }
   double Tanh(double x)
   {
      double e2 = MathExp(2.0 * x);
      return (e2 - 1.0) / (e2 + 1.0);
   }

   void InitializeWeights()
   {
      MathSrand(m_rand_seed);

      // Initialize Conv1
      m_conv1.input_size = CNN_INPUT_SIZE * CNN_NUM_FEATURES;
      m_conv1.num_filters = CNN_CONV1_FILTERS;
      m_conv1.kernel_size = CNN_CONV1_KERNEL;

      double scale1 = MathSqrt(2.0 / (CNN_NUM_FEATURES * CNN_CONV1_KERNEL));
      ArrayResize(m_conv1.weights, CNN_NUM_FEATURES * CNN_CONV1_KERNEL);
      for(int i = 0; i < CNN_NUM_FEATURES * CNN_CONV1_KERNEL; i++)
      {
         for(int j = 0; j < CNN_CONV1_FILTERS; j++)
            m_conv1.weights[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale1;
      }
      for(int j = 0; j < CNN_CONV1_FILTERS; j++)
         m_conv1.biases[j] = 0.0;

      // Initialize Conv2
      int conv1_output_size = CNN_INPUT_SIZE - CNN_CONV1_KERNEL + 1;
      m_conv2.input_size = conv1_output_size * CNN_CONV1_FILTERS;
      m_conv2.num_filters = CNN_CONV2_FILTERS;
      m_conv2.kernel_size = CNN_CONV2_KERNEL;

      double scale2 = MathSqrt(2.0 / (CNN_CONV1_FILTERS * CNN_CONV2_KERNEL));
      ArrayResize(m_conv2.weights, CNN_CONV1_FILTERS * CNN_CONV2_KERNEL);
      for(int i = 0; i < CNN_CONV1_FILTERS * CNN_CONV2_KERNEL; i++)
      {
         for(int j = 0; j < CNN_CONV2_FILTERS; j++)
            m_conv2.weights[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale2;
      }
      for(int j = 0; j < CNN_CONV2_FILTERS; j++)
         m_conv2.biases[j] = 0.0;

      // Initialize Dense1
      int conv2_output_size = conv1_output_size - CNN_CONV2_KERNEL + 1;
      int pooled_size = conv2_output_size / CNN_POOL_SIZE;
      m_dense1.input_size = pooled_size * CNN_CONV2_FILTERS;
      m_dense1.output_size = CNN_DENSE_SIZE;

      double scale3 = MathSqrt(2.0 / (m_dense1.input_size + CNN_DENSE_SIZE));
      ArrayResize(m_dense1.weights, m_dense1.input_size);
      for(int i = 0; i < m_dense1.input_size; i++)
      {
         for(int j = 0; j < CNN_DENSE_SIZE; j++)
            m_dense1.weights[i][j] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale3;
      }
      for(int j = 0; j < CNN_DENSE_SIZE; j++)
         m_dense1.biases[j] = 0.0;

      // Initialize output layer
      double scale4 = MathSqrt(2.0 / (CNN_DENSE_SIZE + CNN_OUTPUT_SIZE));
      for(int i = 0; i < CNN_DENSE_SIZE; i++)
         m_output_weights[i] = ((double)MathRand() / 32767.0 - 0.5) * 2.0 * scale4;
      m_output_bias = 0.0;
   }

   void Conv1D(const double input[], int input_size, const CNNLayer1D &layer,
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
                  for(int feat = 0; feat < CNN_NUM_FEATURES; feat++)
                  {
                     int weight_idx = feat * layer.kernel_size + k;
                     int input_flat_idx = input_idx * CNN_NUM_FEATURES + feat;
                     sum += input[input_flat_idx] * layer.weights[weight_idx][f];
                  }
               }
            }
            output[i * layer.num_filters + f] = ReLU(sum);
         }
      }
   }

   void MaxPool1D(const double input[], int input_size, int num_filters, int pool_size,
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

   void Dense(const double input[], const CNNDenseLayer &layer,
              double &output[], bool use_relu = true)
   {
      ArrayResize(output, layer.output_size);
      ArrayInitialize(output, 0.0);

      for(int j = 0; j < layer.output_size; j++)
      {
         double sum = layer.biases[j];
         for(int i = 0; i < layer.input_size; i++)
            sum += input[i] * layer.weights[i][j];
         output[j] = use_relu ? ReLU(sum) : sum;
      }
   }

   bool NormalizeInput(const MqlRates rates[], int start_idx, double &normalized[])
   {
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
         const MqlRates &bar = rates[start_idx + i];
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
      if(latest_idx < CNN_INPUT_SIZE - 1) return false;

      int start_idx = latest_idx - CNN_INPUT_SIZE + 1;
      if(!NormalizeInput(rates, start_idx, m_input_buffer[0])) return false;

      m_buffer_head = (m_buffer_head + 1) % CNN_INPUT_SIZE;
      if(!m_buffer_filled && m_buffer_head == 0)
         m_buffer_filled = true;

      return true;
   }

public:
   CCNNPatternRecognizer(int seed = 44)
      : IManager(), m_initialized(false), m_rand_seed(seed),
        m_buffer_head(0), m_buffer_filled(false), m_output_bias(0.0)
   {
      for(int i = 0; i < CNN_INPUT_SIZE; i++)
         ArrayInitialize(m_input_buffer[i], 0.0);
   }

   virtual string HandlerName() const override { return "CNNPatternRecognizer"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!IManager::Init(data, bus)) return false;
      InitializeWeights();
      m_initialized = true;
      PrintFormat("[CNNPatternRecognizer] 1D-CNN initialized: %d input, %d conv1 filters, %d conv2 filters",
                  CNN_INPUT_SIZE, CNN_CONV1_FILTERS, CNN_CONV2_FILTERS);
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

      // Conv1
      double conv1_out[];
      int conv1_size;
      Conv1D(input, CNN_INPUT_SIZE * CNN_NUM_FEATURES, m_conv1, conv1_out, conv1_size);

      // Conv2
      double conv2_out[];
      int conv2_size;
      Conv1D(conv1_out, conv1_size * CNN_CONV1_FILTERS, m_conv2, conv2_out, conv2_size);

      // Pooling
      double pooled_out[];
      int pooled_size;
      MaxPool1D(conv2_out, conv2_size, CNN_CONV2_FILTERS, CNN_POOL_SIZE, pooled_out, pooled_size);

      // Dense
      double dense_out[];
      Dense(pooled_out, m_dense1, dense_out, true);

      // Output layer
      double final_scores[CNN_OUTPUT_SIZE];
      for(int j = 0; j < CNN_OUTPUT_SIZE; j++)
      {
         double sum = m_output_bias;
         for(int i = 0; i < CNN_DENSE_SIZE; i++)
            sum += dense_out[i] * m_output_weights[i];
         final_scores[j] = Tanh(sum);
      }

      // Apply softmax
      double sum_exp = 0.0;
      for(int j = 0; j < CNN_OUTPUT_SIZE; j++)
         sum_exp += MathExp(final_scores[j]);

      if(sum_exp > 0)
      {
         for(int j = 0; j < CNN_OUTPUT_SIZE; j++)
            output.pattern_scores[j] = MathExp(final_scores[j]) / sum_exp;
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
      return RecognizePattern(rates, ArraySize(rates) - 1, output);
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

   bool IsBufferFilled() const { return m_buffer_filled; }
   void ResetBuffer()
   {
      m_buffer_head = 0;
      m_buffer_filled = false;
      for(int i = 0; i < CNN_INPUT_SIZE; i++)
         ArrayInitialize(m_input_buffer[i], 0.0);
   }
};

#endif // __ANALYSIS_CNN_PATTERN_RECOGNIZER_MQH__
