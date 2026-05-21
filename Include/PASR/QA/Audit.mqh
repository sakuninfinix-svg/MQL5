//+------------------------------------------------------------------+
//| QA/Audit.mqh — v1.00                                             |
//| Config + system health auditor (PASR_QA_BUILD only)              |
//+------------------------------------------------------------------+
#property strict
#ifndef __QA_AUDIT_MQH__
#define __QA_AUDIT_MQH__

#include "../Core/IManager.mqh"
#include "../Trade/RiskManager.mqh"

//+------------------------------------------------------------------+
//| CPASRAudit — runtime health checks                               |
//+------------------------------------------------------------------+
class CPASRAudit
  {
private:
   const StrategyConfig *m_cfg;
   CRiskManager         *m_risk;

   struct AuditItem { string check; bool pass; string detail; };
   AuditItem m_items[32];
   int       m_count;

   void Add(const string check, bool pass, const string detail="")
     {
      if(m_count >= 32) return;
      m_items[m_count].check  = check;
      m_items[m_count].pass   = pass;
      m_items[m_count].detail = detail;
      m_count++;
     }

public:
   CPASRAudit(const StrategyConfig *cfg, CRiskManager *risk)
      : m_cfg(cfg), m_risk(risk), m_count(0) {}

   // Run all checks; returns true if all pass
   bool Run()
     {
      m_count = 0;

      // Config checks
      Add("MagicNumber > 0",           m_cfg.MagicNumber > 0);
      Add("RiskPerTrade in [0.1,10]",
          m_cfg.Risk.RiskPerTrade >= 0.1 && m_cfg.Risk.RiskPerTrade <= 10.0,
          StringFormat("%.2f", m_cfg.Risk.RiskPerTrade));
      Add("SLMultiplier >= 0.5",        m_cfg.Risk.SLMultiplier >= 0.5);
      Add("TPMultiplier >= SLMult",     m_cfg.Risk.TPMultiplier >= m_cfg.Risk.SLMultiplier);
      Add("MaxOpenTrades >= 1",         m_cfg.Risk.MaxOpenTrades >= 1);
      Add("MaxDailyLossPct in [0,50]",
          m_cfg.Risk.MaxDailyLossPct >= 0 && m_cfg.Risk.MaxDailyLossPct <= 50.0);
      Add("MaxDrawdownPct in [0,100]",
          m_cfg.Risk.MaxDrawdownPct >= 0 && m_cfg.Risk.MaxDrawdownPct <= 100.0);

      // Account checks
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      Add("AccountBalance > 0", bal > 0, StringFormat("%.2f", bal));
      Add("Leverage >= 1",      AccountInfoInteger(ACCOUNT_LEVERAGE) >= 1);

      // Symbol checks
      Add("Symbol digits valid", _Digits >= 2 && _Digits <= 8);
      Add("Symbol point > 0",    _Point > 0);

      // Risk state (if available)
      if(m_risk != NULL)
        {
         Add("DD < max", m_risk.GetDrawdownPct() < m_cfg.Risk.MaxDrawdownPct,
             StringFormat("DD=%.1f%%", m_risk.GetDrawdownPct()));
         Add("Daily PnL > loss limit",
             m_risk.GetDailyPnLPct() > -m_cfg.Risk.MaxDailyLossPct,
             StringFormat("DailyPnL=%.1f%%", m_risk.GetDailyPnLPct()));
        }

      // Report
      bool allPass = true;
      for(int i=0; i<m_count; i++)
        {
         if(!m_items[i].pass)
           {
            allPass = false;
            PrintFormat("[Audit] FAIL: %s %s", m_items[i].check, m_items[i].detail);
           }
         else if(m_items[i].detail != "")
            PrintFormat("[Audit] OK:   %s = %s", m_items[i].check, m_items[i].detail);
        }

      PrintFormat("[Audit] %d/%d checks passed", m_count - (allPass?0:1), m_count);
      return allPass;
     }

   int  GetCount()  const { return m_count; }
   bool GetResult(int i) const { return (i>=0&&i<m_count)?m_items[i].pass:false; }
  };

#endif
