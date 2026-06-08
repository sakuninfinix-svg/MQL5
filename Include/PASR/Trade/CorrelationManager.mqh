//+------------------------------------------------------------------+
//| CorrelationManager.mqh                                    v2.02 |
//| Dynamic Correlation Matrix for Multi-Symbol Risk Management      |
//+------------------------------------------------------------------+
#ifndef PASR_CORRELATION_MANAGER_MQH
#define PASR_CORRELATION_MANAGER_MQH

#include "../Core/IManager.mqh"
#include "PositionRegistry.mqh"

#define CORR_WINDOW_SIZE      20
#define CORR_HIGH_THRESHOLD   0.80
#define CORR_UPDATE_INTERVAL  60
#define CORR_MAX_PAIRS        100

struct CorrPair
  {
   string   symbol1;
   string   symbol2;
   double   value;
   datetime last_update;

   void Init(const string s1, const string s2)
     {
      symbol1 = s1;
      symbol2 = s2;
      value = 0.0;
      last_update = 0;
     }
  };

class CCorrelationManager : public IManager
  {
private:
   CorrPair       m_matrix[];
   int            m_pair_count;
   datetime       m_last_update;
   string         m_tracked_symbols[];
   int            m_tracked_count;
   double         m_returns1[CORR_WINDOW_SIZE];
   double         m_returns2[CORR_WINDOW_SIZE];
   ulong          m_calc_count;
   ulong          m_block_count;
   CPositionRegistry m_positions;

public:
   CCorrelationManager()
      : IManager(), m_pair_count(0), m_last_update(0),
        m_tracked_count(0), m_calc_count(0), m_block_count(0)
     {
      ArrayResize(m_matrix, CORR_MAX_PAIRS);
     }

   ~CCorrelationManager()
     {
      Deinit();
     }

   virtual string HandlerName() const override { return "CorrelationManager"; }

   virtual bool Init(IDataManager *data, CEventBus *bus) override
     {
      if(!IManager::Init(data, bus)) return false;
      ArrayResize(m_matrix, CORR_MAX_PAIRS);
      ArrayResize(m_tracked_symbols, 0);
      m_pair_count = 0;
      m_tracked_count = 0;
      m_last_update = 0;
      Print("[CORR] v2.02 initialized. Window=", CORR_WINDOW_SIZE,
            " Threshold=", CORR_HIGH_THRESHOLD,
            " UpdateInterval=", CORR_UPDATE_INTERVAL, "s");
      return true;
     }

   virtual void Deinit() override
     {
      if(!IsInitialized()) return;
      Print("[CORR] Shutdown. Calcs=", m_calc_count, " Blocked=", m_block_count);
      ArrayFree(m_matrix);
      ArrayFree(m_tracked_symbols);
      m_pair_count = 0;
      m_tracked_count = 0;
      IManager::Deinit();
     }

   virtual void DeclareEvents() override
     {
      AddEvent(EVENT_ID_NEW_BAR);
      AddEvent(EVENT_ID_TIMER);
     }

   virtual void OnEvent(const PASREvent &ev) override
     {
      if(!IsInitialized()) return;
      switch(ev.id)
        {
         case EVENT_ID_NEW_BAR:
            RefreshSymbolList();
            if(m_tracked_count >= 2)
               UpdateMatrix(m_tracked_symbols, m_tracked_count);
            break;

         case EVENT_ID_TIMER:
            if(TimeCurrent() - m_last_update >= CORR_UPDATE_INTERVAL &&
               m_tracked_count >= 2)
               UpdateMatrix(m_tracked_symbols, m_tracked_count);
            break;

         default:
            break;
        }
     }

   bool IsCorrelationSafe(const string symbol, const string &open_symbols[], int open_count)
     {
      if(!IsInitialized() || open_count == 0) return true;
      for(int i = 0; i < open_count; i++)
        {
         if(open_symbols[i] == symbol) continue;
         double corr = GetCorrelation(symbol, open_symbols[i]);
         if(MathAbs(corr) >= CORR_HIGH_THRESHOLD)
           {
            m_block_count++;
            PrintFormat("[CORR] BLOCKED: %s vs %s corr=%.2f >= %.2f",
                        symbol, open_symbols[i], corr, CORR_HIGH_THRESHOLD);
            return false;
           }
        }
      return true;
     }

   bool IsCorrelationSafe(const string symbol, double threshold, int window)
     {
      if(!IsInitialized()) return true;
      double check_threshold = (threshold > 0.0) ? threshold : CORR_HIGH_THRESHOLD;
      m_positions.Scan("", 0);
      SPositionSnapshot pos;
      for(int i = 0; i < m_positions.Count(); i++)
        {
         if(!m_positions.GetAt(i, pos)) continue;
         string pos_sym = pos.symbol;
         if(pos_sym == symbol) continue;
         double corr = GetCorrelation(symbol, pos_sym);
         if(MathAbs(corr) >= check_threshold)
           {
            m_block_count++;
            PrintFormat("[CORR] BLOCKED: %s vs %s corr=%.2f >= %.2f",
                        symbol, pos_sym, corr, check_threshold);
            return false;
           }
        }
      return true;
     }

   double GetCorrelation(const string symbol1, const string symbol2)
     {
      if(!IsInitialized()) return 0.0;
      int idx = FindPairIndex(symbol1, symbol2);
      if(idx >= 0 && idx < m_pair_count)
         return m_matrix[idx].value;
      double r1[CORR_WINDOW_SIZE], r2[CORR_WINDOW_SIZE];
      GetPriceReturns(symbol1, r1, CORR_WINDOW_SIZE);
      GetPriceReturns(symbol2, r2, CORR_WINDOW_SIZE);
      return CalculatePearson(r1, r2, CORR_WINDOW_SIZE);
     }

   void UpdateMatrix(const string &symbols[], int count)
     {
      if(!IsInitialized() || count < 2) return;
      int required = (count * (count - 1)) / 2;
      if(required > ArraySize(m_matrix))
         ArrayResize(m_matrix, required + 10);
      m_pair_count = 0;
      datetime now = TimeCurrent();
      for(int i = 0; i < count; i++)
        {
         for(int j = i + 1; j < count; j++)
           {
            if(symbols[i] == symbols[j]) continue;
            double r1[CORR_WINDOW_SIZE], r2[CORR_WINDOW_SIZE];
            GetPriceReturns(symbols[i], r1, CORR_WINDOW_SIZE);
            GetPriceReturns(symbols[j], r2, CORR_WINDOW_SIZE);
            m_matrix[m_pair_count].symbol1 = symbols[i];
            m_matrix[m_pair_count].symbol2 = symbols[j];
            m_matrix[m_pair_count].value = CalculatePearson(r1, r2, CORR_WINDOW_SIZE);
            m_matrix[m_pair_count].last_update = now;
            m_pair_count++;
           }
        }
      m_last_update = now;
      m_calc_count++;
     }

   string GetHighestCorrelatedPair()
     {
      if(m_pair_count == 0) return "";
      double max_corr = 0.0;
      int max_idx = -1;
      for(int i = 0; i < m_pair_count; i++)
        {
         double v = MathAbs(m_matrix[i].value);
         if(v > max_corr) { max_corr = v; max_idx = i; }
        }
      if(max_idx >= 0)
         return StringFormat("%s/%s (%.2f)", m_matrix[max_idx].symbol1,
                             m_matrix[max_idx].symbol2, m_matrix[max_idx].value);
      return "";
     }

   void GetStats(ulong &calc_out, ulong &block_out) const
     {
      calc_out = m_calc_count;
      block_out = m_block_count;
     }

   void PrintStatus()
     {
      if(!IsInitialized()) return;
      PrintFormat("[CORR] Status: %d pairs, last=%s, calcs=%I64u, blocked=%I64u",
                  m_pair_count, TimeToString(m_last_update), m_calc_count, m_block_count);
      for(int i = 0; i < m_pair_count; i++)
         if(MathAbs(m_matrix[i].value) >= 0.70)
            PrintFormat("  %s <-> %s : %.3f", m_matrix[i].symbol1,
                        m_matrix[i].symbol2, m_matrix[i].value);
     }

private:
   void RefreshSymbolList()
     {
      ArrayResize(m_tracked_symbols, 0);
      m_tracked_count = 0;
      m_positions.Scan("", 0);
      SPositionSnapshot pos;
      for(int i = 0; i < m_positions.Count(); i++)
        {
         if(!m_positions.GetAt(i, pos)) continue;
         string sym = pos.symbol;
         bool found = false;
         for(int k = 0; k < m_tracked_count; k++)
            if(m_tracked_symbols[k] == sym) { found = true; break; }
         if(!found)
           {
            ArrayResize(m_tracked_symbols, m_tracked_count + 1);
            m_tracked_symbols[m_tracked_count] = sym;
            m_tracked_count++;
           }
        }
      bool has_self = false;
      for(int k = 0; k < m_tracked_count; k++)
         if(m_tracked_symbols[k] == _Symbol) { has_self = true; break; }
      if(!has_self)
        {
         ArrayResize(m_tracked_symbols, m_tracked_count + 1);
         m_tracked_symbols[m_tracked_count] = _Symbol;
         m_tracked_count++;
        }
     }

   double CalculatePearson(const double &arr1[], const double &arr2[], int size)
     {
      if(size < 2) return 0.0;
      double s1=0, s2=0, s1q=0, s2q=0, sp=0;
      for(int i = 0; i < size; i++)
        {
         double v1 = arr1[i], v2 = arr2[i];
         s1 += v1; s2 += v2;
         s1q += v1*v1; s2q += v2*v2;
         sp += v1*v2;
        }
      double num = size * sp - s1 * s2;
      double den = MathSqrt((size*s1q - s1*s1) * (size*s2q - s2*s2));
      return (den == 0.0) ? 0.0 : num / den;
     }

   void GetPriceReturns(const string symbol, double &returns[], int window)
     {
      ArrayInitialize(returns, 0.0);
      double closes[];
      ArraySetAsSeries(closes, true);
      // Closed bars only: start=1 excludes the active unfinished candle.
      int copied = CopyClose(symbol, PERIOD_CURRENT, 1, window + 1, closes);
      if(copied < window + 1) return;
      for(int i = 0; i < window && i < ArraySize(returns); i++)
         if(closes[i+1] > 0 && closes[i] > 0)
            returns[i] = MathLog(closes[i+1] / closes[i]);
     }

   int FindPairIndex(const string s1, const string s2)
     {
      for(int i = 0; i < m_pair_count; i++)
         if((m_matrix[i].symbol1==s1 && m_matrix[i].symbol2==s2) ||
            (m_matrix[i].symbol1==s2 && m_matrix[i].symbol2==s1))
            return i;
      return -1;
     }
  };

#endif // PASR_CORRELATION_MANAGER_MQH
