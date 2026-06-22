#!/usr/bin/env python3
"""
PASR Parameter Optimization System
===================================
Optimizes PASR_PRERELEASE.mq5 parameters for:
- Profit Factor (PF) >= 1.5
- Daily trading frequency
- Maximum drawdown control
- Overall profitability

Usage:
    python3 optimize_pasr_parameters.py --symbol EURUSD --timeframe H1 --months 12
"""

import subprocess
import json
import os
import sys
import argparse
from pathlib import Path
from datetime import datetime, timedelta
import pandas as pd
import numpy as np
from typing import Dict, List, Tuple, Any
import re

# Configuration
MT5_WINE_PREFIX = "/home/agus/.mt5"
MT5_TERMINAL = f"{MT5_WINE_PREFIX}/drive_c/Program Files/MetaTrader 5"
MT5_METAEDITOR = f"{MT5_TERMINAL}/MetaEditor64.exe"
MT5_TESTER = f"{MT5_TERMINAL}/metatester64.exe"
MQL5_PATH = f"{MT5_TERMINAL}/D0E8209F77C8CF37AD8BF550E51FF075/MQL5"
EA_PATH = f"{MQL5_PATH}/Experts/PASR_PRERELEASE.mq5"
OUTPUT_DIR = f"{MQL5_PATH}/tools/output"

# Parameter optimization ranges
PARAMETER_RANGES = {
    # Risk parameters
    'InpLotSize': [0.01, 0.02, 0.05, 0.1],
    'InpRiskPercent': [0.5, 1.0, 1.5, 2.0],
    'InpSLMultiplier': [1.0, 1.5, 2.0, 2.5],
    'InpTPMultiplier': [1.5, 2.0, 2.5, 3.0],
    'InpMaxDailyLossPct': [2.0, 3.0, 5.0],
    'InpMaxDrawdownPct': [5.0, 10.0, 15.0],
    'InpMaxOpenPositions': [1, 2, 3, 5],
    'InpMaxConsecLoss': [3, 5, 7],
    
    # Market parameters
    'InpATRPeriod': [7, 14, 21],
    'InpADXPeriod': [7, 14, 21],
    'InpADXTrendThreshold': [20.0, 25.0, 30.0],
    'InpSpreadFilterPips': [2.0, 3.0, 5.0],
    
    # Signal parameters
    'InpSignalLookback': [10, 20, 30],
    'InpMinConfluence': [1, 2, 3],
    'InpSignalMinScore': [0.3, 0.4, 0.5, 0.6],
    'InpMinRRRatio': [1.2, 1.5, 2.0],
    
    # Pattern parameters
    'InpMinPatternScore': [35.0, 45.0, 55.0],
    'InpPatternLookbackBars': [30, 50, 70],
    'InpPinBarRatio': [1.5, 2.0, 2.5],
    'InpEngulfMultiplier': [1.0, 1.1, 1.2],
    
    # AI parameters
    'InpAIMinConfidence': [0.5, 0.6, 0.7, 0.8],
    'InpAILearningRate': [0.0001, 0.0003, 0.001],
    'InpAITrainIntervalBars': [3, 5, 10],
}


class PASROptimizer:
    def __init__(self, symbol: str = "EURUSD", timeframe: str = "H1", 
                 months: int = 12, max_iterations: int = 50):
        self.symbol = symbol
        self.timeframe = timeframe
        self.months = months
        self.max_iterations = max_iterations
        self.results = []
        self.best_config = None
        self.iteration = 0
        
        # Create output directory
        Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)
    
    def generate_set_file(self, params: Dict[str, Any]) -> str:
        """Generate MT5 .set file with given parameters."""
        set_content = f"; PASR Optimization Set File\n"
        set_content += f"; Generated: {datetime.now().isoformat()}\n\n"
        
        for key, value in params.items():
            if isinstance(value, bool):
                value = 1 if value else 0
            set_content += f"{key}={value}\n"
        
        set_filename = f"{OUTPUT_DIR}/optimization_iter_{self.iteration}.set"
        with open(set_filename, 'w') as f:
            f.write(set_content)
        
        return set_filename
    
    def run_backtest(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Run MT5 backtest with given parameters."""
        self.iteration += 1
        print(f"\n{'='*60}")
        print(f"Iteration {self.iteration}/{self.max_iterations}")
        print(f"{'='*60}")
        
        # Generate set file
        set_file = self.generate_set_file(params)
        
        # Calculate date range
        end_date = datetime.now()
        start_date = end_date - timedelta(days=self.months * 30)
        
        # Build MT5 tester command
        cmd = [
            'wine', MT5_METAEDITOR,
            f'/compile:{EA_PATH}',
            f'/close'
        ]
        
        try:
            # Compile EA
            subprocess.run(cmd, check=True, capture_output=True, timeout=120)
            print(f"✓ EA compiled successfully")
        except subprocess.TimeoutExpired:
            print(f"✗ Compilation timeout")
            return self._failed_result(params)
        except subprocess.CalledProcessError as e:
            print(f"✗ Compilation failed: {e}")
            return self._failed_result(params)
        
        # Run backtest
        tester_cmd = f'''
        WINEPREFIX="{MT5_WINE_PREFIX}" wine "{MT5_TESTER}" \\
        /config:"{MT5_TERMINAL}/config/common.ini" \\
        /profile:Default \\
        /expert:"{EA_PATH}" \\
        /symbol:{self.symbol} \\
        /period:{self.timeframe} \\
        /deposit:10000 \\
        /currency:USD \\
        /leverage:100 \\
        /model:0 \\
        /spread:10 \\
        /optimization_mode:0 \\
        /set_file:"{set_file}" \\
        /tester:"{OUTPUT_DIR}/backtest_iter_{self.iteration}" \\
        /from:{start_date.strftime("%Y.%m.%d")} \\
        /to:{end_date.strftime("%Y.%m.%d")} \\
        /portable
        '''
        
        try:
            result = subprocess.run(
                tester_cmd, 
                shell=True, 
                capture_output=True, 
                timeout=600,
                cwd=MT5_TERMINAL
            )
            print(f"✓ Backtest completed")
        except subprocess.TimeoutExpired:
            print(f"✗ Backtest timeout")
            return self._failed_result(params)
        except subprocess.CalledProcessError as e:
            print(f"✗ Backtest failed: {e}")
            return self._failed_result(params)
        
        # Parse results
        return self._parse_backtest_results(params, OUTPUT_DIR, self.iteration)
    
    def _parse_backtest_results(self, params: Dict[str, Any], 
                               output_dir: str, iteration: int) -> Dict[str, Any]:
        """Parse MT5 backtest results."""
        result_file = f"{output_dir}/backtest_iter_{iteration}/report.htm"
        
        if not os.path.exists(result_file):
            print(f"✗ Result file not found: {result_file}")
            return self._failed_result(params)
        
        # Try to extract results from HTML report
        try:
            with open(result_file, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Extract key metrics using regex
            metrics = self._extract_metrics_from_html(content)
            
            if not metrics:
                print(f"✗ Could not extract metrics from report")
                return self._failed_result(params)
            
            # Calculate optimization score
            score = self._calculate_optimization_score(metrics)
            
            result = {
                'params': params,
                'metrics': metrics,
                'score': score,
                'iteration': iteration,
                'timestamp': datetime.now().isoformat()
            }
            
            # Print summary
            print(f"\nResults:")
            print(f"  Profit: ${metrics.get('profit', 0):.2f}")
            print(f"  Profit Factor: {metrics.get('profit_factor', 0):.2f}")
            print(f"  Recovery Factor: {metrics.get('recovery_factor', 0):.2f}")
            print(f"  Total Trades: {metrics.get('total_trades', 0)}")
            print(f"  Win Rate: {metrics.get('win_rate', 0):.1f}%")
            print(f"  Drawdown: {metrics.get('drawdown_pct', 0):.1f}%")
            print(f"  Daily Trades: {metrics.get('daily_trades', 0):.1f}")
            print(f"  Optimization Score: {score:.3f}")
            
            return result
            
        except Exception as e:
            print(f"✗ Error parsing results: {e}")
            return self._failed_result(params)
    
    def _extract_metrics_from_html(self, html_content: str) -> Dict[str, float]:
        """Extract metrics from MT5 HTML report."""
        metrics = {}
        
        # Common patterns in MT5 reports
        patterns = {
            'profit': r'Profit:\s*([-\d.]+)',
            'profit_factor': r'Profit Factor:\s*([\d.]+)',
            'recovery_factor': r'Recovery Factor:\s*([\d.]+)',
            'expected_payoff': r'Expected Payoff:\s*([-\d.]+)',
            'total_trades': r'Total trades:\s*(\d+)',
            'profit_trades': r'Profit trades:\s*(\d+)',
            'loss_trades': r'Loss trades:\s*(\d+)',
            'drawdown_pct': r'Equity DD %:\s*([\d.]+)',
            'sharpe_ratio': r'Sharpe Ratio:\s*([-\d.]+)'
        }
        
        for key, pattern in patterns.items():
            match = re.search(pattern, html_content)
            if match:
                try:
                    metrics[key] = float(match.group(1))
                except ValueError:
                    continue
        
        # Calculate derived metrics
        if 'total_trades' in metrics and metrics['total_trades'] > 0:
            if 'profit_trades' in metrics:
                metrics['win_rate'] = (metrics['profit_trades'] / metrics['total_trades']) * 100
            
            # Estimate daily trades (assuming 5 trading days per week)
            trading_days = self.months * 30 * 5 / 7  # approximate
            metrics['daily_trades'] = metrics['total_trades'] / trading_days if trading_days > 0 else 0
        
        return metrics
    
    def _calculate_optimization_score(self, metrics: Dict[str, float]) -> float:
        """Calculate optimization score based on user criteria."""
        score = 0.0
        
        # Profit Factor (target: >= 1.5)
        pf = metrics.get('profit_factor', 0)
        if pf >= 1.5:
            score += 10.0 * (pf / 1.5)  # Bonus for exceeding target
        elif pf > 0:
            score += 5.0 * (pf / 1.5)  # Partial credit
        else:
            score -= 20.0  # Heavy penalty for negative PF
        
        # Daily trading (target: >= 1 trade per day)
        daily_trades = metrics.get('daily_trades', 0)
        if daily_trades >= 1.0:
            score += 5.0 * min(daily_trades, 3.0)  # Cap bonus at 3 trades/day
        elif daily_trades > 0.5:
            score += 2.5
        else:
            score -= 5.0  # Penalty for insufficient trading
        
        # Total trades (minimum: 50)
        total_trades = metrics.get('total_trades', 0)
        if total_trades >= 50:
            score += 3.0
        elif total_trades >= 20:
            score += 1.5
        
        # Drawdown control (target: <= 15%)
        drawdown = metrics.get('drawdown_pct', 100)
        if drawdown <= 10:
            score += 5.0
        elif drawdown <= 15:
            score += 3.0
        elif drawdown <= 20:
            score += 1.0
        else:
            score -= 10.0  # Heavy penalty for high drawdown
        
        # Recovery Factor (target: >= 1.0)
        rf = metrics.get('recovery_factor', 0)
        if rf >= 1.0:
            score += 3.0 * (rf / 1.0)
        elif rf > 0:
            score += 1.5 * (rf / 1.0)
        
        # Win rate (target: >= 40%)
        win_rate = metrics.get('win_rate', 0)
        if win_rate >= 50:
            score += 3.0
        elif win_rate >= 40:
            score += 2.0
        elif win_rate >= 30:
            score += 1.0
        
        # Profit (target: positive)
        profit = metrics.get('profit', 0)
        if profit > 0:
            score += 2.0 * min(profit / 1000, 5.0)  # Cap bonus
        elif profit < -100:
            score -= 10.0  # Heavy penalty for significant losses
        
        return score
    
    def _failed_result(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Return failed result."""
        return {
            'params': params,
            'metrics': {},
            'score': -1000.0,
            'iteration': self.iteration,
            'timestamp': datetime.now().isoformat(),
            'error': True
        }
    
    def optimize(self) -> Dict[str, Any]:
        """Run optimization using grid search with smart sampling."""
        print(f"Starting PASR Parameter Optimization")
        print(f"Symbol: {self.symbol}, Timeframe: {self.timeframe}")
        print(f"Period: {self.months} months")
        print(f"Max iterations: {self.max_iterations}")
        print(f"Target: PF >= 1.5, Daily trading >= 1 trade/day")
        
        # Start with baseline configuration
        baseline_params = {
            'InpLotSize': 0.01,
            'InpRiskPercent': 1.0,
            'InpSLMultiplier': 1.5,
            'InpTPMultiplier': 2.5,
            'InpMaxDailyLossPct': 3.0,
            'InpMaxDrawdownPct': 10.0,
            'InpMaxOpenPositions': 3,
            'InpMaxConsecLoss': 5,
            'InpATRPeriod': 14,
            'InpADXPeriod': 14,
            'InpADXTrendThreshold': 25.0,
            'InpSpreadFilterPips': 3.0,
            'InpSignalLookback': 20,
            'InpMinConfluence': 1,
            'InpSignalMinScore': 0.40,
            'InpMinRRRatio': 1.5,
            'InpMinPatternScore': 45.0,
            'InpPatternLookbackBars': 50,
            'InpPinBarRatio': 2.0,
            'InpEngulfMultiplier': 1.1,
            'InpAIMinConfidence': 0.60,
            'InpAILearningRate': 0.0003,
            'InpAITrainIntervalBars': 5,
            'InpEnableAI': False,  # Start without AI
            'InpEnableGBR': False,  # Start without GBR
            'InpEnablePatterns': True,
            'InpUseMTF': True,
        }
        
        print(f"\n{'='*60}")
        print(f"Running baseline configuration...")
        print(f"{'='*60}")
        baseline_result = self.run_backtest(baseline_params)
        self.results.append(baseline_result)
        self.best_config = baseline_result
        
        # Smart sampling: focus on most impactful parameters
        key_parameters = [
            'InpSLMultiplier', 'InpTPMultiplier', 'InpSignalMinScore',
            'InpMinPatternScore', 'InpATRPeriod', 'InpADXPeriod',
            'InpMaxOpenPositions', 'InpRiskPercent'
        ]
        
        for iteration in range(self.max_iterations - 1):
            if iteration >= self.max_iterations - 1:
                break
            
            # Generate new parameters based on best result
            new_params = self._generate_next_params(self.best_config['params'], key_parameters)
            result = self.run_backtest(new_params)
            self.results.append(result)
            
            # Update best configuration
            if result['score'] > self.best_config['score']:
                self.best_config = result
                print(f"✓ New best configuration found! Score: {result['score']:.3f}")
            
            # Early termination if target reached
            if self._check_target_reached(result):
                print(f"\n✓ Target criteria reached!")
                break
        
        # Save results
        self._save_results()
        
        return self.best_config
    
    def _generate_next_params(self, current_params: Dict[str, Any], 
                            key_params: List[str]) -> Dict[str, Any]:
        """Generate next parameters based on current best."""
        new_params = current_params.copy()
        
        # Randomly select 2-3 key parameters to modify
        params_to_modify = np.random.choice(
            key_params, 
            size=np.random.randint(2, 4), 
            replace=False
        )
        
        for param in params_to_modify:
            if param in PARAMETER_RANGES:
                current_value = current_params.get(param)
                options = PARAMETER_RANGES[param]
                
                # Get current index and move to adjacent value
                try:
                    current_idx = options.index(current_value)
                    # Move to adjacent value (randomly up or down)
                    direction = np.random.choice([-1, 1])
                    new_idx = max(0, min(len(options) - 1, current_idx + direction))
                    new_params[param] = options[new_idx]
                except (ValueError, IndexError):
                    # If current value not in options, pick random
                    new_params[param] = np.random.choice(options)
        
        return new_params
    
    def _check_target_reached(self, result: Dict[str, Any]) -> bool:
        """Check if target criteria are reached."""
        metrics = result.get('metrics', {})
        
        pf = metrics.get('profit_factor', 0)
        daily_trades = metrics.get('daily_trades', 0)
        drawdown = metrics.get('drawdown_pct', 100)
        
        # Target: PF >= 1.5, Daily trades >= 1, Drawdown <= 15%
        return (pf >= 1.5 and daily_trades >= 1.0 and drawdown <= 15.0)
    
    def _save_results(self):
        """Save optimization results to file."""
        results_file = f"{OUTPUT_DIR}/optimization_results.json"
        
        with open(results_file, 'w') as f:
            json.dump({
                'best_config': self.best_config,
                'all_results': self.results,
                'symbol': self.symbol,
                'timeframe': self.timeframe,
                'months': self.months,
                'timestamp': datetime.now().isoformat()
            }, f, indent=2)
        
        print(f"\n✓ Results saved to {results_file}")
        
        # Generate summary report
        self._generate_summary_report()
    
    def _generate_summary_report(self):
        """Generate human-readable summary report."""
        report_file = f"{OUTPUT_DIR}/optimization_summary.txt"
        
        with open(report_file, 'w') as f:
            f.write("="*70 + "\n")
            f.write("PASR PARAMETER OPTIMIZATION SUMMARY\n")
            f.write("="*70 + "\n\n")
            
            f.write(f"Symbol: {self.symbol}\n")
            f.write(f"Timeframe: {self.timeframe}\n")
            f.write(f"Optimization Period: {self.months} months\n")
            f.write(f"Iterations: {self.iteration}\n")
            f.write(f"Timestamp: {datetime.now().isoformat()}\n\n")
            
            if self.best_config and not self.best_config.get('error'):
                f.write("BEST CONFIGURATION:\n")
                f.write("-"*70 + "\n")
                for key, value in self.best_config['params'].items():
                    f.write(f"  {key}: {value}\n")
                
                f.write("\nBEST METRICS:\n")
                f.write("-"*70 + "\n")
                metrics = self.best_config.get('metrics', {})
                for key, value in metrics.items():
                    f.write(f"  {key}: {value}\n")
                
                f.write(f"\nOPTIMIZATION SCORE: {self.best_config['score']:.3f}\n")
                
                # Check if target reached
                target_reached = self._check_target_reached(self.best_config)
                f.write(f"\nTARGET REACHED: {'YES' if target_reached else 'NO'}\n")
                f.write(f"  - Profit Factor >= 1.5: {'YES' if metrics.get('profit_factor', 0) >= 1.5 else 'NO'}\n")
                f.write(f"  - Daily Trades >= 1: {'YES' if metrics.get('daily_trades', 0) >= 1.0 else 'NO'}\n")
                f.write(f"  - Drawdown <= 15%: {'YES' if metrics.get('drawdown_pct', 100) <= 15.0 else 'NO'}\n")
            else:
                f.write("No valid configuration found.\n")
            
            f.write("\n" + "="*70 + "\n")
        
        print(f"✓ Summary report saved to {report_file}")


def main():
    parser = argparse.ArgumentParser(
        description="Optimize PASR_PRERELEASE.mq5 parameters for profitable trading"
    )
    parser.add_argument("--symbol", default="EURUSD",
                        help="Trading symbol (default: EURUSD)")
    parser.add_argument("--timeframe", default="H1",
                        help="Timeframe (default: H1)")
    parser.add_argument("--months", type=int, default=12,
                        help="Optimization period in months (default: 12)")
    parser.add_argument("--max-iterations", type=int, default=50,
                        help="Maximum optimization iterations (default: 50)")
    
    args = parser.parse_args()
    
    optimizer = PASROptimizer(
        symbol=args.symbol,
        timeframe=args.timeframe,
        months=args.months,
        max_iterations=args.max_iterations
    )
    
    try:
        best_config = optimizer.optimize()
        
        print(f"\n{'='*70}")
        print("OPTIMIZATION COMPLETED")
        print(f"{'='*70}")
        
        if best_config and not best_config.get('error'):
            print(f"Best score: {best_config['score']:.3f}")
            print(f"Results saved to: {OUTPUT_DIR}")
        else:
            print("No valid configuration found. Check logs for details.")
        
    except KeyboardInterrupt:
        print("\nOptimization interrupted by user")
        optimizer._save_results()
    except Exception as e:
        print(f"\nError during optimization: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
