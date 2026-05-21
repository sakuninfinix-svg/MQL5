//+------------------------------------------------------------------+
//|                               Core/Orchestrator.mqh             |
//|                          Copyright 2026, Agsicentre             |
//|                                                                  |
//|  PURPOSE: Owns and wires all PASR managers.                      |
//|    EA's OnInit/OnTick/OnDeinit/OnTradeTransaction → delegate    |
//|    to COrchestrator with one call each.                         |
//|                                                                  |
//|  USAGE (in your EA .mq5 file):                                   |
//|    #include <PASR/Core/PASR.mqh>                                 |
//|    COrchestrator g_orch;                                         |
//|    int OnInit()   { return g_orch.Init(); }                      |
//|    void OnTick()  { g_orch.OnTick();  }                          |
//|    void OnDeinit(const int r) { g_orch.OnDeinit(r); }            |
//|    void OnTimer() { g_orch.OnTimer(); }                          |
//|    void OnTradeTransaction(                                      |
//|           const MqlTradeTransaction &t,                          |
//|           const MqlTradeRequest &rq,                             |
//|           const MqlTradeResult   &rs)                            |
//|    { g_orch.OnTradeTransaction(t, rq, rs); }                     |
//|                                                                  |
//|  INIT ORDER:                                                      |
//|    L0  Config Validate                                           |
//|    L2  DataManager                                               |
//|    L3  SRManager (Analysis) + ZoneManager (Analysis)            |
//|    L4  PatternManager                                            |
//|    L5a SignalManager + inject deps + register sources            |
//|    L5b AIManager + AISignalSource                                |
//|    L5c RegimeFilter + RegimeSignalSource  [Phase 4 NEW]          |
//|    L5d RiskManager                        [Phase 4 NEW position] |
//|    L6a ExecutionManager                                          |
//|    L6b RecoveryManager                                           |
//|    L7  DashboardManager + inject deps (Risk+Signal+Regime)       |
//|                                                                  |
//|  SIGNAL SOURCE WIRING (all sources + weights):                   |
//|    PatternSignalSource  w=1.2  VOTER  — price action patterns    |
//|    SRSignalSource       w=1.5  VOTER  — SR zone proximity        |
//|    AISignalSource       w=0.8  VOTER  — neural net confidence    |
//|    RegimeSignalSource   w=0.0  MULT   — regime modulator         |
//|      (set w=-1.0 to use VETO mode: VOLATILE blocks all signals)  |
//|                                                                  |
//|  CHANGE LOG:                                                     |
//|  v2.10 (2026-05-21) — Phase 4 wiring:                           |
//|    + CRegimeFilter allocated + init (L5c)                        |
//|    + CRegimeSignalSource registered as MULT (w=0.0)              |
//|      Regime TRENDING → x1.3 score boost                         |
//|      Regime RANGING  → x0.8 score cut                           |
//|      Regime VOLATILE → SIGNAL_NONE (acts like veto via w=0)     |
//|      Regime SQUEEZE  → x0.6 score cut                           |
//|    + SignalManager.SetRegimeManager() call added                 |
//|    + DashboardManager.SetRegimeFilter() call added               |
//|    + FreeAll(): m_regime + m_srcRegime added                     |
//|    + PrintSummary(): all managers listed with version            |
//|  v2.00 (2026-05-21) — Phase 3 complete wiring                   |
//|  v1.01 (2026-05-21) — FIX #1/#2/#4                              |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __CORE_ORCHESTRATOR_MQH__
#define __CORE_ORCHESTRATOR_MQH__

#ifdef __CORE_PASR_MASTER_MQH__
  // OK — included via PASR.mqh
#else
  #error "Include <PASR/Core/PASR.mqh> instead of Orchestrator.mqh directly."
#endif

//+------------------------------------------------------------------+
//| COrchestrator — owns all managers, wires them together           |
//+------------------------------------------------------------------+
class COrchestrator
  {
private:
   // ── Managers (owned, heap-allocated) ───────────────────────────
   CDataManager           *m_data;
   CAnalysisSRManager     *m_sr;
   CAnalysisZoneManager   *m_zone;
   CPatternManager        *m_pattern;
   CSignalManager         *m_signal;
   AIManager              *m_ai;
   CRegimeFilter          *m_regime;    // Phase 4 NEW
   CRiskManager           *m_risk;
   CExecutionManager      *m_exec;
   CRecoveryManager       *m_recovery;
   CDashboardManager      *m_dash;

   // ── Signal source plugins (owned) ──────────────────────────────
   PatternSignalSource    *m_srcPattern;
   SRSignalSource         *m_srcSR;
   AISignalSource         *m_srcAI;
   CRegimeSignalSource    *m_srcRegime;  // Phase 4 NEW

   // ── Infrastructure ─────────────────────────────────────────────
   CEventBus              *m_bus;
   StrategyConfig          m_cfg;
   CConfigManager         *m_cfgMgr;

   datetime   m_lastBarTime;
   bool       m_debugMode;
   bool       m_initialised;

   // ── Bar detection ──────────────────────────────────────────────
   bool BarChanged()
     {
      datetime t = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
      if(t != m_lastBarTime) { m_lastBarTime = t; return true; }
      return false;
     }

   // ── Manager registration helpers ───────────────────────────────
   void RegisterManager(IManager *mgr)
     {
      if(mgr == NULL) return;
      mgr.DeclareEvents();
      m_bus.Register(mgr);
     }

   bool InitManager(IManager *mgr, const string name)
     {
      if(mgr == NULL)
        { PrintFormat("[Orchestrator] %s: alloc failed", name); return false; }
      if(m_debugMode) mgr.SetDebugMode(true);
      if(!mgr.Init(m_data, m_bus))
        { PrintFormat("[Orchestrator] %s.Init() FAILED", name); return false; }
      RegisterManager(mgr);
      return true;
     }

   // ── Event queue drain ──────────────────────────────────────────
   void DrainQueue()
     {
      PASREvent ev;
      while(m_bus.Pop(ev))
         m_bus.Dispatch(ev);
     }

   // ── Init summary log ───────────────────────────────────────────
   void PrintSummary()
     {
      Print("╔══════════════════════════════════════════════════╗");
      PrintFormat("║  PASR EA v3.00 — %s  %s", _Symbol,
                  EnumToString((ENUM_TIMEFRAMES)_Period));
      Print("╠══════════════════════════════════════════════════╣");
      Print("║  Managers:");
      PrintFormat("║    DataManager        : OK");
      PrintFormat("║    SRManager(Analysis): OK  zones=%d",
                  m_sr != NULL ? m_sr.ZoneCount() : 0);
      PrintFormat("║    ZoneManager(S/D)   : OK");
      PrintFormat("║    PatternManager     : OK");
      PrintFormat("║    SignalManager v3   : OK  sources=%d",
                  m_signal != NULL ? m_signal.SourceCount() : 0);
      PrintFormat("║      Registered sources:");
      PrintFormat("║        PatternSignalSource w=1.2 VOTER");
      PrintFormat("║        SRSignalSource      w=1.5 VOTER");
      PrintFormat("║        AISignalSource      w=0.8 VOTER");
      PrintFormat("║        RegimeSignalSource  w=0.0 MULT");
      PrintFormat("║    AIManager              : OK");
      PrintFormat("║    RegimeFilter    [P4]   : OK");
      PrintFormat("║    RiskManager     [P4]   : OK  magic=%d", m_cfg.MagicNumber);
      PrintFormat("║    ExecutionManager       : OK");
      PrintFormat("║    RecoveryManager        : OK");
      PrintFormat("║    DashboardManager v3    : OK");
      Print("╚══════════════════════════════════════════════════╝");
     }

   // ── Cleanup ────────────────────────────────────────────────────
   void FreeAll()
     {
      // signal source plugins before managers that hold non-owning ptrs
      if(m_srcRegime)  { delete m_srcRegime;  m_srcRegime=NULL;  }
      if(m_srcPattern) { delete m_srcPattern; m_srcPattern=NULL; }
      if(m_srcSR)      { delete m_srcSR;      m_srcSR=NULL;      }
      if(m_srcAI)      { delete m_srcAI;      m_srcAI=NULL;      }

      if(m_dash)     { delete m_dash;     m_dash=NULL;     }
      if(m_recovery) { delete m_recovery; m_recovery=NULL; }
      if(m_exec)     { delete m_exec;     m_exec=NULL;     }
      if(m_risk)     { delete m_risk;     m_risk=NULL;     }
      if(m_regime)   { delete m_regime;   m_regime=NULL;   }
      if(m_ai)       { delete m_ai;       m_ai=NULL;       }
      if(m_signal)   { delete m_signal;   m_signal=NULL;   }
      if(m_pattern)  { delete m_pattern;  m_pattern=NULL;  }
      if(m_zone)     { delete m_zone;     m_zone=NULL;     }
      if(m_sr)       { delete m_sr;       m_sr=NULL;       }
      if(m_data)     { delete m_data;     m_data=NULL;     }
      if(m_cfgMgr)   { delete m_cfgMgr;   m_cfgMgr=NULL;   }
      if(m_bus)      { delete m_bus;      m_bus=NULL;      }
     }

   // ── Core trading logic (called once per new bar) ────────────────
   void ProcessNewBar()
     {
      // 1) Signal available?
      if(!m_signal.HasSignal()) return;

      FinalSignal sig = m_signal.GetCurrent();
      if(sig.direction == SIGNAL_NONE) return;

      // 2) Pre-trade risk gate (no lot yet — margin estimate)
      RiskCheckResult rr = m_risk.Check(0);
      if(!rr.allowed)
        {
         if(m_debugMode)
            PrintFormat("[Orchestrator] RiskBlock(pre): %s", rr.reason);
         return;
        }

      // 3) Build trade plan
      CTradePlan builder;
      builder.Init(m_data, m_bus);
      builder.SetCfg(m_cfg);

      double atrSL = m_data.GetATRPoints() * m_cfg.Risk.SLMultiplier;
      double lot   = m_risk.CalcLot(atrSL);
      TradePlan plan = builder.Build(sig, lot);
      if(!plan.valid) return;

      // 4) Final risk check with real SL distance
      RiskCheckResult rr2 = m_risk.Check(plan.slPoints);
      if(!rr2.allowed)
        {
         if(m_debugMode)
            PrintFormat("[Orchestrator] RiskBlock(lot): %s", rr2.reason);
         return;
        }
      plan.lot = rr2.suggestedLot;

      // 5) Execute
      ExecResult er = m_exec.Execute(plan);
      if(er.status == EXEC_OK)
        {
         m_risk.OnTradeOpened();
         m_recovery.OnTradeOpen(er.ticket, plan.direction, plan.entryPrice);
         if(m_debugMode)
            PrintFormat("[Orchestrator] ✓ Trade opened ticket=%d lot=%.2f %s",
                        er.ticket, plan.lot,
                        plan.direction==SIGNAL_BUY ? "BUY" : "SELL");
        }
     }

public:
   COrchestrator()
      : m_data(NULL), m_sr(NULL), m_zone(NULL),
        m_pattern(NULL), m_signal(NULL), m_ai(NULL),
        m_regime(NULL), m_risk(NULL),
        m_exec(NULL), m_recovery(NULL), m_dash(NULL),
        m_srcPattern(NULL), m_srcSR(NULL),
        m_srcAI(NULL), m_srcRegime(NULL),
        m_bus(NULL), m_cfgMgr(NULL),
        m_lastBarTime(0), m_debugMode(false), m_initialised(false)
     {}

   ~COrchestrator() { FreeAll(); }

   void SetDebugMode(bool on) { m_debugMode = on; }

   //+----------------------------------------------------------------+
   //| Init — Phase 4 complete wiring                                 |
   //+----------------------------------------------------------------+
   int Init()
     {
      // ── L0: Config ──────────────────────────────────────────────
      m_cfgMgr = new CConfigManager();
      if(m_cfgMgr==NULL || !m_cfgMgr.Init(m_cfg))
        { Print("[Orchestrator] Config FAILED"); return INIT_PARAMETERS_INCORRECT; }

      m_bus = new CEventBus();
      if(m_bus==NULL)
        { Print("[Orchestrator] EventBus alloc FAILED"); return INIT_FAILED; }

      // ── L2: DataManager ─────────────────────────────────────────
      m_data = new CDataManager();
      if(m_data==NULL || !m_data.Init(m_cfg))
        { Print("[Orchestrator] DataManager FAILED"); FreeAll(); return INIT_FAILED; }

      // ── L3: Analysis — SR + Zone ────────────────────────────────
      m_sr = new CAnalysisSRManager();
      if(!InitManager(m_sr, "CAnalysisSRManager")) { FreeAll(); return INIT_FAILED; }

      m_zone = new CAnalysisZoneManager();
      if(!InitManager(m_zone, "CAnalysisZoneManager")) { FreeAll(); return INIT_FAILED; }

      // ── L4: Pattern ─────────────────────────────────────────────
      m_pattern = new CPatternManager();
      if(!InitManager(m_pattern, "CPatternManager")) { FreeAll(); return INIT_FAILED; }

      // ── L5a: SignalManager ──────────────────────────────────────
      m_signal = new CSignalManager();
      if(!InitManager(m_signal, "CSignalManager")) { FreeAll(); return INIT_FAILED; }

      m_signal.SetPatternManager(m_pattern);
      m_signal.SetSRManager((CSRManager*)m_sr);   // Analysis SR is-a CSRManager

      // Register voter sources
      m_srcPattern = new PatternSignalSource(m_pattern);
      m_srcSR      = new SRSignalSource(m_sr, m_data, 0.5);
      m_signal.RegisterSource(m_srcPattern, 1.2); // VOTER: PA pattern
      m_signal.RegisterSource(m_srcSR,      1.5); // VOTER: SR confluence

      // ── L5b: AI + AISignalSource ────────────────────────────────
      m_ai = new AIManager();
      if(!InitManager(m_ai, "AIManager")) { FreeAll(); return INIT_FAILED; }

      m_srcAI = new AISignalSource(m_ai, 0.6, 0.8);
      m_signal.RegisterSource(m_srcAI, 0.8);      // VOTER: AI (learning weight)

      // ── L5c: RegimeFilter + RegimeSignalSource ── Phase 4 NEW ───
      m_regime = new CRegimeFilter();
      if(!InitManager(m_regime, "CRegimeFilter")) { FreeAll(); return INIT_FAILED; }

      m_signal.SetRegimeManager((CMarketRegime*)m_regime); // Regime is-a CMarketRegime

      // Register as MULT (w=0.0):
      //   TRENDING  → multiplier x1.3 (boost score)
      //   RANGING   → multiplier x0.8 (reduce score)
      //   VOLATILE  → direction=SIGNAL_NONE, confidence=0 (suppress)
      //   SQUEEZE   → multiplier x0.6 (strong reduce)
      // To use HARD VETO instead: change weight to -1.0
      m_srcRegime = new CRegimeSignalSource(m_regime);
      m_signal.RegisterSource(m_srcRegime, 0.0);  // MULT: regime modulator

      // ── L5d: RiskManager ────────────────────────────────────────
      m_risk = new CRiskManager();
      if(!InitManager(m_risk, "CRiskManager")) { FreeAll(); return INIT_FAILED; }

      // ── L6a: ExecutionManager ───────────────────────────────────
      m_exec = new CExecutionManager();
      if(!InitManager(m_exec, "CExecutionManager")) { FreeAll(); return INIT_FAILED; }

      // ── L6b: RecoveryManager ────────────────────────────────────
      m_recovery = new CRecoveryManager();
      if(!InitManager(m_recovery, "CRecoveryManager")) { FreeAll(); return INIT_FAILED; }

      // ── L7: DashboardManager + inject all deps ── v3.00 ────────
      m_dash = new CDashboardManager();
      if(!InitManager(m_dash, "CDashboardManager")) { FreeAll(); return INIT_FAILED; }
      m_dash.SetRiskManager  (m_risk);
      m_dash.SetSignalManager(m_signal);
      m_dash.SetRegimeFilter (m_regime);  // Phase 4 NEW

      m_initialised = true;
      PrintSummary();
      return INIT_SUCCEEDED;
     }

   //+----------------------------------------------------------------+
   //| OnTick — every-tick vs new-bar separated                       |
   //+----------------------------------------------------------------+
   void OnTick()
     {
      if(!m_initialised) return;

      // Every tick: update price + fire PRICE_UPDATE
      m_data.OnTick();
      PASREvent evTick;
      evTick.id       = EVENT_ID_PRICE_UPDATE;
      evTick.priority = 5;
      m_bus.Push(evTick);

      bool isNewBar = BarChanged();
      if(isNewBar)
        {
         PASREvent evBar;
         evBar.id       = EVENT_ID_NEW_BAR;
         evBar.priority = 10;
         m_bus.Push(evBar);

         // Drain analysis (SR, Pattern, Regime, Signal) before entry attempt
         DrainQueue();

         // Attempt trade entry
         ProcessNewBar();
        }

      // Final drain: trailing stop + dashboard updates
      DrainQueue();
     }

   //+----------------------------------------------------------------+
   //| OnTimer                                                        |
   //+----------------------------------------------------------------+
   void OnTimer()
     {
      if(!m_initialised) return;
      PASREvent ev; ev.id=EVENT_ID_TIMER; ev.priority=1;
      m_bus.Push(ev);
      DrainQueue();
     }

   //+----------------------------------------------------------------+
   //| OnTradeTransaction                                             |
   //+----------------------------------------------------------------+
   void OnTradeTransaction(const MqlTradeTransaction &trans,
                            const MqlTradeRequest    &request,
                            const MqlTradeResult     &result)
     {
      if(!m_initialised) return;
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
      if(trans.deal  == 0) return;
      if(!HistoryDealSelect(trans.deal)) return;
      if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != m_cfg.MagicNumber) return;

      ENUM_DEAL_ENTRY entry  = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      double          profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      ulong           pos    = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

      // Trade OPENED
      if(entry == DEAL_ENTRY_IN)
        {
         int    dir   = (int)HistoryDealGetInteger(trans.deal, DEAL_TYPE)==DEAL_TYPE_BUY ? 1 : -1;
         double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         m_recovery.OnTradeOpen((ulong)pos, dir, price);
        }

      // Trade CLOSED
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
        {
         m_recovery.OnTradeClose((ulong)pos);
         m_risk.OnTradeClosed();

         // AI backpropagation on result
         if(m_ai != NULL)
           {
            float label = (profit >= 0.0) ? 1.0f : 0.0f;
            float features[AI_INPUT_DIM];
            if(m_ai.BuildFeaturesPublic(features))
               m_ai.OnTradeResult(features, label);
            else
              {
               ArrayInitialize(features, 0.0f);
               m_ai.OnTradeResult(features, label, 0.1f);
              }
           }

         // Fire position update → dashboard redraws immediately
         PASREvent ev;
         ev.id=EVENT_ID_POSITION_UPDATE; ev.priority=8;
         ev.ticket=pos; ev.profit=profit;
         m_bus.Push(ev);
         DrainQueue();
        }
     }

   //+----------------------------------------------------------------+
   //| OnDeinit                                                       |
   //+----------------------------------------------------------------+
   void OnDeinit(const int reason)
     {
      if(!m_initialised) return;
      m_initialised = false;
      if(m_ai   != NULL) m_ai.Deinit();
      if(m_dash != NULL) m_dash.Destroy();  // removes chart objects before FreeAll
      FreeAll();
      PrintFormat("[Orchestrator] Deinit reason=%d", reason);
     }

   // ── Accessors (for external tools / QA) ────────────────────────
   CDataManager         *GetDataManager()     const { return m_data;     }
   CAnalysisSRManager   *GetSRManager()       const { return m_sr;       }
   CAnalysisZoneManager *GetZoneManager()     const { return m_zone;     }
   CSignalManager       *GetSignalManager()   const { return m_signal;   }
   AIManager            *GetAIManager()       const { return m_ai;       }
   CRegimeFilter        *GetRegimeFilter()    const { return m_regime;   }
   CRiskManager         *GetRiskManager()     const { return m_risk;     }
   CExecutionManager    *GetExecManager()     const { return m_exec;     }
   CRecoveryManager     *GetRecoveryManager() const { return m_recovery; }
   CDashboardManager    *GetDashboard()       const { return m_dash;     }
   const StrategyConfig &GetConfig()          const { return m_cfg;      }
  };

#endif // __CORE_ORCHESTRATOR_MQH__
