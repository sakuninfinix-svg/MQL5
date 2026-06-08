#!/usr/bin/env python3
"""
PASR Strategy Simulator
Python-based backtesting simulator for PASR_MODULAR parameter optimization
Dapat dijalankan sepenuhnya di Linux tanpa perlu Wine atau MetaTrader 5
"""

import numpy as np
import pandas as pd
import json
import os
import sys
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import List, Dict, Tuple, Optional
import random

@dataclass
class PASRConfig:
    """Konfigurasi Parameter PASR"""
    # Risk Management
    lot_size: float = 0.01
    risk_percent: float = 1.0
    sl_multiplier: float = 1.5
    tp_multiplier: float = 2.5
    max_daily_loss_pct: float = 3.0
    max_drawdown_pct: float = 10.0
    max_open_positions: int = 3
    use_break_even: bool = True
    break_even_atr_mult: float = 1.0
    use_trailing_stop: bool = False
    trail_atr_mult: float = 1.0
    
    # Market Parameters
    atr_period: int = 14
    adx_period: int = 14
    adx_trend_threshold: float = 25.0
    spread_filter_pips: float = 3.0
    session_start_hour: int = 0
    session_end_hour: int = 23
    
    # Pattern Parameters
    min_pattern_score: float = 45.0
    pattern_lookback_bars: int = 50
    pin_bar_ratio: float = 2.0
    engulf_multiplier: float = 1.1

@dataclass 
class TradeResult:
    """Hasil Trade"""
    entry_price: float
    direction: int  # 1 = buy, -1 = sell
    sl_price: float
    tp_price: float
    exit_price: float
    profit: float
    profit_pips: float
    duration_bars: int
    hit_tp: bool
    hit_sl: bool
    entry_time: datetime
    exit_time: datetime

class MarketDataGenerator:
    """Generator Data Market Simulasi"""
    
    def __init__(self, seed: int = 42):
        np.random.seed(seed)
        self.current_price = 1.1000
        
    def generate_candlestick_data(self, n_bars: int = 10000, 
                                  trend: float = 0.0001,
                                  volatility: float = 0.001) -> pd.DataFrame:
        """Generate candlestick data simulasi"""
        
        opens = []
        highs = []
        lows = []
        closes = []
        volumes = []
        timestamps = []
        
        base_time = datetime(2024, 1, 1)
        
        for i in range(n_bars):
            # Generate realistic price movement
            open_price = self.current_price
            
            # Trend component
            trend_move = trend * np.random.randn()
            
            # Volatility component
            volatility_move = volatility * np.random.randn()
            
            # High-low range
            hl_range = abs(volatility * np.random.randn() * 0.5)
            
            high = open_price + max(0, trend_move) + hl_range
            low = open_price + min(0, trend_move) - hl_range
            
            # Close with some momentum
            close_move = trend_move * 0.7 + volatility_move * 0.3
            close = open_price + close_move
            
            # Ensure realistic OHLC relationships
            high = max(high, open, close)
            low = min(low, open, close)
            
            # Volume with some randomness
            volume = int(1000 + abs(np.random.randn()) * 500)
            
            opens.append(open_price)
            highs.append(high)
            lows.append(low)
            closes.append(close)
            volumes.append(volume)
            
            # Add 1 hour for H1 timeframe
            timestamp = base_time + timedelta(hours=i)
            timestamps.append(timestamp)
            
            self.current_price = close
        
        df = pd.DataFrame({
            'timestamp': timestamps,
            'open': opens,
            'high': highs,
            'low': lows,
            'close': closes,
            'volume': volumes
        })
        
        return df

class TechnicalIndicators:
    """Kalkulasi Indikator Teknis"""
    
    @staticmethod
    def atr(data: pd.DataFrame, period: int = 14) -> pd.Series:
        """Calculate Average True Range"""
        high = data['high']
        low = data['low']
        close = data['close']
        
        tr1 = high - low
        tr2 = abs(high - close.shift(1))
        tr3 = abs(low - close.shift(1))
        
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        atr = tr.rolling(window=period).mean()
        
        return atr
    
    @staticmethod
    def adx(data: pd.DataFrame, period: int = 14) -> pd.Series:
        """Calculate Average Directional Index (simplified)"""
        high = data['high']
        low = data['low']
        close = data['close']
        
        # Simplified ADX calculation
        tr = TechnicalIndicators.atr(data, period)
        
        plus_dm = high.diff()
        minus_dm = -low.diff()
        
        plus_dm = plus_dm.where((plus_dm > 0) & (plus_dm > minus_dm), 0)
        minus_dm = minus_dm.where((minus_dm > 0) & (minus_dm > plus_dm), 0)
        
        plus_di = 100 * (plus_dm.rolling(window=period).mean() / tr)
        minus_di = 100 * (minus_dm.rolling(window=period).mean() / tr)
        
        dx = 100 * abs(plus_di - minus_di) / (plus_di + minus_di)
        adx = dx.rolling(window=period).mean()
        
        return adx
    
    @staticmethod
    def rsi(data: pd.DataFrame, period: int = 14) -> pd.Series:
        """Calculate Relative Strength Index"""
        close = data['close']
        delta = close.diff()
        
        gain = delta.where(delta > 0, 0)
        loss = -delta.where(delta < 0, 0)
        
        avg_gain = gain.rolling(window=period).mean()
        avg_loss = loss.rolling(window=period).mean()
        
        rs = avg_gain / avg_loss
        rsi = 100 - (100 / (1 + rs))
        
        return rsi
    
    @staticmethod
    def detect_support_resistance(data: pd.DataFrame, lookback: int = 50,
                                  sensitivity: float = 0.001) -> Dict[str, float]:
        """Detect support and resistance levels (simplified)"""
        close = data['close'].values
        
        recent_data = close[-lookback:]
        recent_high = np.max(recent_data)
        recent_low = np.min(recent_data)
        current_price = close[-1]
        
        # Calculate distance to nearest S/R
        resistance_dist = (recent_high - current_price) / current_price
        support_dist = (current_price - recent_low) / current_price
        
        # Pattern score based on price position in range
        range_size = recent_high - recent_low
        position_in_range = (current_price - recent_low) / range_size if range_size > 0 else 0.5
        
        # Simplified pattern score
        pattern_score = 50 + (position_in_range - 0.5) * 100
        
        return {
            'resistance_distance': min(resistance_dist, 1.0),
            'support_distance': min(support_dist, 1.0),
            'pattern_score': max(0, min(100, pattern_score)),
            'zone_strength': min(1.0, sensitivity / (range_size / current_price))
        }

class PASRStrategySimulator:
    """Simulator Strategy PASR"""
    
    def __init__(self, config: PASRConfig):
        self.config = config
        self.trades: List[TradeResult] = []
        self.current_positions = 0
        self.daily_pnl = 0.0
        self.max_daily_loss = config.max_daily_loss_pct * 1000 / 100  # Assuming $1000 account
        self.peak_equity = 1000.0
        self.current_equity = 1000.0
        self.max_drawdown = 0.0
        
    def check_signal(self, data: pd.DataFrame, current_idx: int) -> Tuple[bool, int]:
        """Check if trading signal is generated"""
        
        if current_idx < self.config.pattern_lookback_bars:
            return False, 0
        
        current_data = data.iloc[current_idx]
        historical_data = data.iloc[current_idx - self.config.pattern_lookback_bars:current_idx]
        
        # Calculate technical indicators
        atr = TechnicalIndicators.atr(historical_data, self.config.atr_period).iloc[-1]
        adx = TechnicalIndicators.adx(historical_data, self.config.adx_period).iloc[-1]
        rsi = TechnicalIndicators.rsi(historical_data, 14).iloc[-1]
        
        # Detect S/R levels
        sr_info = TechnicalIndicators.detect_support_resistance(
            historical_data, 
            self.config.pattern_lookback_bars,
            0.001
        )
        
        current_price = current_data['close']
        
        # Session filter
        current_hour = current_data['timestamp'].hour
        if not (self.config.session_start_hour <= current_hour <= self.config.session_end_hour):
            return False, 0
        
        # Spread filter (simplified - assume fixed spread)
        # In real scenario, this would check actual spread
        # For simulation, we'll assume spread is acceptable
        
        # Trend filter using ADX
        if adx < self.config.adx_trend_threshold:
            return False, 0
        
        # Pattern score filter
        if sr_info['pattern_score'] < self.config.min_pattern_score:
            return False, 0
        
        # Generate signals based on PASR logic (simplified)
        # Buy signal: Price near support with good pattern
        buy_signal = (
            sr_info['support_distance'] < 0.002 and  # Close to support
            sr_info['pattern_score'] > self.config.min_pattern_score and
            rsi < 70 and  # Not overbought
            sr_info['zone_strength'] > 0.3  # Decent zone strength
        )
        
        # Sell signal: Price near resistance with good pattern
        sell_signal = (
            sr_info['resistance_distance'] < 0.002 and  # Close to resistance
            sr_info['pattern_score'] > self.config.min_pattern_score and
            rsi > 30 and  # Not oversold
            sr_info['zone_strength'] > 0.3  # Decent zone strength
        )
        
        if buy_signal:
            return True, 1  # Buy signal
        elif sell_signal:
            return True, -1  # Sell signal
        else:
            return False, 0
    
    def execute_trade(self, signal: int, data: pd.DataFrame, current_idx: int) -> Optional[TradeResult]:
        """Execute trade and simulate outcome"""
        
        if self.current_positions >= self.config.max_open_positions:
            return None
        
        current_data = data.iloc[current_idx]
        historical_data = data.iloc[max(0, current_idx - 50):current_idx]
        
        entry_price = current_data['close']
        atr = TechnicalIndicators.atr(historical_data, self.config.atr_period).iloc[-1]
        
        # Calculate SL and TP
        if signal == 1:  # Buy
            sl_price = entry_price - atr * self.config.sl_multiplier
            tp_price = entry_price + atr * self.config.tp_multiplier
        else:  # Sell
            sl_price = entry_price + atr * self.config.sl_multiplier
            tp_price = entry_price - atr * self.config.tp_multiplier
        
        # Simulate trade outcome (simplified - random but realistic)
        # In real scenario, this would follow actual price movements
        future_bars = min(100, len(data) - current_idx - 1)
        
        if future_bars < 10:
            return None
        
        # Simulate price movement with trend and noise
        trend = np.random.normal(0, 0.0001)
        volatility = atr * 0.5
        
        hit_tp = False
        hit_sl = False
        exit_price = entry_price
        exit_bar = current_idx
        
        for i in range(1, future_bars):
            future_idx = current_idx + i
            future_data = data.iloc[future_idx]
            future_price = future_data['close']
            
            # Add some randomness to create realistic outcomes
            price_move = trend + np.random.normal(0, volatility)
            simulated_price = entry_price + price_move * i
            
            # Check if TP or SL hit
            if signal == 1:  # Buy
                if simulated_price >= tp_price:
                    hit_tp = True
                    exit_price = tp_price
                    exit_bar = future_idx
                    break
                elif simulated_price <= sl_price:
                    hit_sl = True
                    exit_price = sl_price
                    exit_bar = future_idx
                    break
            else:  # Sell
                if simulated_price <= tp_price:
                    hit_tp = True
                    exit_price = tp_price
                    exit_bar = future_idx
                    break
                elif simulated_price >= sl_price:
                    hit_sl = True
                    exit_price = sl_price
                    exit_bar = future_idx
                    break
        
        # If neither TP nor SL hit within simulation period, use current price
        if not hit_tp and not hit_sl:
            exit_price = entry_price + trend * future_bars
            exit_bar = current_idx + future_bars
        
        # Calculate profit
        if signal == 1:
            profit = exit_price - entry_price
        else:
            profit = entry_price - exit_price
        
        profit_pips = profit * 10000  # Assuming EURUSD
        
        # Create trade result
        trade = TradeResult(
            entry_price=entry_price,
            direction=signal,
            sl_price=sl_price,
            tp_price=tp_price,
            exit_price=exit_price,
            profit=profit * self.config.lot_size * 100000,  # Convert to dollar value
            profit_pips=profit_pips,
            duration_bars=exit_bar - current_idx,
            hit_tp=hit_tp,
            hit_sl=hit_sl,
            entry_time=current_data['timestamp'],
            exit_time=data.iloc[exit_bar]['timestamp'] if exit_bar < len(data) else current_data['timestamp']
        )
        
        # Update account state
        self.current_equity += trade.profit
        self.daily_pnl += trade.profit
        self.current_positions += 1 if signal != 0 else 0
        
        # Update drawdown
        if self.current_equity > self.peak_equity:
            self.peak_equity = self.current_equity
        
        drawdown = (self.peak_equity - self.current_equity) / self.peak_equity
        if drawdown > self.max_drawdown:
            self.max_drawdown = drawdown
        
        self.trades.append(trade)
        
        # Reduce position count after trade completes
        self.current_positions -= 1
        
        return trade
    
    def backtest(self, data: pd.DataFrame) -> Dict:
        """Run backtest simulation"""
        
        print(f"Starting backtest simulation...")
        print(f"Data points: {len(data)}")
        print(f"Configuration: {self.config}")
        
        self.trades = []
        self.current_equity = 1000.0
        self.peak_equity = 1000.0
        self.max_drawdown = 0.0
        
        for i in range(len(data)):
            # Reset daily PNL at start of new day
            if i > 0 and data.iloc[i]['timestamp'].date() != data.iloc[i-1]['timestamp'].date():
                self.daily_pnl = 0.0
                self.current_positions = 0  # Reset positions daily
            
            # Check daily loss limit
            if self.daily_pnl < -self.max_daily_loss:
                continue
            
            # Check max drawdown limit
            if self.max_drawdown > self.config.max_drawdown_pct / 100:
                continue
            
            # Check for signal
            has_signal, direction = self.check_signal(data, i)
            
            if has_signal and direction != 0:
                self.execute_trade(direction, data, i)
        
        # Calculate performance metrics
        results = self.calculate_performance_metrics()
        
        return results
    
    def calculate_performance_metrics(self) -> Dict:
        """Calculate performance metrics"""
        
        if not self.trades:
            return {
                'total_trades': 0,
                'profitable_trades': 0,
                'win_rate': 0.0,
                'total_profit': 0.0,
                'total_loss': 0.0,
                'profit_factor': 0.0,
                'average_profit': 0.0,
                'average_loss': 0.0,
                'max_drawdown_pct': 0.0,
                'final_equity': 1000.0,
                'total_return_pct': 0.0,
                'sharpe_ratio': 0.0,
                'fitness_score': -1000.0
            }
        
        profitable_trades = [t for t in self.trades if t.profit > 0]
        losing_trades = [t for t in self.trades if t.profit <= 0]
        
        total_profit = sum(t.profit for t in profitable_trades)
        total_loss = abs(sum(t.profit for t in losing_trades))
        
        win_rate = len(profitable_trades) / len(self.trades) if self.trades else 0.0
        profit_factor = total_profit / total_loss if total_loss > 0 else 0.0
        
        avg_profit = total_profit / len(profitable_trades) if profitable_trades else 0.0
        avg_loss = total_loss / len(losing_trades) if losing_trades else 0.0
        
        total_return = (self.current_equity - 1000.0) / 1000.0 * 100
        sharpe_ratio = total_return / (self.max_drawdown * 100) if self.max_drawdown > 0 else 0.0
        
        # Fitness score (similar to MT5 implementation)
        if len(self.trades) < 20:
            fitness_score = -1000.0 + len(self.trades)
        elif total_profit <= 0:
            fitness_score = -1000.0 - abs(total_profit) - self.max_drawdown * 100
        else:
            fitness_score = (
                np.log(1.0 + total_profit) +
                2.0 * np.log(1.0 + profit_factor) +
                np.log(1.0 + win_rate) +
                0.25 * sharpe_ratio +
                min(2.0, len(self.trades) / 50.0) -
                0.15 * (self.max_drawdown * 100)
            )
        
        return {
            'total_trades': len(self.trades),
            'profitable_trades': len(profitable_trades),
            'win_rate': win_rate,
            'total_profit': total_profit,
            'total_loss': total_loss,
            'profit_factor': profit_factor,
            'average_profit': avg_profit,
            'average_loss': avg_loss,
            'max_drawdown_pct': self.max_drawdown * 100,
            'final_equity': self.current_equity,
            'total_return_pct': total_return,
            'sharpe_ratio': sharpe_ratio,
            'fitness_score': fitness_score,
            'config': asdict(self.config)
        }

class ParameterOptimizer:
    """Optimasi Parameter PASR"""
    
    def __init__(self, data: pd.DataFrame):
        self.data = data
    
    def optimize_parameters(self, param_ranges: Dict, n_iterations: int = 100) -> List[Dict]:
        """Optimasi parameter menggunakan random search"""
        
        print(f"Starting parameter optimization...")
        print(f"Parameter ranges: {param_ranges}")
        print(f"Iterations: {n_iterations}")
        
        results = []
        
        for i in range(n_iterations):
            # Generate random parameter combination
            config = self.generate_random_config(param_ranges)
            
            # Run backtest
            simulator = PASRStrategySimulator(config)
            result = simulator.backtest(self.data)
            
            results.append(result)
            
            if (i + 1) % 10 == 0:
                print(f"Completed {i + 1}/{n_iterations} iterations")
                print(f"Best fitness so far: {max(r['fitness_score'] for r in results):.2f}")
        
        # Sort results by fitness score
        results.sort(key=lambda x: x['fitness_score'], reverse=True)
        
        return results
    
    def generate_random_config(self, param_ranges: Dict) -> PASRConfig:
        """Generate random configuration from parameter ranges"""
        
        config = PASRConfig()
        
        # Risk parameters
        config.lot_size = 0.01  # Fixed for simulation
        config.risk_percent = random.uniform(*param_ranges.get('risk_percent', (0.5, 3.0)))
        config.sl_multiplier = random.uniform(*param_ranges.get('sl_multiplier', (1.0, 3.0)))
        config.tp_multiplier = random.uniform(*param_ranges.get('tp_multiplier', (1.5, 4.0)))
        config.max_open_positions = random.randint(*param_ranges.get('max_open_positions', (1, 5)))
        config.use_break_even = random.choice([True, False])
        config.use_trailing_stop = random.choice([True, False])
        
        # Market parameters
        config.atr_period = random.randint(*param_ranges.get('atr_period', (7, 35)))
        config.adx_period = random.randint(*param_ranges.get('adx_period', (7, 35)))
        config.adx_trend_threshold = random.uniform(*param_ranges.get('adx_trend_threshold', (20.0, 40.0)))
        
        # Pattern parameters
        config.min_pattern_score = random.uniform(*param_ranges.get('min_pattern_score', (35.0, 60.0)))
        config.pattern_lookback_bars = random.randint(*param_ranges.get('pattern_lookback_bars', (30, 80)))
        
        return config

def main():
    """Main execution function"""
    
    print("=" * 60)
    print("PASR_MODULAR Strategy Simulator & Parameter Optimizer")
    print("=" * 60)
    print()
    
    # Generate synthetic market data
    print("1. Generating synthetic market data...")
    generator = MarketDataGenerator(seed=42)
    data = generator.generate_candlestick_data(n_bars=5000, trend=0.00005, volatility=0.0008)
    print(f"   Generated {len(data)} candlesticks")
    print()
    
    # Define parameter ranges for optimization
    print("2. Setting up parameter optimization...")
    param_ranges = {
        'risk_percent': (0.5, 2.0),
        'sl_multiplier': (1.0, 2.5),
        'tp_multiplier': (1.5, 3.5),
        'max_open_positions': (1, 4),
        'atr_period': (7, 21),
        'adx_period': (7, 21),
        'adx_trend_threshold': (20.0, 35.0),
        'min_pattern_score': (40.0, 55.0),
        'pattern_lookback_bars': (30, 60)
    }
    print()
    
    # Run parameter optimization
    print("3. Running parameter optimization (this may take several minutes)...")
    optimizer = ParameterOptimizer(data)
    results = optimizer.optimize_parameters(param_ranges, n_iterations=50)
    print()
    
    # Display results
    print("=" * 60)
    print("OPTIMIZATION RESULTS")
    print("=" * 60)
    print()
    
    print("TOP 5 PARAMETER COMBINATIONS:")
    print()
    
    for i, result in enumerate(results[:5]):
        print(f"Rank {i+1}:")
        print(f"  Fitness Score: {result['fitness_score']:.2f}")
        print(f"  Total Trades: {result['total_trades']}")
        print(f"  Win Rate: {result['win_rate']*100:.1f}%")
        print(f"  Profit Factor: {result['profit_factor']:.2f}")
        print(f"  Total Return: {result['total_return_pct']:.1f}%")
        print(f"  Max Drawdown: {result['max_drawdown_pct']:.1f}%")
        print(f"  Sharpe Ratio: {result['sharpe_ratio']:.2f}")
        print(f"  Config: {result['config']}")
        print()
    
    # Save results to file
    print("4. Saving results to file...")
    output_file = "pasr_optimization_results.json"
    with open(output_file, 'w') as f:
        json.dump(results[:10], f, indent=2, default=str)
    print(f"   Results saved to {output_file}")
    print()
    
    # Save best configuration
    best_result = results[0]
    best_config = best_result['config']
    
    config_file = "pasr_best_config.json"
    with open(config_file, 'w') as f:
        json.dump(best_config, f, indent=2)
    print(f"   Best config saved to {config_file}")
    print()
    
    print("=" * 60)
    print("SIMULATION COMPLETED SUCCESSFULLY!")
    print("=" * 60)
    print()
    print("Note: This is a simplified simulator using synthetic data.")
    print("For production use, run the actual optimization in MetaTrader 5")
    print("using the preset files provided in the MQL5/Presets/ directory.")

if __name__ == "__main__":
    main()