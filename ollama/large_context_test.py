#!/usr/bin/env python3
"""
Script to generate and test a large context file with Ollama.
This will create a test file with many numbered lines and then query
the model to verify how many lines it can see.
"""

import os
import subprocess
import sys
import time
import argparse

# Number of lines to generate
DEFAULT_LINES = 15000  # Should be enough to test a 128K context window
# The typical line "12345. This is line number 12345 in our context window test."
# is around 5-8 tokens, so 15K lines should be ~75K-120K tokens

def estimate_qwen_tokens(text):
    """
    Estimate token count for Qwen models more accurately than tiktoken.
    Based on typical tokenization patterns for multilingual models.
    """
    # Split into words, punctuation, and spaces
    words = len(text.split())
    
    # Count Chinese/Japanese/Korean characters which are often tokenized as individual tokens
    cjk_chars = sum(1 for char in text if ord(char) > 0x4E00 and ord(char) < 0x9FFF)
    
    # Count numbers, which are often tokenized digit by digit
    numeric_chars = sum(1 for char in text if char.isdigit())
    
    # Count special characters, which often get their own tokens
    special_chars = sum(1 for char in text if not (char.isalnum() or char.isspace()))
    
    # For Qwen models, we'll use a reasonable approximation based on these factors
    # This is more accurate than just dividing by 4 for English text with numbers
    estimated_tokens = words + cjk_chars + (numeric_chars * 0.5) + (special_chars * 0.5)
    
    return int(estimated_tokens)

def generate_test_file(num_lines, output_file):
    """Generate a test file with numbered lines."""
    print(f"Generating test file with {num_lines} lines...")
    
    # Calculate the metadata header tokens
    header = "This is a test file to check the context window size of the Ollama model.\n"
    header += "Each line contains a number that we'll use to determine how much context is actually being used.\n\n"
    header_tokens = estimate_qwen_tokens(header)
    
    # Calculate tokens for a sample line to get a better estimate
    sample_line = f"{num_lines}. This is line number {num_lines} in our context window test.\n"
    tokens_per_line = estimate_qwen_tokens(sample_line)
    
    # Calculate total estimated tokens
    total_estimated_tokens = header_tokens + (tokens_per_line * num_lines)
    
    with open(output_file, 'w') as f:
        f.write(header)
        
        # Write numbered lines
        for i in range(1, num_lines + 1):
            f.write(f"{i}. This is line number {i} in our context window test.\n")
    
    print(f"Test file created at: {output_file}")
    print(f"Estimated token count: ~{total_estimated_tokens} tokens")
    
    file_size_bytes = os.path.getsize(output_file)
    print(f"File size: {file_size_bytes / 1024:.2f} KB")
    
    return output_file

def run_context_test(test_file, ocode_script):
    """Run the context test using the ocode.py script."""
    print(f"Running context test with file: {test_file}")
    print(f"Using script: {ocode_script}")
    
    # Execute the ocode.py script with our test file
    cmd = [
        "python3", 
        ocode_script, 
        "--debug",
        test_file, 
        "What is the last numbered line in this file? Be specific and just tell me the last line number you can see."
    ]
    
    print("\nExecuting command: " + " ".join(cmd))
    print("\n" + "="*80)
    
    start_time = time.time()
    process = subprocess.Popen(
        cmd, 
        stdout=subprocess.PIPE, 
        stderr=subprocess.PIPE,
        universal_newlines=True
    )
    
    # Print output in real-time and capture model's response
    model_output = []
    in_response_block = False
    
    for line in process.stdout:
        print(line, end='')
        
        # Capture the model's actual response for analysis
        if "=== Ollama Response ===" in line:
            in_response_block = True
            continue
        
        if in_response_block and line.strip() and not line.startswith("["):
            model_output.append(line.strip())
    
    process.wait()
    end_time = time.time()
    
    print("\n" + "="*80)
    print(f"Test completed in {end_time - start_time:.2f} seconds")
    
    # Extract the last line number from model output
    if model_output:
        response_text = " ".join(model_output)
        print("\nModel response summary:")
        print(response_text)
        
        # Try to extract the last line number from the response
        import re
        number_matches = re.findall(r'(\d+)', response_text)
        if number_matches:
            try:
                last_line_seen = int(number_matches[-1])
                print(f"\n🎯 RESULT: The model was able to see up to line {last_line_seen}.")
                
                # Calculate tokens per line based on the line number
                sample_line = f"{last_line_seen}. This is line number {last_line_seen} in our context window test.\n"
                tokens_per_line = estimate_qwen_tokens(sample_line)
                
                # Estimate the token capacity based on the last line seen
                estimated_token_capacity = last_line_seen * tokens_per_line
                print(f"Estimated effective context window: ~{estimated_token_capacity} tokens")
                
            except ValueError:
                print("Could not determine the last line number from the model's response.")
    
    if process.returncode != 0:
        print(f"Error: Process returned non-zero exit code: {process.returncode}")
        stderr = process.stderr.read()
        if stderr:
            print(f"Error output:\n{stderr}")

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Test Ollama context window size')
    parser.add_argument('--lines', type=int, default=DEFAULT_LINES, 
                        help=f'Number of lines to generate (default: {DEFAULT_LINES})')
    parser.add_argument('--output', default='large_context_test.txt',
                        help='Output file path (default: large_context_test.txt)')
    args = parser.parse_args()
    
    # Get the path to the ocode.py script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    ocode_script = os.path.join(script_dir, 'ocode.py')
    
    if not os.path.exists(ocode_script):
        print(f"Error: Could not find ocode.py at {ocode_script}")
        return 1
    
    # Generate the test file
    test_file_path = os.path.abspath(args.output)
    generate_test_file(args.lines, test_file_path)
    
    # Run the context test
    run_context_test(test_file_path, ocode_script)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())