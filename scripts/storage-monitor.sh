#!/bin/bash
# Storage monitoring script for pgGit tiered storage

echo "📊 Storage Tier Usage Report"
echo "============================"

# Check hot storage
HOT_USAGE=$(du -sh /var/lib/postgresql/storage/hot 2>/dev/null | cut -f1 || echo "0")
echo "🔥 HOT Storage: $HOT_USAGE / $PGGIT_HOT_STORAGE_LIMIT"

# Check warm storage  
WARM_USAGE=$(du -sh /var/lib/postgresql/storage/warm 2>/dev/null | cut -f1 || echo "0")
echo "☁️  WARM Storage: $WARM_USAGE / $PGGIT_WARM_STORAGE_LIMIT"

# Check cold storage
COLD_USAGE=$(du -sh /var/lib/postgresql/storage/cold 2>/dev/null | cut -f1 || echo "0")
echo "🧊 COLD Storage: $COLD_USAGE (unlimited)"

# Database statistics
psql -U postgres -d storage_test -t << EOF
SELECT '
📈 Database Statistics:
  Total Objects: ' || COUNT(*) || '
  Hot Tier: ' || SUM(CASE WHEN current_tier = 'HOT' THEN 1 ELSE 0 END) || ' objects
  Warm Tier: ' || SUM(CASE WHEN current_tier = 'WARM' THEN 1 ELSE 0 END) || ' objects
  Cold Tier: ' || SUM(CASE WHEN current_tier = 'COLD' THEN 1 ELSE 0 END) || ' objects
  Dedup Ratio: ' || COALESCE(ROUND(AVG(original_size_bytes::DECIMAL / NULLIF(deduplicated_size_bytes, 0)), 2), 0) || 'x'
FROM pggit.storage_objects;
EOF

# Performance metrics
echo ""
echo "⚡ Performance Metrics:"
psql -U postgres -d storage_test -t << EOF
SELECT '  Avg Hot Retrieval: ' || COALESCE(ROUND(AVG(response_time_ms), 2), 0) || 'ms' 
FROM pggit.access_patterns 
WHERE object_name IN (
    SELECT object_name FROM pggit.storage_objects WHERE current_tier = 'HOT'
);
EOF