//+------------------------------------------------------------------+
//| Infra/AccountSnapshot.mqh - per-cycle account state snapshot     |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_INFRA_ACCOUNT_SNAPSHOT_MQH__
#define __PASR_INFRA_ACCOUNT_SNAPSHOT_MQH__

struct SAccountSnapshot
  {
   datetime captured_at;
   long     login;
   double   balance;
   double   equity;
   double   margin;
   double   free_margin;
   double   margin_level;
   double   profit;
   double   drawdown_pct;
   bool     valid;

   void Clear()
     {
      captured_at = 0;
      login = 0;
      balance = 0.0;
      equity = 0.0;
      margin = 0.0;
      free_margin = 0.0;
      margin_level = 0.0;
      profit = 0.0;
      drawdown_pct = 0.0;
      valid = false;
     }

   bool Capture(const double peakEquity = 0.0)
     {
      captured_at = TimeCurrent();
      login = AccountInfoInteger(ACCOUNT_LOGIN);
      balance = AccountInfoDouble(ACCOUNT_BALANCE);
      equity = AccountInfoDouble(ACCOUNT_EQUITY);
      margin = AccountInfoDouble(ACCOUNT_MARGIN);
      free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      profit = AccountInfoDouble(ACCOUNT_PROFIT);
      double peak = (peakEquity > 0.0) ? peakEquity : balance;
      drawdown_pct = (peak > 0.0) ? MathMax(0.0, (1.0 - equity / peak) * 100.0) : 0.0;
      valid = (login > 0 && balance >= 0.0 && equity >= 0.0);
      return valid;
     }

   bool IsFresh(const int maxAgeSec = 5) const
     {
      return valid && captured_at > 0 && (TimeCurrent() - captured_at) <= maxAgeSec;
     }
  };

#endif // __PASR_INFRA_ACCOUNT_SNAPSHOT_MQH__
