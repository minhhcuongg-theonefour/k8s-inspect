#!/usr/bin/env python3
import os
import subprocess
import yaml
import requests
from urllib.parse import urljoin

# --- CONFIG ---
HARBOR_REGISTRY = "harbor.servicesec.io"
HARBOR_PROJECT = "aiaas-images"
HARBOR_URL = f"https://{HARBOR_REGISTRY}"
USERNAME = os.getenv("HARBOR_USERNAME", "admin")
PASSWORD = os.getenv("HARBOR_PASSWORD", "")
IMAGES_FILE = "images.yaml"
LOG_FILE = "push.log"

# --- HELPERS ---
def run(cmd: list, check=True):
    print(f"[RUN] {' '.join(cmd)}")
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0 and check:
        print(result.stderr)
        raise RuntimeError(f"Command failed: {' '.join(cmd)}")
    return result.stdout.strip()

def ensure_project_exists():
    print(f"[INFO] Checking if project '{HARBOR_PROJECT}' exists...")
    resp = requests.get(
        f"{HARBOR_URL}/api/v2.0/projects/{HARBOR_PROJECT}",
        auth=(USERNAME, PASSWORD),
        verify=False,
    )
    if resp.status_code == 200:
        print("[OK] Project already exists.")
        return
    elif resp.status_code == 404:
        print("[INFO] Creating new project...")
        create_resp = requests.post(
            f"{HARBOR_URL}/api/v2.0/projects",
            auth=(USERNAME, PASSWORD),
            headers={"Content-Type": "application/json"},
            json={"project_name": HARBOR_PROJECT, "public": True},
            verify=False,
        )
        if create_resp.status_code not in (201, 409):
            raise RuntimeError(f"Cannot create project: {create_resp.text}")
        print("[OK] Project created successfully.")
    else:
        raise RuntimeError(f"Unexpected Harbor response: {resp.status_code}")

def docker_login():
    print("[INFO] Logging into Harbor...")
    run(["docker", "login", HARBOR_REGISTRY, "-u", USERNAME, "-p", PASSWORD])

def push_images_to_harbor():
    if not os.path.exists(IMAGES_FILE):
        raise FileNotFoundError(f"{IMAGES_FILE} not found.")

    with open(IMAGES_FILE, "r") as f:
        data = yaml.safe_load(f)
    images = data.get("images", [])

    print(f"[INFO] Found {len(images)} images to push.")
    with open(LOG_FILE, "w") as log:
        for src_img in images:
            if src_img.startswith("docker.io/"):
                src_img = src_img.replace("docker.io/", "")
            repo_tag = src_img.split("/")[-1]
            harbor_img = f"{HARBOR_REGISTRY}/{HARBOR_PROJECT}/{repo_tag}"

            print(f"[PUSH] {src_img}  →  {harbor_img}")
            try:
                run(["docker", "pull", src_img])
                run(["docker", "tag", src_img, harbor_img])
                run(["docker", "push", harbor_img])
                log.write(f"OK: {src_img} → {harbor_img}\n")
            except Exception as e:
                print(f"[ERROR] {e}")
                log.write(f"FAIL: {src_img} ({e})\n")

# --- MAIN ---
if __name__ == "__main__":
    import urllib3
    urllib3.disable_warnings()  # skip SSL verify warning
    ensure_project_exists()
    docker_login()
    push_images_to_harbor()
    print(f"[DONE] Log saved to {LOG_FILE}")
