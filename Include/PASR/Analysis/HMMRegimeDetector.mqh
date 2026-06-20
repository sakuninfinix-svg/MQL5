//+------------------------------------------------------------------+
//| Analysis/HMMRegimeDetector.mqh — v1.0                            |
//| Hidden Markov Model for probabilistic regime detection           |
//| Replaces rule-based regime detection with stochastic modeling    |
//| Copyright @2026                                                  |
//| agsicentre.wordpress.com                                         |
//+------------------------------------------------------------------+
#property strict
#ifndef __ANALYSIS_HMM_REGIME_DETECTOR_MQH__
#define __ANALYSIS_HMM_REGIME_DETECTOR_MQH__

#include "../Core/IManager.mqh"
#include "../Data/RegimeTypes.mqh"

#define HMM_NUM_STATES 6
#define HMM_NUM_OBSERVATIONS 3
#define HMM_HISTORY_SIZE 100

enum ENUM_HMM_STATE
{
   HMM_STATE_TREND_UP = 0,
   HMM_STATE_TREND_DOWN = 1,
   HMM_STATE_RANGE = 2,
   HMM_STATE_VOLATILE = 3,
   HMM_STATE_SQUEEZE = 4,
   HMM_STATE_TRANSITION = 5
};

struct HMMObservation
{
   double trend_strength;    // Normalized 0-1
   double volatility;        // Normalized 0-1
   double momentum;         // Normalized -1 to 1

   void Reset()
   {
      trend_strength = 0.5;
      volatility = 0.5;
      momentum = 0.0;
   }
};

struct HMMParameters
{
   double transition[HMM_NUM_STATES][HMM_NUM_STATES];  // State transition probabilities
   double emission[HMM_NUM_STATES][HMM_NUM_OBSERVATIONS]; // Emission probabilities
   double initial[HMM_NUM_STATES];                      // Initial state probabilities

   void Reset()
   {
      for(int i = 0; i < HMM_NUM_STATES; i++)
      {
         initial[i] = 1.0 / HMM_NUM_STATES;
         for(int j = 0; j < HMM_NUM_STATES; j++)
            transition[i][j] = 1.0 / HMM_NUM_STATES;
         for(int j = 0; j < HMM_NUM_OBSERVATIONS; j++)
            emission[i][j] = 1.0 / HMM_NUM_OBSERVATIONS;
      }
   }

   void NormalizeTransitions()
   {
      for(int i = 0; i < HMM_NUM_STATES; i++)
      {
         double sum = 0.0;
         for(int j = 0; j < HMM_NUM_STATES; j++)
            sum += transition[i][j];
         if(sum > 0)
         {
            for(int j = 0; j < HMM_NUM_STATES; j++)
               transition[i][j] /= sum;
         }
      }
   }
};

class CHMMRegimeDetector : public IManager
{
private:
   HMMParameters m_params;
   double m_state_probabilities[HMM_NUM_STATES];
   HMMObservation m_observation_history[HMM_HISTORY_SIZE];
   int m_history_head;
   bool m_history_filled;
   int m_current_state;
   int m_state_history[HMM_HISTORY_SIZE];
   int m_state_history_head;
   bool m_state_history_filled;
   double m_regime_confidence;
   int m_regime_streak;
   datetime m_last_state_change;

   int m_atr_handle;
   int m_adx_handle;
   int m_rsi_handle;

   double Clamp01(double v) const { return MathMax(0.0, MathMin(1.0, v)); }

   void InitializeParameters()
   {
      m_params.Reset();

      // Initialize with reasonable prior knowledge
      // Trend states tend to persist
      m_params.transition[HMM_STATE_TREND_UP][HMM_STATE_TREND_UP] = 0.7;
      m_params.transition[HMM_STATE_TREND_UP][HMM_STATE_RANGE] = 0.15;
      m_params.transition[HMM_STATE_TREND_UP][HMM_STATE_TRANSITION] = 0.15;

      m_params.transition[HMM_STATE_TREND_DOWN][HMM_STATE_TREND_DOWN] = 0.7;
      m_params.transition[HMM_STATE_TREND_DOWN][HMM_STATE_RANGE] = 0.15;
      m_params.transition[HMM_STATE_TREND_DOWN][HMM_STATE_TRANSITION] = 0.15;

      // Range tends to be stable
      m_params.transition[HMM_STATE_RANGE][HMM_STATE_RANGE] = 0.6;
      m_params.transition[HMM_STATE_RANGE][HMM_STATE_TREND_UP] = 0.2;
      m_params.transition[HMM_STATE_RANGE][HMM_STATE_TREND_DOWN] = 0.2;

      // Volatile tends to transition to other states
      m_params.transition[HMM_STATE_VOLATILE][HMM_STATE_VOLATILE] = 0.3;
      m_params.transition[HMM_STATE_VOLATILE][HMM_STATE_RANGE] = 0.3;
      m_params.transition[HMM_STATE_VOLATILE][HMM_STATE_TREND_UP] = 0.2;
      m_params.transition[HMM_STATE_VOLATILE][HMM_STATE_TREND_DOWN] = 0.2;

      // Squeeze tends to expand
      m_params.transition[HMM_STATE_SQUEEZE][HMM_STATE_SQUEEZE] = 0.4;
      m_params.transition[HMM_STATE_SQUEEZE][HMM_STATE_VOLATILE] = 0.3;
      m_params.transition[HMM_STATE_SQUEEZE][HMM_STATE_RANGE] = 0.3;

      // Transition is temporary
      m_params.transition[HMM_STATE_TRANSITION][HMM_STATE_TRANSITION] = 0.3;
      m_params.transition[HMM_STATE_TRANSITION][HMM_STATE_TREND_UP] = 0.2;
      m_params.transition[HMM_STATE_TRANSITION][HMM_STATE_TREND_DOWN] = 0.2;
      m_params.transition[HMM_STATE_TRANSITION][HMM_STATE_RANGE] = 0.3;

      m_params.NormalizeTransitions();

      // Emission probabilities (simplified)
      // Each state has characteristic observation patterns
      m_params.emission[HMM_STATE_TREND_UP][0] = 0.8;     // High trend
      m_params.emission[HMM_STATE_TREND_UP][1] = 0.4;     // Medium volatility
      m_params.emission[HMM_STATE_TREND_UP][2] = 0.7;     // Positive momentum

      m_params.emission[HMM_STATE_TREND_DOWN][0] = 0.8;   // High trend
      m_params.emission[HMM_STATE_TREND_DOWN][1] = 0.4;   // Medium volatility
      m_params.emission[HMM_STATE_TREND_DOWN][2] = 0.3;   // Negative momentum

      m_params.emission[HMM_STATE_RANGE][0] = 0.3;        // Low trend
      m_params.emission[HMM_STATE_RANGE][1] = 0.3;        // Low volatility
      m_params.emission[HMM_STATE_RANGE][2] = 0.5;        // Neutral momentum

      m_params.emission[HMM_STATE_VOLATILE][0] = 0.5;     // Medium trend
      m_params.emission[HMM_STATE_VOLATILE][1] = 0.9;     // High volatility
      m_params.emission[HMM_STATE_VOLATILE][2] = 0.4;     // Variable momentum

      m_params.emission[HMM_STATE_SQUEEZE][0] = 0.2;      // Very low trend
      m_params.emission[HMM_STATE_SQUEEZE][1] = 0.1;      // Very low volatility
      m_params.emission[HMM_STATE_SQUEEZE][2] = 0.3;      // Low momentum

      m_params.emission[HMM_STATE_TRANSITION][0] = 0.5;   // Variable
      m_params.emission[HMM_STATE_TRANSITION][1] = 0.5;   // Variable
      m_params.emission[HMM_STATE_TRANSITION][2] = 0.5;   // Variable
   }

   double GetObservationProbability(int state, const HMMObservation &obs) const
   {
      // Simplified Gaussian-like emission probability
      double trend_prob = (state == HMM_STATE_TREND_UP || state == HMM_STATE_TREND_DOWN) ?
                         (obs.trend_strength > 0.6 ? 0.8 : 0.2) :
                         (state == HMM_STATE_RANGE ? (obs.trend_strength < 0.4 ? 0.7 : 0.3) : 0.5);

      double vol_prob = (state == HMM_STATE_VOLATILE) ?
                       (obs.volatility > 0.7 ? 0.8 : 0.2) :
                       (state == HMM_STATE_SQUEEZE ? (obs.volatility < 0.3 ? 0.8 : 0.2) : 0.5);

      double mom_prob = 0.5;
      if(state == HMM_STATE_TREND_UP) mom_prob = (obs.momentum > 0.3) ? 0.7 : 0.3;
      else if(state == HMM_STATE_TREND_DOWN) mom_prob = (obs.momentum < -0.3) ? 0.7 : 0.3;
      else if(state == HMM_STATE_RANGE) mom_prob = (MathAbs(obs.momentum) < 0.2) ? 0.7 : 0.3;

      return trend_prob * vol_prob * mom_prob;
   }

   HMMObservation GetCurrentObservation()
   {
      HMMObservation obs;
      obs.Reset();

      // Get indicator values
      double atr = 0.0, adx = 0.0, rsi = 0.0;

      if(m_atr_handle != INVALID_HANDLE)
      {
         double atr_buf[1];
         if(CopyBuffer(m_atr_handle, 0, 1, 1, atr_buf) > 0)
            atr = atr_buf[0];
      }

      if(m_adx_handle != INVALID_HANDLE)
      {
         double adx_buf[1];
         if(CopyBuffer(m_adx_handle, 0, 1, 1, adx_buf) > 0)
            adx = adx_buf[0];
      }

      if(m_rsi_handle != INVALID_HANDLE)
      {
         double rsi_buf[1];
         if(CopyBuffer(m_rsi_handle, 0, 1, 1, rsi_buf) > 0)
            rsi = rsi_buf[0];
      }

      // Calculate normalized features
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double price = (bid + ask) / 2.0;

      // Trend strength from ADX (normalized 0-1)
      obs.trend_strength = Clamp01(adx / 50.0);

      // Volatility from ATR (normalized 0-1)
      if(atr > 0 && price > 0)
         obs.volatility = Clamp01((atr / price) * 1000.0);

      // Momentum from RSI (normalized -1 to 1)
      obs.momentum = (rsi - 50.0) / 50.0;

      return obs;
   }

   void UpdateStateProbabilities(const HMMObservation &obs)
   {
      double new_probs[HMM_NUM_STATES];
      ArrayInitialize(new_probs, 0.0);

      // Forward algorithm step
      for(int j = 0; j < HMM_NUM_STATES; j++)
      {
         double sum = 0.0;
         for(int i = 0; i < HMM_NUM_STATES; i++)
         {
            double trans_prob = m_params.transition[i][j];
            double emit_prob = GetObservationProbability(j, obs);
            sum += m_state_probabilities[i] * trans_prob * emit_prob;
         }
         new_probs[j] = sum;
      }

      // Normalize
      double total = 0.0;
      for(int i = 0; i < HMM_NUM_STATES; i++)
         total += new_probs[i];

      if(total > 0)
      {
         for(int i = 0; i < HMM_NUM_STATES; i++)
            m_state_probabilities[i] = new_probs[i] / total;
      }
   }

   void UpdateTransitionMatrix(const HMMObservation &obs, int actual_state)
   {
      // Online learning: update transition probabilities based on observed transitions
      double learning_rate = 0.01;

      // Increase probability of observed transition
      for(int i = 0; i < HMM_NUM_STATES; i++)
      {
         if(m_state_probabilities[i] > 0.1) // Only update from probable previous states
         {
            m_params.transition[i][actual_state] =
               (1 - learning_rate) * m_params.transition[i][actual_state] +
               learning_rate;
         }
      }

      m_params.NormalizeTransitions();
   }

   int GetMostProbableState() const
   {
      int best_state = 0;
      double best_prob = m_state_probabilities[0];

      for(int i = 1; i < HMM_NUM_STATES; i++)
      {
         if(m_state_probabilities[i] > best_prob)
         {
            best_prob = m_state_probabilities[i];
            best_state = i;
         }
      }

      return best_state;
   }

   EMarketRegime HMMStateToRegime(int hmm_state) const
   {
      switch(hmm_state)
      {
         case HMM_STATE_TREND_UP:    return REGIME_TREND_UP;
         case HMM_STATE_TREND_DOWN:  return REGIME_TREND_DOWN;
         case HMM_STATE_RANGE:       return REGIME_RANGE;
         case HMM_STATE_VOLATILE:    return REGIME_VOLATILE;
         case HMM_STATE_SQUEEZE:     return REGIME_SQUEEZE;
         case HMM_STATE_TRANSITION:  return REGIME_TRANSITION;
         default:                    return REGIME_UNKNOWN;
      }
   }

   void AddToHistory(const HMMObservation &obs, int state)
   {
      m_observation_history[m_history_head] = obs;
      m_history_head = (m_history_head + 1) % HMM_HISTORY_SIZE;
      if(!m_history_filled && m_history_head == 0)
         m_history_filled = true;

      m_state_history[m_state_history_head] = state;
      m_state_history_head = (m_state_history_head + 1) % HMM_HISTORY_SIZE;
      if(!m_state_history_filled && m_state_history_head == 0)
         m_state_history_filled = true;
   }

public:
   CHMMRegimeDetector()
      : IManager(), m_history_head(0), m_history_filled(false),
        m_current_state(HMM_STATE_RANGE), m_state_history_head(0),
        m_state_history_filled(false), m_regime_confidence(0.5),
        m_regime_streak(0), m_last_state_change(0),
        m_atr_handle(INVALID_HANDLE), m_adx_handle(INVALID_HANDLE), m_rsi_handle(INVALID_HANDLE)
   {
      ArrayInitialize(m_state_probabilities, 1.0 / HMM_NUM_STATES);
      for(int i = 0; i < HMM_HISTORY_SIZE; i++)
      {
         m_observation_history[i].Reset();
         m_state_history[i] = HMM_STATE_RANGE;
      }
   }

   virtual string HandlerName() const override { return "HMMRegimeDetector"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!IManager::Init(data, bus)) return false;

      InitializeParameters();

      // Initialize indicators
      m_atr_handle = iATR(_Symbol, _Period, 14);
      m_adx_handle = iADX(_Symbol, _Period, 14);
      m_rsi_handle = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);

      Print("[HMMRegimeDetector] Initialized with 6-state HMM for regime detection");
      return true;
   }

   virtual void Deinit() override
   {
      if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);
      if(m_adx_handle != INVALID_HANDLE) IndicatorRelease(m_adx_handle);
      if(m_rsi_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_handle);
      m_atr_handle = INVALID_HANDLE;
      m_adx_handle = INVALID_HANDLE;
      m_rsi_handle = INVALID_HANDLE;
      IManager::Deinit();
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_NEW_BAR);
   }

   virtual void OnEvent(const PASREvent &ev) override
   {
      if(ev.id == EVENT_ID_NEW_BAR)
         OnNewBar();
   }

   virtual void OnNewBar() override
   {
      HMMObservation obs = GetCurrentObservation();
      UpdateStateProbabilities(obs);

      int new_state = GetMostProbableState();
      double confidence = m_state_probabilities[new_state];

      // Update transition matrix with online learning
      UpdateTransitionMatrix(obs, new_state);

      // Check for state change
      if(new_state != m_current_state)
      {
         m_regime_streak = 0;
         m_last_state_change = TimeCurrent();
         m_current_state = new_state;
      }
      else
      {
         m_regime_streak++;
      }

      m_regime_confidence = confidence;
      AddToHistory(obs, new_state);

      if(m_debugMode && confidence > 0.6)
         PrintFormat("[HMMRegimeDetector] State: %s Conf: %.2f%% Streak: %d",
                   EnumToString(HMMStateToRegime(new_state)), confidence * 100, m_regime_streak);
   }

   EMarketRegime GetCurrentRegime() const
   {
      return HMMStateToRegime(m_current_state);
   }

   double GetRegimeConfidence() const { return m_regime_confidence; }

   int GetRegimeStreak() const { return m_regime_streak; }

   double GetStateProbability(int state) const
   {
      if(state >= 0 && state < HMM_NUM_STATES)
         return m_state_probabilities[state];
      return 0.0;
   }

   bool IsRegimeStable(int minStreak = 3) const
   {
      return (m_regime_streak >= minStreak && m_regime_confidence > 0.6);
   }
};

#endif // __ANALYSIS_HMM_REGIME_DETECTOR_MQH__
