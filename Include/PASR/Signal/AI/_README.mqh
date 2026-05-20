//+------------------------------------------------------------------+
//| PASR LAYER 4 — SIGNAL/AI SUBLAYER                               |
//|                                                                  |
//| PURPOSE:                                                         |
//|   AI/ML subsystem. Decomposed from the original monolithic      |
//|   7.AIManager.mqh (69 KB God Object) into three focused files. |
//|                                                                  |
//| DECOMPOSITION STRATEGY:                                          |
//|                                                                  |
//|   AIInference.mqh                                               |
//|     — Forward pass only. Reads input features from DataManager  |
//|       and MarketRegime. Produces probability scores.           |
//|     — Called every tick: must be O(layers) with zero alloc.   |
//|     — No training data, no weight updates, no file I/O.        |
//|                                                                  |
//|   AITrainer.mqh                                                  |
//|     — Backpropagation + weight updates + replay buffer.        |
//|     — ONLY executed via deferred EventBus event (NewBar).      |
//|     — Never called directly from OnTick().                     |
//|     — Owns the replay buffer and minibatch sampling.           |
//|     — Handles model persistence (file save/load).              |
//|                                                                  |
//|   AIOrchestrator.mqh                                            |
//|     — Thin coordinator between Inference and Trainer.          |
//|     — Decides when to train (throttle, market hours).          |
//|     — Manages the expert regime switch logic.                  |
//|     — This is the ONLY file included by SignalManager.mqh.     |
//|                                                                  |
//| LATENCY BUDGET:                                                  |
//|   AIInference.mqh per-tick: target < 0.5ms (1 layer = ~0.05ms)|
//|   AITrainer.mqh per-NewBar: target < 50ms (deferred, not tick) |
//+------------------------------------------------------------------+
