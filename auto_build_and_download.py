import subprocess
import urllib.request
import json
import time
import zipfile
import io
import os
import sys

def get_github_token():
    p = subprocess.Popen(['git', 'credential', 'fill'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    out, _ = p.communicate('protocol=https\nhost=github.com\nusername=y41418845-CY\n\n')
    for line in out.splitlines():
        if line.startswith('password='):
            return line.split('=', 1)[1].strip()
    return None

token = get_github_token()
if not token:
    print("Failed to retrieve GitHub token from git credential helper.")
    sys.exit(1)

REPO = "y41418845-CY/vflat"
HEADERS = {
    "Accept": "application/vnd.github.v3+json",
    "Authorization": f"Bearer {token}",
    "User-Agent": "vFlat-Build-Watcher"
}

def get_latest_run():
    url = f"https://api.github.com/repos/{REPO}/actions/runs?per_page=1"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        runs = data.get("workflow_runs", [])
        if runs:
            return runs[0]
    return None

def download_and_extract_ipa(run_id, output_path="vFlat.ipa"):
    url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/artifacts"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        artifacts = data.get("artifacts", [])
        for art in artifacts:
            if art.get("name") == "vFlat-IPA":
                download_url = art.get("archive_download_url")
                print(f"Downloading artifact {art['name']} ({art['size_in_bytes']} bytes)...")
                down_req = urllib.request.Request(download_url, headers=HEADERS)
                with urllib.request.urlopen(down_req) as down_resp:
                    zip_data = down_resp.read()
                    print(f"Downloaded zip: {len(zip_data)} bytes. Extracting...")
                    with zipfile.ZipFile(io.BytesIO(zip_data)) as z:
                        for filename in z.namelist():
                            if filename.endswith(".ipa") or filename == "vFlat.ipa":
                                ipa_content = z.read(filename)
                                with open(output_path, "wb") as f_out:
                                    f_out.write(ipa_content)
                                print(f"Successfully saved {output_path} ({len(ipa_content)} bytes)!")
                                return True
    return False

print("Monitoring GitHub Actions build...")
while True:
    run = get_latest_run()
    if not run:
        print("Waiting for run to appear...")
        time.sleep(5)
        continue

    run_id = run['id']
    status = run['status']
    conclusion = run.get('conclusion')
    commit_msg = run['head_commit']['message'].splitlines()[0]
    print(f"Run {run_id}: status={status}, conclusion={conclusion} (Commit: {commit_msg})")

    if status == "completed":
        if conclusion == "success":
            print("Build succeeded! Downloading IPA artifact...")
            success = download_and_extract_ipa(run_id)
            if success:
                print("All done!")
                sys.exit(0)
            else:
                print("Artifact not found yet. Retrying in 5 seconds...")
        else:
            print(f"Build completed with failure conclusion: {conclusion}")
            sys.exit(1)
    
    time.sleep(10)
