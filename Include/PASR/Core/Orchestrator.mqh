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
//|    L5c RiskManager (NEW Phase 3)                                 |
//|    L6a ExecutionManager                                          |
//|    L6b RecoveryManager                                           |
//|    L7  DashboardManager + inject deps                            |
//|                                                                  |
//|  CHANGE LOG:                                                     |
//|  v2.00 (2026-05-21) — Phase 3 complete wiring:                   |
//|    + CAnalysisSRManager + CAnalysisZoneManager added            |
//|    + CRiskManager added (missing #7 from architecture)           |
//|    + SignalManager deps injected (Pattern, SR, Regime)           |
//|    + 3 ISignalSource plugins registered:                         |
//|        PatternSignalSource (w=1.2)                               |
//|        SRSignalSource      (w=1.5)                               |
//|        AISignalSource      (w=0.8)                               |
//|    + RiskManager.Check() gate before Execute()                   |
//|    + DashboardManager gets RiskManager + SignalManager refs      |
//|    + RecoveryManager.OnTradeOpen/Close called on transactions     |
//|    + New-bar logic separated from every-tick logic               |
//|  v1.01 (2026-05-21) — FIX #1/#2/#4 (see history)               |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __CORE_ORCHESTRATOR_MQH__
#define __CORE_ORCHESTRATOR_MQH__

#ifdef __CORE_PASR_MASTER_MQH__
  // OK
#else
  #error "Include <PASR/Core/PASR.mqh> instead of Orchestrator.mqh directly."
#endif

//+------------------------------------------------------------------+
//| COrchestrator — owns all managers, wires them together           |
//+------------------------------------------------------------------+
class COrchestrator
  {
private:
   // ── Managers (owned, heap-allocated)
   CDataManager           *m_data;
   CAnalysisSRManager     *m_sr;
   CAnalysisZoneManager   *m_zone;
   CPatternManager        *m_pattern;
   CSignalManager         *m_signal;
   AIManager              *m_ai;
   CRiskManager           *m_risk;
   CExecutionManager      *m_exec;
   CRecoveryManager       *m_recovery;
   CDashboardManager      *m_dash;

   // ── Signal source plugins (owned)
   PatternSignalSource    *m_srcPattern;
   SRSignalSource         *m_srcSR;
   AISignalSource         *m_srcAI;

   // ── Infrastructure
   CEventBus              *m_bus;
   StrategyConfig          m_cfg;
   CConfigManager         *m_cfgMgr;

   datetime   m_lastBarTime;
   bool       m_debugMode;
   bool       m_initialised;

   // ─────────────────────────────────────────────────────────────────
   bool BarChanged()
     {
      datetime t = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
      if(t != m_lastBarTime) { m_lastBarTime = t; return true; }
      return false;
     }

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

   void DrainQueue()
     {
      PASREvent ev;
      while(m_bus.Pop(ev))
         m_bus.Dispatch(ev);
     }

   void FreeAll()
     {
      // signal sources before managers (non-owning ptrs inside managers)
      if(m_srcPattern) { delete m_srcPattern; m_srcPattern=NULL; }
      if(m_srcSR)      { delete m_srcSR;      m_srcSR=NULL;      }
      if(m_srcAI)      { delete m_srcAI;      m_srcAI=NULL;      }

      if(m_dash)     { delete m_dash;     m_dash=NULL;     }
      if(m_recovery) { delete m_recovery; m_recovery=NULL; }
      if(m_exec)     { delete m_exec;     m_exec=NULL;     }
      if(m_risk)     { delete m_risk;     m_risk=NULL;     }
      if(m_ai)       { delete m_ai;       m_ai=NULL;       }
      if(m_signal)   { delete m_signal;   m_signal=NULL;   }
      if(m_pattern)  { delete m_pattern;  m_pattern=NULL;  }
      if(m_zone)     { delete m_zone;     m_zone=NULL;     }
      if(m_sr)       { delete m_sr;       m_sr=NULL;       }
      if(m_data)     { delete m_data;     m_data=NULL;     }
      if(m_cfgMgr)   { delete m_cfgMgr;   m_cfgMgr=NULL;   }
      if(m_bus)      { delete m_bus;      m_bus=NULL;      }
     }

   // ── Core trading logic called on new bar ────────────────────────
   void ProcessNewBar()
     {
      // 1) Signal available?
      if(!m_signal.HasSignal()) return;

      FinalSignal sig = m_signal.GetCurrent();
      if(sig.direction == SIGNAL_NONE) return;

      // 2) Risk gate: check before any execution
      RiskCheckResult rr = m_risk.Check(0);   // pre-check without lot (margin check uses estimated lot)
      if(!rr.allowed)
        {
         if(m_debugMode)
            PrintFormat("[Orchestrator] RiskBlock: %s", rr.reason);
         return;
        }

      // 3) Build trade plan
      CTradePlan builder;
      builder.Init(m_data, m_bus);
      builder.SetCfg(m_cfg);

      double lot  = m_risk.CalcLot(m_data.GetATRPoints() * m_cfg.Risk.SLMultiplier);
      TradePlan plan = builder.Build(sig, lot);
      if(!plan.valid) return;

      // 4) Final risk check with real SL points
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
            PrintFormat("[Orchestrator] Trade opened ticket=%d", er.ticket);
        }
     }

public:
   COrchestrator()
      : m_data(NULL), m_sr(NULL), m_zone(NULL),
        m_pattern(NULL), m_signal(NULL), m_ai(NULL),
        m_risk(NULL), m_exec(NULL), m_recovery(NULL), m_dash(NULL),
        m_srcPattern(NULL), m_srcSR(NULL), m_srcAI(NULL),
        m_bus(NULL), m_cfgMgr(NULL),
        m_lastBarTime(0), m_debugMode(false), m_initialised(false)
     {}

   ~COrchestrator() { FreeAll(); }

   void SetDebugMode(bool on) { m_debugMode = on; }

   //+----------------------------------------------------------------+
   //| Init — full Phase 3 wiring                                    |
   //+----------------------------------------------------------------+
   int Init()
     {
      // ── L0: Config
      m_cfgMgr = new CConfigManager();
      if(m_cfgMgr==NULL || !m_cfgMgr.Init(m_cfg))
        { Print("[Orchestrator] Config init FAILED"); return INIT_PARAMETERS_INCORRECT; }

      m_bus = new CEventBus();
      if(m_bus==NULL) { Print("[Orchestrator] EventBus alloc FAILED"); return INIT_FAILED; }

      // ── L2: DataManager
      m_data = new CDataManager();
      if(m_data==NULL || !m_data.Init(m_cfg))
        { Print("[Orchestrator] DataManager FAILED"); FreeAll(); return INIT_FAILED; }

      // ── L3: Analysis — SR + Zone
      m_sr   = new CAnalysisSRManager();
      if(!InitManager(m_sr,   "CAnalysisSRManager"))   { FreeAll(); return INIT_FAILED; }

      m_zone = new CAnalysisZoneManager();
      if(!InitManager(m_zone, "CAnalysisZoneManager")) { FreeAll(); return INIT_FAILED; }

      // ── L4: Pattern
      m_pattern = new CPatternManager();
      if(!InitManager(m_pattern, "CPatternManager")) { FreeAll(); return INIT_FAILED; }

      // ── L5a: SignalManager + inject deps + register sources
      m_signal = new CSignalManager();
      if(!InitManager(m_signal, "CSignalManager")) { FreeAll(); return INIT_FAILED; }

      m_signal.SetPatternManager(m_pattern);
      m_signal.SetSRManager((CSRManager*)m_sr);  // upcast: Analysis SR is-a CSRManager

      // Register signal sources with weights
      m_srcPattern = new PatternSignalSource(m_pattern);
      m_srcSR      = new SRSignalSource(m_sr, m_data, 0.5);

      m_signal.RegisterSource(m_srcPattern, 1.2);  // PA pattern: high weight
      m_signal.RegisterSource(m_srcSR,      1.5);  // SR confluence: highest weight

      // ── L5b: AI
      m_ai = new AIManager();
      if(!InitManager(m_ai, "AIManager")) { FreeAll(); return INIT_FAILED; }

      m_srcAI = new AISignalSource(m_ai, 0.6, 0.8);
      m_signal.RegisterSource(m_srcAI, 0.8);       // AI: lower weight (learning)

      // ── L5c: RiskManager (Phase 3 addition)
      m_risk = new CRiskManager();
      if(!InitManager(m_risk, "CRiskManager")) { FreeAll(); return INIT_FAILED; }

      // ── L6a: ExecutionManager
      m_exec = new CExecutionManager();
      if(!InitManager(m_exec, "CExecutionManager")) { FreeAll(); return INIT_FAILED; }

      // ── L6b: RecoveryManager
      m_recovery = new CRecoveryManager();
      if(!InitManager(m_recovery, "CRecoveryManager")) { FreeAll(); return INIT_FAILED; }

      // ── L7: DashboardManager + inject deps
      m_dash = new CDashboardManager();
      if(!InitManager(m_dash, "CDashboardManager")) { FreeAll(); return INIT_FAILED; }
      m_dash.SetRiskManager(m_risk);
      m_dash.SetSignalManager(m_signal);

      m_initialised = true;
      Print("[Orchestrator] v2.00 Init OK — all managers wired");
      return INIT_SUCCEEDED;
     }

   //+----------------------------------------------------------------+
   //| OnTick — separated: every-tick vs new-bar logic               |
   //+----------------------------------------------------------------+
   void OnTick()
     {
      if(!m_initialised) return;

      // Every tick: price data + price-update event
      m_data.OnTick();
      PASREvent evTick;
      evTick.id       = EVENT_ID_PRICE_UPDATE;
      evTick.priority = 5;
      m_bus.Push(evTick);

      bool isNewBar = BarChanged();
      if(isNewBar)
        {
         // New bar: fire bar event → all analysis managers update
         PASREvent evBar;
         evBar.id       = EVENT_ID_NEW_BAR;
         evBar.priority = 10;
         m_bus.Push(evBar);

         // Drain analysis events first so pattern/signal/SR are up to date
         DrainQueue();

         // Then attempt trade entry
         ProcessNewBar();
        }

      // Final drain: flush trailing stop + dashboard events
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

      // Trade OPENED (DEAL_ENTRY_IN)
      if(entry == DEAL_ENTRY_IN)
        {
         int    dir      = (int)HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BUY ? 1 : -1;
         double price    = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         m_recovery.OnTradeOpen((ulong)pos, dir, price);
        }

      // Trade CLOSED (DEAL_ENTRY_OUT / DEAL_ENTRY_INOUT)
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
        {
         m_recovery.OnTradeClose((ulong)pos);
         m_risk.OnTradeClosed();

         // AI backprop
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

         // Fire position update event
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
      if(m_dash != NULL) m_dash.Destroy();
      FreeAll();
      PrintFormat("[Orchestrator] Deinit (reason=%d)", reason);
     }

   // ── Accessors
   CDataManager         *GetDataManager()     const { return m_data;     }
   CAnalysisSRManager   *GetSRManager()       const { return m_sr;       }
   CAnalysisZoneManager *GetZoneManager()     const { return m_zone;     }
   CSignalManager       *GetSignalManager()   const { return m_signal;   }
   AIManager            *GetAIManager()       const { return m_ai;       }
   CRiskManager         *GetRiskManager()     const { return m_risk;     }
   CExecutionManager    *GetExecManager()     const { return m_exec;     }
   CRecoveryManager     *GetRecoveryManager() const { return m_recovery; }
   const StrategyConfig &GetConfig()          const { return m_cfg;      }
  };

#endif // __CORE_ORCHESTRATOR_MQH__
