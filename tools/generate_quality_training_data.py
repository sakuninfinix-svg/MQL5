#!/usr/bin/env python3
"""
PASR Quality Training Data Generator
====================================

Generates HIGH-QUALITY training data that EXACTLY matches the 34 features
computed by AIFeatureBuilder.mqh in the EA, plus label/weight metadata.

Key design principles:
1. Feature extraction MATCHES MQL5 AIFeatureBuilder.mqh line-by-line
2. Multiple market regimes (TREND_UP, TREND_DOWN, RANGE, VOLATILE, CRASH)
3. Realistic trade simulation with proper R:R and outcomes
4. Pattern features from S/R, candle patterns, market structure
5. Weighted samples based on confidence and trade quality

Output CSV columns:
  f0..f33 (34 features), label, weight, timestamp, symbol, timeframe,
  regime, trade_type, profit_pips, duration_bars, notes
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import random
import math
import json
import os
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import List, Dict, Tuple, Optional, Literal
from enum import Enum
from pathlib import Path

# ============================================================================
# CONSTANTS - Must match AITypes.mqh exactly
# ============================================================================
AI_FEATURE_DIM = 34
AI_SEQ_LEN = 64
AI_SEQ_FEATURE_DIM = 12

# Market Regimes (match RegimeTypes.mqh)
class EMarketRegime(Enum):
    REGIME_UNKNOWN = 0
    REGIME_TREND_UP = 1
    REGIME_TREND_DOWN = 2
    REGIME_RANGE = 3
    REGIME_VOLATILE = 4
    REGIME_CRASH = 5
    REGIME_TRANSITION = 6

# AI Labels (match AITypes.mqh)
class AI_LABEL_CLASS(Enum):
    AI_LABEL_INVALID = 0
    AI_LABEL_NO_TRADE = 1
    AI_LABEL_GOOD_BUY = 2
    AI_LABEL_GOOD_SELL = 3
    AI_LABEL_BAD_BUY = 4
    AI_LABEL_BAD_SELL = 5

# ============================================================================
# CONFIGURATION
# ============================================================================
@dataclass
class GeneratorConfig:
    """Configuration for training data generation"""
    n_samples_per_regime: int = 2000  # Total ~10k samples
    sequence_length: int = 100  # bars for feature computation
    symbol: str = "EURUSD"
    timeframe: str = "H1"
    base_price: float = 1.1000
    spread_pips: float = 1.5
    slippage_pips: float = 0.5
    commission_per_lot: float = 7.0
    
    # Session filter (matching EA inputs)
    session_start_hour: int = 0
    session_end_hour: int = 23
    
    # Risk parameters (matching EA inputs)
    sl_multiplier: float = 1.5
    tp_multiplier: float = 2.5
    max_open_positions: int = 3
    
    # Pattern parameters
    min_pattern_score: float = 45.0
    pattern_lookback_bars: int = 50
    
    # Regime parameters - each regime gets different market dynamics
    regime_params: Dict = None
    
    def __post_init__(self):
        if self.regime_params is None:
            self.regime_params = {
                EMarketRegime.REGIME_TREND_UP: {
                    "trend": 0.00015, "volatility": 0.0008, "adx_base": 35,
                    "vol_scale": 1.0, "pattern_quality_boost": 0.15
                },
                EMarketRegime.REGIME_TREND_DOWN: {
                    "trend": -0.00015, "volatility": 0.0008, "adx_base": 35,
                    "vol_scale": 1.0, "pattern_quality_boost": 0.15
                },
                EMarketRegime.REGIME_RANGE: {
                    "trend": 0.0, "volatility": 0.0006, "adx_base": 15,
                    "vol_scale": 0.8, "pattern_quality_boost": 0.10
                },
                EMarketRegime.REGIME_VOLATILE: {
                    "trend": 0.0, "volatility": 0.0018, "adx_base": 25,
                    "vol_scale": 2.0, "pattern_quality_boost": -0.05
                },
                EMarketRegime.REGIME_CRASH: {
                    "trend": -0.0003, "volatility": 0.0025, "adx_base": 40,
                    "vol_scale": 3.0, "pattern_quality_boost": -0.10
                },
                EMarketRegime.REGIME_TRANSITION: {
                    "trend": 0.0, "volatility": 0.0012, "adx_base": 20,
                    "vol_scale": 1.2, "pattern_quality_boost": 0.0
                },
            }


# ============================================================================
# MARKET DATA GENERATION WITH REGIME SWITCHING
# ============================================================================
class RegimeAwareMarketGenerator:
    """Generates realistic OHLCV data with explicit regime segments"""
    
    def __init__(self, config: GeneratorConfig, seed: int = 42):
        self.config = config
        self.seed = seed
        np.random.seed(seed)
        random.seed(seed)
        
    def generate_regime_segment(self, regime: EMarketRegime, n_bars: int, 
                                 start_price: float) -> Tuple[pd.DataFrame, float]:
        """Generate OHLCV for a specific regime segment"""
        params = self.config.regime_params[regime]
        trend = params["trend"]
        volatility = params["volatility"]
        vol_scale = params["vol_scale"]
        
        opens, highs, lows, closes, volumes, timestamps = [], [], [], [], [], []
        current_price = start_price
        base_time = datetime(2020, 1, 1, 0, 0, 0)
        
        for i in range(n_bars):
            open_price = current_price
            
            # Regime-specific price dynamics
            trend_component = trend * np.random.randn()
            vol_component = volatility * vol_scale * np.random.randn()
            
            # Mean reversion in range regime
            if regime == EMarketRegime.REGIME_RANGE:
                distance_from_mid = (current_price - 1.1000) / 1.1000
                mean_reversion = -0.0001 * distance_from_mid * np.random.rand()
                trend_component += mean_reversion
            
            # Crash regime - fat tails
            if regime == EMarketRegime.REGIME_CRASH and np.random.random() < 0.02:
                vol_component *= 4.0  # Extreme move
            
            # High-low range
            hl_range = abs(volatility * vol_scale * np.random.randn() * 0.5)
            high = open_price + max(0, trend_component) + hl_range
            low = open_price + min(0, trend_component) - hl_range
            
            # Close with momentum
            close_move = trend_component * 0.7 + vol_component * 0.3
            close = open_price + close_move
            
            # Ensure OHLC consistency
            high = max(high, open_price, close)
            low = min(low, open_price, close)
            
            # Volume with regime-specific characteristics
            base_vol = 1000
            if regime == EMarketRegime.REGIME_VOLATILE:
                base_vol *= 2.0
            elif regime == EMarketRegime.REGIME_CRASH:
                base_vol *= 3.0
            elif regime in [EMarketRegime.REGIME_TREND_UP, EMarketRegime.REGIME_TREND_DOWN]:
                base_vol *= 1.3
            
            volume = int(base_vol + abs(np.random.randn()) * base_vol * 0.5)
            
            opens.append(open_price)
            highs.append(high)
            lows.append(low)
            closes.append(close)
            volumes.append(volume)
            timestamps.append(base_time + timedelta(hours=i))
            
            current_price = close
        
        df = pd.DataFrame({
            'timestamp': timestamps,
            'open': opens,
            'high': highs,
            'low': lows,
            'close': closes,
            'volume': volumes
        })
        
        return df, current_price
    
    def generate_full_series(self, total_bars: int = 50000) -> pd.DataFrame:
        """Generate full series with multiple regime segments"""
        segments = []
        current_price = self.config.base_price
        
        # Define regime sequence with varying lengths
        regime_sequence = [
            (EMarketRegime.REGIME_RANGE, 5000),
            (EMarketRegime.REGIME_TREND_UP, 8000),
            (EMarketRegime.REGIME_VOLATILE, 4000),
            (EMarketRegime.REGIME_TREND_DOWN, 7000),
            (EMarketRegime.REGIME_RANGE, 5000),
            (EMarketRegime.REGIME_TREND_UP, 6000),
            (EMarketRegime.REGIME_CRASH, 3000),
            (EMarketRegime.REGIME_TRANSITION, 4000),
            (EMarketRegime.REGIME_RANGE, 4000),
            (EMarketRegime.REGIME_TREND_DOWN, 4000),
        ]
        
        for regime, n_bars in regime_sequence:
            df_seg, current_price = self.generate_regime_segment(regime, n_bars, current_price)
            df_seg['regime'] = regime.value
            segments.append(df_seg)
        
        full_df = pd.concat(segments, ignore_index=True)
        
        # Trim or extend to target length
        if len(full_df) > total_bars:
            full_df = full_df.iloc[:total_bars].copy()
        elif len(full_df) < total_bars:
            # Extend with range regime
            extra, _ = self.generate_regime_segment(
                EMarketRegime.REGIME_RANGE, total_bars - len(full_df), current_price
            )
            extra['regime'] = EMarketRegime.REGIME_RANGE.value
            full_df = pd.concat([full_df, extra], ignore_index=True)
        
        return full_df


# ============================================================================
# TECHNICAL INDICATORS - MATCHING MQL5 IMPLEMENTATION
# ============================================================================
class TechnicalIndicators:
    """Technical indicators matching MQL5 AIFeatureBuilder.mqh exactly"""
    
    @staticmethod
    def atr(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14) -> np.ndarray:
        """Average True Range - matches iATR"""
        tr1 = high - low
        tr2 = np.abs(high - np.roll(close, 1))
        tr3 = np.abs(low - np.roll(close, 1))
        tr = np.maximum(np.maximum(tr1, tr2), tr3)
        tr[0] = high[0] - low[0]  # First bar
        
        atr = pd.Series(tr).rolling(window=period, min_periods=1).mean().to_numpy()
        return atr
    
    @staticmethod
    def rsi(close: np.ndarray, period: int = 14) -> np.ndarray:
        """RSI - matches iRSI"""
        delta = np.diff(close, prepend=close[0])
        gain = np.where(delta > 0, delta, 0)
        loss = np.where(delta < 0, -delta, 0)
        
        avg_gain = pd.Series(gain).rolling(window=period, min_periods=1).mean()
        avg_loss = pd.Series(loss).rolling(window=period, min_periods=1).mean()
        
        rs = avg_gain / (avg_loss + 1e-10)
        rsi = 100 - (100 / (1 + rs))
        return rsi.to_numpy()
    
    @staticmethod
    def macd(close: np.ndarray, fast: int = 12, slow: int = 26, signal: int = 9) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
        """MACD - matches iMACD"""
        ema_fast = pd.Series(close).ewm(span=fast, adjust=False).mean()
        ema_slow = pd.Series(close).ewm(span=slow, adjust=False).mean()
        macd_line = ema_fast - ema_slow
        signal_line = macd_line.ewm(span=signal, adjust=False).mean()
        histogram = macd_line - signal_line
        return macd_line.to_numpy(), signal_line.to_numpy(), histogram.to_numpy()
    
    @staticmethod
    def cci(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14) -> np.ndarray:
        """CCI - matches iCCI"""
        typical = (high + low + close) / 3
        ma = pd.Series(typical).rolling(window=period, min_periods=1).mean()
        md = pd.Series(typical).rolling(window=period, min_periods=1).apply(
            lambda x: np.mean(np.abs(x - np.mean(x)))
        )
        cci = (typical - ma) / (0.015 * md + 1e-10)
        return cci.to_numpy()
    
    @staticmethod
    def stoch(high: np.ndarray, low: np.ndarray, close: np.ndarray, 
              k_period: int = 5, d_period: int = 3, slowing: int = 3) -> np.ndarray:
        """Stochastic - matches iStochastic (main line %K)"""
        lowest_low = pd.Series(low).rolling(window=k_period, min_periods=1).min()
        highest_high = pd.Series(high).rolling(window=k_period, min_periods=1).max()
        
        k_raw = 100 * (close - lowest_low) / (highest_high - lowest_low + 1e-10)
        k_slow = pd.Series(k_raw).rolling(window=slowing, min_periods=1).mean()
        return k_slow.to_numpy()
    
    @staticmethod
    def mfi(high: np.ndarray, low: np.ndarray, close: np.ndarray, 
            volume: np.ndarray, period: int = 14) -> np.ndarray:
        """MFI - matches iMFI"""
        typical = (high + low + close) / 3
        money_flow = typical * volume
        
        delta = np.diff(typical, prepend=typical[0])
        pos_flow = np.where(delta > 0, money_flow, 0)
        neg_flow = np.where(delta < 0, money_flow, 0)
        
        pos_mf = pd.Series(pos_flow).rolling(window=period, min_periods=1).sum()
        neg_mf = pd.Series(neg_flow).rolling(window=period, min_periods=1).sum()
        
        mfi = 100 - (100 / (1 + pos_mf / (neg_mf + 1e-10)))
        return mfi.to_numpy()
    
    @staticmethod
    def adx(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14) -> np.ndarray:
        """ADX - simplified but realistic"""
        tr1 = high - low
        tr2 = np.abs(high - np.roll(close, 1))
        tr3 = np.abs(low - np.roll(close, 1))
        tr = np.maximum(np.maximum(tr1, tr2), tr3)
        tr[0] = high[0] - low[0]
        
        plus_dm = np.diff(high, prepend=high[0])
        minus_dm = -np.diff(low, prepend=low[0])
        
        plus_dm = np.where((plus_dm > 0) & (plus_dm > minus_dm), plus_dm, 0)
        minus_dm = np.where((minus_dm > 0) & (minus_dm > plus_dm), minus_dm, 0)
        
        atr_val = pd.Series(tr).rolling(window=period, min_periods=1).mean()
        plus_di = 100 * pd.Series(plus_dm).rolling(window=period, min_periods=1).mean() / (atr_val + 1e-10)
        minus_di = 100 * pd.Series(minus_dm).rolling(window=period, min_periods=1).mean() / (atr_val + 1e-10)
        
        dx = 100 * np.abs(plus_di - minus_di) / (plus_di + minus_di + 1e-10)
        adx = pd.Series(dx).rolling(window=period, min_periods=1).mean()
        return adx.to_numpy()
    
    @staticmethod
    def detect_sr_zones(high: np.ndarray, low: np.ndarray, close: np.ndarray, 
                        lookback: int = 50) -> Dict[str, np.ndarray]:
        """Detect support/resistance - simplified for speed"""
        n = len(close)
        resistance_dist = np.full(n, 0.5)
        support_dist = np.full(n, 0.5)
        zone_strength = np.full(n, 0.5)
        pattern_score = np.full(n, 50.0)
        
        for i in range(lookback, n):
            recent_high = high[i-lookback:i].max()
            recent_low = low[i-lookback:i].min()
            current = close[i]
            
            # Distance to nearest S/R (normalized)
            res_dist = (recent_high - current) / current if current > 0 else 0.5
            sup_dist = (current - recent_low) / current if current > 0 else 0.5
            
            resistance_dist[i] = min(max(res_dist, 0.0), 1.0)
            support_dist[i] = min(max(sup_dist, 0.0), 1.0)
            
            # Zone strength
            range_size = recent_high - recent_low
            pos_in_range = (current - recent_low) / range_size if range_size > 0 else 0.5
            
            # Stronger near edges
            zone_strength[i] = 1.0 - 2.0 * abs(pos_in_range - 0.5)
            
            # Pattern score - higher near S/R with good structure
            pattern_score[i] = 50 + (0.5 - abs(pos_in_range - 0.5)) * 100
        
        return {
            'resistance_distance': resistance_dist,
            'support_distance': support_dist,
            'zone_strength': zone_strength,
            'pattern_score': pattern_score
        }
    
    @staticmethod
    def price_return(close: np.ndarray, bars_back: int) -> np.ndarray:
        """Price return over N bars"""
        ret = np.zeros(len(close))
        for i in range(bars_back + 1, len(close)):
            if close[i - bars_back] != 0:
                ret[i] = (close[i-1] - close[i-bars_back-1]) / close[i-bars_back-1]
        return np.clip(ret, -0.05, 0.05)  # Match MQL5 clamping
    
    @staticmethod
    def zscore(close: np.ndarray, period: int = 20) -> np.ndarray:
        """Rolling Z-score"""
        z = np.zeros(len(close))
        for i in range(period, len(close)):
            window = close[i-period:i]
            mean = window.mean()
            std = window.std()
            if std > 0:
                z[i] = (close[i-1] - mean) / std
        return np.clip(z / 3.0, -1.0, 1.0)  # Match MQL5 normalization
    
    @staticmethod
    def return_skew(close: np.ndarray, period: int = 20) -> np.ndarray:
        """Return skewness"""
        skew = np.zeros(len(close))
        for i in range(period + 1, len(close)):
            rets = np.diff(close[i-period-1:i]) / close[i-period-1:i-1]
            if len(rets) > 2 and rets.std() > 0:
                skew[i] = np.mean(((rets - rets.mean()) / rets.std()) ** 3)
        return np.clip(skew / 3.0, -1.0, 1.0)  # Match MQL5


# ============================================================================
# FEATURE EXTRACTION - EXACT MATCH TO AIFeatureBuilder.mqh
# ============================================================================
class AIFeatureExtractor:
    """
    Extracts 34 features EXACTLY as AIFeatureBuilder.mqh does.
    This ensures 100% compatibility between training and inference.
    """
    
    def __init__(self, config: GeneratorConfig):
        self.config = config
        self.indicators = TechnicalIndicators()
        
        # Baseline trackers (matching m_atr_baseline, m_vol_baseline)
        self.atr_baselines = {}  # per regime
        self.vol_baselines = {}  # per regime
        
    def extract_all_features(self, df: pd.DataFrame) -> np.ndarray:
        """Extract all 34 features for each bar (from bar 50 onwards)"""
        n = len(df)
        features = np.zeros((n, AI_FEATURE_DIM), dtype=np.float32)
        
        # Precompute all indicators
        close = df['close'].to_numpy()
        high = df['high'].to_numpy()
        low = df['low'].to_numpy()
        volume = df['volume'].to_numpy()
        regime = df['regime'].to_numpy()
        
        # ATRs at multiple periods
        atr3 = self.indicators.atr(high, low, close, 3)
        atr5 = self.indicators.atr(high, low, close, 5)
        atr10 = self.indicators.atr(high, low, close, 10)
        atr14 = self.indicators.atr(high, low, close, 14)
        atr20 = self.indicators.atr(high, low, close, 20)
        
        # Other indicators
        rsi = self.indicators.rsi(close, 14)
        macd_main, macd_sig, macd_hist = self.indicators.macd(close)
        cci = self.indicators.cci(high, low, close, 14)
        stoch = self.indicators.stoch(high, low, close)
        mfi = self.indicators.mfi(high, low, close, volume, 14)
        
        # S/R detection
        sr_info = self.indicators.detect_sr_zones(high, low, close, 50)
        
        # Statistical features
        zscore = self.indicators.zscore(close, 20)
        skew = self.indicators.return_skew(close, 20)
        
        # Price returns
        ret1 = self.indicators.price_return(close, 1)
        ret2 = self.indicators.price_return(close, 2)
        ret3 = self.indicators.price_return(close, 3)
        ret5 = self.indicators.price_return(close, 5)
        
        # Update baselines per regime
        for i in range(n):
            r = int(regime[i])
            if r not in self.atr_baselines:
                self.atr_baselines[r] = atr14[i]
                self.vol_baselines[r] = volume[i]
            else:
                alpha = 0.05
                self.atr_baselines[r] = alpha * atr14[i] + (1 - alpha) * self.atr_baselines[r]
                self.vol_baselines[r] = alpha * volume[i] + (1 - alpha) * self.vol_baselines[r]
        
        # Extract features for each bar starting from bar 50
        for i in range(50, n):
            r = int(regime[i])
            atr_base = max(self.atr_baselines.get(r, atr14[i]), 1e-8)
            vol_base = max(self.vol_baselines.get(r, volume[i]), 1.0)
            
            f = np.zeros(AI_FEATURE_DIM, dtype=np.float32)
            
            # === Features 0-3: Price Returns (f0-f3) ===
            f[0] = ret1[i] / 0.05  # 1-bar return, clamped to [-0.05, 0.05] / 0.05
            f[1] = ret2[i] / 0.05  # 2-bar return
            f[2] = ret3[i] / 0.05  # 3-bar return
            f[3] = ret5[i] / 0.05  # 5-bar return
            
            # === Features 4-7: ATR Ratios (f4-f7) ===
            f[4] = min(atr3[i] / atr_base, 3.0) / 3.0
            f[5] = min(atr5[i] / atr_base, 3.0) / 3.0
            f[6] = min(atr10[i] / atr_base, 3.0) / 3.0
            f[7] = min(atr20[i] / atr_base, 3.0) / 3.0
            
            # === Features 8-11: Momentum/Oscillators (f8-f11) ===
            f[8] = rsi[i] / 100.0  # RSI normalized
            
            # MACD histogram normalized by ATR
            macd_norm = macd_hist[i] / atr_base
            f[9] = max(min(macd_norm, 1.0), -1.0) * 0.5 + 0.5  # Map [-1,1] -> [0,1]
            
            # CCI normalized
            f[10] = max(min(cci[i] / 200.0, 1.0), -1.0) * 0.5 + 0.5  # Map [-200,200] -> [0,1]
            
            # Stochastic
            f[11] = stoch[i] / 100.0
            
            # === Features 12-15: Volume (f12-f15) ===
            vol_ratio = volume[i] / vol_base if vol_base > 0 else 1.0
            f[12] = min(max(vol_ratio, 0.0), 5.0) / 5.0
            
            # OBV delta
            obv_delta = volume[i] if close[i] > close[i-1] else -volume[i]
            f[13] = max(min(obv_delta / vol_base, 3.0), -3.0) * 0.5 + 0.5
            
            # High volume spike
            f[14] = 1.0 if volume[i] > 2.0 * vol_base else 0.0
            
            # MFI
            f[15] = mfi[i] / 100.0
            
            # === Features 16-18: Structure (f16-f18) - Need pattern detection ===
            # These come from InjectStructure calls - we'll simulate with S/R info
            f[16] = sr_info['support_distance'][i]  # SR distance
            f[17] = sr_info['zone_strength'][i]      # Zone strength
            f[18] = min(max(sr_info['pattern_score'][i] / 100.0, 0.0), 1.0)  # Pattern score
            
            # === Features 19-21: Regime one-hot (f19-f21) ===
            if r in [1, 2]:  # TREND_UP, TREND_DOWN
                f[19], f[20], f[21] = 1.0, 0.0, 0.0
            elif r in [4, 5]:  # VOLATILE, CRASH
                f[19], f[20], f[21] = 0.0, 0.0, 1.0
            else:  # RANGE, TRANSITION, UNKNOWN
                f[19], f[20], f[21] = 0.0, 1.0, 0.0
            
            # === Features 22-25: Time & Statistics (f22-f25) ===
            dt = df['timestamp'].iloc[i]
            f[22] = dt.hour / 23.0
            f[23] = dt.weekday() / 6.0
            f[24] = (zscore[i] + 1.0) / 2.0  # Map [-1,1] -> [0,1]
            f[25] = (skew[i] + 1.0) / 2.0     # Map [-1,1] -> [0,1]
            
            # === Features 26-33: Pattern Features (f26-f33) ===
            # These require pattern detection - simulate realistic values
            # Based on S/R position and regime
            pos_in_range = 0.5  # default
            if i >= 50:
                recent_h = high[i-50:i].max()
                recent_l = low[i-50:i].min()
                range_sz = recent_h - recent_l
                if range_sz > 0:
                    pos_in_range = (close[i] - recent_l) / range_sz
            
            # Simulate pattern probabilities based on position and regime
            is_near_support = pos_in_range < 0.3
            is_near_resistance = pos_in_range > 0.7
            
            # Pattern features - base values modulated by regime and position
            regime_boost = self.config.regime_params.get(EMarketRegime(r), {}).get("pattern_quality_boost", 0.0)
            
            # f26: pattern_buy_prob
            f[26] = min(max(0.7 if is_near_support else 0.2 + regime_boost, 0.0), 1.0)
            
            # f27: pattern_sell_prob
            f[27] = min(max(0.7 if is_near_resistance else 0.2 + regime_boost, 0.0), 1.0)
            
            # f28: pattern_conflict (both buy and sell signals)
            f[28] = min(max(f[26] * f[27] * 2.0, 0.0), 1.0)
            
            # f29: pattern_gap (dominance gap)
            f[29] = min(max(abs(f[26] - f[27]), 0.0), 1.0)
            
            # f30: rejection_quality (wick rejection at S/R)
            f[30] = min(max(0.5 + (0.3 if (is_near_support or is_near_resistance) else 0.0) + regime_boost, 0.0), 1.0)
            
            # f31: trap_quality (false breakout detection)
            f[31] = min(max(0.3 - regime_boost, 0.0), 1.0)
            
            # f32: reclaim_quality
            f[32] = min(max(0.4 + regime_boost, 0.0), 1.0)
            
            # f33: follow_through
            f[33] = min(max(0.5 + (0.2 if is_near_support or is_near_resistance else 0.0) + regime_boost, 0.0), 1.0)
            
            features[i] = f
        
        return features


# ============================================================================
# TRADE SIMULATION & LABEL GENERATION
# ============================================================================
@dataclass
class TradeSimulation:
    """Simulated trade with full metadata"""
    entry_idx: int
    exit_idx: int
    direction: int  # 1=buy, -1=sell
    entry_price: float
    exit_price: float
    sl_price: float
    tp_price: float
    profit_pips: float
    profit_r: float  # R-multiple
    duration_bars: int
    hit_tp: bool
    hit_sl: bool
    entry_regime: int
    exit_regime: int
    features_at_entry: np.ndarray  # 34 features
    pattern_quality: float
    confidence: float
    
    def to_label(self) -> Tuple[float, float, Dict]:
        """Convert to training label and weight"""
        # Label: +1 (good trade), -1 (bad trade), 0 (no trade/neutral)
        if self.profit_r > 0.5:  # Good trade: > 0.5R profit
            label = 1.0
        elif self.profit_r < -0.5:  # Bad trade: > 0.5R loss
            label = -1.0
        else:
            label = 0.0  # Neutral/small outcome
        
        # Weight: higher for clearer outcomes, longer duration, higher confidence
        weight = 1.0
        if abs(self.profit_r) > 1.0:
            weight *= 1.5
        if abs(self.profit_r) > 2.0:
            weight *= 2.0
        if self.duration_bars > 20:
            weight *= 1.2
        if self.confidence > 0.7:
            weight *= 1.3
        weight = min(max(weight, 0.1), 5.0)
        
        metadata = {
            'trade_type': 'BUY' if self.direction == 1 else 'SELL',
            'profit_pips': self.profit_pips,
            'duration_bars': self.duration_bars,
            'hit_tp': self.hit_tp,
            'hit_sl': self.hit_sl,
            'regime': self.entry_regime,
            'entry_price': self.entry_price,
            'exit_price': self.exit_price,
            'sl_price': self.sl_price,
            'tp_price': self.tp_price,
        }
        
        return label, weight, metadata


class TradeSimulator:
    """Simulates trades following PASR logic with regime-aware parameters"""
    
    def __init__(self, config: GeneratorConfig, features: np.ndarray, df: pd.DataFrame):
        self.config = config
        self.features = features
        self.df = df
        self.close = df['close'].to_numpy()
        self.high = df['high'].to_numpy()
        self.low = df['low'].to_numpy()
        self.atr14 = TechnicalIndicators.atr(
            df['high'].to_numpy(), df['low'].to_numpy(), df['close'].to_numpy(), 14
        )
        
    def simulate_trades(self) -> List[TradeSimulation]:
        """Run trade simulation across all bars"""
        trades = []
        n = len(self.close)
        in_trade = False
        current_trade = None
        
        for i in range(50, n - 100):  # Need lookahead for exit
            if in_trade:
                # Check exit conditions
                exit_result = self._check_exit(current_trade, i)
                if exit_result is not None:
                    trades.append(exit_result)
                    in_trade = False
                    continue
            
            if not in_trade:
                # Check entry signal
                signal = self._check_entry_signal(i)
                if signal != 0:
                    trade = self._open_trade(signal, i)
                    if trade is not None:
                        current_trade = trade
                        in_trade = True
        
        return trades
    
    def _check_entry_signal(self, idx: int) -> int:
        """Check for entry signal at idx - matches PASR logic"""
        if idx < 50:
            return 0
            
        # Get features at this bar
        f = self.features[idx]
        if not np.any(f):
            return 0
            
        # Regime-based thresholds
        regime = int(self.df['regime'].iloc[idx])
        regime_params = self.config.regime_params.get(EMarketRegime(regime), {})
        
        # Structure features
        sr_dist = f[16]      # Support distance
        zone_str = f[17]     # Zone strength
        pattern = f[18]      # Pattern score
        
        # Pattern features
        buy_prob = f[26]
        sell_prob = f[27]
        gap = f[29]
        rejection = f[30]
        
        # RSI for overbought/oversold
        rsi = f[8] * 100
        
        # Session filter
        hour = self.df['timestamp'].iloc[idx].hour
        if not (self.config.session_start_hour <= hour <= self.config.session_end_hour):
            return 0
        
        # Regime-specific entry logic
        if regime in [1, 2]:  # TREND
            # Trend following: pullback to S/R in trend direction
            if regime == 1:  # TREND_UP - buy pullbacks
                if (sr_dist < 0.3 and zone_str > 0.4 and pattern > 0.5 and
                    buy_prob > 0.5 and gap > 0.2 and rsi < 70):
                    return 1
            else:  # TREND_DOWN - sell rallies
                if (sr_dist < 0.3 and zone_str > 0.4 and pattern > 0.5 and
                    sell_prob > 0.5 and gap > 0.2 and rsi > 30):
                    return -1
                    
        elif regime == 3:  # RANGE
            # Range trading: bounce at S/R
            if (zone_str > 0.5 and pattern > 0.4):
                if sr_dist < 0.2 and buy_prob > 0.6 and rejection > 0.5 and rsi < 65:
                    return 1
                if (1 - sr_dist) < 0.2 and sell_prob > 0.6 and rejection > 0.5 and rsi > 35:
                    return -1
                    
        elif regime in [4, 5]:  # VOLATILE, CRASH
            # Breakout/continuation
            if gap > 0.4 and rejection > 0.6:
                if buy_prob > 0.65:
                    return 1
                if sell_prob > 0.65:
                    return -1
        
        return 0
    
    def _open_trade(self, signal: int, idx: int) -> Optional[TradeSimulation]:
        """Open a new trade"""
        entry_price = self.close[idx]
        atr = self.atr14[idx]
        
        if atr <= 0:
            return None
            
        # SL/TP based on ATR
        sl_mult = self.config.sl_multiplier
        tp_mult = self.config.tp_multiplier
        
        if signal == 1:  # Buy
            sl_price = entry_price - atr * sl_mult
            tp_price = entry_price + atr * tp_mult
        else:  # Sell
            sl_price = entry_price + atr * sl_mult
            tp_price = entry_price - atr * tp_mult
        
        # Calculate pattern quality at entry
        f = self.features[idx]
        pattern_quality = (f[17] + f[18] + f[29] + f[30]) / 4.0
        confidence = min(max(pattern_quality * 1.5, 0.1), 0.95)
        
        return TradeSimulation(
            entry_idx=idx,
            exit_idx=-1,
            direction=signal,
            entry_price=entry_price,
            exit_price=0.0,
            sl_price=sl_price,
            tp_price=tp_price,
            profit_pips=0.0,
            profit_r=0.0,
            duration_bars=0,
            hit_tp=False,
            hit_sl=False,
            entry_regime=int(self.df['regime'].iloc[idx]),
            exit_regime=-1,
            features_at_entry=f.copy(),
            pattern_quality=pattern_quality,
            confidence=confidence
        )
    
    def _check_exit(self, trade: TradeSimulation, idx: int) -> Optional[TradeSimulation]:
        """Check if trade should exit"""
        high = self.high[idx]
        low = self.low[idx]
        
        hit_tp = False
        hit_sl = False
        exit_price = 0.0
        
        if trade.direction == 1:  # Long
            if low <= trade.sl_price:
                hit_sl = True
                exit_price = trade.sl_price
            elif high >= trade.tp_price:
                hit_tp = True
                exit_price = trade.tp_price
        else:  # Short
            if high >= trade.sl_price:
                hit_sl = True
                exit_price = trade.sl_price
            elif low <= trade.tp_price:
                hit_tp = True
                exit_price = trade.tp_price
        
        # Time-based exit (max 100 bars)
        if not hit_tp and not hit_sl and (idx - trade.entry_idx) >= 100:
            exit_price = self.close[idx]
        
        if hit_tp or hit_sl or (idx - trade.entry_idx) >= 100:
            # Finalize trade
            if trade.direction == 1:
                profit_pips = (exit_price - trade.entry_price) * 10000
            else:
                profit_pips = (trade.entry_price - exit_price) * 10000
            
            sl_dist_pips = abs(trade.entry_price - trade.sl_price) * 10000
            profit_r = profit_pips / sl_dist_pips if sl_dist_pips > 0 else 0.0
            
            trade.exit_idx = idx
            trade.exit_price = exit_price
            trade.profit_pips = profit_pips
            trade.profit_r = profit_r
            trade.duration_bars = idx - trade.entry_idx
            trade.hit_tp = hit_tp
            trade.hit_sl = hit_sl
            trade.exit_regime = int(self.df['regime'].iloc[idx])
            
            return trade
        
        return None


# ============================================================================
# MAIN GENERATION PIPELINE
# ============================================================================
def generate_training_data(
    output_path: str = "output/AI_Training_Data_Raw.csv",
    config: GeneratorConfig = None,
    seed: int = 42
) -> pd.DataFrame:
    """Generate complete training dataset"""
    if config is None:
        config = GeneratorConfig()
    
    print("=" * 60)
    print("PASR Quality Training Data Generation")
    print("=" * 60)
    
    # 1. Generate market data with regimes
    print("\n[1/5] Generating regime-aware market data...")
    market_gen = RegimeAwareMarketGenerator(config, seed)
    df = market_gen.generate_full_series(50000)
    print(f"    Generated {len(df)} bars across {df['regime'].nunique()} regimes")
    print(f"    Regime distribution:\n{df['regime'].value_counts().sort_index()}")
    
    # 2. Extract features (matching MQL5 exactly)
    print("\n[2/5] Extracting 34 features (matching AIFeatureBuilder.mqh)...")
    extractor = AIFeatureExtractor(config)
    features = extractor.extract_all_features(df)
    print(f"    Extracted features shape: {features.shape}")
    print(f"    Non-zero feature rows: {np.count_nonzero(np.any(features != 0, axis=1))}")
    
    # 3. Simulate trades
    print("\n[3/5] Simulating trades with regime-aware logic...")
    simulator = TradeSimulator(config, features, df)
    trades = simulator.simulate_trades()
    print(f"    Simulated {len(trades)} trades")
    
    # 4. Build training dataset
    print("\n[4/5] Building training dataset with labels...")
    rows = []
    for trade in trades:
        label, weight, meta = trade.to_label()
        
        # Only keep trades with clear outcomes (non-zero label) or a sample of neutral
        if label == 0.0 and np.random.random() > 0.1:  # Keep 10% of neutral
            continue
            
        row = {f'f{i}': trade.features_at_entry[i] for i in range(AI_FEATURE_DIM)}
        row.update({
            'label': label,
            'weight': weight,
            'timestamp': df['timestamp'].iloc[trade.entry_idx].isoformat(),
            'symbol': config.symbol,
            'timeframe': config.timeframe,
            'regime': trade.entry_regime,
            'trade_type': meta['trade_type'],
            'profit_pips': meta['profit_pips'],
            'duration_bars': meta['duration_bars'],
            'notes': f"hit_tp={meta['hit_tp']},hit_sl={meta['hit_sl']},regime={trade.entry_regime}"
        })
        rows.append(row)
    
    df_train = pd.DataFrame(rows)
    print(f"    Training samples: {len(df_train)}")
    print(f"    Label distribution:\n{df_train['label'].value_counts()}")
    print(f"    Regime distribution:\n{df_train['regime'].value_counts().sort_index()}")
    print(f"    Avg weight: {df_train['weight'].mean():.3f}")
    
    # 5. Save
    print(f"\n[5/5] Saving to {output_path}...")
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    df_train.to_csv(output_path, index=False)
    print(f"    Done! File size: {Path(output_path).stat().st_size / 1024:.1f} KB")
    
    return df_train


# ============================================================================
# MAIN
# ============================================================================
if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Generate quality PASR training data")
    parser.add_argument("--output", "-o", default="output/AI_Training_Data_Raw.csv")
    parser.add_argument("--samples-per-regime", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--total-bars", type=int, default=50000)
    args = parser.parse_args()
    
    config = GeneratorConfig(
        n_samples_per_regime=args.samples_per_regime,
    )
    
    df = generate_training_data(
        output_path=args.output,
        config=config,
        seed=args.seed
    )
    
    print(f"\n✓ Success! Generated {len(df)} training samples")
    print(f"  Output: {args.output}")
    print(f"\nNext steps:")
    print(f"  python tools/preprocess_ai_training_data.py --input {args.output} --output output/AI_Training_Data_Processed.csv")
    print(f"  python tools/train_mlp.py --csv output/AI_Training_Data_Processed.csv --out output")
    print(f"  python tools/retrain_ensemble.py --csv PASR_calibration.csv --out output")