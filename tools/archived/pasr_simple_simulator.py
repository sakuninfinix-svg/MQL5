#!/usr/bin/env python3
"""
PASR Strategy Simple Simulator
Version without numpy/pandas dependencies - uses standard library only
"""

import random
import json
import math
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import List, Dict, Tuple, Optional

# Aliases untuk built-in functions yang mungkin ter-shadow
builtins_max = max
builtins_min = min

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
    entry_time: str
    exit_time: str

class CandlestickData:
    """Simple candlestick data structure"""
    
    def __init__(self):
        self.opens = []
        self.highs = []
        self.lows = []
        self.closes = []
        self.volumes = []
        self.timestamps = []
    
    def add_candle(self, open_p, high_p, low_p, close_p, volume, timestamp):
        self.opens.append(open_p)
        self.highs.append(high_p)
        self.lows.append(low_p)
        self.closes.append(close_p)
        self.volumes.append(volume)
        self.timestamps.append(timestamp)
    
    def __len__(self):
        return len(self.closes)
    
    def get_recent(self, n_bars):
        """Get recent n bars"""
        start = builtins_max(0, len(self) - n_bars)
        return {
            'opens': self.opens[start:],
            'highs': self.highs[start:],
            'lows': self.lows[start:],
            'closes': self.closes[start:],
            'volumes': self.volumes[start:],
            'timestamps': self.timestamps[start:]
        }

class MarketDataGenerator:
    """Generator Data Market Simulasi"""
    
    def __init__(self, seed: int = 42):
        random.seed(seed)
        self.current_price = 1.1000
        self.peak_price = 1.1000
        
    def generate_candlestick_data(self, n_bars: int = 5000, 
                                  trend: float = 0.0001,
                                  volatility: float = 0.001) -> CandlestickData:
        """Generate candlestick data simulasi"""
        
        data = CandlestickData()
        base_time = datetime(2024, 1, 1)
        
        for i in range(n_bars):
            # Generate realistic price movement
            open_price = self.current_price
            
            # Trend component
            trend_move = trend * random.gauss(0, 1)
            
            # Volatility component
            volatility_move = volatility * random.gauss(0, 1)
            
            # High-low range
            hl_range = abs(volatility * random.gauss(0, 1) * 0.5)
            
            high = open_price + builtins_max(0, trend_move) + hl_range
            low = open_price + builtins_min(0, trend_move) - hl_range
            
            # Close with some momentum
            close_move = trend_move * 0.7 + volatility_move * 0.3
            close = open_price + close_move
            
            # Ensure realistic OHLC relationships
            high = builtins_max(high, open_price, close)
            low = builtins_min(low, open_price, close)
            
            # Volume with some randomness
            volume = int(1000 + abs(random.gauss(0, 1)) * 500)
            
            # Add 1 hour for H1 timeframe
            timestamp = base_time + timedelta(hours=i)
            
            data.add_candle(open_price, high, low, close, volume, timestamp)
            
            self.current_price = close
        
        return data

class TechnicalIndicators:
    """Kalkulasi Indikator Teknis (Standard Library Only)"""
    
    @staticmethod
    def calculate_atr(highs: List[float], lows: List[float], closes: List[float], period: int = 14) -> List[float]:
        """Calculate Average True Range"""
        atr = []
        
        for i in range(len(closes)):
            if i < period - 1:
                atr.append(0.0)
                continue
            
            tr_values = []
            for j in range(builtins_max(0, i - period + 1), i + 1):
                if j == 0:
                    prev_close = closes[j]
                else:
                    prev_close = closes[j - 1]
                
                tr1 = highs[j] - lows[j]
                tr2 = abs(highs[j] - prev_close)
                tr3 = abs(lows[j] - prev_close)
                tr = builtins_max(tr1, tr2, tr3)
                tr_values.append(tr)
            
            atr.append(sum(tr_values) / len(tr_values) if tr_values else 0.0)
        
        return atr
    
    @staticmethod
    def calculate_rsi(closes: List[float], period: int = 14) -> List[float]:
        """Calculate Relative Strength Index"""
        rsi = []
        
        for i in range(len(closes)):
            if i < period:
                rsi.append(50.0)  # Neutral
                continue
            
            gains = []
            losses = []
            
            for j in range(builtins_max(0, i - period), i):
                change = closes[j] - closes[j - 1] if j > 0 else 0
                if change > 0:
                    gains.append(change)
                    losses.append(0)
                else:
                    gains.append(0)
                    losses.append(abs(change))
            
            avg_gain = sum(gains) / len(gains) if gains else 0
            avg_loss = sum(losses) / len(losses) if losses else 0
            
            if avg_loss == 0:
                rsi.append(100.0 if avg_gain > 0 else 50.0)
            else:
                rs = avg_gain / avg_loss
                rsi_value = 100 - (100 / (1 + rs))
                rsi.append(rsi_value)
        
        return rsi
    
    @staticmethod
    def calculate_simplified_adx(highs: List[float], lows: List[float], closes: List[float], period: int = 14) -> List[float]:
        """Calculate simplified ADX"""
        adx = []
        
        for i in range(len(closes)):
            if i < period:
                adx.append(20.0)  # Default value
                continue
            
            # Use recent price range as simplified trend strength
            recent_high = builtins_max(highs[i-period:i])
            recent_low = builtins_min(lows[i-period:i])
            price_range = recent_high - recent_low
            avg_price = sum(closes[i-period:i]) / period
            
            # Simplified trend strength
            trend_strength = builtins_min(50.0, (price_range / avg_price) * 10000) if avg_price > 0 else 20.0
            adx.append(trend_strength)
        
        return adx

class PASRStrategySimulator:
    """Simulator Strategy PASR (Standard Library Only)"""
    
    def __init__(self, config: PASRConfig):
        self.config = config
        self.trades: List[TradeResult] = []
        self.current_positions = 0
        self.daily_pnl = 0.0
        self.max_daily_loss = config.max_daily_loss_pct * 1000 / 100  # Assuming $1000 account
        self.peak_equity = 1000.0
        self.current_equity = 1000.0
        self.max_drawdown = 0.0
        
    def check_signal(self, data: CandlestickData, current_idx: int) -> Tuple[bool, int]:
        """Check if trading signal is generated"""
        
        if current_idx < self.config.pattern_lookback_bars:
            return False, 0
        
        recent_data = data.get_recent(self.config.pattern_lookback_bars)
        
        # Calculate technical indicators
        atr = TechnicalIndicators.calculate_atr(
            recent_data['highs'], recent_data['lows'], recent_data['closes'], 
            self.config.atr_period
        )[-1] if recent_data['closes'] else 0.0
        
        adx = TechnicalIndicators.calculate_simplified_adx(
            recent_data['highs'], recent_data['lows'], recent_data['closes'],
            self.config.adx_period
        )[-1] if recent_data['closes'] else 0.0
        
        rsi = TechnicalIndicators.calculate_rsi(
            recent_data['closes'], 14
        )[-1] if recent_data['closes'] else 50.0
        
        # Detect S/R levels (simplified)
        recent_highs = recent_data['highs']
        recent_lows = recent_data['lows']
        recent_closes = recent_data['closes']
        
        if not recent_closes:
            return False, 0
            
        recent_high = builtins_max(recent_highs)
        recent_low = builtins_min(recent_lows)
        current_price = recent_closes[-1]
        
        # Calculate distance to nearest S/R
        resistance_dist = (recent_high - current_price) / current_price if current_price > 0 else 0
        support_dist = (current_price - recent_low) / current_price if current_price > 0 else 0
        
        # Pattern score based on price position in range
        range_size = recent_high - recent_low
        position_in_range = (current_price - recent_low) / range_size if range_size > 0 else 0.5
        
        # Simplified pattern score
        pattern_score = 50 + (position_in_range - 0.5) * 100
        
        # Session filter
        current_time = recent_data['timestamps'][-1] if recent_data['timestamps'] else datetime.now()
        current_hour = current_time.hour
        if not (self.config.session_start_hour <= current_hour <= self.config.session_end_hour):
            return False, 0
        
        # Trend filter using ADX (relaxed)
        if adx < (self.config.adx_trend_threshold * 0.5):  # More relaxed
            return False, 0
        
        # Pattern score filter (relaxed)
        if pattern_score < (self.config.min_pattern_score - 15):  # More relaxed
            return False, 0
        
        # Generate signals based on PASR logic (simplified and relaxed)
        buy_signal = (
            support_dist < 0.01 and  # Relaxed support distance
            pattern_score > (self.config.min_pattern_score - 10) and  # Relaxed pattern score
            rsi < 75  # Relaxed RSI
        )
        
        sell_signal = (
            resistance_dist < 0.01 and  # Relaxed resistance distance
            pattern_score > (self.config.min_pattern_score - 10) and  # Relaxed pattern score
            rsi > 25  # Relaxed RSI
        )
        
        if buy_signal:
            return True, 1  # Buy signal
        elif sell_signal:
            return True, -1  # Sell signal
        else:
            return False, 0
    
    def execute_trade(self, signal: int, data: CandlestickData, current_idx: int) -> Optional[TradeResult]:
        """Execute trade and simulate outcome"""
        
        if self.current_positions >= self.config.max_open_positions:
            return None
        
        recent_data = data.get_recent(self.config.atr_period)
        
        if not recent_data['closes']:
            return None
            
        entry_price = recent_data['closes'][-1]
        
        atr_list = TechnicalIndicators.calculate_atr(
            recent_data['highs'], recent_data['lows'], recent_data['closes'],
            self.config.atr_period
        )
        atr = atr_list[-1] if atr_list else 0.001
        
        # Calculate SL and TP
        if signal == 1:  # Buy
            sl_price = entry_price - atr * self.config.sl_multiplier
            tp_price = entry_price + atr * self.config.tp_multiplier
        else:  # Sell
            sl_price = entry_price + atr * self.config.sl_multiplier
            tp_price = entry_price - atr * self.config.tp_multiplier
        
        # Simulate trade outcome (simplified)
        future_bars = builtins_min(100, len(data) - current_idx - 1)
        
        if future_bars < 10:
            return None
        
        # Simulate price movement with trend and noise
        trend = random.gauss(0, 0.0001)
        volatility = atr * 0.5
        
        hit_tp = False
        hit_sl = False
        exit_price = entry_price
        exit_bar = current_idx
        
        for i in range(1, future_bars):
            future_idx = current_idx + i
            if future_idx >= len(data):
                break
                
            future_data = data.get_recent(1)
            if not future_data['closes']:
                break
                
            # Add some randomness to create realistic outcomes
            price_move = trend + random.gauss(0, volatility)
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
        
        # Get timestamps
        entry_time = data.timestamps[current_idx] if current_idx < len(data.timestamps) else str(datetime.now())
        exit_time = data.timestamps[exit_bar] if exit_bar < len(data.timestamps) else str(datetime.now())
        
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
            entry_time=str(entry_time),
            exit_time=str(exit_time)
        )
        
        # Update account state
        self.current_equity += trade.profit
        self.daily_pnl += trade.profit
        self.current_positions += 1 if signal != 0 else 0
        
        # Update drawdown
        if self.current_equity > self.peak_equity:
            self.peak_equity = self.current_equity
        
        drawdown = (self.peak_equity - self.current_equity) / self.peak_equity if self.peak_equity > 0 else 0
        if drawdown > self.max_drawdown:
            self.max_drawdown = drawdown
        
        self.trades.append(trade)
        
        # Reduce position count after trade completes
        self.current_positions -= 1
        
        return trade
    
    def backtest(self, data: CandlestickData) -> Dict:
        """Run backtest simulation"""
        
        print(f"Starting backtest simulation...")
        print(f"Data points: {len(data)}")
        print(f"Configuration: risk_percent={self.config.risk_percent}, sl_mult={self.config.sl_multiplier}, tp_mult={self.config.tp_multiplier}")
        
        self.trades = []
        self.current_equity = 1000.0
        self.peak_equity = 1000.0
        self.max_drawdown = 0.0
        
        for i in range(len(data)):
            # Reset daily PNL at start of new day
            if i > 0:
                current_date = data.timestamps[i].date() if isinstance(data.timestamps[i], datetime) else datetime.strptime(str(data.timestamps[i]), "%Y-%m-%d %H:%M:%S").date()
                prev_date = data.timestamps[i-1].date() if isinstance(data.timestamps[i-1], datetime) else datetime.strptime(str(data.timestamps[i-1]), "%Y-%m-%d %H:%M:%S").date()
                
                if current_date != prev_date:
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
                math.log(1.0 + total_profit) +
                2.0 * math.log(1.0 + profit_factor) +
                math.log(1.0 + win_rate) +
                0.25 * sharpe_ratio +
                builtins_min(2.0, len(self.trades) / 50.0) -
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
    """Optimasi Parameter PASR (Standard Library Only)"""
    
    def __init__(self, data: CandlestickData):
        self.data = data
    
    def optimize_parameters(self, param_ranges: Dict, n_iterations: int = 50) -> List[Dict]:
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
            
            if (i + 1) % 5 == 0:
                print(f"Completed {i + 1}/{n_iterations} iterations")
                best_fitness = builtins_max(r['fitness_score'] for r in results)
                print(f"Best fitness so far: {best_fitness:.2f}")
        
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
    print("PASR_MODULAR Strategy Simple Simulator")
    print("Standard Library Version - No numpy/pandas required")
    print("=" * 60)
    print()
    
    # Generate synthetic market data
    print("1. Generating synthetic market data...")
    generator = MarketDataGenerator(seed=42)
    data = generator.generate_candlestick_data(n_bars=2000, trend=0.00005, volatility=0.0008)
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
    print("3. Running parameter optimization (20 iterations for speed)...")
    optimizer = ParameterOptimizer(data)
    results = optimizer.optimize_parameters(param_ranges, n_iterations=20)
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
        if 'config' in result:
            print(f"  Key Config: risk_pct={result['config']['risk_percent']:.2f}, sl_mult={result['config']['sl_multiplier']:.2f}, tp_mult={result['config']['tp_multiplier']:.2f}")
        else:
            print(f"  Config: Not available")
        print()
    
    # Save results to file
    print("4. Saving results to file...")
    output_file = "/home/agus/pasr_optimization_results.json"
    with open(output_file, 'w') as f:
        json.dump(results[:10], f, indent=2, default=str)
    print(f"   Results saved to {output_file}")
    print()
    
    # Save best configuration
    best_result = results[0]
    best_config = best_result['config']
    
    config_file = "/home/agus/pasr_best_config.json"
    with open(config_file, 'w') as f:
        json.dump(best_config, f, indent=2)
    print(f"   Best config saved to {config_file}")
    print()
    
    print("=" * 60)
    print("SIMULATION COMPLETED SUCCESSFULLY!")
    print("=" * 60)
    print()
    print("Summary:")
    print(f"- Best fitness score: {results[0]['fitness_score']:.2f}")
    print(f"- Total return: {results[0]['total_return_pct']:.1f}%")
    print(f"- Win rate: {results[0]['win_rate']*100:.1f}%")
    print(f"- Profit factor: {results[0]['profit_factor']:.2f}")
    print()
    print("Note: This is a simplified simulator using synthetic data.")
    print("For production use, run the actual optimization in MetaTrader 5")
    print("using the preset files provided in the MQL5/Presets/ directory.")

if __name__ == "__main__":
    main()