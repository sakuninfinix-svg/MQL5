//+------------------------------------------------------------------+
//|                                               AIOrchestrator.mqh |
//|   IManager subclass — event wiring, model persistence, dispatch  |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property version   "3.00"
#property strict

#ifndef __AI_ORCHESTRATOR_MQH__
#define __AI_ORCHESTRATOR_MQH__

#include "AITypes.mqh"
#include "AIFeatureBuilder.mqh"
#include "AIInference.mqh"
#include "AITrainer.mqh"
#include "../IManager.mqh"
#include "../10.DataManager.mqh"
#include "../12.MarketRegime.mqh"

class AIOrchestrator : public IManager
{
private:
   AIModelState      m_model;
   AIFeatureBuilder  m_features;
   AIInference       m_inference;
   AITrainer         m_trainer;

   MarketRegimeFilter *m_regime;     // non-owning
   AISignalSample     m_samples[];   // pending labeled samples
   int                m_sampleCount;
   datetime           m_lastHeartbeat;
   double             m_lastSavedWinRate;
   bool               m_modelDirty;
   string             m_datasetFile;
   string             m_ticketFile;
   string             m_outcomeFile;
   int                m_loggedSamples;
   int                m_labeledSince;

   string GVPrefix() const
   { return "PASR_AI_" + IntegerToString(Config().magic) + "_" + _Symbol + "_"; }

   void SaveModel()
   {
      string p = GVPrefix();
      GlobalVariableSet(p+"bias",         m_model.bias);
      GlobalVariableSet(p+"atr",          m_model.atrWeight);
      GlobalVariableSet(p+"spread",       m_model.spreadWeight);
      GlobalVariableSet(p+"sl",           m_model.slWeight);
      GlobalVariableSet(p+"momentum",     m_model.momentumWeight);
      GlobalVariableSet(p+"loss",         m_model.lossStreakWeight);
      GlobalVariableSet(p+"volnoise",     m_model.volNoiseWeight);
      GlobalVariableSet(p+"regimescore",  m_model.regimeScoreWeight);
      GlobalVariableSet(p+"timeofday",    m_model.timeOfDayWeight);
      GlobalVariableSet(p+"mtconfluence", m_model.mtConfluenceWeight);
      GlobalVariableSet(p+"volume",       m_model.volumeWeight);
      GlobalVariableSet(p+"trendexpert",    m_model.trendExpertWeight);
      GlobalVariableSet(p+"meanrevexpert",  m_model.meanRevExpertWeight);
      GlobalVariableSet(p+"momentumexpert", m_model.momentumExpertWeight);
      GlobalVariableSet(p+"recentwr",     m_model.recentWinRate);
      GlobalVariableSet(p+"longtermwr",   m_model.longTermWinRate);
      for(int i=0;i<NN_INPUTS;i++) for(int j=0;j<NN_H1;j++)
         GlobalVariableSet(p+"h1w_"+IntegerToString(i)+"_"+IntegerToString(j), m_model.h1w[i][j]);
      for(int j=0;j<NN_H1;j++) GlobalVariableSet(p+"h1b_"+IntegerToString(j), m_model.h1b[j]);
      for(int i=0;i<NN_H1;i++) for(int j=0;j<NN_H2;j++)
         GlobalVariableSet(p+"h2w_"+IntegerToString(i)+"_"+IntegerToString(j), m_model.h2w[i][j]);
      for(int j=0;j<NN_H2;j++) GlobalVariableSet(p+"h2b_"+IntegerToString(j), m_model.h2b[j]);
      for(int j=0;j<NN_H2;j++) GlobalVariableSet(p+"ow_"+IntegerToString(j), m_model.ow[j]);
      GlobalVariableSet(p+"ob",      m_model.ob);
      GlobalVariableSet(p+"plattA",  m_model.plattA);
      GlobalVariableSet(p+"plattB",  m_model.plattB);
      GlobalVariableSet(p+"plattS",  (double)m_model.plattSamples);
      GlobalVariableSet(p+"nn_lr",   m_model.nnLearningRate);
      GlobalVariableSet(p+"nn_ts",   (double)m_model.nnTrainingSamples);
      GlobalVariableSet(p+"nn_rb",   (double)m_model.replayTrainCount);
      m_modelDirty = false;
   }

   void LoadModel()
   {
      string p = GVPrefix();
      if(GlobalVariableCheck(p+"bias"))         m_model.bias              = GlobalVariableGet(p+"bias");
      if(GlobalVariableCheck(p+"atr"))          m_model.atrWeight         = GlobalVariableGet(p+"atr");
      if(GlobalVariableCheck(p+"spread"))       m_model.spreadWeight      = GlobalVariableGet(p+"spread");
      if(GlobalVariableCheck(p+"sl"))           m_model.slWeight          = GlobalVariableGet(p+"sl");
      if(GlobalVariableCheck(p+"momentum"))     m_model.momentumWeight    = GlobalVariableGet(p+"momentum");
      if(GlobalVariableCheck(p+"loss"))         m_model.lossStreakWeight  = GlobalVariableGet(p+"loss");
      if(GlobalVariableCheck(p+"volnoise"))     m_model.volNoiseWeight    = GlobalVariableGet(p+"volnoise");
      if(GlobalVariableCheck(p+"regimescore"))  m_model.regimeScoreWeight = GlobalVariableGet(p+"regimescore");
      if(GlobalVariableCheck(p+"timeofday"))    m_model.timeOfDayWeight   = GlobalVariableGet(p+"timeofday");
      if(GlobalVariableCheck(p+"mtconfluence")) m_model.mtConfluenceWeight= GlobalVariableGet(p+"mtconfluence");
      if(GlobalVariableCheck(p+"volume"))       m_model.volumeWeight      = GlobalVariableGet(p+"volume");
      if(GlobalVariableCheck(p+"trendexpert"))     m_model.trendExpertWeight    = GlobalVariableGet(p+"trendexpert");
      if(GlobalVariableCheck(p+"meanrevexpert"))   m_model.meanRevExpertWeight  = GlobalVariableGet(p+"meanrevexpert");
      if(GlobalVariableCheck(p+"momentumexpert"))  m_model.momentumExpertWeight = GlobalVariableGet(p+"momentumexpert");
      if(GlobalVariableCheck(p+"recentwr"))     m_model.recentWinRate     = GlobalVariableGet(p+"recentwr");
      if(GlobalVariableCheck(p+"longtermwr"))   m_model.longTermWinRate   = GlobalVariableGet(p+"longtermwr");
      for(int i=0;i<NN_INPUTS;i++) for(int j=0;j<NN_H1;j++)
      { string k=p+"h1w_"+IntegerToString(i)+"_"+IntegerToString(j); if(GlobalVariableCheck(k)) m_model.h1w[i][j]=GlobalVariableGet(k); }
      for(int j=0;j<NN_H1;j++) { string k=p+"h1b_"+IntegerToString(j); if(GlobalVariableCheck(k)) m_model.h1b[j]=GlobalVariableGet(k); }
      for(int i=0;i<NN_H1;i++) for(int j=0;j<NN_H2;j++)
      { string k=p+"h2w_"+IntegerToString(i)+"_"+IntegerToString(j); if(GlobalVariableCheck(k)) m_model.h2w[i][j]=GlobalVariableGet(k); }
      for(int j=0;j<NN_H2;j++) { string k=p+"h2b_"+IntegerToString(j); if(GlobalVariableCheck(k)) m_model.h2b[j]=GlobalVariableGet(k); }
      for(int j=0;j<NN_H2;j++) { string k=p+"ow_"+IntegerToString(j);  if(GlobalVariableCheck(k)) m_model.ow[j] =GlobalVariableGet(k); }
      if(GlobalVariableCheck(p+"ob"))     m_model.ob                = GlobalVariableGet(p+"ob");
      if(GlobalVariableCheck(p+"plattA")) m_model.plattA            = GlobalVariableGet(p+"plattA");
      if(GlobalVariableCheck(p+"plattB")) m_model.plattB            = GlobalVariableGet(p+"plattB");
      if(GlobalVariableCheck(p+"plattS")) m_model.plattSamples      = (int)GlobalVariableGet(p+"plattS");
      if(GlobalVariableCheck(p+"nn_lr"))  m_model.nnLearningRate    = GlobalVariableGet(p+"nn_lr");
      if(GlobalVariableCheck(p+"nn_ts"))  m_model.nnTrainingSamples = (int)GlobalVariableGet(p+"nn_ts");
      if(GlobalVariableCheck(p+"nn_rb"))  m_model.replayTrainCount  = (int)GlobalVariableGet(p+"nn_rb");
      m_model.initialized = true;
      Log("Model loaded. NN samples=" + IntegerToString(m_model.nnTrainingSamples)
          + " batches=" + IntegerToString(m_model.replayTrainCount));
   }

   void AdaptToPerformance()
   {
      if(CheckPointer(m_data) == POINTER_INVALID) return;
      PerformanceStats stats = m_data.GetPerformanceStats();
      int total = stats.safeTotal + stats.aggTotal;
      if(total <= 0) return;
      double winRate = (double)(stats.safeWins + stats.aggWins) / total;
      if(m_model.recentWinRate  < 0) m_model.recentWinRate  = winRate;
      else                            m_model.recentWinRate  = m_model.recentWinRate  * 0.9  + winRate * 0.1;
      if(m_model.longTermWinRate< 0) m_model.longTermWinRate = winRate;
      else                            m_model.longTermWinRate = m_model.longTermWinRate* 0.95 + winRate * 0.05;

      bool drift = (m_model.recentWinRate >= 0 && m_model.longTermWinRate >= 0 &&
                    (m_model.longTermWinRate - m_model.recentWinRate) > 0.15);
      if(MathAbs(winRate - m_lastSavedWinRate) < 0.01 && !drift) return;

      double err = winRate - 0.50;
      m_model.bias             = MathMax(0.01, MathMin(2.0, m_model.bias             + err*0.08));
      m_model.atrWeight        = MathMax(0.01, MathMin(2.0, m_model.atrWeight        + err*0.015));
      m_model.spreadWeight     = MathMax(0.01, MathMin(2.0, m_model.spreadWeight     + err*0.015));
      m_model.slWeight         = MathMax(0.01, MathMin(2.0, m_model.slWeight         + err*0.012));
      m_model.momentumWeight   = MathMax(0.01, MathMin(2.0, m_model.momentumWeight   + err*0.01));
      m_model.regimeScoreWeight= MathMax(0.01, MathMin(2.0, m_model.regimeScoreWeight+ err*0.01));
      if(CheckPointer(m_data) != POINTER_INVALID)
         m_model.lossStreakWeight = MathMax(0.01, MathMin(2.0,
            m_model.lossStreakWeight - m_data.GetConsecutiveLosses()*0.005));

      if(drift)
      {
         Log("CONCEPT DRIFT detected. Rebalancing ensemble...");
         m_model.trendExpertWeight    = MathMax(0.01, MathMin(2.0, m_model.trendExpertWeight    + err*0.15));
         m_model.meanRevExpertWeight  = MathMax(0.01, MathMin(2.0, m_model.meanRevExpertWeight  - err*0.05));
         m_model.momentumExpertWeight = MathMax(0.01, MathMin(2.0, m_model.momentumExpertWeight + err*0.08));
         double tot = m_model.trendExpertWeight + m_model.meanRevExpertWeight + m_model.momentumExpertWeight;
         if(tot > 0) { m_model.trendExpertWeight/=tot; m_model.meanRevExpertWeight/=tot; m_model.momentumExpertWeight/=tot; }
      }

      m_lastSavedWinRate = winRate;
      m_modelDirty       = true;
      SaveModel();
      Log("AI adapted winRate=" + DoubleToString(winRate, 2) + (drift ? " [DRIFT]" : ""));
   }

   void DecayWeights(double decay)
   {
      double d = MathMax(0.9, MathMin(1.0, decay));
      m_model.atrWeight          = MathMax(0.01, MathMin(2.0, m_model.atrWeight         *d));
      m_model.spreadWeight       = MathMax(0.01, MathMin(2.0, m_model.spreadWeight      *d));
      m_model.slWeight           = MathMax(0.01, MathMin(2.0, m_model.slWeight          *d));
      m_model.momentumWeight     = MathMax(0.01, MathMin(2.0, m_model.momentumWeight    *d));
      m_model.lossStreakWeight   = MathMax(0.01, MathMin(2.0, m_model.lossStreakWeight  *d));
      m_model.regimeScoreWeight  = MathMax(0.01, MathMin(2.0, m_model.regimeScoreWeight *d));
      m_model.timeOfDayWeight    = MathMax(0.01, MathMin(2.0, m_model.timeOfDayWeight   *d));
      m_model.mtConfluenceWeight = MathMax(0.01, MathMin(2.0, m_model.mtConfluenceWeight*d));
      m_model.volumeWeight       = MathMax(0.01, MathMin(2.0, m_model.volumeWeight      *d));
   }

public:
   AIOrchestrator() : IManager("AIManager", 35),
      m_regime(NULL), m_sampleCount(0),
      m_lastHeartbeat(0), m_lastSavedWinRate(-1.0),
      m_modelDirty(false), m_loggedSamples(0), m_labeledSince(0)
   {
      m_model.InitWeights();
      ArrayResize(m_samples, 0);
   }

   void SetRegimeFilter(MarketRegimeFilter *r)
   {
      m_regime = r;
      m_features.SetRegime(r);
      m_inference.SetRegime(r);
      Log("MarketRegimeFilter injected.");
   }
   MarketRegimeFilter* GetRegimeFilter() const { return m_regime; }

   virtual bool Init() override
   {
      if(!IManager::Init()) return false;
      if(CheckPointer(m_data) == POINTER_INVALID)
      { Log("CRITICAL: DataManager NULL"); return false; }
      if(CheckPointer(m_regime) == POINTER_INVALID)
         Log("WARNING: MarketRegimeFilter not injected.");

      m_features.SetData(m_data);
      m_trainer.SetModel(&m_model);
      m_trainer.SetData(m_data);

      string prefix     = "AI_ml_" + IntegerToString(Config().magic) + "_" + _Symbol + "_";
      m_datasetFile     = prefix + "data.csv";
      m_ticketFile      = prefix + "ticketmap.csv";
      m_outcomeFile     = prefix + "outcomes.csv";
      m_trainer.SetFiles(m_outcomeFile, m_ticketFile);

      LoadModel();
      Log("AIManager v3.00 ready. NN samples: " + IntegerToString(m_model.nnTrainingSamples)
          + " | Replay: " + IntegerToString(m_trainer.GetReplayCount()));
      return true;
   }

   virtual void DeclareEvents() override
   {
      AddEvent(EVENT_ID_SIGNAL_GENERATED);
      AddEvent(EVENT_ID_ORDER_EXECUTION);
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_HEARTBEAT);
      AddEvent(EVENT_ID_CONFIG_RELOAD);
      AddEvent(EVENT_ID_POSITION_UPDATE);
   }

   virtual void OnNewBar(NewBarEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      if(!Config().ai.use) return;
      if(CheckPointer(m_regime) != POINTER_INVALID) m_regime.Update();
      m_features.RefreshCache();
      DecayWeights(0.995);
   }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID) return;
      if(!Config().ai.use) return;
      if(TimeCurrent() - m_lastHeartbeat < 5) return;
      m_lastHeartbeat = TimeCurrent();
      m_features.RefreshCache();
      AdaptToPerformance();
      // AI-ARCH-2: dispatch training as background event (non-blocking)
      if(m_trainer.ShouldTrain())
      {
         TrainBatchEvent *job = new TrainBatchEvent();
         job.priority = PRIORITY_BACKGROUND;
         DispatchEvent(job);
      }
   }

   virtual void OnTrainBatch(TrainBatchEvent *e) override
   {
      // Runs in background queue — safe to block here
      if(CheckPointer(e) == POINTER_INVALID) return;
      if(!Config().ai.use) return;
      m_trainer.TrainMiniBatch();
      m_modelDirty = true;
      SaveModel();
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !Config().ai.use || !e.signal.valid) return;
      m_features.RefreshCache();

      EvalContext ctx;
      m_features.Build(ctx, e.signal, e.atrPoints, e.support, e.resistance);

      double score     = m_inference.Evaluate(m_model, ctx, e.signal, Config().ai.patternBonus);
      double threshold = m_inference.AdaptiveThreshold(Config().ai.minConfidence);
      bool   accepted  = score >= threshold;

      Log("AI score=" + DoubleToString(score, 2) + " threshold=" + DoubleToString(threshold, 2)
          + " replay=" + IntegerToString(m_trainer.GetReplayCount()));

      // Register sample for future labeling
      m_loggedSamples++;
      if(m_sampleCount >= ArraySize(m_samples)) ArrayResize(m_samples, m_sampleCount + 1);
      AISignalSample &s = m_samples[m_sampleCount];
      s.sampleId=IntegerToString(m_loggedSamples)+"_"+IntegerToString((int)TimeCurrent());
      s.ticket=0; s.timestamp=TimeCurrent(); s.accepted=accepted; s.labeled=false;
      s.atrPoints=e.atrPoints; s.support=e.support; s.resistance=e.resistance;
      s.signal=e.signal;
      s.features[0]=ctx.atrNorm; s.features[1]=ctx.regimeScore;
      s.features[2]=ctx.mtConfluenceNorm; s.features[3]=ctx.rsiNorm;
      s.features[4]=ctx.candleBodyRatio;  s.features[5]=ctx.emaDistNorm;
      s.features[6]=ctx.sessionNorm;      s.features[7]=ctx.momentumNorm;
      if(m_sampleCount < 64) m_sampleCount++; else { ArrayRemove(m_samples, 0); }

      if(!accepted)
      { e.signal.valid=false; e.signal.reason+= " | AI_REJECT("+DoubleToString(score,2)+")"; return; }
      double slAdj = 1.0 + (1.0/(1.0+MathExp(-score)) * m_model.volNoiseWeight);
      e.signal.reason    += " | AI_ACCEPT(" + DoubleToString(score,2) + ") SL_ADJ:" + DoubleToString(slAdj,2);
      e.signal.slMultiplier *= slAdj;
   }

   virtual void OnOrderExecution(OrderExecutionEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !Config().ai.use) return;
      if(e.success) m_trainer.AttachTicket(e.ticket, m_samples, m_sampleCount);
      else { m_model.bias = MathMax(0.25, m_model.bias - 0.01); m_modelDirty = true; }
      SaveModel();
   }

   virtual void OnPositionUpdate(PositionUpdateEvent *e) override
   {
      if(CheckPointer(e) == POINTER_INVALID || !Config().ai.use) return;
      if(e.isClosing) { m_trainer.LabelOutcome(e.ticket, e.unrealizedPnL, m_samples, m_sampleCount); return; }
      if(e.unrealizedPnL < 0) { m_model.bias = MathMax(0.25, m_model.bias - 0.002); m_modelDirty = true; }
      else if(e.unrealizedPnL > 0) { m_model.bias = MathMin(0.85, m_model.bias + 0.002); m_modelDirty = true; }
   }

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   { IManager::OnConfigReload(e); LoadModel(); }

   // Public accessors for dashboard
   int    GetNNTrainingSamples() const { return m_model.nnTrainingSamples; }
   double GetNNLearningRate()    const { return m_model.nnLearningRate; }
   int    GetReplayCount()       const { return m_trainer.GetReplayCount(); }
   int    GetReplayTrainCount()  const { return m_model.replayTrainCount; }
   double GetPlattA()            const { return m_model.plattA; }
   double GetPlattB()            const { return m_model.plattB; }
   ExpertType GetActiveExpert()  const { return m_inference.SelectExpert(); }
};

// Backward-compatible alias — existing EAs using AIManager continue to compile
typedef AIOrchestrator AIManager;

#endif // __AI_ORCHESTRATOR_MQH__
