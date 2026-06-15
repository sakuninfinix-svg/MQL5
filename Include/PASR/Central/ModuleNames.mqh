//+------------------------------------------------------------------+
//| Central/ModuleNames.mqh — v0.20                                  |
//| Canonical module names for PASR central registry                   |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_CENTRAL_MODULE_NAMES_MQH__
#define __PASR_CENTRAL_MODULE_NAMES_MQH__

#define PASR_MOD_DATA_MANAGER       "DataManager"
#define PASR_MOD_SR_MANAGER         "SRManager"
#define PASR_MOD_ZONE_MANAGER       "ZoneManager"
#define PASR_MOD_PATTERN_MANAGER    "PatternManager"
#define PASR_MOD_SIGNAL_MANAGER     "SignalManager"
#define PASR_MOD_REGIME_DETECTOR    "MarketRegimeDetector"
#define PASR_MOD_AI_ORCHESTRATOR    "AIOrchestrator"
#define PASR_MOD_REGIME_FILTER      "RegimeFilter"
#define PASR_MOD_RISK_MANAGER       "RiskManager"
#define PASR_MOD_EXECUTION_MANAGER  "ExecutionManager"
#define PASR_MOD_EXIT_ENGINE        "ExitEngine"
#define PASR_MOD_RECOVERY_MANAGER   "RecoveryManager"
#define PASR_MOD_JOURNAL_MANAGER    "JournalManager"
#define PASR_MOD_DASHBOARD_MANAGER  "DashboardManager"

// Optional infra services used by the Centralized Modular Pipeline facade.
#define PASR_MOD_SANITY_MANAGER     "SanityManager"
#define PASR_MOD_TELEMETRY_RECORDER "TelemetryRecorder"
#define PASR_MOD_ADAPTIVE_MANAGER   "AdaptiveParameterManager"
#define PASR_MOD_HEALTH_MONITOR     "HealthMonitor"
#define PASR_MOD_SNAPSHOT_MANAGER   "SnapshotManager"
#define PASR_MOD_SESSION_STATE      "SessionState"

// Non-IManager runtime services tracked by central documentation and adapters.
#define PASR_MOD_EVENT_BUS          "EventBus"
#define PASR_MOD_PIPELINE_ENGINE    "PipelineEngine"
#define PASR_MOD_LATENCY_OPTIMIZER  "LatencyOptimizer"
#define PASR_MOD_ASYNC_ORDER_MANAGER "AsyncOrderManager"
#define PASR_MOD_CNN_PATTERN_RECOGNIZER "CNNPatternRecognizer"

#endif // __PASR_CENTRAL_MODULE_NAMES_MQH__
