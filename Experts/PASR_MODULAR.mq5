//+------------------------------------------------------------------+
//| PASR_MODULAR.mq5                                                 |
//| Centralized Modular PASR Expert Advisor                          |
//+------------------------------------------------------------------+
#property strict

#include <PASR/Core/PASR.mqh>

input bool InpDebugMode = true;
input bool InpEnableProfiling = true;
input int  InpTimerSeconds = 1;

CPASRKernel g_kernel;

struct EAState
  {
   bool     initialized;
   datetime last_tick;
   void Reset()
     {
      initialized = false;
      last_tick = 0;
     }
  };

EAState g_state;

#ifdef PASR_QA_BUILD
#include <PASR/QA/QAStressTest.mqh>
CQAStressTest g_qa;
#endif

StrategyConfig BuildConfigFromInputs()
  {
   StrategyConfig cfg;
   cfg.EAName = "PASR_MODULAR";
   cfg.Version = "2.15.0";
   cfg.MagicNumber = 123456;
   return cfg;
  }

int OnInit()
  {
   g_state.Reset();
   StrategyConfig cfg = BuildConfigFromInputs();
   g_kernel.SetDebugMode(InpDebugMode);
   g_kernel.SetProfilingEnabled(InpEnableProfiling);
   int init = g_kernel.Init(cfg);
   if(init != INIT_SUCCEEDED) return init;
   EventSetTimer(MathMax(1, InpTimerSeconds));
#ifdef PASR_QA_BUILD
   g_qa.Init();
#endif
   g_state.initialized = true;
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_kernel.OnDeinit(reason);
   g_state.Reset();
  }

void OnTick()
  {
   if(!g_state.initialized) return;
   g_state.last_tick = TimeCurrent();
#ifdef PASR_QA_BUILD
   CEventBus *bus = g_kernel.GetEventBus();
   CRiskManager *risk = g_kernel.GetRiskManager();
   if(bus != NULL && risk != NULL)
      g_qa.OnTick(_Symbol, bus, risk);
#endif
   g_kernel.OnTick();
  }

void OnTimer()
  {
   if(!g_state.initialized) return;
   g_kernel.OnTimer();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!g_state.initialized) return;
   g_kernel.OnTradeTransaction(trans, request, result);
  }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(!g_state.initialized) return;
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      CDashboardManager *dash = g_kernel.GetDashboard();
      if(dash != NULL) dash.OnChartEvent(id, lparam, dparam, sparam);
     }
  }
