#!/usr/bin/env python3
"""
PASR_MODULAR AI Training Data Preprocessor
Preprocesses and validates training data for AI model training
"""

import pandas as pd
import numpy as np
import json
import os
import sys
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional

class AITrainingDataPreprocessor:
    """Preprocesses AI training data for PASR_MODULAR"""
    
    def __init__(self, config_file: str = None):
        self.config = self.load_config(config_file)
        self.feature_dim = 34
        self.expected_columns = 44  # 34 features + 10 metadata
        
    def load_config(self, config_file: str) -> Dict:
        """Load configuration from file or use defaults"""
        default_config = {
            "input_file": "AI_Training_Data_Template.csv",
            "output_file": "AI_Training_Data_Processed.csv",
            "validation_file": "AI_Training_Data_Validation.json",
            "feature_ranges": {
                "min": 0.0,
                "max": 1.0
            },
            "label_values": [-1.0, 0.0, 1.0],
            "weight_range": [0.1, 2.0],
            "min_samples": 500,
            "balance_ratio": 0.4  # Minimum 40% of each class
        }
        
        if config_file and os.path.exists(config_file):
            try:
                with open(config_file, 'r') as f:
                    user_config = json.load(f)
                default_config.update(user_config)
            except Exception as e:
                print(f"Warning: Could not load config file: {e}")
                print("Using default configuration")
        
        return default_config
    
    def load_data(self, input_file: str = None) -> pd.DataFrame:
        """Load training data from CSV file"""
        file_path = input_file or self.config["input_file"]
        
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"Input file not found: {file_path}")
        
        print(f"Loading data from {file_path}...")
        
        try:
            # Read CSV, skipping comment lines starting with #
            df = pd.read_csv(file_path, comment='#')
            
            if len(df) == 0:
                raise ValueError("No data found in file")
            
            print(f"Loaded {len(df)} rows")
            return df
            
        except Exception as e:
            raise ValueError(f"Error loading CSV file: {e}")
    
    def validate_structure(self, df: pd.DataFrame) -> Tuple[bool, List[str]]:
        """Validate data structure and column count"""
        errors = []
        
        # Check column count
        if len(df.columns) != self.expected_columns:
            errors.append(f"Expected {self.expected_columns} columns, found {len(df.columns)}")
        
        # Check for missing column names
        expected_feature_cols = [f'f{i}' for i in range(self.feature_dim)]
        expected_meta_cols = ['timestamp', 'symbol', 'timeframe', 'label', 'weight', 
                              'regime', 'trade_type', 'profit_pips', 'duration_bars', 'notes']
        expected_cols = expected_feature_cols + expected_meta_cols
        
        missing_cols = set(expected_cols) - set(df.columns)
        if missing_cols:
            errors.append(f"Missing columns: {missing_cols}")
        
        return len(errors) == 0, errors
    
    def validate_features(self, df: pd.DataFrame) -> Tuple[bool, Dict]:
        """Validate feature values and ranges"""
        validation_results = {
            "valid": True,
            "errors": [],
            "warnings": [],
            "feature_stats": {}
        }
        
        feature_cols = [f'f{i}' for i in range(self.feature_dim)]
        
        for col in feature_cols:
            if col not in df.columns:
                validation_results["errors"].append(f"Feature column {col} missing")
                validation_results["valid"] = False
                continue
            
            # Convert to numeric, coerce errors to NaN
            series = pd.to_numeric(df[col], errors='coerce')
            
            # Check for NaN values
            nan_count = series.isna().sum()
            if nan_count > 0:
                validation_results["warnings"].append(
                    f"{col}: {nan_count} NaN values found")
                # Fill NaN with 0.5 (neutral)
                df[col] = series.fillna(0.5)
            else:
                df[col] = series
            
            # Check range
            min_val = df[col].min()
            max_val = df[col].max()
            
            validation_results["feature_stats"][col] = {
                "min": float(min_val),
                "max": float(max_val),
                "mean": float(df[col].mean()),
                "std": float(df[col].std())
            }
            
            # Warn if values are outside expected range (but allow some flexibility)
            if min_val < -0.1 or max_val > 1.1:
                validation_results["warnings"].append(
                    f"{col}: Values outside expected range [0,1]: min={min_val:.3f}, max={max_val:.3f}")
        
        return validation_results["valid"], validation_results
    
    def validate_labels(self, df: pd.DataFrame) -> Tuple[bool, Dict]:
        """Validate label values and distribution"""
        validation_results = {
            "valid": True,
            "errors": [],
            "warnings": [],
            "distribution": {}
        }
        
        if 'label' not in df.columns:
            validation_results["errors"].append("Label column missing")
            return False, validation_results
        
        # Convert to numeric
        df['label'] = pd.to_numeric(df['label'], errors='coerce')
        
        # Check for valid label values
        valid_labels = set(self.config["label_values"])
        unique_labels = set(df['label'].dropna().unique())
        invalid_labels = unique_labels - valid_labels
        
        if invalid_labels:
            validation_results["errors"].append(
                f"Invalid label values found: {invalid_labels}. Valid values: {valid_labels}")
            validation_results["valid"] = False
        
        # Check label distribution
        label_counts = df['label'].value_counts()
        validation_results["distribution"] = {
            str(label): int(count) for label, count in label_counts.items()
        }
        
        total_samples = len(df)
        for label, count in label_counts.items():
            percentage = (count / total_samples) * 100
            validation_results["distribution"][f"{label}_pct"] = round(percentage, 2)
            
            # Check for class imbalance
            if percentage < (self.config["balance_ratio"] * 100):
                validation_results["warnings"].append(
                    f"Label {label}: Underrepresented ({percentage:.1f}% < {self.config['balance_ratio']*100}%)")
        
        return validation_results["valid"], validation_results
    
    def validate_weights(self, df: pd.DataFrame) -> Tuple[bool, Dict]:
        """Validate weight values"""
        validation_results = {
            "valid": True,
            "errors": [],
            "warnings": [],
            "stats": {}
        }
        
        if 'weight' not in df.columns:
            validation_results["warnings"].append("Weight column missing, using default weight 1.0")
            df['weight'] = 1.0
            return True, validation_results
        
        # Convert to numeric
        df['weight'] = pd.to_numeric(df['weight'], errors='coerce')
        
        # Check range
        min_weight = df['weight'].min()
        max_weight = df['weight'].max()
        weight_range = self.config["weight_range"]
        
        validation_results["stats"] = {
            "min": float(min_weight),
            "max": float(max_weight),
            "mean": float(df['weight'].mean())
        }
        
        # Clamp weights to valid range
        df['weight'] = df['weight'].clip(weight_range[0], weight_range[1])
        
        if min_weight < weight_range[0] or max_weight > weight_range[1]:
            clamped_count = ((df['weight'] < weight_range[0]) | (df['weight'] > weight_range[1])).sum()
            validation_results["warnings"].append(
                f"{clamped_count} weights clamped to range [{weight_range[0]}, {weight_range[1]}]")
        
        return validation_results["valid"], validation_results
    
    def normalize_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Normalize features to [0,1] range if needed"""
        feature_cols = [f'f{i}' for i in range(self.feature_dim)]
        
        for col in feature_cols:
            if col in df.columns:
                # Min-max normalization
                min_val = df[col].min()
                max_val = df[col].max()
                
                if max_val > min_val:
                    df[col] = (df[col] - min_val) / (max_val - min_val)
                else:
                    df[col] = 0.5  # All values same, set to neutral
        
        return df
    
    def balance_dataset(self, df: pd.DataFrame) -> pd.DataFrame:
        """Balance dataset by undersampling majority class"""
        if 'label' not in df.columns:
            return df
        
        label_counts = df['label'].value_counts()
        min_count = label_counts.min()
        
        # Only balance if severe imbalance
        max_count = label_counts.max()
        if max_count / min_count < 3.0:  # Less than 3:1 ratio
            print("Dataset is reasonably balanced, skipping balancing")
            return df
        
        print(f"Balancing dataset: max_count={max_count}, min_count={min_count}")
        
        balanced_dfs = []
        for label in label_counts.index:
            label_df = df[df['label'] == label]
            if len(label_df) > min_count:
                # Undersample
                balanced_df = label_df.sample(n=min_count, random_state=42)
            else:
                balanced_df = label_df
            balanced_dfs.append(balanced_df)
        
        balanced_df = pd.concat(balanced_dfs, ignore_index=True)
        print(f"Balanced dataset size: {len(balanced_df)}")
        
        return balanced_df
    
    def remove_duplicates(self, df: pd.DataFrame) -> pd.DataFrame:
        """Remove duplicate samples"""
        feature_cols = [f'f{i}' for i in range(self.feature_dim)]
        
        initial_count = len(df)
        df = df.drop_duplicates(subset=feature_cols, keep='first')
        removed_count = initial_count - len(df)
        
        if removed_count > 0:
            print(f"Removed {removed_count} duplicate samples")
        
        return df
    
    def shuffle_data(self, df: pd.DataFrame) -> pd.DataFrame:
        """Shuffle dataset randomly"""
        df = df.sample(frac=1, random_state=42).reset_index(drop=True)
        return df
    
    def save_processed_data(self, df: pd.DataFrame, output_file: str = None):
        """Save processed data to CSV"""
        file_path = output_file or self.config["output_file"]
        
        print(f"Saving processed data to {file_path}...")
        df.to_csv(file_path, index=False)
        print(f"Saved {len(df)} processed samples")
    
    def save_validation_report(self, validation_results: Dict, output_file: str = None):
        """Save validation report to JSON"""
        file_path = output_file or self.config["validation_file"]
        
        report = {
            "timestamp": datetime.now().isoformat(),
            "validation_results": validation_results,
            "config": self.config
        }
        
        with open(file_path, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"Validation report saved to {file_path}")
    
    def preprocess(self, input_file: str = None, output_file: str = None) -> pd.DataFrame:
        """Main preprocessing pipeline"""
        print("=" * 50)
        print("PASR_MODULAR AI Training Data Preprocessing")
        print("=" * 50)
        
        try:
            # Load data
            df = self.load_data(input_file)
            
            # Validate structure
            print("\n1. Validating data structure...")
            structure_valid, structure_errors = self.validate_structure(df)
            if not structure_valid:
                print("ERROR: Structure validation failed")
                for error in structure_errors:
                    print(f"  - {error}")
                return None
            
            print("   ✓ Structure validation passed")
            
            # Validate features
            print("\n2. Validating feature values...")
            features_valid, features_results = self.validate_features(df)
            
            if features_results["warnings"]:
                print(f"   ⚠ {len(features_results['warnings'])} warnings:")
                for warning in features_results["warnings"]:
                    print(f"     - {warning}")
            
            if not features_valid:
                print("   ✗ Feature validation failed")
                return None
            
            print("   ✓ Feature validation passed")
            
            # Validate labels
            print("\n3. Validating labels...")
            labels_valid, labels_results = self.validate_labels(df)
            
            if labels_results["warnings"]:
                print(f"   ⚠ {len(labels_results['warnings'])} warnings:")
                for warning in labels_results["warnings"]:
                    print(f"     - {warning}")
            
            print(f"   Label distribution: {labels_results['distribution']}")
            
            if not labels_valid:
                print("   ✗ Label validation failed")
                return None
            
            print("   ✓ Label validation passed")
            
            # Validate weights
            print("\n4. Validating weights...")
            weights_valid, weights_results = self.validate_weights(df)
            
            if weights_results["warnings"]:
                print(f"   ⚠ {len(weights_results['warnings'])} warnings:")
                for warning in weights_results["warnings"]:
                    print(f"     - {warning}")
            
            print("   ✓ Weight validation passed")
            
            # Check minimum samples
            print(f"\n5. Checking sample count...")
            if len(df) < self.config["min_samples"]:
                print(f"   ⚠ Warning: Only {len(df)} samples (minimum {self.config['min_samples']} recommended)")
            else:
                print(f"   ✓ Sufficient samples: {len(df)}")
            
            # Preprocessing steps
            print("\n6. Preprocessing data...")
            
            # Remove duplicates
            df = self.remove_duplicates(df)
            
            # Normalize features
            df = self.normalize_features(df)
            print("   ✓ Features normalized")
            
            # Balance dataset
            df = self.balance_dataset(df)
            
            # Shuffle data
            df = self.shuffle_data(df)
            print("   ✓ Data shuffled")
            
            # Save processed data
            self.save_processed_data(df, output_file)
            
            # Save validation report
            all_validation = {
                "structure": {"valid": structure_valid, "errors": structure_errors},
                "features": features_results,
                "labels": labels_results,
                "weights": weights_results
            }
            self.save_validation_report(all_validation)
            
            print("\n" + "=" * 50)
            print("✓ Preprocessing completed successfully!")
            print(f"Final dataset size: {len(df)} samples")
            print("=" * 50)
            
            return df
            
        except Exception as e:
            print(f"\n✗ ERROR during preprocessing: {e}")
            import traceback
            traceback.print_exc()
            return None

def main():
    """Main execution function"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Preprocess AI training data for PASR_MODULAR')
    parser.add_argument('--input', '-i', help='Input CSV file', default='AI_Training_Data_Template.csv')
    parser.add_argument('--output', '-o', help='Output CSV file', default='AI_Training_Data_Processed.csv')
    parser.add_argument('--config', '-c', help='Configuration file', default='ai_training_config.json')
    
    args = parser.parse_args()
    
    # Run preprocessor
    preprocessor = AITrainingDataPreprocessor(args.config)
    processed_df = preprocessor.preprocess(args.input, args.output)
    
    if processed_df is not None:
        print("\n✓ Success! Processed data ready for AI training.")
        return 0
    else:
        print("\n✗ Preprocessing failed.")
        return 1

if __name__ == "__main__":
    sys.exit(main())