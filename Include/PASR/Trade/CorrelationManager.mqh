//+------------------------------------------------------------------+
//| CorrelationManager.mqh                                     v1.0 |
//| Copyright (C) 2024, PASR Trading System                          |
//| https://pasr.trading                                             |
//|                                                                  |
//| Dynamic Correlation Matrix for Multi-Symbol Risk Management     |
//| - Pearson correlation calculation (rolling window)              |
//| - Cluster risk detection & prevention                           |
//| - Circuit Breaker #7: High Correlation Exposure                 |
//+------------------------------------------------------------------+
#ifndef PASR_CORRELATION_MANAGER_MQH
#define PASR_CORRELATION_MANAGER_MQH

#include <PASR/Core/IManager.h>
#include <PASR/Tools/TickCache.mqh>

//+------------------------------------------------------------------+
//| Configuration Constants                                          |
//+------------------------------------------------------------------+
#define CORR_WINDOW_SIZE      20    // Rolling window for correlation calc
#define CORR_HIGH_THRESHOLD   0.80  // Threshold for high correlation block
#define CORR_UPDATE_INTERVAL  60    // Update every 60 seconds (not every tick)

//+------------------------------------------------------------------+
//| Correlation Pair Structure                                       |
//+------------------------------------------------------------------+
struct CorrPair
{
   string symbol1;
   string symbol2;
   double value;
   datetime last_update;
   
   void Init(const string s1, const string s2)
   {
      symbol1 = s1;
      symbol2 = s2;
      value = 0.0;
      last_update = 0;
   }
};

//+------------------------------------------------------------------+
//| CCorrelationManager Class                                        |
//| Manages dynamic correlation matrix for portfolio risk control    |
//+------------------------------------------------------------------+
class CCorrelationManager : public IManager
{
private:
   CorrPair          m_matrix[];           // Correlation matrix (flattened)
   int               m_pair_count;         // Number of symbol pairs
   datetime          m_last_update;        // Last full matrix update
   bool              m_initialized;        // Initialization flag
   
   // Static buffers for zero-allocation calculation
   double            m_returns1[CORR_WINDOW_SIZE];
   double            m_returns2[CORR_WINDOW_SIZE];
   
   // Performance metrics
   ulong             m_calc_count;
   ulong             m_block_count;
   
public:
   CCorrelationManager();
   ~CCorrelationManager();
   
   // IManager interface
   virtual bool      Initialize() override;
   virtual void      Shutdown() override;
   virtual void      OnTick(const string symbol) override;
   virtual void      OnTimer() override;
   virtual void      OnTrade() override;
   
   // Core functionality
   bool              IsCorrelationSafe(const string symbol, const string& open_symbols[], int open_count);
   double            GetCorrelation(const string symbol1, const string symbol2);
   void              UpdateMatrix(const string& symbols[], int count);
   
   // Utility functions
   string            GetHighestCorrelatedPair();
   void              PrintStatus();
   
private:
   double            CalculatePearson(const double &arr1[], const double &arr2[], int size);
   void              GetPriceReturns(const string symbol, double &returns[], int window);
   int               FindPairIndex(const string s1, const string s2);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CCorrelationManager::CCorrelationManager()
{
   m_initialized = false;
   m_pair_count = 0;
   m_last_update = 0;
   m_calc_count = 0;
   m_block_count = 0;
   ArrayResize(m_matrix, 100); // Pre-allocate for up to 100 pairs
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CCorrelationManager::~CCorrelationManager()
{
   Shutdown();
}

//+------------------------------------------------------------------+
//| Initialize manager                                                |
//+------------------------------------------------------------------+
bool CCorrelationManager::Initialize()
{
   if(m_initialized) return true;
   
   Print("[CORR] Initializing CorrelationManager...");
   Print("[CORR] Window size: ", CORR_WINDOW_SIZE, " bars");
   Print("[CORR] High correlation threshold: ", CORR_HIGH_THRESHOLD);
   Print("[CORR] Update interval: ", CORR_UPDATE_INTERVAL, " seconds");
   
   m_initialized = true;
   m_last_update = 0;
   
   return true;
}

//+------------------------------------------------------------------+
//| Shutdown manager                                                  |
//+------------------------------------------------------------------+
void CCorrelationManager::Shutdown()
{
   if(!m_initialized) return;
   
   Print("[CORR] Shutting down. Total calculations: ", m_calc_count);
   Print("[CORR] Positions blocked due to high correlation: ", m_block_count);
   
   ArrayFree(m_matrix);
   m_initialized = false;
}

//+------------------------------------------------------------------+
//| OnTick handler - check if update needed                         |
//+------------------------------------------------------------------+
void CCorrelationManager::OnTick(const string symbol)
{
   if(!m_initialized) return;
   
   // Update matrix periodically, not every tick
   if(TimeCurrent() - m_last_update >= CORR_UPDATE_INTERVAL)
   {
      // Matrix update handled by OnTimer or explicit call
   }
}

//+------------------------------------------------------------------+
//| OnTimer handler - update correlation matrix                     |
//+------------------------------------------------------------------+
void CCorrelationManager::OnTimer()
{
   if(!m_initialized) return;
   
   // Matrix update is triggered externally with symbol list
}

//+------------------------------------------------------------------+
//| OnTrade handler                                                   |
//+------------------------------------------------------------------+
void CCorrelationManager::OnTrade()
{
   // No action needed on trade events
}

//+------------------------------------------------------------------+
//| Check if new position is safe from correlation perspective      |
//+------------------------------------------------------------------+
bool CCorrelationManager::IsCorrelationSafe(
   const string symbol, 
   const string& open_symbols[], 
   int open_count)
{
   if(!m_initialized) return true;
   if(open_count == 0) return true; // No open positions, always safe
   
   // Check correlation with all open positions
   for(int i = 0; i < open_count; i++)
   {
      if(open_symbols[i] == symbol) continue; // Skip same symbol
      
      double corr = GetCorrelation(symbol, open_symbols[i]);
      
      if(MathAbs(corr) >= CORR_HIGH_THRESHOLD)
      {
         m_block_count++;
         PrintFormat("[CORR] BLOCKED: %s vs %s correlation %.2f exceeds threshold %.2f",
                     symbol, open_symbols[i], corr, CORR_HIGH_THRESHOLD);
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get correlation value between two symbols                       |
//+------------------------------------------------------------------+
double CCorrelationManager::GetCorrelation(const string symbol1, const string symbol2)
{
   if(!m_initialized) return 0.0;
   
   int idx = FindPairIndex(symbol1, symbol2);
   if(idx >= 0 && idx < m_pair_count)
   {
      return m_matrix[idx].value;
   }
   
   // If pair not in matrix, calculate on-demand
   double returns1[CORR_WINDOW_SIZE];
   double returns2[CORR_WINDOW_SIZE];
   
   GetPriceReturns(symbol1, returns1, CORR_WINDOW_SIZE);
   GetPriceReturns(symbol2, returns2, CORR_WINDOW_SIZE);
   
   return CalculatePearson(returns1, returns2, CORR_WINDOW_SIZE);
}

//+------------------------------------------------------------------+
//| Update entire correlation matrix                                |
//+------------------------------------------------------------------+
void CCorrelationManager::UpdateMatrix(const string& symbols[], int count)
{
   if(!m_initialized) return;
   if(count < 2) return;
   
   datetime now = TimeCurrent();
   
   // Calculate required pair count: n*(n-1)/2
   int required_pairs = (count * (count - 1)) / 2;
   if(required_pairs > ArraySize(m_matrix))
   {
      ArrayResize(m_matrix, required_pairs + 10);
   }
   
   m_pair_count = 0;
   
   // Calculate correlation for each unique pair
   for(int i = 0; i < count; i++)
   {
      for(int j = i + 1; j < count; j++)
      {
         if(symbols[i] == symbols[j]) continue;
         
         double returns1[CORR_WINDOW_SIZE];
         double returns2[CORR_WINDOW_SIZE];
         
         GetPriceReturns(symbols[i], returns1, CORR_WINDOW_SIZE);
         GetPriceReturns(symbols[j], returns2, CORR_WINDOW_SIZE);
         
         double corr = CalculatePearson(returns1, returns2, CORR_WINDOW_SIZE);
         
         m_matrix[m_pair_count].symbol1 = symbols[i];
         m_matrix[m_pair_count].symbol2 = symbols[j];
         m_matrix[m_pair_count].value = corr;
         m_matrix[m_pair_count].last_update = now;
         
         m_pair_count++;
      }
   }
   
   m_last_update = now;
   m_calc_count++;
}

//+------------------------------------------------------------------+
//| Get pair with highest correlation                               |
//+------------------------------------------------------------------+
string CCorrelationManager::GetHighestCorrelatedPair()
{
   if(m_pair_count == 0) return "";
   
   double max_corr = 0.0;
   int max_idx = -1;
   
   for(int i = 0; i < m_pair_count; i++)
   {
      double abs_corr = MathAbs(m_matrix[i].value);
      if(abs_corr > max_corr)
      {
         max_corr = abs_corr;
         max_idx = i;
      }
   }
   
   if(max_idx >= 0)
   {
      return StringFormat("%s/%s (%.2f)", 
                          m_matrix[max_idx].symbol1,
                          m_matrix[max_idx].symbol2,
                          m_matrix[max_idx].value);
   }
   
   return "";
}

//+------------------------------------------------------------------+
//| Print current correlation status                                |
//+------------------------------------------------------------------+
void CCorrelationManager::PrintStatus()
{
   if(!m_initialized) return;
   
   PrintFormat("[CORR] Status: %d pairs, last update %s", 
               m_pair_count, TimeToString(m_last_update));
   
   if(m_pair_count > 0)
   {
      Print("--- HIGH CORRELATION PAIRS (>|0.70|) ---");
      for(int i = 0; i < m_pair_count; i++)
      {
         if(MathAbs(m_matrix[i].value) >= 0.70)
         {
            PrintFormat("  %s <-> %s : %.3f", 
                        m_matrix[i].symbol1, 
                        m_matrix[i].symbol2, 
                        m_matrix[i].value);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Pearson correlation coefficient                       |
//+------------------------------------------------------------------+
double CCorrelationManager::CalculatePearson(const double &arr1[], const double &arr2[], int size)
{
   if(size < 2) return 0.0;
   
   double sum1 = 0.0, sum2 = 0.0;
   double sum1_sq = 0.0, sum2_sq = 0.0;
   double sum_prod = 0.0;
   
   for(int i = 0; i < size; i++)
   {
      double v1 = arr1[i];
      double v2 = arr2[i];
      
      sum1 += v1;
      sum2 += v2;
      sum1_sq += v1 * v1;
      sum2_sq += v2 * v2;
      sum_prod += v1 * v2;
   }
   
   double numerator = size * sum_prod - sum1 * sum2;
   double denominator = MathSqrt((size * sum1_sq - sum1 * sum1) * 
                                  (size * sum2_sq - sum2 * sum2));
   
   if(denominator == 0.0) return 0.0;
   
   return numerator / denominator;
}

//+------------------------------------------------------------------+
//| Get price returns for a symbol (log returns)                    |
//+------------------------------------------------------------------+
void CCorrelationManager::GetPriceReturns(const string symbol, double &returns[], int window)
{
   ArrayInitialize(returns, 0.0);
   
   // Get close prices for the last 'window+1' bars
   double closes[];
   ArraySetAsSeries(closes, true);
   
   int copied = CopyClose(symbol, PERIOD_CURRENT, 0, window + 1, closes);
   if(copied < window + 1) return;
   
   // Calculate log returns: ln(P_t / P_{t-1})
   for(int i = 0; i < window && i < ArraySize(returns); i++)
   {
      if(closes[i+1] > 0 && closes[i] > 0)
      {
         returns[i] = MathLog(closes[i+1] / closes[i]);
      }
   }
}

//+------------------------------------------------------------------+
//| Find pair index in matrix                                       |
//+------------------------------------------------------------------+
int CCorrelationManager::FindPairIndex(const string s1, const string s2)
{
   for(int i = 0; i < m_pair_count; i++)
   {
      if((m_matrix[i].symbol1 == s1 && m_matrix[i].symbol2 == s2) ||
         (m_matrix[i].symbol1 == s2 && m_matrix[i].symbol2 == s1))
      {
         return i;
      }
   }
   return -1;
}

#endif // PASR_CORRELATION_MANAGER_MQH
