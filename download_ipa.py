import subprocess
import urllib.request
import json
import time
import os
import zipfile
import io

def get_token():
    res = subprocess.run(
        ['git', 'credential', 'fill'],
        input='protocol=https\nhost=github.com\nusername=y41418845-CY\n\n',
        capture_output=True,
        text=True,
        check=True
    )
    for line in res.stdout.splitlines():
        if line.startswith('password='):
            return line.split('=', 1)[1].strip()
    raise RuntimeError("Cannot find password in git credentials")

def main():
    token = get_token()
    headers = {
        'Authorization': f'Bearer {token}',
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'vFlat-Downloader'
    }

    repo = "y41418845-CY/vflat"
    url = f"https://api.github.com/repos/{repo}/actions/runs?per_page=3"

    print("[INFO] Checking latest GitHub Actions workflow runs...", flush=True)
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode())

    runs = data.get('workflow_runs', [])
    if not runs:
        print("[ERROR] No workflow runs found.", flush=True)
        return

    latest_run = runs[0]
    run_id = latest_run['id']
    status = latest_run['status']
    conclusion = latest_run['conclusion']
    commit_msg = latest_run['head_commit']['message'].split('\n')[0]

    print(f"[INFO] Latest Run ID: {run_id}", flush=True)
    print(f"[INFO] Commit: {commit_msg}", flush=True)
    print(f"[INFO] Initial Status: {status}, Conclusion: {conclusion}", flush=True)

    start_wait = time.time()
    while status in ['in_progress', 'queued', 'waiting']:
        elapsed = int(time.time() - start_wait)
        print(f"[INFO] Waiting for build completion... ({elapsed}s elapsed, status: {status})", flush=True)
        time.sleep(15)
        req = urllib.request.Request(f"https://api.github.com/repos/{repo}/actions/runs/{run_id}", headers=headers)
        with urllib.request.urlopen(req) as resp:
            run_data = json.loads(resp.read().decode())
            status = run_data['status']
            conclusion = run_data['conclusion']

    print(f"[INFO] Final Status: {status}, Conclusion: {conclusion}", flush=True)
    if conclusion != 'success':
        print(f"[ERROR] Build did not succeed. Conclusion: {conclusion}", flush=True)
        return

    # Check artifacts
    art_url = f"https://api.github.com/repos/{repo}/actions/runs/{run_id}/artifacts"
    req = urllib.request.Request(art_url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        art_data = json.loads(resp.read().decode())

    artifacts = art_data.get('artifacts', [])
    target_art = None
    for a in artifacts:
        if 'ipa' in a['name'].lower():
            target_art = a
            break

    if target_art:
        dl_url = target_art['archive_download_url']
        print(f"[INFO] Downloading artifact from {dl_url}...", flush=True)
        req = urllib.request.Request(dl_url, headers=headers)
        with urllib.request.urlopen(req) as resp:
            zip_content = resp.read()

        print(f"[INFO] Received {len(zip_content)} bytes. Extracting vFlat.ipa...", flush=True)
        with zipfile.ZipFile(io.BytesIO(zip_content)) as z:
            for filename in z.namelist():
                if filename.endswith('.ipa'):
                    out_path = os.path.join(os.getcwd(), 'vFlat.ipa')
                    with open(out_path, 'wb') as f:
                        f.write(z.read(filename))
                    file_size = os.path.getsize(out_path)
                    print(f"[SUCCESS] Successfully saved {out_path} ({file_size} bytes)", flush=True)
                    return

    # Fallback to Release
    print("[INFO] No artifact found or extracted. Checking GitHub Releases...", flush=True)
    rel_url = f"https://api.github.com/repos/{repo}/releases"
    req = urllib.request.Request(rel_url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        releases = json.loads(resp.read().decode())

    for rel in releases:
        for asset in rel.get('assets', []):
            if asset['name'] == 'vFlat.ipa':
                asset_url = asset['url']
                dl_headers = headers.copy()
                dl_headers['Accept'] = 'application/octet-stream'
                print(f"[INFO] Downloading release asset from {asset_url}...", flush=True)
                req = urllib.request.Request(asset_url, headers=dl_headers)
                with urllib.request.urlopen(req) as resp:
                    ipa_bytes = resp.read()
                out_path = os.path.join(os.getcwd(), 'vFlat.ipa')
                with open(out_path, 'wb') as f:
                    f.write(ipa_bytes)
                file_size = os.path.getsize(out_path)
                print(f"[SUCCESS] Successfully saved {out_path} ({file_size} bytes)", flush=True)
                return

    print("[ERROR] Could not find vFlat.ipa in artifacts or releases.", flush=True)

if __name__ == '__main__':
    main()
