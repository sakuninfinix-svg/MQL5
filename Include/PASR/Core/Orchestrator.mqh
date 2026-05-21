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
//|    void OnTimer() { g_orch.OnTimer(); }                           |
//|    void OnTradeTransaction(                                       |
//|           const MqlTradeTransaction &t,                          |
//|           const MqlTradeRequest &rq,                             |
//|           const MqlTradeResult   &rs)                            |
//|    { g_orch.OnTradeTransaction(t, rq, rs); }                     |
//|                                                                  |
//|  INIT ORDER (matches PASR.mqh L-numbers):                       |
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
//|  v1.00 (2026-05-21) Phase 8: initial wiring                     |
//+------------------------------------------------------------------+

#property copyright "Copyright 2026, Agsicentre"
#property strict

#ifndef __CORE_ORCHESTRATOR_MQH__
#define __CORE_ORCHESTRATOR_MQH__

// All managers are already included via PASR.mqh before this file.
// Guard against accidental direct inclusion.
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
   // ── Manager pointers (owned by Orchestrator) ─────────────────────
   // Heap-allocated so destruction order is explicit in OnDeinit().
   CDataManager       *m_data;       // L2 — market data + indicators
   CPatternManager    *m_pattern;    // L4 — candlestick patterns
   CSignalManager     *m_signal;     // L5a — trade signal logic
   AIManager          *m_ai;         // L5b — AI signal filter
   CExecutionManager  *m_exec;       // L6a — order placement
   CRecoveryManager   *m_recovery;   // L6b — hedging / partial close
   CDashboardManager  *m_dash;       // L7 — on-chart panel

   // ── Infrastructure ───────────────────────────────────────────────
   CEventBus          *m_bus;        // shared event bus (all managers share one)
   StrategyConfig      m_cfg;        // live config (populated by CConfigManager)
   CConfigManager     *m_cfgMgr;     // config reload manager

   // ── Runtime state ────────────────────────────────────────────────
   datetime   m_lastBarTime;   // for new-bar detection
   bool       m_debugMode;     // forward to all managers when set
   bool       m_initialised;   // guard: prevents OnTick before Init()

   // ── Private helpers ──────────────────────────────────────────────

   // Detect new bar on _Symbol/_Period.
   // Returns true once per bar boundary; false on every other tick.
   bool BarChanged()
     {
      datetime t = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
      if(t != m_lastBarTime)
        {
         m_lastBarTime = t;
         return true;
        }
      return false;
     }

   // Register one manager with the event bus and call DeclareEvents().
   // Called for every manager during Init() — centralises the wiring.
   void RegisterManager(IManager *mgr)
     {
      if(mgr == NULL) return;
      mgr.DeclareEvents();
      m_bus.Register(mgr);
     }

   // Free all heap objects in reverse init order.
   // Safe to call multiple times (checks for NULL).
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

   // Initialise a single manager: call Init(), log on failure.
   // Returns false (and sets out error) if Init() fails.
   bool InitManager(IManager *mgr, const string name)
     {
      if(mgr == NULL)
        {
         PrintFormat("[Orchestrator] %s: NULL pointer — allocation failed", name);
         return false;
        }
      if(m_debugMode) mgr.SetDebugMode(true);
      if(!mgr.Init(m_data, m_bus))
        {
         PrintFormat("[Orchestrator] %s.Init() FAILED", name);
         return false;
        }
      RegisterManager(mgr);
      return true;
     }

public:
   COrchestrator()
      : m_data(NULL), m_pattern(NULL), m_signal(NULL),
        m_ai(NULL), m_exec(NULL), m_recovery(NULL), m_dash(NULL),
        m_bus(NULL), m_cfgMgr(NULL),
        m_lastBarTime(0), m_debugMode(false), m_initialised(false)
     {}

   ~COrchestrator() { FreeAll(); }

   // Enable verbose logging on all managers (call before Init()).
   void SetDebugMode(bool on) { m_debugMode = on; }

   //+----------------------------------------------------------------+
   //| Init — called from EA OnInit()                                 |
   //| Returns INIT_SUCCEEDED or INIT_PARAMETERS_INCORRECT            |
   //+----------------------------------------------------------------+
   int Init()
     {
      // ── L0: Config load + validator gate ─────────────────────────
      // Create config manager first; it populates m_cfg via Init().
      m_cfgMgr = new CConfigManager();
      if(m_cfgMgr == NULL)
        {
         Print("[Orchestrator] CConfigManager allocation failed");
         return INIT_FAILED;
        }
      if(!m_cfgMgr.Init(m_cfg))
        {
         // CConfigManager already prints the error list via Validator::PrintErrors()
         return INIT_PARAMETERS_INCORRECT;
        }

      // ── Infrastructure: EventBus ──────────────────────────────────
      m_bus = new CEventBus();
      if(m_bus == NULL)
        {
         Print("[Orchestrator] CEventBus allocation failed");
         return INIT_FAILED;
        }

      // ── L2: DataManager ──────────────────────────────────────────
      m_data = new CDataManager();
      if(m_data == NULL || !m_data.Init(m_cfg))
        {
         Print("[Orchestrator] CDataManager.Init() FAILED");
         FreeAll();
         return INIT_FAILED;
        }

      // ── L4: PatternManager ────────────────────────────────────────
      m_pattern = new CPatternManager();
      if(!InitManager(m_pattern, "CPatternManager"))
        { FreeAll(); return INIT_FAILED; }

      // ── L5a: SignalManager ────────────────────────────────────────
      m_signal = new CSignalManager();
      if(!InitManager(m_signal, "CSignalManager"))
        { FreeAll(); return INIT_FAILED; }

      // ── L5b: AIManager ────────────────────────────────────────────
      m_ai = new AIManager();
      if(!InitManager(m_ai, "AIManager"))
        { FreeAll(); return INIT_FAILED; }

      // ── L6a: ExecutionManager ─────────────────────────────────────
      m_exec = new CExecutionManager();
      if(!InitManager(m_exec, "CExecutionManager"))
        { FreeAll(); return INIT_FAILED; }

      // ── L6b: RecoveryManager ──────────────────────────────────────
      m_recovery = new CRecoveryManager();
      if(!InitManager(m_recovery, "CRecoveryManager"))
        { FreeAll(); return INIT_FAILED; }

      // ── L7: DashboardManager ──────────────────────────────────────
      m_dash = new CDashboardManager();
      if(!InitManager(m_dash, "CDashboardManager"))
        { FreeAll(); return INIT_FAILED; }

      // ── Optional: enable periodic timer (1-second resolution) ─────
      // EventSetTimer(1);

      m_initialised = true;
      Print("[Orchestrator] Init OK — all managers ready");
      return INIT_SUCCEEDED;
     }

   //+----------------------------------------------------------------+
   //| OnTick — called from EA OnTick()                               |
   //+----------------------------------------------------------------+
   void OnTick()
     {
      if(!m_initialised) return;

      // Refresh market data first (indicator buffers, spread, etc.)
      m_data.OnTick();

      // Detect new bar before dispatching events
      bool isNewBar = BarChanged();

      // Dispatch NEW_BAR first (AIManager.OnNewBar deferred backprop fires here)
      if(isNewBar)
        {
         PASREvent evBar;
         evBar.id       = EVENT_ID_NEW_BAR;
         evBar.priority = 10;  // high — bar events before price updates
         m_bus.Dispatch(evBar);
        }

      // Dispatch PRICE_UPDATE — AIManager.OnPriceUpdate() forward pass runs here
      PASREvent evTick;
      evTick.id       = EVENT_ID_PRICE_UPDATE;
      evTick.priority = 5;
      m_bus.Dispatch(evTick);
     }

   //+----------------------------------------------------------------+
   //| OnTimer — called from EA OnTimer()                             |
   //+----------------------------------------------------------------+
   void OnTimer()
     {
      if(!m_initialised) return;
      PASREvent ev;
      ev.id       = EVENT_ID_TIMER;
      ev.priority = 1;
      m_bus.Dispatch(ev);
     }

   //+----------------------------------------------------------------+
   //| OnTradeTransaction — called from EA OnTradeTransaction()       |
   //| Handles position close detection for AI labelling              |
   //+----------------------------------------------------------------+
   void OnTradeTransaction(const MqlTradeTransaction &trans,
                            const MqlTradeRequest    &request,
                            const MqlTradeResult     &result)
     {
      if(!m_initialised) return;

      // Only interested in deal additions (position opened or closed)
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
      if(trans.deal  == 0) return;

      // Check if it's OUR magic number
      if(HistoryDealSelect(trans.deal))
        {
         if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != m_cfg.MagicNumber)
            return;

         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

         // Position closed — label experience for AI
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
           {
            double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
            float  label  = (profit >= 0.0) ? 1.0f : 0.0f;

            // Build feature vector from current market snapshot for labelling
            // (features at close time — best proxy for entry features)
            float features[AI_INPUT_DIM];
            // Note: BuildFeatures is private in AIManager;
            // use the public labelling shim OnTradeResult()
            if(m_ai != NULL)
              {
               // For now pass empty features — the replay entry is labelled
               // retroactively. Full feature capture at entry is a Phase 9+ task.
               ArrayInitialize(features, 0.0f);
               m_ai.OnTradeResult(features, label);
              }

            // Forward to RecoveryManager for state tracking
            if(m_recovery != NULL)
              {
               PASREvent evClose;
               evClose.id       = EVENT_ID_TRADE_CLOSED;
               evClose.priority = 8;
               evClose.ticket   = (ulong)trans.deal;
               evClose.profit   = profit;
               m_bus.Dispatch(evClose);
              }
           }
        }
     }

   //+----------------------------------------------------------------+
   //| OnDeinit — called from EA OnDeinit()                           |
   //+----------------------------------------------------------------+
   void OnDeinit(const int reason)
     {
      if(!m_initialised) return;
      m_initialised = false;

      // Persist AI weights before teardown
      if(m_ai != NULL) m_ai.Deinit();

      // Destroy dashboard objects (chart objects must be removed explicitly)
      if(m_dash != NULL) m_dash.Destroy();

      // EventKillTimer();  // uncomment if EventSetTimer was used

      FreeAll();
      Print("[Orchestrator] Deinit OK (reason=", reason, ")");
     }

   // ── Accessors (for EA expert params or unit tests) ────────────────
   CDataManager      *GetDataManager()     const { return m_data;     }
   CSignalManager    *GetSignalManager()   const { return m_signal;   }
   AIManager         *GetAIManager()       const { return m_ai;       }
   CExecutionManager *GetExecManager()     const { return m_exec;     }
   CRecoveryManager  *GetRecoveryManager() const { return m_recovery; }
   const StrategyConfig &GetConfig()       const { return m_cfg;      }
  };

#endif // __CORE_ORCHESTRATOR_MQH__
