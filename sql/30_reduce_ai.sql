INSERT INTO analytics.llm_reduce_results
SELECT
  investigation_id,
  1 AS reduce_level,
  reduce_group,
  aiGenerate(
    'llm_reduce',
    concat(
      'Ты Reduce-LLM уровня 1. Сожми результаты Map-LLM в один JSON. ',
      'Нужно сохранить только root causes, сервисы, временные окна, фильтры для ClickHouse и доказательства. ',
      'Не выдумывай данные. summaries=',
      arrayStringConcat(groupArray(map_summary_json), '\n')
    ),
    0.1
  ) AS summary_json,
  '' AS refined_sql,
  now64(3) AS created_at
FROM
(
  SELECT
    *,
    intDiv(row_number() OVER (ORDER BY batch_no) - 1, 50) AS reduce_group
  FROM analytics.llm_map_results FINAL
  WHERE investigation_id = {investigation_id:String}
)
GROUP BY investigation_id, reduce_group
SETTINGS
  allow_experimental_ai_functions = 1,
  ai_function_credentials = 'llm_reduce',
  ai_function_max_api_calls_per_query = 16,
  ai_function_max_input_tokens_per_query = 1000000,
  ai_function_max_output_tokens_per_query = 100000,
  ai_function_request_timeout_sec = 180,
  ai_function_max_retries = 2;
