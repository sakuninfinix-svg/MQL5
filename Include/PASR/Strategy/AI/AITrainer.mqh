//+------------------------------------------------------------------+
//|                                                    AITrainer.mqh |
//|          Backpropagation, replay buffer, sample labeling         |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
//| V3.01 FIXES:                                                     |
//| - AI-BUG-FIX-1 [CRITICAL]: Stale h2w gradient bug.             |
//|   H2 weights were updated before being read for H1 gradient.    |
//|   Now saves snap_h2w[][] snapshot before H2 update loop.        |
//| - AI-BUG-FIX-2 [HIGH]: LR decay floor caused network to stop   |
//|   learning after ~140 batches. Added cyclical reset every 200   |
//|   batches back to initial LR.                                   |
//| - AI-BUG-FIX-3 [MEDIUM]: AppendCsvRow FileClose not guaranteed  |
//|   on FileWrite failure. Now uses goto-free guard pattern.       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Agsicentre"
#property version   "3.01"
#property strict

#ifndef __AI_TRAINER_MQH__
#define __AI_TRAINER_MQH__

#include "AITypes.mqh"
#include "../../Core/IManager.mqh"

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

   // AI-BUG-FIX-3: FileClose is now guaranteed via explicit close before every return.
   void AppendCsvRow(const string filename,
                     const string h1, const string h2, const string h3, const string h4,
                     const string v1, const string v2, const string v3, const string v4)
   {
      int handle = FileOpen(filename, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
      if(handle == INVALID_HANDLE) return;

      FileSeek(handle, 0, SEEK_END);
      bool ok = true;
      if(FileTell(handle) == 0)
         ok = FileWrite(handle, h1, h2, h3, h4) > 0;
      if(ok)
         FileWrite(handle, v1, v2, v3, v4);

      FileClose(handle); // guaranteed — always reached
   }

public:
   AITrainer() : m_model(NULL), m_data(NULL), m_head(0), m_count(0), m_labeledSince(0)
   { ZeroMemory(m_buffer); }

   void SetModel(AIModelState *model)   { m_model = model; }
   void SetData(DataManager *data)      { m_data  = data; }
   void SetFiles(const string outcomeFile, const string ticketFile)
   { m_outcomeFile = outcomeFile; m_ticketFile = ticketFile; }

   int  GetReplayCount()     const { return m_count; }
   bool ShouldTrain()        const { return m_labeledSince >= MINIBATCH_SIZE && m_count >= MINIBATCH_SIZE; }

   //--- Circular replay buffer push (O(1))
   void PushReplay(const double &features[], double label)
   {
      for(int i=0;i<NN_INPUTS;i++) m_buffer[m_head].features[i] = features[i];
      m_buffer[m_head].label = label;
      m_head  = (m_head + 1) % REPLAY_CAPACITY;
      if(m_count < REPLAY_CAPACITY) m_count++;
   }

   //--- Minibatch backpropagation — O(MINIBATCH_SIZE * NN_INPUTS * NN_H1 * NN_H2)
   //    Should be dispatched as PRIORITY_BACKGROUND event, not called on tick thread.
   void TrainMiniBatch()
   {
      if(CheckPointer(m_model) == POINTER_INVALID || m_count < MINIBATCH_SIZE) return;
      double lr = m_model.nnLearningRate;

      for(int b=0;b<MINIBATCH_SIZE;b++)
      {
         int    idx   = (int)(MathRand() % MathMin(m_count, REPLAY_CAPACITY));
         double feat[NN_INPUTS];
         for(int i=0;i<NN_INPUTS;i++) feat[i] = m_buffer[idx].features[i];
         double label = m_buffer[idx].label;

         //--- Forward pass
         double h1[NN_H1], z1[NN_H1];
         for(int j=0;j<NN_H1;j++)
         {
            z1[j]=m_model.h1b[j];
            for(int i=0;i<NN_INPUTS;i++) z1[j]+=feat[i]*m_model.h1w[i][j];
            h1[j]=MathMax(0.0,z1[j]);
         }
         double h2[NN_H2], z2[NN_H2];
         for(int j=0;j<NN_H2;j++)
         {
            z2[j]=m_model.h2b[j];
            for(int i=0;i<NN_H1;i++) z2[j]+=h1[i]*m_model.h2w[i][j];
            h2[j]=MathMax(0.0,z2[j]);
         }
         double raw=m_model.ob;
         for(int j=0;j<NN_H2;j++) raw+=h2[j]*m_model.ow[j];
         double pred=Logistic(raw), err=pred-label;
         double d_out=err*pred*(1.0-pred);

         //--- Output layer update
         for(int j=0;j<NN_H2;j++)
            m_model.ow[j] -= lr*(d_out*h2[j]+L2_LAMBDA*m_model.ow[j]);
         m_model.ob -= lr*d_out;

         //--- AI-BUG-FIX-1: Snapshot h2w BEFORE updating, so H1 gradient
         //    uses original weights — not the already-modified values.
         double snap_h2w[NN_H1][NN_H2];
         for(int i=0;i<NN_H1;i++)
            for(int j=0;j<NN_H2;j++)
               snap_h2w[i][j] = m_model.h2w[i][j];

         //--- Hidden layer 2 update
         double d_h2[NN_H2];
         for(int j=0;j<NN_H2;j++)
         {
            d_h2[j]=(z2[j]>0) ? d_out*m_model.ow[j] : 0.0;
            for(int i=0;i<NN_H1;i++)
               m_model.h2w[i][j] -= lr*(d_h2[j]*h1[i]+L2_LAMBDA*m_model.h2w[i][j]);
            m_model.h2b[j] -= lr*d_h2[j];
         }

         //--- Hidden layer 1 update — uses snap_h2w (clean, pre-update values)
         for(int j=0;j<NN_H1;j++)
         {
            double grad=0;
            for(int k=0;k<NN_H2;k++) grad+=d_h2[k]*snap_h2w[j][k]; // ← fixed
            double d_h1=(z1[j]>0) ? grad : 0.0;
            for(int i=0;i<NN_INPUTS;i++)
               m_model.h1w[i][j] -= lr*(d_h1*feat[i]+L2_LAMBDA*m_model.h1w[i][j]);
            m_model.h1b[j] -= lr*d_h1;
         }

         //--- Platt scaling update (inline)
         double plattPred = Logistic(m_model.plattA*raw + m_model.plattB);
         double plattErr  = plattPred - label;
         m_model.plattA  -= 0.01*plattErr*plattPred*(1.0-plattPred)*raw;
         m_model.plattB  -= 0.01*plattErr*plattPred*(1.0-plattPred);
         m_model.plattSamples++;
      }

      m_model.replayTrainCount++;
      m_model.nnTrainingSamples += MINIBATCH_SIZE;

      //--- AI-BUG-FIX-2: Cyclical LR reset every 200 batches to prevent
      //    permanent learning freeze when floor (0.001) is reached.
      if(m_model.replayTrainCount % 200 == 0)
      {
         m_model.nnLearningRate = 0.01; // reset to initial
         PrintFormat("[AITrainer] LR cyclical reset at batch #%d", m_model.replayTrainCount);
      }
      else if(m_model.replayTrainCount % 10 == 0 && m_model.nnLearningRate > 0.001)
         m_model.nnLearningRate *= 0.95;

      m_model.lastUpdateTime = TimeCurrent();
      m_labeledSince = 0;

      PrintFormat("[AITrainer] Batch #%d | LR=%.5f | replay=%d | platt=%d",
                  m_model.replayTrainCount, m_model.nnLearningRate, m_count, m_model.plattSamples);
   }

   //--- Label a closed position outcome and push to replay
   void LabelOutcome(ulong ticket, double pnl, AISignalSample &samples[], int sampleCount)
   {
      for(int i=sampleCount-1;i>=0;i--)
      {
         if(samples[i].ticket != ticket || samples[i].labeled) continue;
         samples[i].labeled = true;
         double label = (pnl > 0) ? 1.0 : 0.0;
         PushReplay(samples[i].features, label);
         m_labeledSince++;

         AppendCsvRow(m_outcomeFile,
                      "sample_id","ticket","pnl","label_time",
                      samples[i].sampleId,
                      IntegerToString((int)ticket),
                      DoubleToString(pnl, 2),
                      TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
         break;
      }
   }

   //--- Attach ticket to most recent unlinked sample (60 s window)
   void AttachTicket(ulong ticket, AISignalSample &samples[], int sampleCount)
   {
      for(int i=sampleCount-1;i>=0;i--)
      {
         if(samples[i].ticket != 0 || samples[i].labeled) continue;
         if(TimeCurrent() - samples[i].timestamp > 60)  continue;
         samples[i].ticket = ticket;
         AppendCsvRow(m_ticketFile,
                      "sample_id","ticket","accepted","attached_time",
                      samples[i].sampleId,
                      IntegerToString((int)ticket),
                      samples[i].accepted ? "1" : "0",
                      TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
         return;
      }
   }
};

#endif // __AI_TRAINER_MQH__
