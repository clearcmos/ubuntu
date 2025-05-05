# Large Context Test Debugging

## Issue
When running large context tests with 4000 lines, the script doesn't extract the line number from the model's response, despite correctly setting the context window to 65536 tokens.

## Debugging Steps

1. Examine the raw model response:
   ```python
   # In large_context_test.py, modify the run_context_test function to always print the raw response:
   if model_output:
       response_text = " ".join(model_output)
       print("\nRaw model response:")
       print(repr(response_text))  # Use repr to show whitespace and special chars
       print("\nModel response summary:")
       print(response_text)
   ```

2. Improve the regex pattern for more flexible number extraction:
   ```python
   # Try a more lenient regex that can find numbers in various formats:
   number_matches = re.findall(r'(?:line|number|#)?\s*(\d+)', response_text, re.IGNORECASE)
   # Or try a pattern that looks for "last line" context:
   last_line_match = re.search(r'(?:last|final)(?:\s+line|\s+number)?\s*(?:is|:|=)?\s*(\d+)', response_text, re.IGNORECASE)
   ```

3. Try adding a more explicit instruction in the prompt:
   ```python
   # In large_context_test.py, modify the run_context_test function:
   cmd = [
       "python3", 
       ocode_script, 
       "--debug",
       test_file, 
       "What is the last numbered line in this file? Please respond ONLY with the number, for example: 'The last line is 4000'"
   ]
   ```

4. Check if the model is timing out:
   ```bash
   # Run with a shorter context to see if timing is the issue
   python3 large_context_test.py --lines 2000
   ```

5. Analyze model's streaming response timing:
   ```python
   # Add timing information in ocode.py to see if response generation is being cut off
   last_chunk_time = time.time()
   for line in response.iter_lines():
       if line:
           current_time = time.time()
           if current_time - last_chunk_time > 5:
               debug(f"Long pause detected: {current_time - last_chunk_time:.2f}s")
           last_chunk_time = current_time
           try:
               chunk = json.loads(line)
               print(chunk.get("response", ""), end="", flush=True)
           except json.JSONDecodeError:
               debug(f"Failed to decode JSON: {line}")
   ```

## Next Steps to Try

1. Run tests with different line counts (2000, 3000, 4000, 5000) to find the threshold
2. Modify the model's temperature parameter (try 0.0 for more deterministic responses)
3. Try with a different prompt that encourages a simpler response format
4. Check if the model is actually processing the full context by asking about specific lines near the end
5. Add sleep time between initialization and query to ensure the model is fully loaded