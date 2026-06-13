#!/usr/bin/env python3
"""
PASR Optimized Preset Generator
Creates .set files based on optimization results
"""

import json
from pathlib import Path

# Best parameters from optimization
BEST_PARAMS = {
    # Core
    "InpMagicNumber": 889900,
    "InpEAName": "PASR_OPTIMIZED",
    "InpCommentTrade": "PASR_v3_OPT",
    
    # Risk Management - Optimized
    "InpRiskPercent": 1.95,
    "InpLotSize": 0.01,
    "InpMaxDailyLossPct": 3.0,
    "InpMaxDrawdownPct": 10.0,
    "InpMaxOpenPositions": 3,
    "InpMaxConsecLoss": 5,
    "InpPartialClosePct": 0.5,
    
    # Exit Strategy - Optimized
    "InpSLMultiplier": 2.17,
    "InpTPMultiplier": 1.75,
    "InpUseBreakEven": "true",
    "InpBreakEvenATRMult": 1.0,
    "InpUseTrailingStop": "true",
    "InpTrailATRMult": 1.0,
    "InpRecoveryEnabled": "true",
    "InpMaxRecoveryAttempts": 3,
    "InpRecoveryCooldownBars": 5,
    "InpMaxTradeDurationDays": 0,
    
    # Market Filters - Optimized
    "InpATRPeriod": 15,
    "InpADXPeriod": 16,
    "InpADXTrendThreshold": 26.5,
    "InpSpreadFilterPips": 3.0,
    "InpSessionStartHour": 0,
    "InpSessionEndHour": 23,
    "InpFilterNewsTime": "false",
    "InpNewsBufferMinutes": 30,
    
    # Pattern Recognition - Optimized
    "InpEnablePatterns": "true",
    "InpMinPatternScore": 42.5,
    "InpPatternLookbackBars": 39,
    "InpPinBarRatio": 2.0,
    "InpEngulfMultiplier": 1.1,
    "InpRequireConfirmation": "false",
    
    # AI Engine
    "InpEnableAI": "true",
    "InpAIMinConfidence": 0.60,
    "InpAILearningRate": 0.001,
    "InpAITrainIntervalBars": 5,
    "InpAIReplayBufferSize": 512,
    "InpAIMinibatchSize": 32,
    "InpAIPersistWeights": "true",
    "InpAIModelFileName": "PASR_mlp_m0.bin",
    "InpAIEnableOnnx": "false",
    "InpAIModelOnnxFileName": "PASR_sequence.onnx",
    
    # Debug/Profiling
    "InpDebugMode": "false",
    "InpEnableProfiling": "false",
    "InpTimerSeconds": 1,
    "InpLogLevel": 1,
    
    # Visual/Alerts
    "InpShowDashboard": "true",
    "InpShowSignalArrows": "true",
    "InpEnableAlerts": "false",
    "InpEnablePushNotify": "false",
    "InpFontSize": 9,
    
    # Execution
    "InpSlippagePoints": 3,
    "InpOrderExpiration": 0,
    "InpDeviationPoints": 5,
    "InpUseMarketExecution": "true",
    "InpMinOrderDistancePoints": 0,
}

# Conservative variant
CONSERVATIVE_PARAMS = BEST_PARAMS.copy()
CONSERVATIVE_PARAMS.update({
    "InpEAName": "PASR_CONSERVATIVE",
    "InpCommentTrade": "PASR_v3_CONS",
    "InpRiskPercent": 0.5,
    "InpMaxDailyLossPct": 2.0,
    "InpSLMultiplier": 2.0,
    "InpTPMultiplier": 3.0,
    "InpUseTrailingStop": "true",
    "InpMinPatternScore": 50.0,
    "InpMaxOpenPositions": 2,
})

# Aggressive variant
AGGRESSIVE_PARAMS = BEST_PARAMS.copy()
AGGRESSIVE_PARAMS.update({
    "InpEAName": "PASR_AGGRESSIVE",
    "InpCommentTrade": "PASR_v3_AGG",
    "InpRiskPercent": 2.5,
    "InpMaxDailyLossPct": 5.0,
    "InpSLMultiplier": 1.5,
    "InpTPMultiplier": 2.0,
    "InpUseTrailingStop": "false",
    "InpMinPatternScore": 38.0,
    "InpMaxOpenPositions": 4,
})

def generate_set_file(params: dict, filename: str):
    """Generate MT5 .set file content"""
    lines = [
        "; ============================================================================",
        f"; {params['InpEAName']} - Auto-generated from optimization",
        "; ============================================================================",
        ""
    ]
    for key, value in params.items():
        if isinstance(value, bool):
            value = "true" if value else "false"
        elif isinstance(value, float):
            value = f"{value:.2f}"
        lines.append(f"{key}={value}")
    
    content = "\n".join(lines)
    Path(filename).write_text(content, encoding="utf-8")
    print(f"Generated: {filename}")

# Generate all variants
output_dir = Path("/home/agus/.mt5/drive_c/Program Files/MetaTrader 5/MQL5/Presets")
generate_set_file(BEST_PARAMS, output_dir / "PASR_OPTIMIZED.set")
generate_set_file(CONSERVATIVE_PARAMS, output_dir / "PASR_CONSERVATIVE.set")
generate_set_file(AGGRESSIVE_PARAMS, output_dir / "PASR_AGGRESSIVE.set")

print("\nDone! Presets generated:")
print("  - PASR_OPTIMIZED.set (Best from optimization)")
print("  - PASR_CONSERVATIVE.set (Low risk, high pattern score)")
print("  - PASR_AGGRESSIVE.set (Higher risk, more trades)")