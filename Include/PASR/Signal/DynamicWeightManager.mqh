//+------------------------------------------------------------------+
//| Signal/DynamicWeightManager.mqh — v1.0                            |
//| Dynamic Bayesian Network for signal fusion with adaptive weights  |
//| Replaces static weights with performance-based adaptation        |
//+------------------------------------------------------------------+
#property strict
#ifndef __SIGNAL_DYNAMIC_WEIGHT_MANAGER_MQH__
#define __SIGNAL_DYNAMIC_WEIGHT_MANAGER_MQH__

#include "../Core/IManager.mqh"
#include "../Core/PipelineTypes.mqh"

#define MAX_SIGNAL_SOURCES 10
#define WEIGHT_HISTORY_SIZE 100
#define LEARNING_RATE 0.01
#define MIN_WEIGHT 0.1
#define MAX_WEIGHT 2.0

struct SourcePerformance
{
   string sourceName;
   double totalSignals;
   double successfulSignals;
   double avgConfidence;
   double avgProfit;
   double currentWeight;
   datetime lastUpdate;

   void Reset()
   {
      sourceName = "";
      totalSignals = 0;
      successfulSignals = 0;
      avgConfidence = 0.0;
      avgProfit = 0.0;
      currentWeight = 1.0;
      lastUpdate = 0;
   }

   double GetSuccessRate() const
   {
      return (totalSignals > 0) ? successfulSignals / totalSignals : 0.5;
   }

   double GetPerformanceScore() const
   {
      double successRate = GetSuccessRate();
      double confScore = avgConfidence;
      double profitScore = (avgProfit > 0) ? MathMin(2.0, avgProfit / 100.0) : 0.0;
      return 0.4 * successRate + 0.3 * confScore + 0.3 * profitScore;
   }
};

class CDynamicWeightManager : public IManager
{
private:
    SourcePerformance m_sources[MAX_SIGNAL_SOURCES];
    int m_sourceCount;
    double m_weightHistory[];
    int m_historyHead;
    bool m_historyFilled;
   double m_learningRate;
   double m_minWeight;
   double m_maxWeight;
   datetime m_lastUpdate;

   double Clamp(double value, double minVal, double maxVal) const
   {
      return MathMax(minVal, MathMin(maxVal, value));
   }

    void SaveWeightHistory()
    {
       int baseIdx = m_historyHead * MAX_SIGNAL_SOURCES;
       for(int i = 0; i < m_sourceCount; i++)
          m_weightHistory[baseIdx + i] = m_sources[i].currentWeight;

       m_historyHead = (m_historyHead + 1) % WEIGHT_HISTORY_SIZE;
       if(!m_historyFilled && m_historyHead == 0)
          m_historyFilled = true;
    }

    double CalculateWeightedMovingAverage(int sourceIdx, int window = 20) const
    {
       if(!m_historyFilled) return m_sources[sourceIdx].currentWeight;

       double sum = 0.0;
       int count = 0;
       int actualWindow = MathMin(window, WEIGHT_HISTORY_SIZE);

       for(int i = 0; i < actualWindow; i++)
       {
          int idx = (m_historyHead - 1 - i + WEIGHT_HISTORY_SIZE) % WEIGHT_HISTORY_SIZE;
          sum += m_weightHistory[idx * MAX_SIGNAL_SOURCES + sourceIdx];
          count++;
       }

       return (count > 0) ? sum / count : m_sources[sourceIdx].currentWeight;
    }

   void NormalizeWeights()
   {
      double totalWeight = 0.0;
      for(int i = 0; i < m_sourceCount; i++)
         totalWeight += m_sources[i].currentWeight;

      if(totalWeight <= 0) return;

      // Normalize to sum to m_sourceCount (preserve average weight of 1.0)
      double scaleFactor = (double)m_sourceCount / totalWeight;
      for(int i = 0; i < m_sourceCount; i++)
         m_sources[i].currentWeight = Clamp(m_sources[i].currentWeight * scaleFactor,
                                           m_minWeight, m_maxWeight);
   }

public:
   CDynamicWeightManager()
      : IManager(), m_sourceCount(0), m_historyHead(0), m_historyFilled(false),
        m_learningRate(LEARNING_RATE), m_minWeight(MIN_WEIGHT), m_maxWeight(MAX_WEIGHT),
        m_lastUpdate(0)
   {
      ArrayResize(m_weightHistory, WEIGHT_HISTORY_SIZE * MAX_SIGNAL_SOURCES);
      ArrayInitialize(m_weightHistory, 0.0);
      for(int i = 0; i < MAX_SIGNAL_SOURCES; i++)
         m_sources[i].Reset();
   }

   virtual string HandlerName() const override { return "DynamicWeightManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
   {
      if(!IManager::Init(data, bus)) return false;
      Print("[DynamicWeightManager] Initialized with adaptive Bayesian weighting");
      return true;
   }

   virtual void Deinit() override
   {
      IManager::Deinit();
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_TRADE_OPEN);
      AddEvent(EVENT_ID_TRADE_CLOSE);
      AddEvent(EVENT_ID_NEW_BAR);
   }

   virtual void OnEvent(const PASREvent &ev) override
   {
      if(ev.id == EVENT_ID_NEW_BAR)
      {
         UpdateWeights();
      }
      else if(ev.id == EVENT_ID_TRADE_CLOSE)
      {
         // Update performance based on trade result
         UpdatePerformance(ev.comment, ev.profit > 0);
      }
   }

   int RegisterSource(const string sourceName, double initialWeight = 1.0)
   {
      if(m_sourceCount >= MAX_SIGNAL_SOURCES) return -1;

      m_sources[m_sourceCount].sourceName = sourceName;
      m_sources[m_sourceCount].currentWeight = Clamp(initialWeight, m_minWeight, m_maxWeight);
      m_sources[m_sourceCount].lastUpdate = TimeCurrent();

      if(m_debugMode)
         PrintFormat("[DynamicWeightManager] Registered source: %s with weight %.2f",
                     sourceName, initialWeight);

      return m_sourceCount++;
   }

   bool UpdateSourcePerformance(const string sourceName, bool success, double confidence = 0.5, double profit = 0.0)
   {
      for(int i = 0; i < m_sourceCount; i++)
      {
         if(m_sources[i].sourceName == sourceName)
         {
            m_sources[i].totalSignals++;
            if(success) m_sources[i].successfulSignals++;

            // Exponential moving average for confidence and profit
            double alpha = 0.1;
            m_sources[i].avgConfidence = alpha * confidence + (1 - alpha) * m_sources[i].avgConfidence;
            m_sources[i].avgProfit = alpha * profit + (1 - alpha) * m_sources[i].avgProfit;

            m_sources[i].lastUpdate = TimeCurrent();
            return true;
         }
      }
      return false;
   }

   void UpdateWeights()
   {
      datetime now = TimeCurrent();
      if(now - m_lastUpdate < 60) return; // Update every minute at most
      m_lastUpdate = now;

      for(int i = 0; i < m_sourceCount; i++)
      {
         if(m_sources[i].totalSignals < 5) continue; // Need minimum samples

         double perfScore = m_sources[i].GetPerformanceScore();
         double targetWeight = 1.0 + (perfScore - 0.5) * 2.0; // Scale around 1.0

         // Apply learning rate for smooth adaptation
         m_sources[i].currentWeight = m_learningRate * targetWeight +
                                      (1 - m_learningRate) * m_sources[i].currentWeight;

         // Apply smoothing with moving average
         double smoothedWeight = CalculateWeightedMovingAverage(i);
         m_sources[i].currentWeight = 0.7 * m_sources[i].currentWeight + 0.3 * smoothedWeight;

         // Clamp to valid range
         m_sources[i].currentWeight = Clamp(m_sources[i].currentWeight, m_minWeight, m_maxWeight);
      }

      NormalizeWeights();
      SaveWeightHistory();

      if(m_debugMode)
         PrintWeightStatus();
   }

   void UpdatePerformance(const string signalSource, bool wasProfitable)
   {
      // Parse signal source from comment (format: "AI_PRIMARY:...|Pattern:...")
      string parts[];
      StringSplit(signalSource, '|', parts);

      for(int i = 0; i < ArraySize(parts); i++)
      {
         string sourceName = parts[i];
         // Extract source name (remove confidence scores etc)
         int colonPos = StringFind(sourceName, ":");
         if(colonPos > 0)
            sourceName = StringSubstr(sourceName, 0, colonPos);

         UpdateSourcePerformance(sourceName, wasProfitable);
      }
   }

   double GetSourceWeight(const string sourceName) const
   {
      for(int i = 0; i < m_sourceCount; i++)
      {
         if(m_sources[i].sourceName == sourceName)
            return m_sources[i].currentWeight;
      }
      return 1.0; // Default weight
   }

   double GetSourceWeight(int index) const
   {
      if(index >= 0 && index < m_sourceCount)
         return m_sources[index].currentWeight;
      return 1.0;
   }

   SourcePerformance GetSourcePerformance(const string sourceName) const
   {
      for(int i = 0; i < m_sourceCount; i++)
      {
         if(m_sources[i].sourceName == sourceName)
            return m_sources[i];
      }
      SourcePerformance empty;
      empty.Reset();
      return empty;
   }

   void PrintWeightStatus() const
   {
      string output = "[DynamicWeightManager] Weights: ";
      for(int i = 0; i < m_sourceCount; i++)
      {
         output += StringFormat("%s=%.2f(%.1f%%) ",
                               m_sources[i].sourceName,
                               m_sources[i].currentWeight,
                               m_sources[i].GetSuccessRate() * 100);
      }
      Print(output);
   }

   int GetSourceCount() const { return m_sourceCount; }

   void Reset()
   {
      m_sourceCount = 0;
      m_historyHead = 0;
      m_historyFilled = false;
      for(int i = 0; i < MAX_SIGNAL_SOURCES; i++)
         m_sources[i].Reset();
      ArrayInitialize(m_weightHistory, 0.0);
   }
};

#endif // __SIGNAL_DYNAMIC_WEIGHT_MANAGER_MQH__
