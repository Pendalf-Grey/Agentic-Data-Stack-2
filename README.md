# ADS-2 Elasticsearch Log MapReduce

Минимальный проект под задачу:

`Elasticsearch raw logs -> ClickHouse 26.6 -> Executable UDF compression -> ClickHouse AI functions MapReduce -> LibreChat/MCP ClickHouse -> Grafana MCP`.

Существующие MCP используются как готовые сервисы: `mcp/clickhouse` и `grafana/mcp-grafana`. Отдельный самодельный MCP не добавляется.

## Быстрый запуск

```bash
cp .env.example .env
docker compose up -d clickhouse grafana mcp-clickhouse mcp-grafana librechat
```

Загрузить 10 ГБ файл с Mac в ClickHouse потоково:

```bash
sh tools/import_raw_logs.sh
```

Создать investigation и сжатые batch'и. `LOG_COMPRESS_BATCH_ROWS` отвечает только за технический размер UDF-компрессии; LLM-batch лимитируется отдельно Map-очередью:

```bash
INVESTIGATION_ID=incident-2026h1 \
USER_QUESTION='Сколько раз за последние полгода падали сервера?' \
TIME_FROM='2025-12-17 00:00:00.000' \
TIME_TO='2026-06-18 00:00:00.000' \
LOGS_SOURCE_NAME='elasticsearch-synthetic' \
LOGS_INDEX_LIKE='synthetic-logs%' \
sh tools/run_sql.sh sql/00_create_investigation.sql

sh tools/compress_raw_logs.sh --truncate
```

Запустить MapReduce через ClickHouse AI functions:

```bash
INVESTIGATION_ID=incident-2026h1 \
sh tools/map_queue_worker.sh --create-schema --enqueue --max-iterations 1 --claim-size 10

INVESTIGATION_ID=incident-2026h1 \
sh tools/run_sql.sh sql/30_reduce_ai.sql

INVESTIGATION_ID=incident-2026h1 \
sh tools/run_sql.sh sql/40_final_reduce_sql.sql
```

Или одной командой:

```bash
sh tools/run_mapreduce_once.sh
```

## Где задаются лимиты

Лимиты задаются в SQL `SETTINGS` у AI-запросов:

- `ai_function_max_api_calls_per_query`
- `ai_function_max_input_tokens_per_query`
- `ai_function_max_output_tokens_per_query`
- `ai_function_request_timeout_sec`
- `ai_function_max_retries`

Сами модели задаются в `.env` и ClickHouse named collections:

- `LLM_MAP_MODEL`
- `LLM_REDUCE_MODEL`
- `LLM_MAP_API_KEY`
- `LLM_REDUCE_API_KEY`
- `LLM_MAP_CHAT_COMPLETIONS_ENDPOINT`
- `LLM_REDUCE_CHAT_COMPLETIONS_ENDPOINT`

В текущей схеме Map-LLM рассчитана на локальный Ollama на Mac:

```env
LLM_MAP_API_KEY=ollama
LLM_MAP_BASE_URL=http://host.docker.internal:11434/v1
LLM_MAP_CHAT_COMPLETIONS_ENDPOINT=http://host.docker.internal:11434/v1/chat/completions
LLM_MAP_MODEL=codellama:13b
```

ClickHouse работает в Docker и ходит в Ollama на хостовой macOS через `host.docker.internal:11434`. Сам Ollama не запускается внутри Docker: на Apple Silicon он использует Metal/GPU нативно, если модель помещается в память.

AI-функции настроены по схеме ClickHouse 26.6: prompt, optional constant system prompt, optional temperature. Credentials выбираются через setting `ai_function_credentials`:

```sql
aiGenerate(prompt, system_prompt, 0.1)
SETTINGS ai_function_credentials = 'llm_map'
```

Права на named collections задаются через `GRANT NAMED COLLECTION`; в этом dev-стеке пользователь `analytics` получает XML-grant при старте ClickHouse.

Map-LLM prompt хранится отдельно от кода:

```text
prompts/map_compressed_logs.en.txt
```

При `--create-schema` worker создает/обновляет `analytics.llm_prompts` для отладки и контроля версии prompt. В сам `aiGenerate` worker подставляет содержимое prompt-файла как constant system prompt, потому что ClickHouse 26.6 требует `const String` для `system_prompt`. Ручной `sql/20_map_ai.sql` получает тот же prompt через `tools/run_sql.sh`.

## Важное

Map-этап теперь идет через очередь `analytics.llm_map_queue`. Один worker запускается так:

```bash
INVESTIGATION_ID=incident-2026h1 \
sh tools/map_queue_worker.sh --enqueue --max-iterations 0 --claim-size 10
```

Параллельные worker'ы запускаются с разными `--worker-index` и общим `--worker-count`, например `0/2` и `1/2`. Это делит batch'и по `batch_no % worker_count` и не дает двум Map-LLM брать один и тот же batch.

```bash
INVESTIGATION_ID=incident-2026h1 sh tools/map_queue_worker.sh --worker-index 0 --worker-count 2 --max-iterations 0
INVESTIGATION_ID=incident-2026h1 sh tools/map_queue_worker.sh --worker-index 1 --worker-count 2 --max-iterations 0
```

UDF-компрессор внутри ClickHouse называется:

```sql
log_compress_json(String) -> String
```

Он использует скопированный `tools/log_compressor.py` с параметрами:

```bash
--rle-key template --samples-per-template 3 --top-values 10
```
