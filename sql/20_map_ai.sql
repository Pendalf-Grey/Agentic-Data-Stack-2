INSERT INTO analytics.llm_map_results
SELECT
  i.investigation_id AS investigation_id,
  b.batch_id,
  b.batch_no,
  b.event_time_from,
  b.event_time_to,
  b.rows_read,
  aiGenerate(
    'llm_map',
    concat(
      'Ты Map-LLM. Проанализируй сжатый batch логов. ',
      'Верни строгий JSON: summary, suspected_services, root_causes, candidate_filters, evidence, confidence. ',
      'Не возвращай исходные логи. user_question=', i.user_question,
      '\ncompressed_json=', b.compressed_json
    ),
    'Return strict JSON only. No markdown.',
    0.1
  ) AS map_summary_json,
  now64(3) AS created_at
FROM analytics.llm_investigations FINAL AS i
INNER JOIN analytics.es_log_compressed_batches AS b
  ON b.source_name = i.source_name
 AND b.index_name LIKE i.index_like
 AND b.event_time_to >= i.time_from
 AND b.event_time_from < i.time_to
WHERE i.investigation_id = {investigation_id:String}
  AND b.batch_id NOT IN
  (
    SELECT batch_id
    FROM analytics.llm_map_results FINAL
    WHERE investigation_id = {investigation_id:String}
  )
ORDER BY b.batch_no
LIMIT 50
SETTINGS
  allow_experimental_ai_functions = 1,
  ai_function_credentials = 'llm_map',
  ai_function_max_api_calls_per_query = 50,
  ai_function_max_input_tokens_per_query = 1000000,
  ai_function_max_output_tokens_per_query = 100000,
  ai_function_request_timeout_sec = 120,
  ai_function_max_retries = 2;
