//+------------------------------------------------------------------+
//|                                                    AITrainer.mqh |
//|          Backpropagation, replay buffer, sample labeling         |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
//| v4.01 CHANGES (2026-05-21):                                      |
//| - FIX [CRITICAL]: PushReplay() was copying only NN_INPUTS (8)    |
//|   features — silently truncating F09-F25 from replay buffer.     |
//|   Now copies AI_FEATURE_DIM (26) — full feature vector stored.   |
//| - FIX [HIGH]: LabelOutcome() features copy now uses              |
//|   AI_FEATURE_DIM — replay sample always stores full 26 dims.     |
//| - FIX [MEDIUM]: snap_h2w dimensioned by NN_H1/NN_H2 constants,  |
//|   not hardcoded — safe for future layer size changes.            |
//| - Version bump: 3.01 → 4.01                                      |
//|                                                                  |
//| V3.01 FIXES (retained):                                          |
//| - AI-BUG-FIX-1 [CRITICAL]: Stale h2w gradient — snap before     |
//|   H2 update, use snap for H1 gradient computation.               |
//| - AI-BUG-FIX-2 [HIGH]: LR decay floor — cyclical reset every    |
//|   200 batches back to initial 0.01.                              |
//| - AI-BUG-FIX-3 [MEDIUM]: AppendCsvRow FileClose guaranteed.      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property version   "4.01"
#property strict

#ifndef __AI_TRAINER_MQH__
#define __AI_TRAINER_MQH__

#include "AITypes.mqh"
#include "../Core/IManager.mqh"

/// Owns replay buffer + minibatch backprop + sample outcome labeling.
/// Receives AIModelState by pointer so it can mutate weights.
class AITrainer
  {
private:
   AIModelState     *m_model;     // non-owning pointer to shared model state
   DataManager      *m_data;      // non-owning
   ReplaySample      m_buffer[REPLAY_CAPACITY];
   int               m_head;
   int               m_count;
   int               m_labeledSince;
   string            m_outcomeFile;
   string            m_ticketFile;

   double Logistic(double x) const { return 1.0 / (1.0 + MathExp(-x)); }

   // AI-BUG-FIX-3 (v3.01, retained): FileClose always reached
   void AppendCsvRow(const string filename,
                     const string h1, const string h2,
                     const string h3, const string h4,
                     const string v1, const string v2,
                     const string v3, const string v4)
     {
      int handle = FileOpen(filename, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
      if(handle == INVALID_HANDLE) return;
      FileSeek(handle, 0, SEEK_END);
      bool ok = true;
      if(FileTell(handle) == 0)
         ok = FileWrite(handle, h1, h2, h3, h4) > 0;
      if(ok)
         FileWrite(handle, v1, v2, v3, v4);
      FileClose(handle); // guaranteed
     }

public:
   AITrainer() : m_model(NULL), m_data(NULL),
                 m_head(0), m_count(0), m_labeledSince(0)
     { ZeroMemory(m_buffer); }

   void SetModel(AIModelState *model) { m_model = model; }
   void SetData(DataManager *data)    { m_data  = data; }
   void SetFiles(const string outcomeFile, const string ticketFile)
     { m_outcomeFile = outcomeFile; m_ticketFile = ticketFile; }

   int  GetReplayCount()  const { return m_count; }
   bool ShouldTrain()     const { return m_labeledSince >= MINIBATCH_SIZE
                                      && m_count >= MINIBATCH_SIZE; }

   //+----------------------------------------------------------------+
   //| PushReplay — circular buffer O(1)                              |
   //| v4.01 FIX: copy AI_FEATURE_DIM (26) dims, not NN_INPUTS (12)  |
   //| Replay buffer must store full feature vector for future        |
   //| retraining with any subset of features.                        |
   //+----------------------------------------------------------------+
   void PushReplay(const double &features[], double label)
     {
      int n = MathMin(ArraySize(features), AI_FEATURE_DIM);
      for(int i = 0; i < n; i++)
         m_buffer[m_head].features[i] = features[i];
      // Zero-pad if features array is smaller than AI_FEATURE_DIM
      for(int i = n; i < AI_FEATURE_DIM; i++)
         m_buffer[m_head].features[i] = 0.5; // neutral fallback
      m_buffer[m_head].label = label;
      m_head  = (m_head + 1) % REPLAY_CAPACITY;
      if(m_count < REPLAY_CAPACITY) m_count++;
     }

   // Overload: push directly from FeatureVector (preferred path v4.01)
   void PushReplay(const FeatureVector &fv, double label)
     {
      // Extract NN_INPUTS slice via ToNNInputs for training
      // but store full AI_FEATURE_DIM in replay for replayability
      double buf[AI_FEATURE_DIM];
      for(int i = 0; i < AI_FEATURE_DIM; i++) buf[i] = fv.f[i];
      m_buffer[m_head].label = label;
      for(int i = 0; i < AI_FEATURE_DIM; i++)
         m_buffer[m_head].features[i] = buf[i];
      m_head  = (m_head + 1) % REPLAY_CAPACITY;
      if(m_count < REPLAY_CAPACITY) m_count++;
     }

   //+----------------------------------------------------------------+
   //| TrainMiniBatch — backprop on NN_INPUTS-dim slice of replay     |
   //| NN operates on 12-dim input (ToNNInputs mapping).              |
   //| Full 26-dim is stored in replay for future re-slicing.         |
   //+----------------------------------------------------------------+
   void TrainMiniBatch()
     {
      if(CheckPointer(m_model) == POINTER_INVALID
         || m_count < MINIBATCH_SIZE) return;
      double lr = m_model.nnLearningRate;

      for(int b = 0; b < MINIBATCH_SIZE; b++)
        {
         int idx = (int)(MathRand() % MathMin(m_count, REPLAY_CAPACITY));

         // Extract NN_INPUTS-dim slice from stored 26-dim features
         // Mapping mirrors FeatureVector.ToNNInputs():
         //   [0]ATR [1]Spread [2]SL [3]Vol [4]Mom [5]SRConfl
         //   [6]ADX [7]SRProxBull [8]SRProxBear [9]HourSin
         //   [10]HTFTrendH4 [11]ATRPercentile
         double feat[NN_INPUTS];
         feat[0]  = m_buffer[idx].features[0];   // ATR
         feat[1]  = m_buffer[idx].features[1];   // Spread
         feat[2]  = m_buffer[idx].features[2];   // SL mult
         feat[3]  = m_buffer[idx].features[4];   // Volume
         feat[4]  = m_buffer[idx].features[5];   // Momentum
         feat[5]  = m_buffer[idx].features[13];  // SR confluence
         feat[6]  = m_buffer[idx].features[17];  // ADX
         feat[7]  = m_buffer[idx].features[18];  // SR prox bull  (F19)
         feat[8]  = m_buffer[idx].features[19];  // SR prox bear  (F20)
         feat[9]  = m_buffer[idx].features[22];  // Hour sin      (F23)
         feat[10] = m_buffer[idx].features[24];  // HTF trend H4  (F25)
         feat[11] = m_buffer[idx].features[25];  // ATR percentile(F26)
         double label = m_buffer[idx].label;

         //--- Forward pass
         double h1[NN_H1], z1[NN_H1];
         for(int j = 0; j < NN_H1; j++)
           {
            z1[j] = m_model.h1b[j];
            for(int i = 0; i < NN_INPUTS; i++) z1[j] += feat[i] * m_model.h1w[i][j];
            h1[j] = MathMax(0.0, z1[j]); // ReLU
           }
         double h2[NN_H2], z2[NN_H2];
         for(int j = 0; j < NN_H2; j++)
           {
            z2[j] = m_model.h2b[j];
            for(int i = 0; i < NN_H1; i++) z2[j] += h1[i] * m_model.h2w[i][j];
            h2[j] = MathMax(0.0, z2[j]); // ReLU
           }
         double raw = m_model.ob;
         for(int j = 0; j < NN_H2; j++) raw += h2[j] * m_model.ow[j];
         double pred  = Logistic(raw);
         double err   = pred - label;
         double d_out = err * pred * (1.0 - pred);

         //--- Output layer update
         for(int j = 0; j < NN_H2; j++)
            m_model.ow[j] -= lr * (d_out * h2[j] + L2_LAMBDA * m_model.ow[j]);
         m_model.ob -= lr * d_out;

         //--- AI-BUG-FIX-1 (v3.01 retained): snapshot h2w BEFORE H2 update
         //    so H1 gradient uses pre-update weights (correct backprop)
         //    v4.01: dimensioned via NN_H1/NN_H2 constants (not hardcoded)
         double snap_h2w[NN_H1][NN_H2];
         for(int i = 0; i < NN_H1; i++)
            for(int j = 0; j < NN_H2; j++)
               snap_h2w[i][j] = m_model.h2w[i][j];

         //--- Hidden layer 2 update
         double d_h2[NN_H2];
         for(int j = 0; j < NN_H2; j++)
           {
            d_h2[j] = (z2[j] > 0) ? d_out * m_model.ow[j] : 0.0;
            for(int i = 0; i < NN_H1; i++)
               m_model.h2w[i][j] -= lr * (d_h2[j] * h1[i]
                                          + L2_LAMBDA * m_model.h2w[i][j]);
            m_model.h2b[j] -= lr * d_h2[j];
           }

         //--- Hidden layer 1 update — uses snap_h2w (pre-H2-update)
         for(int j = 0; j < NN_H1; j++)
           {
            double grad = 0;
            for(int k = 0; k < NN_H2; k++) grad += d_h2[k] * snap_h2w[j][k];
            double d_h1 = (z1[j] > 0) ? grad : 0.0;
            for(int i = 0; i < NN_INPUTS; i++)
               m_model.h1w[i][j] -= lr * (d_h1 * feat[i]
                                          + L2_LAMBDA * m_model.h1w[i][j]);
            m_model.h1b[j] -= lr * d_h1;
           }

         //--- Platt scaling inline update
         double plattPred = Logistic(m_model.plattA * raw + m_model.plattB);
         double plattErr  = plattPred - label;
         m_model.plattA  -= 0.01 * plattErr * plattPred * (1.0 - plattPred) * raw;
         m_model.plattB  -= 0.01 * plattErr * plattPred * (1.0 - plattPred);
         m_model.plattSamples++;
        }

      m_model.replayTrainCount++;
      m_model.nnTrainingSamples += MINIBATCH_SIZE;

      //--- AI-BUG-FIX-2 (v3.01 retained): cyclical LR reset every 200 batches
      if(m_model.replayTrainCount % 200 == 0)
        {
         m_model.nnLearningRate = 0.01;
         PrintFormat("[AITrainer] LR cyclical reset at batch #%d",
                     m_model.replayTrainCount);
        }
      else if(m_model.replayTrainCount % 10 == 0
              && m_model.nnLearningRate > 0.001)
         m_model.nnLearningRate *= 0.95;

      m_model.lastUpdateTime = TimeCurrent();
      m_labeledSince = 0;

      PrintFormat("[AITrainer] Batch #%d | LR=%.5f | replay=%d | platt=%d",
                  m_model.replayTrainCount,
                  m_model.nnLearningRate,
                  m_count,
                  m_model.plattSamples);
     }

   //+----------------------------------------------------------------+
   //| LabelOutcome — label closed position, push to replay           |
   //| v4.01 FIX: features copy uses AI_FEATURE_DIM (not NN_INPUTS)   |
   //+----------------------------------------------------------------+
   void LabelOutcome(ulong ticket, double pnl,
                     AISignalSample &samples[], int sampleCount)
     {
      for(int i = sampleCount - 1; i >= 0; i--)
        {
         if(samples[i].ticket != ticket || samples[i].labeled) continue;
         samples[i].labeled = true;
         double label = (pnl > 0) ? 1.0 : 0.0;
         // v4.01: push full AI_FEATURE_DIM features to replay
         double buf[AI_FEATURE_DIM];
         int n = MathMin(AI_FEATURE_DIM, ArraySize(samples[i].features));
         for(int k = 0; k < n; k++)          buf[k] = samples[i].features[k];
         for(int k = n; k < AI_FEATURE_DIM; k++) buf[k] = 0.5;
         PushReplay(buf, label);
         m_labeledSince++;

         AppendCsvRow(m_outcomeFile,
                      "sample_id", "ticket", "pnl", "label_time",
                      samples[i].sampleId,
                      IntegerToString((int)ticket),
                      DoubleToString(pnl, 2),
                      TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
         break;
        }
     }

   //+----------------------------------------------------------------+
   //| AttachTicket — link execution ticket to pending sample         |
   //+----------------------------------------------------------------+
   void AttachTicket(ulong ticket, AISignalSample &samples[], int sampleCount)
     {
      for(int i = sampleCount - 1; i >= 0; i--)
        {
         if(samples[i].ticket != 0 || samples[i].labeled) continue;
         if(TimeCurrent() - samples[i].timestamp > 60)    continue;
         samples[i].ticket = ticket;
         AppendCsvRow(m_ticketFile,
                      "sample_id", "ticket", "accepted", "attached_time",
                      samples[i].sampleId,
                      IntegerToString((int)ticket),
                      samples[i].accepted ? "1" : "0",
                      TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
         return;
        }
     }
  };

#endif // __AI_TRAINER_MQH__
