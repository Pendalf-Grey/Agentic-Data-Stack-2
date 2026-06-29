# Data Flow

## Components

- LibreChat: user UI.
- Existing MCP ClickHouse: safe ClickHouse access for the LLM.
- Existing MCP Grafana: dashboard creation.
- ClickHouse 26.6: raw logs, compressed batches, MapReduce materialization, final analytical SQL.
- Executable UDF: wraps `tools/log_compressor.py` inside ClickHouse as `log_compress_json`.
- ClickHouse AI functions: `aiGenerate` calls Map and Reduce LLMs from SQL.
- Grafana: dashboards from ClickHouse result SQL.

## Flow

1. Raw synthetic Elasticsearch logs stay on the Mac as `LOGS_FILE`.
2. `tools/import_raw_logs.sh` streams the file into `analytics.es_raw_logs`.
3. ClickHouse groups raw rows into bounded batches.
4. `log_compress_json` compresses each batch and stores it in `analytics.es_log_compressed_batches`.
5. `sql/20_map_ai.sql` sends compressed batches to Map-LLM through ClickHouse AI functions.
6. Map outputs are stored in `analytics.llm_map_results`.
7. `sql/30_reduce_ai.sql` reduces Map outputs by groups and stores intermediate summaries.
8. `sql/40_final_reduce_sql.sql` produces a final JSON with `refined_sql` and dashboard hints.
9. LibreChat reads the stored results through existing ClickHouse MCP.
10. LibreChat executes the final SQL through ClickHouse MCP.
11. If the user asks for a dashboard, LibreChat uses existing Grafana MCP.

## Safety Rules

- Grafana must not call AI functions directly.
- LibreChat must not send raw 10 GB logs to the LLM.
- Map SQL is intentionally limited per run.
- Every expensive LLM call is materialized into ClickHouse tables.
- Raw logs remain queryable by `document_id`, time, source, and index.

