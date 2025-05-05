#!/usr/bin/env python3
"""
ocode.py - Enhanced Ollama Code Assistant

A tool for querying Ollama models about code, files or entire repositories
with real-time streaming responses and dynamic context sizing.
"""

import os
import sys
import time
import json
import argparse
import requests
import subprocess
from pathlib import Path
from datetime import datetime
import tiktoken

# Configuration
DEFAULT_MODEL = "qwen2.5-coder-128k:latest"
OLLAMA_API_URL = "http://localhost:11434/api"
MAX_CONTEXT_SIZE = 128000  # Maximum context size for the model
DEBUG_MODE = False  # Set to True to enable debug output
TOKEN_BUFFER = 1000  # Extra tokens to allocate for the model's response

# ANSI color codes
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
RED = "\033[0;31m"
BLUE = "\033[0;34m"
MAGENTA = "\033[0;35m"
CYAN = "\033[0;36m"
GRAY = "\033[0;90m"
RESET = "\033[0m"

def log(message, color=None, timestamp=True):
    """Print a log message with optional color and timestamp."""
    prefix = f"[{datetime.now().strftime('%H:%M:%S.%f')[:-3]}] " if timestamp else ""
    
    if color:
        print(f"{color}{prefix}{message}{RESET}")
    else:
        print(f"{prefix}{message}")

def debug(message):
    """Print a debug message if debug mode is enabled."""
    if DEBUG_MODE:
        log(f"[DEBUG {datetime.now().strftime('%H:%M:%S.%f')[:-3]}] {message}", GRAY, False)

def count_tokens(text, model="gpt-4"):
    """Count the number of tokens in a text string."""
    try:
        encoding = tiktoken.encoding_for_model(model)
        tokens = encoding.encode(text)
        return len(tokens)
    except Exception as e:
        debug(f"Error counting tokens: {e}")
        # Fallback approximation
        return len(text) // 4

def get_file_content(file_path):
    """Read content from a file, handling different file types appropriately."""
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return f.read()
    except UnicodeDecodeError:
        # For binary files, just mention it's a binary file
        return f"[Binary file: {file_path}]"
    except Exception as e:
        return f"[Error reading file {file_path}: {e}]"

def get_directory_content(dir_path, max_depth=3, max_files=50):
    """Get content from a directory, limited by depth and file count."""
    dir_path = Path(dir_path)
    result = []
    file_count = 0
    
    try:
        # Find git root if it exists
        git_root = None
        try:
            git_root = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"], 
                cwd=dir_path, 
                stderr=subprocess.DEVNULL
            ).decode().strip()
        except:
            pass
        
        # Get .gitignore patterns if available
        ignored_patterns = []
        if git_root:
            gitignore_path = Path(git_root) / ".gitignore"
            if gitignore_path.exists():
                with open(gitignore_path, "r") as f:
                    ignored_patterns = [line.strip() for line in f if line.strip() and not line.startswith('#')]
        
        # Function to check if a path should be ignored
        def should_ignore(path):
            # Skip hidden files and directories
            if path.name.startswith('.'):
                return True
                
            # Skip files matching gitignore patterns
            rel_path = str(path.relative_to(dir_path))
            for pattern in ignored_patterns:
                if pattern.endswith('/') and rel_path.startswith(pattern[:-1]):
                    return True
                elif pattern.startswith('*') and rel_path.endswith(pattern[1:]):
                    return True
                elif pattern in rel_path:
                    return True
            
            # Skip binary and large files
            if path.is_file():
                if path.suffix in ['.jpg', '.jpeg', '.png', '.gif', '.pdf', '.zip', '.tar', '.gz']:
                    return True
                if path.stat().st_size > 1000000:  # Skip files larger than 1MB
                    return True
                    
            return False
        
        # Process files with BFS approach
        dirs_to_process = [dir_path]
        current_depth = 0
        
        while dirs_to_process and current_depth < max_depth and file_count < max_files:
            next_dirs = []
            
            for current_dir in dirs_to_process:
                try:
                    # Add directory information
                    result.append(f"===== Directory: {current_dir} =====")
                    
                    # Process all entries in the current directory
                    for entry in sorted(current_dir.iterdir(), key=lambda x: (x.is_file(), x.name)):
                        if should_ignore(entry):
                            continue
                            
                        if entry.is_file():
                            # Process file
                            if file_count < max_files:
                                result.append(f"===== {entry.name} =====")
                                content = get_file_content(entry)
                                result.append(content)
                                file_count += 1
                            else:
                                result.append(f"[Skipped file: {entry.name} - max file limit reached]")
                        elif entry.is_dir():
                            # Add directory to next level
                            next_dirs.append(entry)
                except Exception as e:
                    result.append(f"[Error reading directory {current_dir}: {e}]")
            
            dirs_to_process = next_dirs
            current_depth += 1
        
        if file_count >= max_files:
            result.append(f"[Warning: Only processed {file_count} files. Additional files were skipped.]")
            
    except Exception as e:
        return f"[Error processing directory {dir_path}: {e}]"
        
    return "\n\n".join(result)

def check_ollama_status():
    """Check if Ollama is running and the requested model is available."""
    log("Performing detailed Ollama status check...")
    
    # Step 1: Check if the Ollama API is accessible
    try:
        debug("Checking Ollama API /api/version endpoint...")
        response = requests.get(f"{OLLAMA_API_URL}/version")
        debug(f"Version response status: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            debug(f"Version data: {json.dumps(data)}")
        else:
            log("Ollama server is not responding correctly", RED)
            return False
    except Exception as e:
        log(f"Error connecting to Ollama: {e}", RED)
        return False
    
    # Step 2: Check if the required model is available
    try:
        debug("Checking available models...")
        response = requests.get(f"{OLLAMA_API_URL}/tags")
        debug(f"Models response status: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            models = [model["name"] for model in data.get("models", [])]
            debug(f"Available models: {models}")
            
            if DEFAULT_MODEL in models:
                debug(f"Target model '{DEFAULT_MODEL}' is available")
            else:
                log(f"Required model '{DEFAULT_MODEL}' is not available", RED)
                log(f"Available models: {', '.join(models)}", YELLOW)
                return False
        else:
            log("Failed to get model list from Ollama", RED)
            return False
    except Exception as e:
        log(f"Error checking available models: {e}", RED)
        return False
    
    # Step 3: Test the model with a simple prompt
    try:
        debug("Testing model with a simple prompt...")
        response = requests.post(
            f"{OLLAMA_API_URL}/generate",
            json={"model": DEFAULT_MODEL, "prompt": "Hello!", "stream": False}
        )
        
        if response.status_code == 200:
            data = response.json()
            debug(f"Test generation status: {response.status_code}")
            debug(f"Test generation successful: {data.get('response', '')[:50]}")
        else:
            log(f"Model test failed with status code: {response.status_code}", RED)
            return False
    except Exception as e:
        log(f"Error testing model: {e}", RED)
        return False
    
    log("Ollama status: Ollama is fully operational", GREEN)
    return True

def create_prompt(content, query, target_path):
    """Create a prompt for the Ollama model."""
    # For file content, format it with the filename
    if isinstance(content, str) and len(content.splitlines()) > 0:
        formatted_content = f"===== {os.path.basename(target_path)} =====\n{content}"
    else:
        formatted_content = content
        
    return f"""I'll provide code from my project for you to analyze. Please focus on answering my query effectively.

Project Files:
{formatted_content}

Query: {query}

Please provide a detailed answer focusing specifically on my query."""

def send_query_to_ollama(prompt, stream=True, dynamic_ctx_size=None):
    """Send a query to Ollama and handle the response."""
    # Estimate token count for prompt
    est_tokens = count_tokens(prompt)
    log(f"Prompt size: ~{est_tokens} tokens (approximate)")
    
    # Print the prompt for debugging
    debug(f"Prompt content:\n{prompt}")
    
    # Verify Ollama status before sending
    debug("Verifying Ollama status before sending query...")
    if not check_ollama_status():
        log("Ollama is not ready. Please check the service status.", RED)
        return
    
    # Configure context size based on content
    ctx_size = dynamic_ctx_size if dynamic_ctx_size else MAX_CONTEXT_SIZE
    
    # Prepare the request data
    request_data = {
        "model": DEFAULT_MODEL,
        "prompt": prompt,
        "stream": stream,
        "options": {
            "num_ctx": ctx_size,
            "temperature": 0.2,
            "top_k": 40,
            "top_p": 0.9
        }
    }
    
    debug(f"Setting up request to Ollama API...")
    debug(f"Request data: {json.dumps(request_data)}")
    
    # Send the request
    debug(f"Sending POST request to Ollama API...")
    
    try:
        start_time = time.time()
        
        if stream:
            log("Streaming response from Ollama...")
            print("\n=== Ollama Response ===\n")
            
            # Send request with streaming
            response = requests.post(
                f"{OLLAMA_API_URL}/generate",
                json=request_data,
                stream=True
            )
            
            if response.status_code != 200:
                log(f"Error: Received status code {response.status_code}", RED)
                return
            
            # Process the streaming response
            for line in response.iter_lines():
                if line:
                    try:
                        chunk = json.loads(line)
                        print(chunk.get("response", ""), end="", flush=True)
                    except json.JSONDecodeError:
                        debug(f"Failed to decode JSON: {line}")
            
            print("\n")  # Add newline after streaming completes
            elapsed_time = time.time() - start_time
            log(f"Streaming completed in {elapsed_time:.2f} seconds")
            
        else:
            # Send request without streaming
            log("Waiting for response (this might take a while for long prompts)...")
            
            response = requests.post(
                f"{OLLAMA_API_URL}/generate",
                json=request_data
            )
            
            debug(f"Response received with status code: {response.status_code}")
            
            if response.status_code == 200:
                data = response.json()
                debug(f"Parsing JSON response...")
                debug(f"Response keys: {list(data.keys())}")
                
                elapsed_time = time.time() - start_time
                log(f"Response completed in {elapsed_time:.2f} seconds")
                
                if "response" in data:
                    debug(f"Response length: {len(data['response'])} characters")
                    print("\n=== Ollama Response ===\n")
                    print(data["response"])
            else:
                log(f"Error: Received status code {response.status_code}", RED)
                print(response.text)
                
    except Exception as e:
        log(f"Error communicating with Ollama: {e}", RED)
    
    log("Processing complete!")

def main():
    global DEBUG_MODE
    
    # Set up argument parsing
    parser = argparse.ArgumentParser(description="Query Ollama about code files and repositories")
    parser.add_argument("target", help="File or directory to analyze")
    parser.add_argument("query", help="Question to ask about the code")
    parser.add_argument("--debug", action="store_true", help="Enable debug output")
    parser.add_argument("--stream", action="store_true", help="Stream output in real-time (default)")
    parser.add_argument("--no-stream", action="store_false", dest="stream", help="Don't stream output")
    parser.add_argument("--max-files", type=int, default=50, help="Maximum number of files to process")
    parser.add_argument("--max-depth", type=int, default=3, help="Maximum directory depth to traverse")
    
    # Set streaming to true by default
    parser.set_defaults(stream=True)
    
    # Parse arguments
    args = parser.parse_args()
    
    # Set debug mode
    DEBUG_MODE = args.debug
    
    # Log startup
    script_name = os.path.basename(__file__)
    log(f"Starting {script_name}{' (DEBUG MODE)' if DEBUG_MODE else ''}", GREEN)
    log(f"Target: {args.target}")
    log(f"Query: {args.query}")
    
    # Check if target exists
    target_path = Path(args.target)
    if not target_path.exists():
        log(f"Error: Target '{args.target}' does not exist", RED)
        return 1
    
    # Read content based on target type
    if target_path.is_file():
        log(f"Reading file: {args.target}")
        content = get_file_content(args.target)
        log(f"Read {len(content)} bytes from {args.target}")
    elif target_path.is_dir():
        log(f"Reading directory: {args.target} (max depth: {args.max_depth}, max files: {args.max_files})")
        content = get_directory_content(args.target, args.max_depth, args.max_files)
        log(f"Processed directory content ({len(content)} bytes)")
    else:
        log(f"Error: Target '{args.target}' is neither a file nor a directory", RED)
        return 1
    
    # Create prompt and estimate token count
    prompt = create_prompt(content, args.query, target_path)
    token_count = count_tokens(prompt)
    
    # Determine appropriate context size with buffer for response
    dynamic_ctx_size = min(MAX_CONTEXT_SIZE, token_count + TOKEN_BUFFER)
    
    # Round up to nearest power of 2 for efficiency (minimum 4096)
    dynamic_ctx_size = max(4096, 2**int(dynamic_ctx_size - 1).bit_length())
    
    log(f"Using dynamic context size: {dynamic_ctx_size} tokens")
    
    # Send query to Ollama
    send_query_to_ollama(prompt, args.stream, dynamic_ctx_size)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())