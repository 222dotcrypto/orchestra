#!/usr/bin/env python3
"""Convert YAML from stdin to JSON on stdout."""
import yaml, json, sys

try:
    data = yaml.safe_load(sys.stdin)
    print(json.dumps(data, ensure_ascii=False))
except yaml.YAMLError as e:
    print(json.dumps({"error": str(e)}), file=sys.stderr)
    sys.exit(1)
