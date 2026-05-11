//+------------------------------------------------------------------+
//|                                                   AIManager.mqh  |
//|               Lightweight Adaptive AI Layer for PASR EA          |
//|                          Copyright 2026, Agsicentre              |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"
#property link "agsicentre.wordpress.com"
#property copyright "Copyright 2026, Agsicentre"

#ifndef __AI_MANAGER_MQH__
#define __AI_MANAGER_MQH__

#include "mql5_vscode_fix.h"
#include "2.Config.mqh"
#include "IManager.mqh"
#include "10.DataManager.mqh"

//+------------------------------------------------------------------+
//| AIManager - Enhances signal quality through adaptive scoring      |
//| Utilizes lightweight feature scoring and dynamic model feedback   |
//+------------------------------------------------------------------+
class AIManager : public IManager
{
private:
   struct AIConfigCache
   {
      bool useAI;
      int trainingWindowBars;
      double minConfidence;
      double modelDecay;
      double patternBonus;
   } m_cfgCache;

   struct AIModelState
   {
      double bias;
      double atrWeight;
      double spreadWeight;
      double slWeight;
      double momentumWeight;
      double lossStreakWeight;
      double volNoiseWeight;
   } m_model;

   int m_lastHeartbeat;
   double m_lastSavedWinRate;
   bool m_modelDirty;
   string m_datasetFilename;
   string m_ticketMapFilename;
   string m_outcomeFilename;
   int m_loggedSamples;

   struct AISignalSample
   {
      string sampleId;
      ulong ticket;
      datetime timestamp;
      bool accepted;
      bool labeled;
   } m_pendingSamples[];

public:
   AIManager() : IManager("AIManager", 35), m_lastHeartbeat(0), m_lastSavedWinRate(-1.0), m_modelDirty(false), m_datasetFilename(""), m_ticketMapFilename(""), m_outcomeFilename(""), m_loggedSamples(0)
   {
      m_model.bias = 0.55;
      m_model.atrWeight = 0.18;
      m_model.spreadWeight = 0.14;
      m_model.slWeight = 0.16;
      m_model.momentumWeight = 0.08;
      m_model.lossStreakWeight = 0.06;
      m_model.volNoiseWeight = 0.12;
   }

   virtual void RefreshConfigCache() override
   {
      IManager::RefreshConfigCache();
      m_cfgCache.useAI = CFG.ai.use;
      m_cfgCache.trainingWindowBars = CFG.ai.trainingWindow;
      m_cfgCache.minConfidence = CFG.ai.minConfidence;
      m_cfgCache.modelDecay = 0.98;
      m_cfgCache.patternBonus = CFG.ai.patternBonus;
   }

   virtual bool Init() override
   {
      if (!IManager::Init())
         return false;
      
      m_data = IManager::GetGlobalDataManager();
      string prefix = "AI_ml_" + (string)CFG.risk.magic + "_" + _Symbol + "_";
      m_datasetFilename = prefix + "data.csv";
      m_ticketMapFilename = prefix + "ticketmap.csv";
      m_outcomeFilename = prefix + "outcomes.csv";
      LoadModelState();
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

   virtual void OnConfigReload(ConfigReloadEvent *e) override
   {
      IManager::OnConfigReload(e);
      RefreshConfigCache();
      LoadModelState();
   }

   virtual void OnNewBar(NewBarEvent *e) override
   {
      if (!m_cfgCache.useAI)
         return;
      DecayModel();
   }

   virtual void OnHeartbeat(HeartbeatEvent *e) override
   {
      if (!m_cfgCache.useAI)
         return;
      if (TimeCurrent() - m_lastHeartbeat < 5)
         return;
      m_lastHeartbeat = TimeCurrent();
      AdaptModelToPerformance();
   }

   virtual void OnSignalGenerated(SignalGeneratedEvent *e) override
   {
      if (!m_cfgCache.useAI || !e.signal.valid)
         return;

      double score = EvaluateSignal(e.signal, e.atrPoints, e.support, e.resistance);
      
      // Prediksi Adaptive Multiplier untuk SL (1.0 - 2.0)
      double aiSlAdjustment = 1.0 + (Logistic(score) * m_model.volNoiseWeight);
      
      bool accepted = score >= m_cfgCache.minConfidence;
      Log("AI score=" + DoubleToString(score, 2) + " for signal " + IntegerToString((int)e->signal.patternType));
      LogSignalSample(e->signal, e->atrPoints, e->support, e->resistance, score, accepted);

      if (!accepted)
      {
         e->signal.valid = false;
         e->signal.reason = e->signal.reason + " | AI_REJECT(" + DoubleToString(score, 2) + ")";
         Log("Signal rejected by AI, score=" + DoubleToString(score, 2));
         return;
      }

      e->signal.reason = e->signal.reason + " | AI_ACCEPT(" + DoubleToString(score, 2) + ") SL_ADJ:" + DoubleToString(aiSlAdjustment, 2);
      e->signal.slMultiplier *= aiSlAdjustment; // Terapkan penyesuaian AI ke SL
      Log("Signal accepted by AI, score=" + DoubleToString(score, 2));
   }

   virtual void OnOrderExecution(OrderExecutionEvent *e) override
   {
      if (!m_cfgCache.useAI)
         return;
      if (e->success)
      {
         AttachTicketToRecentSample(e->ticket);
      }
      else
      {
         m_model.bias = NormalizeWeight(m_model.bias - 0.01);
         m_modelDirty = true;
         Log("Order execution failed, reducing bias.");
      }
      SaveModelState();
   }

   virtual void OnPositionUpdate(PositionUpdateEvent *e) override
   {
      if (!m_cfgCache.useAI)
         return;
      if (e->isClosing)
      {
         LabelSampleOutcome(e->ticket, e->unrealizedPnL);
         return;
      }

      if (e->unrealizedPnL < 0)
      {
         m_model.bias = MathMax(0.25, m_model.bias - 0.002);
         m_modelDirty = true;
      }
      else if (e->unrealizedPnL > 0)
      {
         m_model.bias = MathMin(0.85, m_model.bias + 0.002);
         m_modelDirty = true;
      }
   }

private:
   double EvaluateSignal(const SignalDecision &signal, const double atrPoints,
                         const double support, const double resistance) const
   {
      double rawScore = m_model.bias;
      rawScore += m_model.atrWeight * NormalizeATRFeature(atrPoints);
      rawScore += m_model.spreadWeight * NormalizeSpreadFeature();
      rawScore += m_model.slWeight * NormalizeSLFeature(signal.slMultiplier);
      rawScore += m_model.momentumWeight * NormalizeZoneFeature(signal.zonePrice, support, resistance);
      rawScore += m_model.lossStreakWeight * NormalizeLossStreak();

      if (signal.patternType != PATTERN_NONE)
         rawScore += m_cfgCache.patternBonus;

      return Logistic(rawScore);
   }

   double NormalizeATRFeature(double atrPoints) const
   {
      if (atrPoints <= 0)
         return 0.0;
      return MathMin(1.0, atrPoints / 20.0);
   }

   double NormalizeSpreadFeature() const
   {
      double spreadPoints = SymbolInfoDouble(_Symbol, SYMBOL_SPREAD);
      if (spreadPoints <= 0)
         return 1.0;
      double normalized = 1.0 - MathMin(1.0, spreadPoints / 10.0);
      return MathMax(0.0, normalized);
   }

   double NormalizeSLFeature(double slMultiplier) const
   {
      if (slMultiplier <= 0)
         return 0.0;
      return MathMin(1.0, slMultiplier / 3.0);
   }

   double NormalizeZoneFeature(double zonePrice, double support, double resistance) const
   {
      double distance = MathAbs(zonePrice - (support + resistance) / 2.0);
      double range = MathMax(1.0, MathAbs(resistance - support));
      return 1.0 - MathMin(1.0, distance / range);
   }

   double NormalizeNoiseFeature() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      // Sesi transisi (London Open) biasanya punya noise tinggi
      if(dt.hour == 8 || dt.hour == 13) return 1.0; 
      return 0.2;
   }

   double NormalizeLossStreak() const
   {
      if (CheckPointer(m_data) == POINTER_INVALID || m_data == NULL)
         return 0.0;
      int losses = m_data->GetConsecutiveLosses();
      return MathMax(0.0, 1.0 - MathMin(1.0, losses * 0.1));
   }

   double Logistic(double x) const
   {
      return 1.0 / (1.0 + MathExp(-x));
   }

   string ModelGVPrefix() const
   {
      return "PASR_AI_" + (string)CFG.risk.magic + "_" + _Symbol + "_";
   }

   void LoadModelState()
   {
      string prefix = ModelGVPrefix();
      if (GlobalVariableCheck(prefix + "bias"))
         m_model.bias = GlobalVariableGet(prefix + "bias");
      if (GlobalVariableCheck(prefix + "atr"))
         m_model.atrWeight = GlobalVariableGet(prefix + "atr");
      if (GlobalVariableCheck(prefix + "spread"))
         m_model.spreadWeight = GlobalVariableGet(prefix + "spread");
      if (GlobalVariableCheck(prefix + "sl"))
         m_model.slWeight = GlobalVariableGet(prefix + "sl");
      if (GlobalVariableCheck(prefix + "momentum"))
         m_model.momentumWeight = GlobalVariableGet(prefix + "momentum");
      if (GlobalVariableCheck(prefix + "loss"))
         m_model.lossStreakWeight = GlobalVariableGet(prefix + "loss");
      m_lastSavedWinRate = -1.0;
      m_modelDirty = true;
      SaveModelState();
   }

   void SaveModelState()
   {
      string prefix = ModelGVPrefix();
      GlobalVariableSet(prefix + "bias", m_model.bias);
      GlobalVariableSet(prefix + "atr", m_model.atrWeight);
      GlobalVariableSet(prefix + "spread", m_model.spreadWeight);
      GlobalVariableSet(prefix + "sl", m_model.slWeight);
      GlobalVariableSet(prefix + "momentum", m_model.momentumWeight);
      GlobalVariableSet(prefix + "loss", m_model.lossStreakWeight);
      m_modelDirty = false;
   }

   string CreateSampleId() const
   {
      return "S" + IntegerToString(m_loggedSamples + 1) + "_" + IntegerToString((int)TimeCurrent());
   }

   void RegisterPendingSample(const string &sampleId, bool accepted)
   {
      AISignalSample sample;
      sample.sampleId = sampleId;
      sample.ticket = 0;
      sample.timestamp = TimeCurrent();
      sample.accepted = accepted;
      sample.labeled = false;

      int size = ArraySize(m_pendingSamples);
      ArrayResize(m_pendingSamples, size + 1);
      m_pendingSamples[size] = sample;

      while (ArraySize(m_pendingSamples) > 48)
      {
         ArrayRemove(m_pendingSamples, 0);
      }
   }

   int FindRecentPendingSampleIndex() const
   {
      for (int i = ArraySize(m_pendingSamples) - 1; i >= 0; --i)
      {
         if (m_pendingSamples[i].ticket == 0 && !m_pendingSamples[i].labeled && TimeCurrent() - m_pendingSamples[i].timestamp <= 15)
            return i;
      }
      return -1;
   }

   int FindPendingSampleIndexByTicket(ulong ticket) const
   {
      for (int i = ArraySize(m_pendingSamples) - 1; i >= 0; --i)
      {
         if (m_pendingSamples[i].ticket == ticket)
            return i;
      }
      return -1;
   }

   void AttachTicketToRecentSample(ulong ticket)
   {
      int index = FindRecentPendingSampleIndex();
      if (index < 0)
         return;

      m_pendingSamples[index].ticket = ticket;
      AppendCsvRow(m_ticketMapFilename, "sample_id", "ticket", "accepted", "attached_time",
                   m_pendingSamples[index].sampleId,
                   IntegerToString((int)ticket),
                   m_pendingSamples[index].accepted ? "1" : "0",
                   TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   }

   void LabelSampleOutcome(ulong ticket, double pnl)
   {
      int index = FindPendingSampleIndexByTicket(ticket);
      if (index < 0 || m_pendingSamples[index].labeled)
         return;

      m_pendingSamples[index].labeled = true;
      AppendCsvRow(m_outcomeFilename, "sample_id", "ticket", "pnl", "label_time",
                   m_pendingSamples[index].sampleId,
                   IntegerToString((int)ticket),
                   DoubleToString(pnl, 2),
                   TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   }

   void AppendCsvRow(const string &filename, const string &h1, const string &h2, const string &h3, const string &h4,
                     const string &v1, const string &v2, const string &v3, const string &v4)
   {
      int handle = FileOpen(filename, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
      if (handle == INVALID_HANDLE)
         return;
      FileSeek(handle, 0, SEEK_END);
      if (FileTell(handle) == 0)
      {
         FileWrite(handle, h1, h2, h3, h4);
      }
      FileWrite(handle, v1, v2, v3, v4);
      FileClose(handle);
   }

   void LogSignalSample(const SignalDecision &signal, double atrPoints, double support, double resistance, double score, bool accepted)
   {
      string sampleId = CreateSampleId();
      string zoneStrength = DoubleToString(NormalizeZoneFeature(signal.zonePrice, support, resistance), 2);
      string filepath = m_datasetFilename;
      int handle = FileOpen(filepath, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
      if (handle == INVALID_HANDLE)
         return;

      FileSeek(handle, 0, SEEK_END);
      if (FileTell(handle) == 0)
      {
         FileWrite(handle, "sample_id", "time", "symbol", "pattern", "bias", "atr", "spread", "sl_mult", "zone_conf", "loss_streak", "score", "accepted");
      }

      double spread = SymbolInfoDouble(_Symbol, SYMBOL_SPREAD);
      int losses = (CheckPointer(m_data) != POINTER_INVALID && m_data != NULL) ? m_data.GetConsecutiveLosses() : 0;
      FileWrite(handle,
                sampleId,
                TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                _Symbol,
                IntegerToString((int)signal.patternType),
                DoubleToString(m_model.bias, 3),
                DoubleToString(atrPoints, 2),
                DoubleToString(spread, 2),
                DoubleToString(signal.slMultiplier, 2),
                zoneStrength,
                losses,
                DoubleToString(score, 4),
                accepted ? "1" : "0");
      FileClose(handle);
      m_loggedSamples++;
      RegisterPendingSample(sampleId, accepted);
   }

   void AdaptModelToPerformance()
   {
      if (CheckPointer(m_data) == POINTER_INVALID || m_data == NULL)
         return;

      PerformanceStats stats = m_data->GetPerformanceStats();
      int total = stats.safeTotal + stats.aggTotal;
      if (total <= 0)
         return;

      double winRate = (double)(stats.safeWins + stats.aggWins) / total;
      if (MathAbs(winRate - m_lastSavedWinRate) < 0.01)
         return;

      double error = winRate - 0.50;
      m_model.bias = NormalizeWeight(m_model.bias + error * 0.08);
      m_model.atrWeight = NormalizeWeight(m_model.atrWeight + error * 0.015);
      m_model.spreadWeight = NormalizeWeight(m_model.spreadWeight + error * 0.015);
      m_model.slWeight = NormalizeWeight(m_model.slWeight + error * 0.012);
      m_model.momentumWeight = NormalizeWeight(m_model.momentumWeight + error * 0.01);
      m_model.lossStreakWeight = NormalizeWeight(m_model.lossStreakWeight - (m_data->GetConsecutiveLosses() * 0.005));

      m_lastSavedWinRate = winRate;
      m_modelDirty = true;
      SaveModelState();
      Log("AI model updated from winRate=" + DoubleToString(winRate, 2));
   }

   void DecayModel()
   {
      m_model.atrWeight = NormalizeWeight(m_model.atrWeight * m_cfgCache.modelDecay);
      m_model.spreadWeight = NormalizeWeight(m_model.spreadWeight * m_cfgCache.modelDecay);
      m_model.slWeight = NormalizeWeight(m_model.slWeight * m_cfgCache.modelDecay);
      m_model.momentumWeight = NormalizeWeight(m_model.momentumWeight * m_cfgCache.modelDecay);
      m_model.lossStreakWeight = NormalizeWeight(m_model.lossStreakWeight * m_cfgCache.modelDecay);
   }

   double NormalizeWeight(double value) const
   {
      return MathMax(0.01, MathMin(2.0, value));
   }
};

#endif // __AI_MANAGER_MQH__
