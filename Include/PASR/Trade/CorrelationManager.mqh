//+------------------------------------------------------------------+
//| CorrelationManager.mqh                                    v2.00 |
//| Copyright (C) 2024, PASR Trading System                          |
//| https://pasr.trading                                             |
//|                                                                  |
//| Dynamic Correlation Matrix for Multi-Symbol Risk Management     |
//| - Pearson correlation calculation (rolling window)              |
//| - Cluster risk detection & prevention                           |
//| - Circuit Breaker #7: High Correlation Exposure                 |
//| Sprint 13: Migrated from monolith v1.0 to IManager pipeline     |
//+------------------------------------------------------------------+
#ifndef PASR_CORRELATION_MANAGER_MQH
#define PASR_CORRELATION_MANAGER_MQH

#include <PASR/Core/IManager.mqh>          // FIX TR-006-A: .h → .mqh
// NOTE: TickCache confirmed in Tools/ but NOT needed here
//       CopyClose() is used directly — no TickCache dependency.

//+------------------------------------------------------------------+
//| Configuration Constants                                          |
//+------------------------------------------------------------------+
#define CORR_WINDOW_SIZE      20    // Rolling window for correlation calc
#define CORR_HIGH_THRESHOLD   0.80  // Threshold for high correlation block
#define CORR_UPDATE_INTERVAL  60    // Update every 60 seconds
#define CORR_MAX_PAIRS        100   // Pre-allocated matrix capacity

//+------------------------------------------------------------------+
//| Correlation Pair Structure                                       |
//+------------------------------------------------------------------+
struct CorrPair
{
   string   symbol1;
   string   symbol2;
   double   value;
   datetime last_update;

   void Init(const string s1, const string s2)
   {
      symbol1      = s1;
      symbol2      = s2;
      value        = 0.0;
      last_update  = 0;
   }
};

//+------------------------------------------------------------------+
//| CCorrelationManager — IManager Pipeline Compliance v2.00        |
//+------------------------------------------------------------------+
class CCorrelationManager : public IManager    // FIX TR-006-B: explicit base
{
private:
   //--- IManager-owned refs (non-owning)
   CDataManager  *m_data;                     // FIX TR-006-C: added
   CEventBus     *m_bus;                      // FIX TR-006-C: added

   //--- Correlation matrix
   CorrPair       m_matrix[];                 // Flattened upper-triangle
   int            m_pair_count;
   datetime       m_last_update;

   //--- Cached symbol list (updated on EVENT_ID_NEW_BAR)
   string         m_tracked_symbols[];
   int            m_tracked_count;

   //--- Static buffers (zero-allocation per-calc)
   double         m_returns1[CORR_WINDOW_SIZE];
   double         m_returns2[CORR_WINDOW_SIZE];

   //--- Stats
   ulong          m_calc_count;
   ulong          m_block_count;

public:
   CCorrelationManager();
   ~CCorrelationManager();

   //--- IManager interface overrides                               FIX TR-006-D
   virtual bool   Init(CDataManager *data, CEventBus *bus) override;
   virtual void   Shutdown() override;
   virtual void   DeclareEvents() override;
   virtual void   OnEvent(const PASREvent &ev) override;

   //--- Public API
   bool           IsCorrelationSafe(const string symbol,
                                    const string &open_symbols[],
                                    int open_count);
   bool           IsCorrelationSafe(const string symbol,
                                    double threshold,
                                    int window);
   double         GetCorrelation(const string symbol1, const string symbol2);
   void           UpdateMatrix(const string &symbols[], int count);

   //--- Utility
   string         GetHighestCorrelatedPair();
   void           GetStats(ulong &calc_out, ulong &block_out) const;
   void           PrintStatus();

private:
   double         CalculatePearson(const double &arr1[],
                                   const double &arr2[], int size);
   void           GetPriceReturns(const string symbol,
                                  double &returns[], int window);
   int            FindPairIndex(const string s1, const string s2);
   void           RefreshSymbolList();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CCorrelationManager::CCorrelationManager()
   : m_data(NULL),
     m_bus(NULL),
     m_pair_count(0),
     m_tracked_count(0),
     m_last_update(0),
     m_calc_count(0),
     m_block_count(0)
{
   ArrayResize(m_matrix, CORR_MAX_PAIRS);
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CCorrelationManager::~CCorrelationManager()
{
   Shutdown();
}

//+------------------------------------------------------------------+
//| IManager::Init — replaces old Initialize()                       |
//| FIX TR-006-D: correct signature override                         |
//+------------------------------------------------------------------+
bool CCorrelationManager::Init(CDataManager *data, CEventBus *bus)
{
   if(m_initialized) return true;   // idempotent guard (IManager base field)

   if(CheckPointer(bus) == POINTER_INVALID)
   {
      Print("[CORR] ERROR: EventBus is NULL in Init()");
      return false;
   }

   m_data = data;   // data may be NULL for correlation (uses CopyClose directly)
   m_bus  = bus;

   ArrayResize(m_tracked_symbols, 0);
   m_tracked_count = 0;
   m_last_update   = 0;

   Print("[CORR] v2.00 initialized. Window=", CORR_WINDOW_SIZE,
         " Threshold=", CORR_HIGH_THRESHOLD,
         " UpdateInterval=", CORR_UPDATE_INTERVAL, "s");

   m_initialized = true;
   return true;
}

//+------------------------------------------------------------------+
//| IManager::Shutdown                                               |
//+------------------------------------------------------------------+
void CCorrelationManager::Shutdown()
{
   if(!m_initialized) return;

   Print("[CORR] Shutdown. Calcs=", m_calc_count, " Blocked=", m_block_count);
   ArrayFree(m_matrix);
   ArrayFree(m_tracked_symbols);
   m_pair_count    = 0;
   m_tracked_count = 0;
   m_data          = NULL;
   m_bus           = NULL;
   m_initialized   = false;
}

//+------------------------------------------------------------------+
//| IManager::DeclareEvents — subscribe to pipeline events          |
//| FIX TR-006-E: was missing entirely in v1.0                       |
//+------------------------------------------------------------------+
void CCorrelationManager::DeclareEvents()
{
   if(CheckPointer(m_bus) == POINTER_INVALID) return;

   // Refresh tracked symbol list and rebuild matrix on every new bar
   AddEvent(EVENT_ID_NEW_BAR);

   // Periodic lightweight staleness check on timer
   AddEvent(EVENT_ID_TIMER);
}

//+------------------------------------------------------------------+
//| IManager::OnEvent — pipeline event handler                      |
//| FIX TR-006-F: was missing entirely in v1.0                       |
//+------------------------------------------------------------------+
void CCorrelationManager::OnEvent(const PASREvent &ev)
{
   if(!m_initialized) return;

   switch(ev.id)
   {
      case EVENT_ID_NEW_BAR:
         //--- Rebuild symbol list from open positions, then full matrix update
         RefreshSymbolList();
         if(m_tracked_count >= 2)
            UpdateMatrix(m_tracked_symbols, m_tracked_count);
         break;

      case EVENT_ID_TIMER:
         //--- Incremental staleness check: re-calc pairs older than interval
         if(TimeCurrent() - m_last_update >= CORR_UPDATE_INTERVAL &&
            m_tracked_count >= 2)
            UpdateMatrix(m_tracked_symbols, m_tracked_count);
         break;

      default:
         break;
   }
}

//+------------------------------------------------------------------+
//| Rebuild m_tracked_symbols from currently open positions          |
//+------------------------------------------------------------------+
void CCorrelationManager::RefreshSymbolList()
{
   ArrayResize(m_tracked_symbols, 0);
   m_tracked_count = 0;

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0 || !PositionSelectByTicket(ticket)) continue;

      string sym = PositionGetString(POSITION_SYMBOL);

      //--- De-duplicate
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

   //--- Always include the EA's own symbol
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

//+------------------------------------------------------------------+
//| Check if new position is safe from correlation perspective      |
//+------------------------------------------------------------------+
bool CCorrelationManager::IsCorrelationSafe(
   const string symbol,
   const string &open_symbols[],
   int open_count)
{
   if(!m_initialized || open_count == 0) return true;

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

//+------------------------------------------------------------------+
//| Overloaded: check against all currently open positions           |
//+------------------------------------------------------------------+
bool CCorrelationManager::IsCorrelationSafe(
   const string symbol,
   double threshold,
   int window)
{
   if(!m_initialized) return true;

   double check_threshold = (threshold > 0.0) ? threshold : CORR_HIGH_THRESHOLD;

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0 || !PositionSelectByTicket(ticket)) continue;

      string pos_sym = PositionGetString(POSITION_SYMBOL);
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

//+------------------------------------------------------------------+
//| Get correlation between two symbols (cached or on-demand)       |
//+------------------------------------------------------------------+
double CCorrelationManager::GetCorrelation(
   const string symbol1, const string symbol2)
{
   if(!m_initialized) return 0.0;

   int idx = FindPairIndex(symbol1, symbol2);
   if(idx >= 0 && idx < m_pair_count)
      return m_matrix[idx].value;

   //--- On-demand calculation (pair not in matrix yet)
   double r1[CORR_WINDOW_SIZE], r2[CORR_WINDOW_SIZE];
   GetPriceReturns(symbol1, r1, CORR_WINDOW_SIZE);
   GetPriceReturns(symbol2, r2, CORR_WINDOW_SIZE);
   return CalculatePearson(r1, r2, CORR_WINDOW_SIZE);
}

//+------------------------------------------------------------------+
//| Rebuild full correlation matrix for given symbol list            |
//+------------------------------------------------------------------+
void CCorrelationManager::UpdateMatrix(
   const string &symbols[], int count)
{
   if(!m_initialized || count < 2) return;

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

         m_matrix[m_pair_count].symbol1     = symbols[i];
         m_matrix[m_pair_count].symbol2     = symbols[j];
         m_matrix[m_pair_count].value       = CalculatePearson(r1, r2, CORR_WINDOW_SIZE);
         m_matrix[m_pair_count].last_update = now;
         m_pair_count++;
      }
   }

   m_last_update = now;
   m_calc_count++;
}

//+------------------------------------------------------------------+
//| Get pair with highest absolute correlation                       |
//+------------------------------------------------------------------+
string CCorrelationManager::GetHighestCorrelatedPair()
{
   if(m_pair_count == 0) return "";

   double max_corr = 0.0;
   int    max_idx  = -1;
   for(int i = 0; i < m_pair_count; i++)
   {
      double v = MathAbs(m_matrix[i].value);
      if(v > max_corr) { max_corr = v; max_idx = i; }
   }

   if(max_idx >= 0)
      return StringFormat("%s/%s (%.2f)",
                          m_matrix[max_idx].symbol1,
                          m_matrix[max_idx].symbol2,
                          m_matrix[max_idx].value);
   return "";
}

//+------------------------------------------------------------------+
//| Export stats for telemetry / health monitor                      |
//+------------------------------------------------------------------+
void CCorrelationManager::GetStats(ulong &calc_out, ulong &block_out) const
{
   calc_out  = m_calc_count;
   block_out = m_block_count;
}

//+------------------------------------------------------------------+
//| Print current matrix status                                      |
//+------------------------------------------------------------------+
void CCorrelationManager::PrintStatus()
{
   if(!m_initialized) return;
   PrintFormat("[CORR] Status: %d pairs, last=%s, calcs=%I64u, blocked=%I64u",
               m_pair_count, TimeToString(m_last_update),
               m_calc_count, m_block_count);
   for(int i = 0; i < m_pair_count; i++)
      if(MathAbs(m_matrix[i].value) >= 0.70)
         PrintFormat("  %s <-> %s : %.3f",
                     m_matrix[i].symbol1, m_matrix[i].symbol2,
                     m_matrix[i].value);
}

//+------------------------------------------------------------------+
//| Pearson correlation coefficient                                  |
//+------------------------------------------------------------------+
double CCorrelationManager::CalculatePearson(
   const double &arr1[], const double &arr2[], int size)
{
   if(size < 2) return 0.0;

   double s1=0, s2=0, s1q=0, s2q=0, sp=0;
   for(int i = 0; i < size; i++)
   {
      double v1 = arr1[i], v2 = arr2[i];
      s1  += v1;   s2  += v2;
      s1q += v1*v1; s2q += v2*v2;
      sp  += v1*v2;
   }

   double num = size * sp  - s1 * s2;
   double den = MathSqrt((size*s1q - s1*s1) * (size*s2q - s2*s2));
   return (den == 0.0) ? 0.0 : num / den;
}

//+------------------------------------------------------------------+
//| Log returns for a symbol (PERIOD_CURRENT bars)                   |
//+------------------------------------------------------------------+
void CCorrelationManager::GetPriceReturns(
   const string symbol, double &returns[], int window)
{
   ArrayInitialize(returns, 0.0);

   double closes[];
   ArraySetAsSeries(closes, true);
   int copied = CopyClose(symbol, PERIOD_CURRENT, 0, window + 1, closes);
   if(copied < window + 1) return;

   for(int i = 0; i < window && i < ArraySize(returns); i++)
      if(closes[i+1] > 0 && closes[i] > 0)
         returns[i] = MathLog(closes[i+1] / closes[i]);
}

//+------------------------------------------------------------------+
//| Find pair index (symmetric lookup)                               |
//+------------------------------------------------------------------+
int CCorrelationManager::FindPairIndex(
   const string s1, const string s2)
{
   for(int i = 0; i < m_pair_count; i++)
      if((m_matrix[i].symbol1==s1 && m_matrix[i].symbol2==s2) ||
         (m_matrix[i].symbol1==s2 && m_matrix[i].symbol2==s1))
         return i;
   return -1;
}

#endif // PASR_CORRELATION_MANAGER_MQH
