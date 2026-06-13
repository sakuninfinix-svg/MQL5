#!/usr/bin/env python3
"""
PASR_MODULAR Optimization Manager
Automates systematic parameter optimization for MetaTrader 5 EA
"""

import os
import sys
import subprocess
import json
import time
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import List, Dict, Any

@dataclass
class MT5Config:
    """MetaTrader 5 Configuration"""
    terminal_path: str
    tester_path: str
    data_dir: str
    ea_path: str
    symbol: str = "EURUSD"
    timeframe: str = "H1"
    deposit: int = 10000
    currency: str = "USD"
    leverage: int = 100
    model: int = 0  # 0=Every tick, 1=Control points, 2=Open prices
    spread: int = 10
    optimization_mode: int = 2  # 0=Disabled, 1=Full, 2=Genetic
    optimization_criteria: int = 0  # 0=Custom max, 1=Custom max, etc.

@dataclass 
class TestResult:
    """Backtest Result Structure"""
    parameters: Dict[str, Any]
    profit: float
    profit_factor: float
    recovery_factor: float
    expected_payoff: float
    sharpe_ratio: float
    equity_dd_percent: float
    trades: int
    fitness_score: float
    timestamp: str

class PASROptimizationManager:
    """Manages PASR EA optimization process"""
    
    def __init__(self, mt5_config: MT5Config):
        self.config = mt5_config
        self.results: List[TestResult] = []
        self.presets_dir = Path(self.config.data_dir) / "MQL5" / "Presets"
        
    def validate_environment(self) -> bool:
        """Validate MT5 environment and files"""
        required_files = [
            self.config.terminal_path,
            self.config.tester_path, 
            self.config.ea_path,
            str(self.presets_dir)
        ]
        
        for file_path in required_files:
            if not Path(file_path).exists():
                print(f"❌ Missing required file/directory: {file_path}")
                return False
        return True
    
    def generate_test_command(self, preset_file: str, output_dir: str) -> List[str]:
        """Generate MT5 tester command line"""
        cmd = [
            "wine",
            self.config.tester_path,
            f"/config:{self.config.data_dir}/config/common.ini",
            f"/profile:Default",
            f"/expert:{self.config.ea_path}",
            f"/symbol:{self.config.symbol}",
            f"/period:{self.config.timeframe}",
            f"/deposit:{self.config.deposit}",
            f"/currency:{self.config.currency}",
            f"/leverage:{self.config.leverage}",
            f"/model:{self.config.model}",
            f"/spread:{self.config.spread}",
            f"/optimization_mode:{self.config.optimization_mode}",
            f"/optimization_criteria:{self.config.optimization_criteria}",
            f"/set_file:{preset_file}",
            f"/tester:{output_dir}",
            f"/portable"
        ]
        return cmd
    
    def run_baseline_test(self) -> TestResult:
        """Run baseline test with default parameters"""
        print("🔄 Running baseline test...")
        
        preset_file = self.presets_dir / "PASR_EPIC_MASTER.set"
        output_dir = Path(self.config.data_dir) / "Tester" / "Baseline"
        output_dir.mkdir(parents=True, exist_ok=True)
        
        cmd = self.generate_test_command(str(preset_file), str(output_dir))
        
        try:
            # Run the test
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=3600  # 1 hour timeout
            )
            
            print(f"✅ Baseline test completed")
            print(f"📊 Output: {result.stdout[:500]}")
            
            # Parse results (this would need actual MT5 result parsing)
            # For now, return a placeholder
            return TestResult(
                parameters={},
                profit=0.0,
                profit_factor=0.0,
                recovery_factor=0.0,
                expected_payoff=0.0,
                sharpe_ratio=0.0,
                equity_dd_percent=0.0,
                trades=0,
                fitness_score=0.0,
                timestamp=time.strftime("%Y-%m-%d %H:%M:%S")
            )
            
        except subprocess.TimeoutExpired:
            print("⏱️ Test timed out")
            return None
        except Exception as e:
            print(f"❌ Test failed: {e}")
            return None
    
    def run_optimization_phase(self, phase_name: str, preset_file: str):
        """Run specific optimization phase"""
        print(f"🚀 Starting {phase_name} optimization phase...")
        
        output_dir = Path(self.config.data_dir) / "Tester" / phase_name
        output_dir.mkdir(parents=True, exist_ok=True)
        
        cmd = self.generate_test_command(str(preset_file), str(output_dir))
        
        # For optimization, we would set different modes
        cmd.extend([
            f"/optimization_mode:2",  # Genetic optimization
            f"/forward:false"
        ])
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=7200  # 2 hour timeout for optimization
            )
            
            print(f"✅ {phase_name} optimization completed")
            
        except subprocess.TimeoutExpired:
            print(f"⏱️ {phase_name} optimization timed out")
        except Exception as e:
            print(f"❌ {phase_name} optimization failed: {e}")
    
    def parse_mt5_results(self, results_dir: str) -> List[TestResult]:
        """Parse MT5 backtest results from files"""
        # This would need to parse MT5 result files (HTML/XML)
        # Placeholder for actual implementation
        return []
    
    def compare_results(self, results: List[TestResult]) -> TestResult:
        """Find best result from optimization"""
        if not results:
            return None
            
        best = max(results, key=lambda x: x.fitness_score)
        return best
    
    def generate_optimization_report(self, best_result: TestResult):
        """Generate optimization report"""
        report = {
            "optimization_summary": {
                "total_tests": len(self.results),
                "best_fitness": best_result.fitness_score if best_result else 0,
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
            },
            "best_parameters": best_result.parameters if best_result else {},
            "performance_metrics": {
                "profit": best_result.profit if best_result else 0,
                "profit_factor": best_result.profit_factor if best_result else 0,
                "recovery_factor": best_result.recovery_factor if best_result else 0,
                "sharpe_ratio": best_result.sharpe_ratio if best_result else 0,
                "drawdown": best_result.equity_dd_percent if best_result else 0,
                "trades": best_result.trades if best_result else 0
            }
        }
        
        report_file = Path(self.config.data_dir) / "MQL5" / "tools" / "optimization_report.json"
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"📋 Optimization report saved to {report_file}")
        return report

def main():
    """Main execution function"""
    
    # MT5 Configuration (detect paths from script location)
    script_dir = Path(__file__).resolve().parent
    mql5_dir = script_dir.parent
    data_dir = mql5_dir.parent
    mt5_config = MT5Config(
        terminal_path=str(Path.home() / ".mt5/drive_c/Program Files/MetaTrader 5/terminal64.exe"),
        tester_path=str(Path.home() / ".mt5/drive_c/Program Files/MetaTrader 5/metatester64.exe"),
        data_dir=str(data_dir),
        ea_path=str(mql5_dir / "Experts/PASR_MODULAR.mq5"),
        symbol="EURUSD",
        timeframe="H1",
        deposit=10000,
        model=0  # Every tick
    )
    
    # Initialize optimization manager
    manager = PASROptimizationManager(mt5_config)
    
    # Validate environment
    if not manager.validate_environment():
        print("❌ Environment validation failed")
        sys.exit(1)
    
    print("✅ Environment validated successfully")
    
    # Run baseline test
    baseline_result = manager.run_baseline_test()
    if baseline_result:
        manager.results.append(baseline_result)
    
    # Run optimization phases
    optimization_phases = [
        ("Risk_Optimization", "PASR_EPIC_MASTER.set"),
        ("Market_Optimization", "PASR_EPIC_MASTER.set"),
        ("Pattern_Optimization", "PASR_EPIC_MASTER.set")
    ]
    
    for phase_name, preset_file in optimization_phases:
        preset_path = manager.presets_dir / preset_file
        if preset_path.exists():
            manager.run_optimization_phase(phase_name, str(preset_path))
        else:
            print(f"⚠️ Preset file not found: {preset_path}")
    
    # Parse and compare results
    all_results = manager.parse_mt5_results(str(mt5_config.data_dir) + "/Tester")
    best_result = manager.compare_results(all_results)
    
    # Generate final report
    report = manager.generate_optimization_report(best_result)
    
    print("🎉 Optimization process completed!")
    print(f"📊 Best fitness score: {best_result.fitness_score if best_result else 'N/A'}")

if __name__ == "__main__":
    main()