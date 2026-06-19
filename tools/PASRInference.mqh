//+------------------------------------------------------------------+
//| PASRInference.mqh                                                |
//| Combined Volatility + Direction predictor for PASR               |
//|   Vol model:  PASR_vol_ridge.bin  (Ridge, 103 features)         |
//|   Dir model:  PASR_dir_{symbol}.bin (LogReg, 35 features)       |
//|   Fallback:   PASR_dir_forex.bin  (combined EURUSD+GBPUSD+USDJPY)|
//| Strategy:                                                        |
//|   2. Direction model → predicts BUY/SELL probability             |
//|      Only used when volatility is in LOW-MID range (filter)      |
//|   3. Output: trade_signal * position_size_factor                 |
//+------------------------------------------------------------------+
#property copyright "PASR"
#property version   "1.0"

#include <MQL5/File.mqh>

//+------------------------------------------------------------------+
//| Direction Predictor (logistic regression)                        |
//+------------------------------------------------------------------+
class CDirectionPredictor
{
private:
   float          m_buy_weights[35];
   float          m_buy_bias;
   float          m_sell_weights[35];
   float          m_sell_bias;
   float          m_mean[35];
   float          m_scale[35];
   bool           m_loaded;

public:
   CDirectionPredictor() : m_loaded(false) {}

   bool Load(const string filename)
   {
      ResetLastError();
      int handle = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
      if(handle == INVALID_HANDLE)
      {
         Print("CDirectionPredictor: Cannot open ", filename, " error ", GetLastError());
         return false;
      }

      // [0] model_type (int32: 1=per-symbol, 2=combined forex)
      int model_type;
      FileReadStruct(handle, model_type);
      if(model_type != 1 && model_type != 2)
      {
         Print("CDirectionPredictor: Invalid model_type = ", model_type);
         FileClose(handle);
         return false;
      }

      // [1..35] BUY weights
      FileReadArray(handle, m_buy_weights, 0, 35);

      // [36] BUY bias
      FileReadStruct(handle, m_buy_bias);

      // [37..71] SELL weights
      FileReadArray(handle, m_sell_weights, 0, 35);

      // [72] SELL bias
      FileReadStruct(handle, m_sell_bias);

      // [73..107] scaler mean
      FileReadArray(handle, m_mean, 0, 35);

      // [108..142] scaler scale
      FileReadArray(handle, m_scale, 0, 35);

      FileClose(handle);
      m_loaded = true;
      Print("CDirectionPredictor: Loaded (35 features)");
      return true;
   }

   // Standardize a single feature value
   float Standardize(int idx, float val) const
   {
      return (val - m_mean[idx]) / fmax(m_scale[idx], 1e-10f);
   }

   // Sigmoid function
   float Sigmoid(float x) const
   {
      return 1.0f / (1.0f + expf(-fmax(fmin(x, 20.0f), -20.0f)));
   }

   // Predict BUY probability from 35 features (34 AI + vol)
   float PredictBuy(const float &input[35]) const
   {
      if(!m_loaded) return 0.5f;
      float z = m_buy_bias;
      for(int i = 0; i < 35; i++)
         z += m_buy_weights[i] * Standardize(i, input[i]);
      return Sigmoid(z);
   }

   // Predict SELL probability
   float PredictSell(const float &input[35]) const
   {
      if(!m_loaded) return 0.5f;
      float z = m_sell_bias;
      for(int i = 0; i < 35; i++)
         z += m_sell_weights[i] * Standardize(i, input[i]);
      return Sigmoid(z);
   }

   bool IsLoaded() const { return m_loaded; }
};

//+------------------------------------------------------------------+
//| Volatility Predictor (Ridge regression)                          |
//+------------------------------------------------------------------+
class CVolatilityPredictor
{
private:
   int            m_n_features;
   float          m_weights[];   // [103]
   float          m_bias;
   float          m_mean[];      // [103]
   float          m_scale[];     // [103]
   bool           m_loaded;

   // Persistence buffer
   float          m_prev_vol;
   int            m_buffer_size;

public:
   CVolatilityPredictor() : m_loaded(false), m_prev_vol(0.0f), m_buffer_size(16) {}

   bool Load(const string filename)
   {
      ResetLastError();
      int handle = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
      if(handle == INVALID_HANDLE)
      {
         Print("CVolatilityPredictor: Cannot open ", filename, " error ", GetLastError());
         return false;
      }

      int header;
      FileReadStruct(handle, header);
      m_n_features = header;

      if(m_n_features <= 0 || m_n_features > 500)
      {
         Print("CVolatilityPredictor: Invalid n_features = ", m_n_features);
         FileClose(handle);
         return false;
      }

      ArrayResize(m_weights, m_n_features);
      ArrayResize(m_mean, m_n_features);
      ArrayResize(m_scale, m_n_features);

      FileReadArray(handle, m_weights, 0, m_n_features);
      FileReadStruct(handle, m_bias);
      FileReadArray(handle, m_mean, 0, m_n_features);
      FileReadArray(handle, m_scale, 0, m_n_features);

      FileClose(handle);
      m_loaded = true;
      Print("CVolatilityPredictor: Loaded (", m_n_features, " features)");
      return true;
   }

   void UpdateVolatility(const float vol_8bar)
   {
      m_prev_vol = vol_8bar;
   }

   float GetPersistence() const
   {
      return m_prev_vol;
   }

   // Input: features[34] = last-bar AI features
   float Predict(const float &features[34], float persistence)
   {
      if(!m_loaded) return 0.0f;

      float x[103];

      x[0] = persistence;

      for(int i = 0; i < 34; i++)
      {
         x[1 + i] = features[i];     // last bar
         x[35 + i] = features[i];     // mean ≈ last bar
         x[69 + i] = 0.0f;            // std ≈ 0
      }

      float y = m_bias;
      for(int i = 0; i < m_n_features; i++)
      {
         float xn = (x[i] - m_mean[i]) / fmax(m_scale[i], 1e-10f);
         y += m_weights[i] * xn;
      }

      return fmax(y, 0.0f);
   }

   bool IsLoaded() const { return m_loaded; }
};

//+------------------------------------------------------------------+
//| Combined PASR Inference                                          |
//+------------------------------------------------------------------+
class CPASRInference
{
private:
   CVolatilityPredictor  m_vol;
   CDirectionPredictor   m_dir;
   bool                  m_loaded;

   // Config
   float                 m_vol_threshold_high; // exclude vols above this
   float                 m_dir_threshold;      // min probability for trade

public:
   CPASRInference() : m_loaded(false),
      m_vol_threshold_high(4.5e-4f),
      m_dir_threshold(0.65f) {}

   // Auto-select direction model based on _Symbol
   bool Load(const string vol_bin, const string dir_bin = "")
   {
      bool v = m_vol.Load(vol_bin);
      if(!v) return false;

      string dir_path = dir_bin;
      if(dir_path == "")
      {
         // Auto-select: try per-symbol, fall back to combined
         string sym = _Symbol;
         StringToUpper(sym);

         // Map symbol to model filename
         string model_name = "PASR_dir_forex.bin";  // default fallback
         if(sym == "EURUSD") model_name = "PASR_dir_eurusd.bin";
         else if(sym == "GBPUSD") model_name = "PASR_dir_gbpusd.bin";
         else if(sym == "USDJPY") model_name = "PASR_dir_usdjpy.bin";
         else if(sym == "XAUUSD") model_name = "PASR_dir_forex.bin"; // use forex model as approx

         dir_path = model_name;
      }

      bool d = m_dir.Load(dir_path);
      if(!d)
      {
         // Fall back to combined forex model
         Print("CPASRInference: ", dir_path, " not found, trying PASR_dir_forex.bin");
         d = m_dir.Load("PASR_dir_forex.bin");
      }

      m_loaded = v && d;
      if(m_loaded) Print("CPASRInference: Loaded OK on ", _Symbol);
      return m_loaded;
   }

   void UpdateVolatility(const float realized_vol)
   {
      m_vol.UpdateVolatility(realized_vol);
   }

   // Main inference: returns trade signal and position size factor
   // trade_signal: +1=BUV, -1=SELL, 0=NEUTRAL
   // position_factor: 0.0=no trade, 0.2-3.0=size multiplier
   void GetSignal(const float &ai_features[34],
                  float &trade_signal,
                  float &position_factor)
   {
      trade_signal = 0.0f;
      position_factor = 0.0f;

      if(!m_loaded)
         return;

      // 1. Predict volatility
      float persistence = m_vol.GetPersistence();
      float pred_vol = m_vol.Predict(ai_features, persistence);

      // 2. Check vol filter
      if(pred_vol >= m_vol_threshold_high)
      {
         // HIGH volatility regime → no direction trading
         // But still scale position down based on vol
         position_factor = fmax(0.2f, fmin(0.5f, 0.003f / fmax(pred_vol, 1e-10f)));
         position_factor = fmin(position_factor, 3.0f);
         return;
      }

      // 3. Predict direction
      float input[35];
      for(int i = 0; i < 34; i++)
         input[i] = ai_features[i];
      input[34] = pred_vol;

      float buy_prob = m_dir.PredictBuy(input);
      float sell_prob = m_dir.PredictSell(input);

      // 4. Determine trade signal
      float max_prob = fmax(buy_prob, sell_prob);
      if(max_prob < m_dir_threshold)
      {
         // No strong signal
         position_factor = 0.0f;
         return;
      }

      trade_signal = (buy_prob > sell_prob) ? 1.0f : -1.0f;

      // 5. Position sizing: inverse vol
      // Low vol → larger position (more confident in direction)
      // High vol → smaller position (less confident)
      float base_factor = 0.003f / fmax(pred_vol, 1e-10f);
      base_factor = fmax(0.2f, fmin(base_factor, 3.0f));

      // Boost by model confidence
      float conf_boost = 0.5f + 0.5f * (max_prob - m_dir_threshold) / (1.0f - m_dir_threshold);
      position_factor = base_factor * conf_boost;
      position_factor = fmax(0.2f, fmin(position_factor, 3.0f));
   }

   bool IsLoaded() const { return m_loaded; }

   // Configure
   void SetVolThresholdHigh(float val) { m_vol_threshold_high = val; }
   void SetDirThreshold(float val) { m_dir_threshold = val; }
};

//+------------------------------------------------------------------+
//| Global instance                                                  |
//+------------------------------------------------------------------+
CPASRInference g_PASR;

//+------------------------------------------------------------------+
//| Helper: compute realized volatility over last N bars              |
//+------------------------------------------------------------------+
float ComputeRealizedVol(const double &close_buffer[], int n)
{
   int size = ArraySize(close_buffer);
   if(size < n + 2)
      return 0.0f;

   double sum = 0.0, sum_sq = 0.0;
   int count = 0;

   for(int i = size - n; i < size - 1; i++)
   {
      double log_ret = MathLog(close_buffer[i+1] / fmax(close_buffer[i], 1e-10));
      sum += log_ret;
      sum_sq += log_ret * log_ret;
      count++;
   }

   if(count < 2)
      return 0.0f;

   double mean = sum / count;
   double variance = (sum_sq - count * mean * mean) / (count - 1);
   return (float)MathSqrt(fmax(variance, 0.0));
}
//+------------------------------------------------------------------+
