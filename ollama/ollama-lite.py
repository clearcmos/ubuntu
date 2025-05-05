#!/usr/bin/env python3
"""
ollama-lite.py - Lightweight Ollama CLI

A minimalist tool for using Ollama models with reduced parameters 
for faster responses to simple queries.
"""

import argparse
import os
import subprocess
import sys

def parse_args():
    parser = argparse.ArgumentParser(description="Run Ollama with lightweight parameters")
    parser.add_argument("--model", "-m", default="qwen2.5-coder:7b", 
                      help="Model to use (default: qwen2.5-coder:7b)")
    parser.add_argument("--context", "-c", type=int, default=4096,
                      help="Context length (default: 4096)")
    parser.add_argument("--pipe", "-p", action="store_true",
                      help="Read input from pipe")
    parser.add_argument("prompt", nargs="?", help="Prompt to send to the model")
    
    return parser.parse_args()

def main():
    args = parse_args()
    
    # Set environment variables for lighter parameters
    env = os.environ.copy()
    env["OLLAMA_MAX_INPUT_TOKENS"] = str(args.context)
    env["OLLAMA_CONTEXT_LENGTH"] = str(args.context)
    
    # Get the prompt from arguments or stdin
    prompt = args.prompt
    
    if args.pipe or not sys.stdin.isatty():
        prompt = sys.stdin.read()
    
    if not prompt:
        print("No prompt provided. Use --help for usage information.", file=sys.stderr)
        sys.exit(1)
    
    # Run ollama
    try:
        ollama_cmd = ["ollama", "run", args.model]
        
        # Start the process and pipe the prompt to it
        process = subprocess.Popen(
            ollama_cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env
        )
        
        stdout, stderr = process.communicate(input=prompt)
        
        if process.returncode != 0:
            print(f"Ollama error: {stderr}", file=sys.stderr)
            sys.exit(process.returncode)
            
        print(stdout)
        
    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()