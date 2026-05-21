//+------------------------------------------------------------------+
//|                               Core/Orchestrator.mqh             |
//|                          Copyright 2026, Agsicentre             |
//|                                                                  |
//|  PURPOSE: Owns and wires all PASR managers into a single object  |
//|    that the EA's OnInit/OnTick/OnDeinit/OnTradeTransaction       |
//|    can delegate to with one line each.                           |
//|                                                                  |
//|  USAGE (in your EA .mq5 file):                                   |
//|    #include <PASR/Core/PASR.mqh>                                 |
//|    COrchestrator g_orch;                                         |
//|                                                                  |
//|    int OnInit()   { return g_orch.Init(); }                      |
//|    void OnTick()  { g_orch.OnTick(); }                           |
//|    void OnDeinit(const int r) { g_orch.OnDeinit(r); }            |
//|    void OnTimer() { g_orch.OnTimer(); }                          |
//|    void OnTradeTransaction(                                      |
//|           const MqlTradeTransaction &t,                          |
//|           const MqlTradeRequest &rq,                             |
//|           const MqlTradeResult   &rs)                            |
//|    { g_orch.OnTradeTransaction(t, rq, rs); }                     |
//|                                                                  |
//|  INIT ORDER (matches PASR.mqh L-numbers):                        |
//|    L0  Config Validate (gate: INIT_PARAMETERS_INCORRECT on fail) |
//|    L2  DataManager                                               |
//|    L4  PatternManager                                            |
//|    L5a SignalManager                                             |
//|    L5b AIManager                                                 |
//|    L6a ExecutionManager                                          |
//|    L6b RecoveryManager                                           |
//|    L7  DashboardManager                                          |
//|                                                                  |
//|  CHANGE LOG:                                                     |
//|  v1.01 (2026-05-21) — All issues fixed:                         |
//|    FIX #1/#2: Replace m_bus.Dispatch() with Push()+DrainQueue() |
//|    FIX #1:    RegisterManager() now calls m_bus.Register()       |
//|    FIX #4:    OnTradeTransaction passes real features to AI      |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __CORE_ORCHESTRATOR_MQH__
#define __CORE_ORCHESTRATOR_MQH__

#ifdef __CORE_PASR_MASTER_MQH__
  // OK — included from PASR.mqh
#else
  #error "Include <PASR/Core/PASR.mqh> instead of Orchestrator.mqh directly."
#endif

//+------------------------------------------------------------------+
//| COrchestrator                                                    |
//+------------------------------------------------------------------+
class COrchestrator
  {
private:
   CDataManager       *m_data;
   CPatternManager    *m_pattern;
   CSignalManager     *m_signal;
   AIManager          *m_ai;
   CExecutionManager  *m_exec;
   CRecoveryManager   *m_recovery;
   CDashboardManager  *m_dash;

   CEventBus          *m_bus;
   StrategyConfig      m_cfg;
   CConfigManager     *m_cfgMgr;

   datetime   m_lastBarTime;
   bool       m_debugMode;
   bool       m_initialised;

   bool BarChanged()
     {
      datetime t = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
      if(t != m_lastBarTime) { m_lastBarTime = t; return true; }
      return false;
     }

   // FIX #1: Register manager with bus subscriber list
   void RegisterManager(IManager *mgr)
     {
      if(mgr == NULL) return;
      mgr.DeclareEvents();
      m_bus.Register(mgr);  // FIX #1 — was missing
     }

   void FreeAll()
     {
      if(m_dash)     { delete m_dash;     m_dash     = NULL; }
      if(m_recovery) { delete m_recovery; m_recovery = NULL; }
      if(m_exec)     { delete m_exec;     m_exec     = NULL; }
      if(m_ai)       { delete m_ai;       m_ai       = NULL; }
      if(m_signal)   { delete m_signal;   m_signal   = NULL; }
      if(m_pattern)  { delete m_pattern;  m_pattern  = NULL; }
      if(m_data)     { delete m_data;     m_data     = NULL; }
      if(m_cfgMgr)   { delete m_cfgMgr;   m_cfgMgr   = NULL; }
      if(m_bus)      { delete m_bus;      m_bus      = NULL; }
     }

   bool InitManager(IManager *mgr, const string name)
     {
      if(mgr == NULL)
        { PrintFormat("[Orchestrator] %s: NULL — alloc failed", name); return false; }
      if(m_debugMode) mgr.SetDebugMode(true);
      if(!mgr.Init(m_data, m_bus))
        { PrintFormat("[Orchestrator] %s.Init() FAILED", name); return false; }
      RegisterManager(mgr);
      return true;
     }

   // FIX #2: DrainQueue — pop all events from heap and broadcast via Dispatch()
   // Called at end of every OnTick() and OnTimer() to flush queued events.
   void DrainQueue()
     {
      PASREvent ev;
      while(m_bus.Pop(ev))
         m_bus.Dispatch(ev);
     }

public:
   COrchestrator()
      : m_data(NULL), m_pattern(NULL), m_signal(NULL),
        m_ai(NULL), m_exec(NULL), m_recovery(NULL), m_dash(NULL),
        m_bus(NULL), m_cfgMgr(NULL),
        m_lastBarTime(0), m_debugMode(false), m_initialised(false)
     {}

   ~COrchestrator() { FreeAll(); }

   void SetDebugMode(bool on) { m_debugMode = on; }

   //+----------------------------------------------------------------+
   //| Init                                                           |
   //+----------------------------------------------------------------+
   int Init()
     {
      m_cfgMgr = new CConfigManager();
      if(m_cfgMgr == NULL) { Print("[Orchestrator] CConfigManager alloc failed"); return INIT_FAILED; }
      if(!m_cfgMgr.Init(m_cfg)) return INIT_PARAMETERS_INCORRECT;

      m_bus = new CEventBus();
      if(m_bus == NULL) { Print("[Orchestrator] CEventBus alloc failed"); return INIT_FAILED; }

      m_data = new CDataManager();
      if(m_data == NULL || !m_data.Init(m_cfg))
        { Print("[Orchestrator] CDataManager.Init() FAILED"); FreeAll(); return INIT_FAILED; }

      m_pattern = new CPatternManager();
      if(!InitManager(m_pattern, "CPatternManager")) { FreeAll(); return INIT_FAILED; }

      m_signal = new CSignalManager();
      if(!InitManager(m_signal, "CSignalManager"))  { FreeAll(); return INIT_FAILED; }

      m_ai = new AIManager();
      if(!InitManager(m_ai, "AIManager"))           { FreeAll(); return INIT_FAILED; }

      m_exec = new CExecutionManager();
      if(!InitManager(m_exec, "CExecutionManager")) { FreeAll(); return INIT_FAILED; }

      m_recovery = new CRecoveryManager();
      if(!InitManager(m_recovery, "CRecoveryManager")) { FreeAll(); return INIT_FAILED; }

      m_dash = new CDashboardManager();
      if(!InitManager(m_dash, "CDashboardManager")) { FreeAll(); return INIT_FAILED; }

      m_initialised = true;
      Print("[Orchestrator] Init OK — all managers ready");
      return INIT_SUCCEEDED;
     }

   //+----------------------------------------------------------------+
   //| OnTick — FIX #2: Push events, then DrainQueue()               |
   //+----------------------------------------------------------------+
   void OnTick()
     {
      if(!m_initialised) return;

      m_data.OnTick();

      bool isNewBar = BarChanged();

      if(isNewBar)
        {
         PASREvent evBar;
         evBar.id       = EVENT_ID_NEW_BAR;
         evBar.priority = 10;
         m_bus.Push(evBar);  // FIX #2: was m_bus.Dispatch() — method didn't exist
        }

      PASREvent evTick;
      evTick.id       = EVENT_ID_PRICE_UPDATE;
      evTick.priority = 5;
      m_bus.Push(evTick);  // FIX #2

      // Drain all queued events and broadcast to subscribers
      DrainQueue();  // FIX #2: NEW — flushes heap, routes via Dispatch()
     }

   //+----------------------------------------------------------------+
   //| OnTimer — FIX #2                                              |
   //+----------------------------------------------------------------+
   void OnTimer()
     {
      if(!m_initialised) return;
      PASREvent ev;
      ev.id       = EVENT_ID_TIMER;
      ev.priority = 1;
      m_bus.Push(ev);  // FIX #2: was m_bus.Dispatch()
      DrainQueue();
     }

   //+----------------------------------------------------------------+
   //| OnTradeTransaction — FIX #4: real feature capture for AI      |
   //+----------------------------------------------------------------+
   void OnTradeTransaction(const MqlTradeTransaction &trans,
                            const MqlTradeRequest    &request,
                            const MqlTradeResult     &result)
     {
      if(!m_initialised) return;
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
      if(trans.deal  == 0) return;

      if(HistoryDealSelect(trans.deal))
        {
         if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != m_cfg.MagicNumber)
            return;

         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
           {
            double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            float  label  = (profit >= 0.0) ? 1.0f : 0.0f;

            if(m_ai != NULL)
              {
               // FIX #4: use real BuildFeaturesPublic() instead of ArrayInitialize zeros
               float features[AI_INPUT_DIM];
               if(m_ai.BuildFeaturesPublic(features))
                  m_ai.OnTradeResult(features, label);
               else
                 {
                  // Fallback: zero features if build fails (data not ready)
                  ArrayInitialize(features, 0.0f);
                  m_ai.OnTradeResult(features, label, 0.1f);  // low weight = uncertain
                 }
              }

            // Forward to RecoveryManager via event bus
            if(m_recovery != NULL)
              {
               PASREvent evClose;
               evClose.id       = EVENT_ID_TRADE_CLOSED;
               evClose.priority = 8;
               evClose.ticket   = (ulong)trans.deal;
               evClose.profit   = profit;
               m_bus.Push(evClose);  // FIX #2: was m_bus.Dispatch()
               DrainQueue();
              }
           }
        }
     }

   //+----------------------------------------------------------------+
   //| OnDeinit                                                       |
   //+----------------------------------------------------------------+
   void OnDeinit(const int reason)
     {
      if(!m_initialised) return;
      m_initialised = false;
      if(m_ai != NULL)   m_ai.Deinit();
      if(m_dash != NULL) m_dash.Destroy();
      FreeAll();
      Print("[Orchestrator] Deinit OK (reason=", reason, ")");
     }

   // ── Accessors ─────────────────────────────────────────────────
   CDataManager      *GetDataManager()     const { return m_data;     }
   CSignalManager    *GetSignalManager()   const { return m_signal;   }
   AIManager         *GetAIManager()       const { return m_ai;       }
   CExecutionManager *GetExecManager()     const { return m_exec;     }
   CRecoveryManager  *GetRecoveryManager() const { return m_recovery; }
   const StrategyConfig &GetConfig()       const { return m_cfg;      }
  };

#endif // __CORE_ORCHESTRATOR_MQH__
