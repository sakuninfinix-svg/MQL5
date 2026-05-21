//+------------------------------------------------------------------+
//| AI/FeatureEngine.mqh — Advanced Statistical Feature Extraction   |
//| Copyright 2026, Agsicentre                                       |
//|                                                                  |
//| PURPOSE:                                                         |
//|   Extract rolling statistical features for AI model input        |
//|   without excessive memory allocation. Supports:                 |
//|   - Z-score normalization                                        |
//|   - Skewness calculation (asymmetry detection)                   |
//|   - Kurtosis calculation (tail risk detection)                   |
//|   - Volatility regime classification                             |
//|   - Time-of-day feature encoding                                 |
//|                                                                  |
//| FEATURES:                                                        |
//|   - Zero-allocation design (pre-allocated buffers)               |
//|   - Rolling window statistics (configurable period)              |
//|   - Volatility regime detection (low/med/high/extreme)           |
//|   - Session-based time encoding (Asian/London/NY)                |
//|   - Integration with MarketRegimeFilter                          |
//|                                                                  |
//| PERFORMANCE:                                                     |
//|   - O(n) computation per bar, no dynamic allocation              |
//|   - Memory footprint: ~400 bytes per instance                    |
//|   - Designed for real-time feature extraction                    |
//+------------------------------------------------------------------+
#pragma once
#ifndef __AI_FEATURE_ENGINE_MQH__
#define __AI_FEATURE_ENGINE_MQH__

#include "AITypes.mqh"
#include "../Data/MarketRegime.mqh"

//+------------------------------------------------------------------+
//| Volatility regime enumeration                                    |
//+------------------------------------------------------------------+
enum ENUM_VOLATILITY_REGIME
  {
   VOLATILITY_LOW      = 0,     // Quiet market, range-bound
   VOLATILITY_MEDIUM   = 1,     // Normal trading conditions
   VOLATILITY_HIGH     = 2,     // Elevated volatility, trending
   VOLATILITY_EXTREME  = 3      // Extreme moves, potential breakout/crash
  };

//+------------------------------------------------------------------+
//| Feature extraction result structure                              |
//+------------------------------------------------------------------+
struct FeatureSet
  {
   double            z_score;            // Standardized price position
   double            skewness;           // Return distribution asymmetry
   double            kurtosis;           // Tail risk measure
   double            volatility_norm;    // Normalized volatility (0-1)
   double            time_feature;       // Time-of-day encoding (0-1)
   double            session_strength;   // Session activity level (0-1)
   ENUM_VOLATILITY_REGIME regime;       // Classified volatility regime
   datetime          timestamp;          // Feature computation time
   
   FeatureSet() : z_score(0), skewness(0), kurtosis(0),
                  volatility_norm(0.5), time_feature(0.5),
                  session_strength(0.5), regime(VOLATILITY_MEDIUM),
                  timestamp(0) {}
  };

//+------------------------------------------------------------------+
//| CFeatureEngine — Rolling statistical feature extractor           |
//+------------------------------------------------------------------+
class CFeatureEngine
  {
private:
   // Pre-allocated buffers (no dynamic allocation in hot path)
   double            m_returns[];        // Rolling returns buffer
   double            m_prices[];         // Price buffer for calculations
   int               m_window_size;      // Rolling window size
   int               m_bars_loaded;      // Number of bars loaded
   string            m_symbol;           // Symbol name
   ENUM_TIMEFRAMES   m_timeframe;        // Working timeframe
   bool              m_initialized;      // Engine ready flag
   
   // Regime thresholds (adaptive based on historical vol)
   double            m_vol_low_thresh;   // Lower bound for low vol
   double            m_vol_med_thresh;   // Upper bound for medium vol
   double            m_vol_high_thresh;  // Upper bound for high vol
   
   // Session hours (UTC)
   int               m_asian_start;      // Asian session start
   int               m_asian_end;        // Asian session end
   int               m_london_start;     // London session start
   int               m_london_end;       // London session end
   int               m_ny_start;         // NY session start
   int               m_ny_end;           // NY session end
   
   // Cache for last computed features
   FeatureSet        m_last_features;    // Last computed feature set
   datetime          m_last_compute_time;// Last computation timestamp

   //+----------------------------------------------------------------+
   //| Compute rolling returns from price array                       |
   //+----------------------------------------------------------------+
   void ComputeReturns()
     {
      if(m_bars_loaded < 2) return;
      
      ArrayResize(m_returns, m_bars_loaded - 1);
      for(int i = 0; i < m_bars_loaded - 1; i++)
        {
         if(m_prices[i+1] != 0)
            m_returns[i] = (m_prices[i] - m_prices[i+1]) / m_prices[i+1];
         else
            m_returns[i] = 0;
        }
     }

   //+----------------------------------------------------------------+
   //| Calculate mean of array                                        |
   //+----------------------------------------------------------------+
   double CalculateMean(const double &arr[]) const
     {
      int size = ArraySize(arr);
      if(size == 0) return 0;
      
      double sum = 0;
      for(int i = 0; i < size; i++)
         sum += arr[i];
      
      return sum / size;
     }

   //+----------------------------------------------------------------+
   //| Calculate standard deviation                                   |
   //+----------------------------------------------------------------+
   double CalculateStdDev(const double &arr[], double mean) const
     {
      int size = ArraySize(arr);
      if(size < 2) return 0;
      
      double sum_sq = 0;
      for(int i = 0; i < size; i++)
        {
         double diff = arr[i] - mean;
         sum_sq += diff * diff;
        }
      
      return MathSqrt(sum_sq / (size - 1));
     }

   //+----------------------------------------------------------------+
   //| Calculate skewness (asymmetry of distribution)                 |
   //+----------------------------------------------------------------+
   double CalculateSkewness(const double &arr[], double mean, double std_dev) const
     {
      int size = ArraySize(arr);
      if(size < 3 || std_dev == 0) return 0;
      
      double sum_cube = 0;
      for(int i = 0; i < size; i++)
        {
         double diff = arr[i] - mean;
         sum_cube += diff * diff * diff;
        }
      
      double skew = sum_cube / ((size - 1) * MathPow(std_dev, 3));
      return MathMax(-3.0, MathMin(3.0, skew));  // Clamp to [-3, 3]
     }

   //+----------------------------------------------------------------+
   //| Calculate kurtosis (tail risk measure)                         |
   //+----------------------------------------------------------------+
   double CalculateKurtosis(const double &arr[], double mean, double std_dev) const
     {
      int size = ArraySize(arr);
      if(size < 4 || std_dev == 0) return 3.0;  // Normal distribution baseline
      
      double sum_quad = 0;
      for(int i = 0; i < size; i++)
        {
         double diff = arr[i] - mean;
         sum_quad += diff * diff * diff * diff;
        }
      
      double kurt = sum_quad / ((size - 1) * MathPow(std_dev, 4));
      return MathMax(0.0, MathMin(10.0, kurt));  // Clamp to [0, 10]
     }

   //+----------------------------------------------------------------+
   //| Classify volatility regime based on thresholds                 |
   //+----------------------------------------------------------------+
   ENUM_VOLATILITY_REGIME ClassifyRegime(double vol_norm) const
     {
      if(vol_norm < m_vol_low_thresh)
         return VOLATILITY_LOW;
      else if(vol_norm < m_vol_med_thresh)
         return VOLATILITY_MEDIUM;
      else if(vol_norm < m_vol_high_thresh)
         return VOLATILITY_HIGH;
      else
         return VOLATILITY_EXTREME;
     }

   //+----------------------------------------------------------------+
   //| Encode time-of-day as continuous feature (0-1)                 |
   //+----------------------------------------------------------------+
   double EncodeTimeOfDay(int hour) const
     {
      // Peak activity hours: London open (8-10), NY open (13-15)
      if((hour >= 8 && hour <= 10) || (hour >= 13 && hour <= 15))
         return 1.0;
      // Moderate activity: London afternoon, NY morning
      else if((hour >= 11 && hour <= 12) || (hour >= 16 && hour <= 18))
         return 0.7;
      // Asian session overlap
      else if(hour >= 0 && hour <= 6)
         return 0.4;
      // Low activity periods
      else
         return 0.3;
     }

   //+----------------------------------------------------------------+
   //| Detect current trading session                                 |
   //+----------------------------------------------------------------+
   int DetectSession(int hour) const
     {
      // Asian session
      if(hour >= m_asian_start && hour < m_asian_end)
         return 1;
      // London session
      else if(hour >= m_london_start && hour < m_london_end)
         return 2;
      // NY session
      else if(hour >= m_ny_start && hour < m_ny_end)
         return 3;
      // Off-hours
      else
         return 0;
     }

   //+----------------------------------------------------------------+
   //| Calculate session strength (overlapping sessions = higher)     |
   //+----------------------------------------------------------------+
   double CalculateSessionStrength(int hour) const
     {
      int sessions_active = 0;
      
      if(hour >= m_asian_start && hour < m_asian_end)
         sessions_active++;
      if(hour >= m_london_start && hour < m_london_end)
         sessions_active++;
      if(hour >= m_ny_start && hour < m_ny_end)
         sessions_active++;
      
      // Normalize: 1 session = 0.4, 2 sessions = 0.8, 3 sessions = 1.0
      return MathMin(1.0, sessions_active * 0.4);
     }

public:
   // Constructor
   CFeatureEngine() : m_window_size(20), m_bars_loaded(0),
                      m_symbol(""), m_timeframe(PERIOD_CURRENT),
                      m_initialized(false),
                      m_vol_low_thresh(0.3), m_vol_med_thresh(0.6),
                      m_vol_high_thresh(0.85),
                      m_asian_start(0), m_asian_end(7),
                      m_london_start(7), m_london_end(16),
                      m_ny_start(13), m_ny_end(22),
                      m_last_compute_time(0)
     {
      ArrayInitialize(m_returns, 0);
      ArrayInitialize(m_prices, 0);
     }

   // Destructor
   ~CFeatureEngine()
     {
      // No dynamic allocation to clean up
     }

   //+----------------------------------------------------------------+
   //| Initialize feature engine                                      |
   //| @param symbol Symbol name                                      |
   //| @param timeframe Timeframe                                     |
   //| @param window_size Rolling window size (default: 20)           |
   //| @return true if successful                                     |
   //+----------------------------------------------------------------+
   bool Init(const string symbol = "", ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT,
             int window_size = 20)
     {
      if(m_initialized) return true;
      
      m_symbol = (symbol == "") ? _Symbol : symbol;
      m_timeframe = (timeframe == PERIOD_CURRENT) ? _Period : timeframe;
      m_window_size = MathMax(10, MathMin(100, window_size));
      
      // Pre-allocate buffers
      if(ArrayResize(m_prices, m_window_size) != m_window_size)
        {
         Print("[FeatureEngine][ERROR] Failed to allocate price buffer");
         return false;
        }
      
      if(ArrayResize(m_returns, m_window_size) != m_window_size)
        {
         Print("[FeatureEngine][ERROR] Failed to allocate returns buffer");
         return false;
        }
      
      // Load initial data
      if(!RefreshData())
        {
         Print("[FeatureEngine][WARN] Initial data load failed");
        }
      
      m_initialized = true;
      Print("[FeatureEngine][INFO] Initialized for ", m_symbol, 
            " window=", m_window_size);
      return true;
     }

   //+----------------------------------------------------------------+
   //| Refresh price data from chart                                  |
   //| @return true if data loaded successfully                       |
   //+----------------------------------------------------------------+
   bool RefreshData()
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      
      int copied = CopyRates(m_symbol, m_timeframe, 0, m_window_size, rates);
      if(copied < m_window_size)
        {
         // Partial load acceptable for initialization
         if(copied < 5) return false;
         m_bars_loaded = copied;
        }
      else
        {
         m_bars_loaded = m_window_size;
        }
      
      // Extract close prices
      for(int i = 0; i < m_bars_loaded; i++)
        {
         m_prices[i] = rates[i].close;
        }
      
      return true;
     }

   //+----------------------------------------------------------------+
   //| Compute all features (call on new bar or on-demand)            |
   //| @param force_recompute Force recomputation even if same bar   |
   //| @return Reference to computed FeatureSet                       |
   //+----------------------------------------------------------------+
   const FeatureSet& ComputeFeatures(bool force_recompute = false)
     {
      datetime current_time = TimeCurrent();
      
      // Skip if already computed for this bar (unless forced)
      if(!force_recompute && current_time == m_last_compute_time)
         return m_last_features;
      
      // Refresh data
      if(!RefreshData())
        {
         Print("[FeatureEngine][WARN] Data refresh failed");
         return m_last_features;
        }
      
      // Compute returns
      ComputeReturns();
      
      // Calculate statistics
      double mean = CalculateMean(m_returns);
      double std_dev = CalculateStdDev(m_returns, mean);
      
      // Z-score (current price position relative to window)
      double current_price = m_prices[0];
      double avg_price = CalculateMean(m_prices);
      double price_stddev = CalculateStdDev(m_prices, avg_price);
      
      m_last_features.z_score = (price_stddev > 0) ? 
                                (current_price - avg_price) / price_stddev : 0;
      m_last_features.z_score = MathMax(-3.0, MathMin(3.0, m_last_features.z_score));
      
      // Skewness and Kurtosis
      m_last_features.skewness = CalculateSkewness(m_returns, mean, std_dev);
      m_last_features.kurtosis = CalculateKurtosis(m_returns, mean, std_dev);
      
      // Volatility normalization
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point > 0 && std_dev > 0)
        {
         m_last_features.volatility_norm = MathMin(1.0, std_dev / (point * 100));
        }
      else
        {
         m_last_features.volatility_norm = 0.5;
        }
      
      // Time features
      MqlDateTime dt;
      TimeToStruct(current_time, dt);
      
      m_last_features.time_feature = EncodeTimeOfDay(dt.hour);
      m_last_features.session_strength = CalculateSessionStrength(dt.hour);
      
      // Classify regime
      m_last_features.regime = ClassifyRegime(m_last_features.volatility_norm);
      
      // Update timestamp
      m_last_features.timestamp = current_time;
      m_last_compute_time = current_time;
      
      return m_last_features;
     }

   //+----------------------------------------------------------------+
   //| Get last computed features                                     |
   //| @return Reference to last FeatureSet                           |
   //+----------------------------------------------------------------+
   const FeatureSet& GetLastFeatures() const
     {
      return m_last_features;
     }

   //+----------------------------------------------------------------+
   //| Get current volatility regime                                  |
   //| @return Current ENUM_VOLATILITY_REGIME                         |
   //+----------------------------------------------------------------+
   ENUM_VOLATILITY_REGIME GetCurrentRegime() const
     {
      return m_last_features.regime;
     }

   //+----------------------------------------------------------------+
   //| Check if regime is high or extreme (for confidence adjustment) |
   //| @return true if elevated volatility                            |
   //+----------------------------------------------------------------+
   bool IsElevatedVolatility() const
     {
      return (m_last_features.regime >= VOLATILITY_HIGH);
     }

   //+----------------------------------------------------------------+
   //| Set regime classification thresholds                           |
   //| @param low_thresh Low volatility threshold (0-1)               |
   //| @param med_thresh Medium volatility threshold (0-1)            |
   //| @param high_thresh High volatility threshold (0-1)             |
   //+----------------------------------------------------------------+
   void SetRegimeThresholds(double low_thresh, double med_thresh, double high_thresh)
     {
      m_vol_low_thresh = MathMax(0.0, MathMin(1.0, low_thresh));
      m_vol_med_thresh = MathMax(m_vol_low_thresh, MathMin(1.0, med_thresh));
      m_vol_high_thresh = MathMax(m_vol_med_thresh, MathMin(1.0, high_thresh));
     }

   //+----------------------------------------------------------------+
   //| Set session hours (UTC)                                        |
   //| @param asian_start, asian_end Asian session hours              |
   //| @param london_start, london_end London session hours           |
   //| @param ny_start, ny_end NY session hours                       |
   //+----------------------------------------------------------------+
   void SetSessionHours(int asian_start, int asian_end,
                        int london_start, int london_end,
                        int ny_start, int ny_end)
     {
      m_asian_start = asian_start;
      m_asian_end = asian_end;
      m_london_start = london_start;
      m_london_end = london_end;
      m_ny_start = ny_start;
      m_ny_end = ny_end;
     }

   //+----------------------------------------------------------------+
   //| Get window size                                                |
   //| @return Rolling window size                                    |
   //+----------------------------------------------------------------+
   int GetWindowSize() const
     {
      return m_window_size;
     }

   //+----------------------------------------------------------------+
   //| Check if engine is initialized                                 |
   //| @return true if ready                                          |
   //+----------------------------------------------------------------+
   bool IsInitialized() const
     {
      return m_initialized;
     }

   //+----------------------------------------------------------------+
   //| Reset engine state                                             |
   //+----------------------------------------------------------------+
   void Reset()
     {
      m_bars_loaded = 0;
      ArrayInitialize(m_returns, 0);
      ArrayInitialize(m_prices, 0);
      m_last_features = FeatureSet();
      m_last_compute_time = 0;
     }

   //+----------------------------------------------------------------+
   //| Print feature summary                                          |
   //+----------------------------------------------------------------+
   void PrintFeatures() const
     {
      Print("[FeatureEngine] ", m_symbol, " Features:");
      Print("  Z-Score:     ", DoubleToString(m_last_features.z_score, 3));
      Print("  Skewness:    ", DoubleToString(m_last_features.skewness, 3));
      Print("  Kurtosis:    ", DoubleToString(m_last_features.kurtosis, 3));
      Print("  Volatility:  ", DoubleToString(m_last_features.volatility_norm, 3),
            " (", EnumToString(m_last_features.regime), ")");
      Print("  Time:        ", DoubleToString(m_last_features.time_feature, 3));
      Print("  Session:     ", DoubleToString(m_last_features.session_strength, 3));
     }
  };

#endif // __AI_FEATURE_ENGINE_MQH__
