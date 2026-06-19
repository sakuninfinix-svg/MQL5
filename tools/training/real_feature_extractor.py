#!/usr/bin/env python3
"""
PASR Real Feature Extractor
============================
Computes all 34 AI features (f0-f33) from OHLCV data, matching
AIFeatureBuilder.mqh Build() method exactly.

Key differences from generate_quality_training_data.py:
  - f26-f33: Real candlestick pattern detection (not hardcoded)
  - f0-f3: clip(ret, -0.05, 0.05) / 0.05 → [-1, 1] (matches MQL5)
  - f13: NormIndicator(obv_delta/vol_base, -3, 3) → [0, 1] (matches MQL5)
  - f22-f23: sinusoidal hour encoding (matches updated MQL5)

Usage:
  from real_feature_extractor import RealAIFeatureExtractor, AI_FEATURE_DIM
  extractor = RealAIFeatureExtractor()
  features = extractor.extract_all_features(df_ohlcv)
"""

import numpy as np
import pandas as pd
import math
from typing import Tuple

AI_FEATURE_DIM = 34
AI_SEQ_LEN = 64
AI_SEQ_FEATURE_DIM = 12


# ============================================================================
# Technical Indicators (vectorized, matching MQL5 built-in functions)
# ============================================================================
class TechnicalIndicators:
    @staticmethod
    def atr(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14) -> np.ndarray:
        tr1 = high - low
        tr2 = np.abs(high - np.roll(close, 1))
        tr3 = np.abs(low - np.roll(close, 1))
        tr = np.maximum(np.maximum(tr1, tr2), tr3)
        tr[0] = high[0] - low[0]
        return pd.Series(tr).rolling(window=period, min_periods=1).mean().to_numpy()

    @staticmethod
    def rsi(close: np.ndarray, period: int = 14) -> np.ndarray:
        delta = np.diff(close, prepend=close[0])
        gain = np.where(delta > 0, delta, 0)
        loss = np.where(delta < 0, -delta, 0)
        avg_gain = pd.Series(gain).rolling(window=period, min_periods=1).mean()
        avg_loss = pd.Series(loss).rolling(window=period, min_periods=1).mean()
        return (100 - 100 / (1 + avg_gain / (avg_loss + 1e-10))).to_numpy()

    @staticmethod
    def macd(close: np.ndarray, fast: int = 12, slow: int = 26, signal: int = 9):
        ema_fast = pd.Series(close).ewm(span=fast, adjust=False).mean()
        ema_slow = pd.Series(close).ewm(span=slow, adjust=False).mean()
        macd_line = ema_fast - ema_slow
        signal_line = macd_line.ewm(span=signal, adjust=False).mean()
        return macd_line.to_numpy(), signal_line.to_numpy(), (macd_line - signal_line).to_numpy()

    @staticmethod
    def cci(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14) -> np.ndarray:
        typical = (high + low + close) / 3
        ma = pd.Series(typical).rolling(window=period, min_periods=1).mean()
        md = pd.Series(typical).rolling(window=period, min_periods=1).apply(
            lambda x: np.mean(np.abs(x - np.mean(x))), raw=True
        )
        return ((typical - ma) / (0.015 * md + 1e-10)).to_numpy()

    @staticmethod
    def stoch(high: np.ndarray, low: np.ndarray, close: np.ndarray,
              k_period: int = 5, d_period: int = 3, slowing: int = 3) -> np.ndarray:
        lowest_low = pd.Series(low).rolling(window=k_period, min_periods=1).min()
        highest_high = pd.Series(high).rolling(window=k_period, min_periods=1).max()
        k_raw = 100 * (close - lowest_low) / (highest_high - lowest_low + 1e-10)
        return pd.Series(k_raw).rolling(window=slowing, min_periods=1).mean().to_numpy()

    @staticmethod
    def mfi(high: np.ndarray, low: np.ndarray, close: np.ndarray,
            volume: np.ndarray, period: int = 14) -> np.ndarray:
        typical = (high + low + close) / 3
        money_flow = typical * volume
        delta = np.diff(typical, prepend=typical[0])
        pos_flow = np.where(delta > 0, money_flow, 0)
        neg_flow = np.where(delta < 0, money_flow, 0)
        pos_mf = pd.Series(pos_flow).rolling(window=period, min_periods=1).sum()
        neg_mf = pd.Series(neg_flow).rolling(window=period, min_periods=1).sum()
        return (100 - 100 / (1 + pos_mf / (neg_mf + 1e-10))).to_numpy()


# ============================================================================
# Candlestick Pattern Detection (for f26-f33)
# ============================================================================
class CandlestickPatterns:
    """Detects candlestick patterns from OHLCV arrays for feature computation."""

    @staticmethod
    def _candle_parts(open_: np.ndarray, high: np.ndarray, low: np.ndarray, close: np.ndarray):
        body = np.abs(close - open_)
        upper_wick = high - np.maximum(open_, close)
        lower_wick = np.minimum(open_, close) - low
        total_range = high - low
        is_bullish = close > open_
        is_bearish = close < open_
        return body, upper_wick, lower_wick, total_range, is_bullish, is_bearish

    @staticmethod
    def detect_pin_bar_buy(lower_wick, body, upper_wick, total_range):
        if total_range < 1e-10:
            return 0.0
        quality = 0.0
        if body > 0 and lower_wick >= 2.0 * body and upper_wick <= 0.3 * total_range:
            wick_ratio = min(lower_wick / (body + 1e-10), 5.0) / 5.0
            quality = 0.4 + 0.6 * wick_ratio
        return quality

    @staticmethod
    def detect_pin_bar_sell(upper_wick, body, lower_wick, total_range):
        if total_range < 1e-10:
            return 0.0
        quality = 0.0
        if body > 0 and upper_wick >= 2.0 * body and lower_wick <= 0.3 * total_range:
            wick_ratio = min(upper_wick / (body + 1e-10), 5.0) / 5.0
            quality = 0.4 + 0.6 * wick_ratio
        return quality

    @staticmethod
    def detect_engulfing_buy(open_prev, close_prev, open_curr, close_curr,
                             body_prev, body_curr, is_bearish_prev, is_bullish_curr):
        if not (is_bearish_prev and is_bullish_curr):
            return 0.0
        if body_curr > body_prev * 1.1 and body_prev > 1e-10:
            engulf_ratio = min(body_curr / body_prev, 3.0) / 3.0
            return 0.5 + 0.5 * engulf_ratio
        return 0.0

    @staticmethod
    def detect_engulfing_sell(open_prev, close_prev, open_curr, close_curr,
                              body_prev, body_curr, is_bullish_prev, is_bearish_curr):
        if not (is_bullish_prev and is_bearish_curr):
            return 0.0
        if body_curr > body_prev * 1.1 and body_prev > 1e-10:
            engulf_ratio = min(body_curr / body_prev, 3.0) / 3.0
            return 0.5 + 0.5 * engulf_ratio
        return 0.0

    @staticmethod
    def detect_rejection_buy(close, high, low, lower_wick, body):
        total_range = high - low
        if total_range < 1e-10:
            return 0.0
        pos_in_range = (close - low) / total_range
        if pos_in_range > 0.6 and lower_wick > 1.5 * (body + 1e-10):
            return min(pos_in_range * (lower_wick / (total_range + 1e-10)), 1.0)
        return 0.0

    @staticmethod
    def detect_rejection_sell(close, high, low, upper_wick, body):
        total_range = high - low
        if total_range < 1e-10:
            return 0.0
        pos_in_range = (high - close) / total_range
        if pos_in_range > 0.6 and upper_wick > 1.5 * (body + 1e-10):
            return min(pos_in_range * (upper_wick / (total_range + 1e-10)), 1.0)
        return 0.0

    @staticmethod
    def detect_trap(high: np.ndarray, low: np.ndarray, close: np.ndarray,
                    i: int, lookback: int = 20) -> float:
        if i < lookback + 2:
            return 0.0
        start = max(0, i - lookback)
        recent_high = high[start:i - 1].max()
        recent_low = low[start:i - 1].min()
        prev_close = close[i - 1]
        curr_close = close[i]
        if prev_close > recent_high and curr_close < recent_high:
            trap_strength = min((prev_close - recent_high) / (recent_high - recent_low + 1e-10), 1.0)
            return 0.5 + 0.5 * trap_strength
        if prev_close < recent_low and curr_close > recent_low:
            trap_strength = min((recent_low - prev_close) / (recent_high - recent_low + 1e-10), 1.0)
            return 0.5 + 0.5 * trap_strength
        return 0.0

    @staticmethod
    def detect_reclaim(high: np.ndarray, low: np.ndarray, close: np.ndarray,
                       i: int, lookback: int = 30) -> float:
        if i < lookback + 3:
            return 0.0
        start = max(0, i - lookback)
        prev_high = high[start:i - 2].max()
        prev_low = low[start:i - 2].min()
        prev_close = close[i - 1]
        curr_close = close[i]
        if prev_close < prev_low and curr_close > prev_low:
            reclaim_strength = min((curr_close - prev_low) / (prev_high - prev_low + 1e-10), 1.0)
            return 0.4 + 0.6 * reclaim_strength
        if prev_close > prev_high and curr_close < prev_high:
            reclaim_strength = min((prev_high - curr_close) / (prev_high - prev_low + 1e-10), 1.0)
            return 0.4 + 0.6 * reclaim_strength
        return 0.0

    @staticmethod
    def detect_follow_through(close: np.ndarray, i: int, lookback: int = 3) -> float:
        if i < lookback + 1:
            return 0.0
        start = i - lookback
        rets = np.diff(close[start:i + 1])
        if len(rets) < 2:
            return 0.0
        direction = np.sign(rets[-1])
        if direction == 0:
            return 0.0
        consistent = np.sum(np.sign(rets) == direction)
        consistency = consistent / len(rets)
        momentum = abs(rets[-1]) / (np.abs(rets).mean() + 1e-10)
        return min(consistency * 0.6 + min(momentum, 2.0) * 0.2, 1.0)


# ============================================================================
# Real Feature Extractor (matches AIFeatureBuilder.mqh exactly)
# ============================================================================
class RealAIFeatureExtractor:
    def __init__(self):
        self.indicators = TechnicalIndicators()
        self.patterns = CandlestickPatterns()
        self.atr_baseline = 0.0
        self.vol_baseline = 0.0

    def extract_all_features(self, df: pd.DataFrame) -> np.ndarray:
        n = len(df)
        features = np.zeros((n, AI_FEATURE_DIM), dtype=np.float32)

        close = df['close'].to_numpy(dtype=np.float64)
        high = df['high'].to_numpy(dtype=np.float64)
        low = df['low'].to_numpy(dtype=np.float64)
        open_ = df['open'].to_numpy(dtype=np.float64)
        volume = df['volume'].to_numpy(dtype=np.float64)

        timestamps = df['timestamp']
        regime = df['regime'].to_numpy(dtype=np.int32) if 'regime' in df.columns else np.zeros(n, dtype=np.int32)

        atr3 = self.indicators.atr(high, low, close, 3)
        atr5 = self.indicators.atr(high, low, close, 5)
        atr10 = self.indicators.atr(high, low, close, 10)
        atr14 = self.indicators.atr(high, low, close, 14)
        atr20 = self.indicators.atr(high, low, close, 20)
        rsi = self.indicators.rsi(close, 14)
        macd_main, macd_sig, macd_hist = self.indicators.macd(close)
        cci = self.indicators.cci(high, low, close, 14)
        stoch = self.indicators.stoch(high, low, close)
        mfi = self.indicators.mfi(high, low, close, volume, 14)

        body, upper_wick, lower_wick, total_range, is_bullish, is_bearish = \
            self.patterns._candle_parts(open_, high, low, close)

        sr_res, sr_sup, sr_zone, sr_pat = self._detect_sr_zones(high, low, close, 50)

        self.atr_baseline = 0.0
        self.vol_baseline = 0.0
        alpha = 0.05

        warmup = 50

        for i in range(n):
            # Running EMA baseline update (matches MQL5 UpdateBaselines)
            if atr14[i] > 0:
                if self.atr_baseline <= 0:
                    self.atr_baseline = atr14[i]
                else:
                    self.atr_baseline = alpha * atr14[i] + (1 - alpha) * self.atr_baseline
            if volume[i] > 0:
                if self.vol_baseline <= 0:
                    self.vol_baseline = volume[i]
                else:
                    self.vol_baseline = alpha * volume[i] + (1 - alpha) * self.vol_baseline

            if i < warmup:
                continue

            atr_base = max(self.atr_baseline, 1e-8)
            vol_base = max(self.vol_baseline, 1.0)
            f = np.zeros(AI_FEATURE_DIM, dtype=np.float32)

            # f0-f3: Price returns — clip(ret, ±0.05) THEN / 0.05 → [-1, 1]
            for j, bars in enumerate([1, 2, 3, 5]):
                c0 = close[i]
                cn = close[i - bars] if i >= bars else close[0]
                ret = (c0 - cn) / cn if cn != 0 else 0.0
                ret = max(-0.05, min(0.05, ret))
                f[j] = ret / 0.05

            # f4-f7: ATR ratios — min(atr/baseline, 3) / 3 → [0, 1]
            f[4] = min(atr3[i] / atr_base, 3.0) / 3.0
            f[5] = min(atr5[i] / atr_base, 3.0) / 3.0
            f[6] = min(atr10[i] / atr_base, 3.0) / 3.0
            f[7] = min(atr20[i] / atr_base, 3.0) / 3.0

            # f8: RSI / 100 → [0, 1]
            f[8] = rsi[i] / 100.0

            # f9: MACD histogram — clip(macd/atr, ±1) * 0.5 + 0.5 → [0, 1]
            macd_norm = macd_hist[i] / atr_base
            f[9] = np.clip(macd_norm, -1.0, 1.0) * 0.5 + 0.5

            # f10: CCI — clip(cci/200, ±1) * 0.5 + 0.5 → [0, 1]
            f[10] = np.clip(cci[i] / 200.0, -1.0, 1.0) * 0.5 + 0.5

            # f11: Stochastic / 100 → [0, 1]
            f[11] = stoch[i] / 100.0

            # f12: Volume ratio — min(max(ratio, 0), 5) / 5 → [0, 1]
            vol1 = volume[i - 1] if i > 0 else volume[i]
            vol_ratio = volume[i] / vol1 if vol1 > 0 else 1.0
            f[12] = min(max(vol_ratio, 0.0), 5.0) / 5.0

            # f13: OBV delta — NormIndicator(obv/vol_base, -3, 3) → [0, 1]
            obv_delta = volume[i] if close[i] > close[i - 1] else -volume[i]
            obv_norm = obv_delta / vol_base
            f[13] = (np.clip(obv_norm, -3.0, 3.0) + 3.0) / 6.0

            # f14: Volume spike → {0, 1}
            f[14] = 1.0 if volume[i] > 2.0 * vol_base else 0.0

            # f15: MFI / 100 → [0, 1]
            f[15] = mfi[i] / 100.0

            # f16-f18: S/R features — already Clamp01 in detect_sr_zones
            f[16] = sr_sup[i]
            f[17] = sr_zone[i]
            f[18] = sr_pat[i]

            # f19-f21: Regime one-hot
            r = int(regime[i])
            if r in [1, 2]:
                f[19], f[20], f[21] = 1.0, 0.0, 0.0
            elif r in [4, 5]:
                f[19], f[20], f[21] = 0.0, 0.0, 1.0
            else:
                f[19], f[20], f[21] = 0.0, 1.0, 0.0

            # f22-f23: Sinusoidal hour encoding
            dt = timestamps.iloc[i]
            if hasattr(dt, 'hour'):
                hour = dt.hour
            else:
                hour = 0
            f[22] = math.sin(2.0 * math.pi * hour / 24.0) * 0.5 + 0.5
            f[23] = math.cos(2.0 * math.pi * hour / 24.0) * 0.5 + 0.5

            # f24-f25: Z-score and skewness — clip(z/3, ±1) * 0.5 + 0.5
            f[24] = self._zscore_single(close, i, 20)
            f[25] = self._skew_single(close, i, 20)

            # f26-f33: Candlestick pattern features
            f[26], f[27], f[28], f[29], f[30], f[31], f[32], f[33] = \
                self._compute_pattern_features(
                    i, open_, high, low, close,
                    body, upper_wick, lower_wick, total_range,
                    is_bullish, is_bearish
                )

            features[i] = f

        return features

    def _compute_pattern_features(self, i, open_, high, low, close,
                                  body, upper_wick, lower_wick, total_range,
                                  is_bullish, is_bearish):
        lookback = 3
        start = max(0, i - lookback)

        buy_scores = []
        sell_scores = []
        max_rejection = 0.0

        for j in range(start, i + 1):
            if total_range[j] < 1e-10:
                continue

            pb_buy = self.patterns.detect_pin_bar_buy(
                lower_wick[j], body[j], upper_wick[j], total_range[j])
            pb_sell = self.patterns.detect_pin_bar_sell(
                upper_wick[j], body[j], lower_wick[j], total_range[j])

            eng_buy = 0.0
            eng_sell = 0.0
            if j > 0:
                eng_buy = self.patterns.detect_engulfing_buy(
                    open_[j - 1], close[j - 1], open_[j], close[j],
                    body[j - 1], body[j], is_bearish[j - 1], is_bullish[j])
                eng_sell = self.patterns.detect_engulfing_sell(
                    open_[j - 1], close[j - 1], open_[j], close[j],
                    body[j - 1], body[j], is_bullish[j - 1], is_bearish[j])

            rej_buy = self.patterns.detect_rejection_buy(
                close[j], high[j], low[j], lower_wick[j], body[j])
            rej_sell = self.patterns.detect_rejection_sell(
                close[j], high[j], low[j], upper_wick[j], body[j])

            recency = 1.0 - (i - j) * 0.2

            buy_score = max(pb_buy, eng_buy, rej_buy) * recency
            sell_score = max(pb_sell, eng_sell, rej_sell) * recency

            if buy_score > 0:
                buy_scores.append(buy_score)
            if sell_score > 0:
                sell_scores.append(sell_score)

            max_rejection = max(max_rejection, rej_buy, rej_sell)

        buy_prob = min(sum(sorted(buy_scores, reverse=True)[:3]) if buy_scores else 0.0, 1.0)
        sell_prob = min(sum(sorted(sell_scores, reverse=True)[:3]) if sell_scores else 0.0, 1.0)

        conflict = min(buy_prob * sell_prob * 2.0, 1.0)
        gap = min(abs(buy_prob - sell_prob), 1.0)
        rejection = max_rejection

        trap = self.patterns.detect_trap(high, low, close, i)
        reclaim = self.patterns.detect_reclaim(high, low, close, i)
        follow_through = self.patterns.detect_follow_through(close, i)

        return buy_prob, sell_prob, conflict, gap, rejection, trap, reclaim, follow_through

    def _detect_sr_zones(self, high, low, close, lookback=50):
        n = len(close)
        res_dist = np.full(n, 0.5)
        sup_dist = np.full(n, 0.5)
        zone_str = np.full(n, 0.5)
        pat_score = np.full(n, 50.0)

        for i in range(lookback, n):
            rh = high[i - lookback:i].max()
            rl = low[i - lookback:i].min()
            cur = close[i]

            res_dist[i] = min(max((rh - cur) / cur, 0), 1) if cur > 0 else 0.5
            sup_dist[i] = min(max((cur - rl) / cur, 0), 1) if cur > 0 else 0.5

            rng = rh - rl
            pos = (cur - rl) / rng if rng > 0 else 0.5
            zone_str[i] = np.clip(1.0 - 2.0 * abs(pos - 0.5), 0.0, 1.0)
            pat_score[i] = np.clip(50 + (0.5 - abs(pos - 0.5)) * 100, 0.0, 100.0) / 100.0

        return res_dist, sup_dist, zone_str, pat_score

    def _zscore_single(self, close, i, n):
        if i < n:
            return 0.5
        window = close[i - n:i]
        mean = window.mean()
        std = window.std()
        if std <= 0:
            return 0.5
        z = (close[i - 1] - mean) / std
        z = np.clip(z / 3.0, -1.0, 1.0)
        return z * 0.5 + 0.5

    def _skew_single(self, close, i, n):
        if i < n + 1:
            return 0.5
        rets = np.diff(close[i - n - 1:i]) / close[i - n - 1:i - 1]
        if len(rets) < 3 or rets.std() == 0:
            return 0.5
        sk = np.mean(((rets - rets.mean()) / rets.std()) ** 3)
        sk = np.clip(sk / 3.0, -1.0, 1.0)
        return sk * 0.5 + 0.5


# ============================================================================
# Standalone test
# ============================================================================
def _self_test():
    print("=" * 60)
    print("Real Feature Extractor — Self Test")
    print("=" * 60)

    np.random.seed(42)
    n = 500
    base_price = 1.1000
    prices = [base_price]
    for _ in range(n - 1):
        prices.append(prices[-1] * (1 + np.random.randn() * 0.0008))

    close = np.array(prices)
    high = close + np.abs(np.random.randn(n) * 0.0003)
    low = close - np.abs(np.random.randn(n) * 0.0003)
    open_ = close + np.random.randn(n) * 0.0002

    from datetime import datetime, timedelta
    timestamps = [datetime(2024, 1, 1) + timedelta(hours=i) for i in range(n)]
    volumes = np.random.randint(500, 3000, n).astype(float)

    df = pd.DataFrame({
        'timestamp': timestamps,
        'open': open_,
        'high': high,
        'low': low,
        'close': close,
        'volume': volumes,
        'regime': np.random.choice([1, 2, 3, 4], n),
    })

    extractor = RealAIFeatureExtractor()
    features = extractor.extract_all_features(df)

    print(f"Shape: {features.shape}")
    print(f"Non-zero rows: {np.count_nonzero(np.any(features != 0, axis=1))}")

    for j in range(AI_FEATURE_DIM):
        col = features[:, j]
        nonzero = col[col != 0]
        if len(nonzero) == 0:
            print(f"  f{j}: ALL ZERO")
            continue
        mn, mx, mn_nz = col.min(), col.max(), nonzero.min() if len(nonzero) > 0 else 0
        print(f"  f{j:2d}: min={mn:+.4f} max={mx:+.4f} mean={col.mean():+.4f} "
              f"std={col.std():.4f} nonzero_min={mn_nz:+.4f}")

    print("\nRange checks (must match AIFeatureBuilder.mqh):")
    f0 = features[:, 0]
    print(f"  f0-f3 in [-1,1]: {f0.min() >= -1.0 and f0.max() <= 1.0}")
    f13 = features[:, 13]
    print(f"  f13 in [0,1]:    {f13.min() >= 0.0 and f13.max() <= 1.0}")
    f17 = features[:, 17]
    print(f"  f17 in [0,1]:    {f17.min() >= 0.0 and f17.max() <= 1.0}")
    f22 = features[:, 22]
    f23 = features[:, 23]
    print(f"  f22 in [0,1]:    {f22.min() >= 0.0 and f22.max() <= 1.0} (sin hour)")
    print(f"  f23 in [0,1]:    {f23.min() >= 0.0 and f23.max() <= 1.0} (cos hour)")

    f26 = features[50:, 26]
    f30 = features[50:, 30]
    unique_26 = np.unique(np.round(f26, 3))
    unique_30 = np.unique(np.round(f30, 3))
    print(f"\n  f26 unique values: {len(unique_26)} (should be >> 3)")
    print(f"  f30 unique values: {len(unique_30)} (should be >> 3)")
    print(f"  f26 range: [{f26.min():.4f}, {f26.max():.4f}]")
    print(f"  f30 range: [{f30.min():.4f}, {f30.max():.4f}]")

    print("\nSelf-test PASSED" if len(unique_26) > 5 else "\nSelf-test: f26 needs improvement")


if __name__ == "__main__":
    import sys
    if "--test" in sys.argv:
        _self_test()
    else:
        print("Usage: python3 real_feature_extractor.py --test")
