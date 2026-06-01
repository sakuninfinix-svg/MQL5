//+------------------------------------------------------------------+
//| Observability/ObservabilityTypes.mqh — v0.20                     |
//| Shared constants for diagnostics, dashboard, journal, telemetry   |
//+------------------------------------------------------------------+
#property strict
#ifndef __PASR_OBSERVABILITY_TYPES_MQH__
#define __PASR_OBSERVABILITY_TYPES_MQH__

// Prefix / top-level observability metrics
#define PASR_OBS_PREFIX                 "Obs_"
#define PASR_OBS_TEXT_LENGTH            "Obs_TextLength"
#define PASR_OBS_SIGNAL_CONFIDENCE      "Obs_SignalConfidence"
#define PASR_OBS_AI_SCORE               "Obs_AIScore"
#define PASR_OBS_SPREAD_POINTS          "Obs_SpreadPts"
#define PASR_OBS_PIPELINE_RESULT        "Obs_Result"

// Core telemetry metrics
#define PASR_METRIC_PIPELINE_LATENCY_PREFIX "Pipeline_Latency_"
#define PASR_METRIC_EXECUTION_SLIPPAGE      "Execution_Slippage"
#define PASR_METRIC_SIGNAL_STRENGTH         "Signal_Strength"

// Units
#define PASR_UNIT_VALUE                 "value"
#define PASR_UNIT_CHARS                 "chars"
#define PASR_UNIT_NORMALIZED            "normalized"
#define PASR_UNIT_SCORE                 "score"
#define PASR_UNIT_POINTS                "points"
#define PASR_UNIT_ENUM                  "enum"
#define PASR_UNIT_MICROSECONDS          "microseconds"

#endif // __PASR_OBSERVABILITY_TYPES_MQH__
