-- Simplified UAT Testing: Focus on working functions
-- Test the functions that should work with current setup

\echo '=== Testing Working pggit_v0 Functions ==='

-- Test analytics functions (should work)
\echo '\n1. Testing analyze_storage_usage()...'
SELECT * FROM pggit_v0.analyze_storage_usage();

\echo '\n2. Testing get_object_size_distribution()...'
SELECT * FROM pggit_v0.get_object_size_distribution();

\echo '\n3. Testing analyze_query_performance()...'
SELECT * FROM pggit_v0.analyze_query_performance();

\echo '\n4. Testing validate_data_integrity()...'
SELECT * FROM pggit_v0.validate_data_integrity();

\echo '\n5. Testing detect_anomalies()...'
SELECT * FROM pggit_v0.detect_anomalies();

\echo '\n6. Testing estimate_storage_growth()...'
SELECT * FROM pggit_v0.estimate_storage_growth();

\echo '\n7. Testing benchmark_extraction_functions()...'
SELECT * FROM pggit_v0.benchmark_extraction_functions();

-- Test monitoring functions (some may work)
\echo '\n8. Testing check_for_alerts()...'
SELECT * FROM pggit_v0.check_for_alerts();

\echo '\n9. Testing get_recommendations()...'
SELECT * FROM pggit_v0.get_recommendations();

\echo '\n10. Testing get_dashboard_summary()...'
SELECT * FROM pggit_v0.get_dashboard_summary();

\echo '\n11. Testing generate_monitoring_report()...'
SELECT * FROM pggit_v0.generate_monitoring_report();

\echo '\n=== Analytics & Monitoring Functions Test Complete ==='