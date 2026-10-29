import urllib.request
import json
import time
import zipfile
import io
import os
import sys

REPO = "y41418845-CY/vflat"
HEADERS = {
    "Accept": "application/vnd.github.v3+json",
    "User-Agent": "vFlat-Build-Watcher"
}

def get_latest_run():
    url = f"https://api.github.com/repos/{REPO}/actions/runs?per_page=1"
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            runs = data.get("workflow_runs", [])
            if runs:
                return runs[0]
    except Exception as e:
        print(f"Error fetching runs: {e}")
    return None

def download_artifact(run_id):
    url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/artifacts"
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            artifacts = data.get("artifacts", [])
            for art in artifacts:
                if art.get("name") == "vFlat-IPA":
                    download_url = art.get("archive_download_url")
                    print(f"Found artifact: {art['name']}, size: {art['size_in_bytes']} bytes")
                    # GitHub API requires authentication for artifact download
                    # We can use git credential helper or public release if available, or curl
                    return art
    except Exception as e:
        print(f"Error fetching artifacts: {e}")
    return None

print("Checking latest workflow run...")
run = get_latest_run()
if run:
    print(f"Run ID: {run['id']}, Status: {run['status']}, Conclusion: {run['conclusion']}, Commit: {run['head_commit']['message'].splitlines()[0]}")
else:
    print("No runs found")
