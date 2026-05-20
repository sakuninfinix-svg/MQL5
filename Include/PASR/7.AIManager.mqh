//+------------------------------------------------------------------+
//|                                                   AIManager.mqh  |
//|          Backward-compatible shim — includes AI subsystem        |
//|                                       Copyright 2026, Agsicentre |
//+------------------------------------------------------------------+
// v3.00 — God-Object decomposed into 5 focused modules under AI/
//
//  AI/AITypes.mqh          — shared structs & enums
//  AI/AIFeatureBuilder.mqh — pure stateless feature normalisation
//  AI/AIInference.mqh      — pure forward pass + expert scorers
//  AI/AITrainer.mqh        — backprop, replay buffer, labeling
//  AI/AIOrchestrator.mqh   — IManager event wiring + persistence
//
// AIManager is now a typedef alias for AIOrchestrator.
// All existing code that includes 7.AIManager.mqh and uses AIManager
// continues to compile without modification.
//+------------------------------------------------------------------+
#pragma once
#ifndef __AI_MANAGER_MQH__
#define __AI_MANAGER_MQH__

#include "AI/AIOrchestrator.mqh"

#endif // __AI_MANAGER_MQH__
