#!/bin/bash
# PASR Framework - Automated Include Path Refactoring Script
# This script updates all #include directives to match the new folder structure

echo "🔧 PASR Framework - Include Path Refactoring Tool"
echo "=================================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counter for changes
CHANGES=0

# Function to update includes in a file
update_includes() {
    local file=$1
    local from_pattern=$2
    local to_pattern=$3
    
    if grep -q "$from_pattern" "$file" 2>/dev/null; then
        sed -i "s|$from_pattern|$to_pattern|g" "$file"
        echo -e "${GREEN}✓${NC} Updated: $file"
        ((CHANGES++))
    fi
}

echo "📁 Updating Core/ files..."
# Update Core/0.EventBus.mqh
update_includes "Core/0.EventBus.mqh" '#include "PASR.Optimizations.mqh"' '#include "../Optimizations/PASR.Optimizations.mqh"'

# Update Core/1.Events.mqh
update_includes "Core/1.Events.mqh" '#include "0.EventBus.mqh"' '#include "0.EventBus.mqh"'
update_includes "Core/1.Events.mqh" '#include "2.Config.Types.mqh"' '#include "2.Config.Types.mqh"'

echo ""
echo "📁 Updating Data/ files..."
for file in Data/*.mqh; do
    [ -f "$file" ] || continue
    update_includes "$file" '#include "IManager.mqh"' '#include "../Core/IManager.mqh"'
    update_includes "$file" '#include "10.DataManager.mqh"' '#include "../Infrastructure/10.DataManager.mqh"'
    update_includes "$file" '#include "4.SRManager.mqh"' '#include "4.SRManager.mqh"'
done

echo ""
echo "📁 Updating Strategy/ files..."
for file in Strategy/*.mqh; do
    [ -f "$file" ] || continue
    update_includes "$file" '#include "IManager.mqh"' '#include "../Core/IManager.mqh"'
    update_includes "$file" '#include "10.DataManager.mqh"' '#include "../Infrastructure/10.DataManager.mqh"'
    update_includes "$file" '#include "4.SRManager.mqh"' '#include "../Data/4.SRManager.mqh"'
    update_includes "$file" '#include "12.MarketRegime.mqh"' '#include "../Infrastructure/12.MarketRegime.mqh"'
done

echo ""
echo "📁 Updating Strategy/AI/ files..."
for file in Strategy/AI/*.mqh; do
    [ -f "$file" ] || continue
    update_includes "$file" '#include "' '#include "../'
done

echo ""
echo "📁 Updating Infrastructure/ files..."
for file in Infrastructure/*.mqh; do
    [ -f "$file" ] || continue
    update_includes "$file" '#include "IManager.mqh"' '#include "../Core/IManager.mqh"'
    update_includes "$file" '#include "10.DataManager.mqh"' '#include "10.DataManager.mqh"'
    update_includes "$file" '#include "2.Config.Types.mqh"' '#include "../Core/2.Config.Types.mqh"'
    update_includes "$file" '#include "2.Config.Manager.mqh"' '#include "../Core/2.Config.Manager.mqh"'
    update_includes "$file" '#include "9.PatternManager.mqh"' '#include "9.PatternManager.mqh"'
    update_includes "$file" '#include "12.MarketRegime.mqh"' '#include "12.MarketRegime.mqh"'
done

echo ""
echo "📁 Updating Optimizations/ files..."
for file in Optimizations/*.mqh; do
    [ -f "$file" ] || continue
    update_includes "$file" '#include "0.EventBus.mqh"' '#include "../Core/0.EventBus.mqh"'
done

echo ""
echo "📁 Updating Testing/ files..."
for file in Testing/*.mqh; do
    [ -f "$file" ] || continue
    update_includes "$file" '#include "' '#include "../Core/'
done

echo ""
echo "=================================================="
if [ $CHANGES -gt 0 ]; then
    echo -e "${GREEN}✅ Completed! $CHANGES files updated.${NC}"
else
    echo -e "${YELLOW}⚠️  No changes needed or files not found.${NC}"
fi
echo ""
echo "📋 Next steps:"
echo "   1. Review changes with: git diff"
echo "   2. Test compilation in MetaEditor"
echo "   3. Run unit tests: Testing/PASR.Test.mqh"
echo "   4. Run audit: Testing/PASR.Audit.mqh"
