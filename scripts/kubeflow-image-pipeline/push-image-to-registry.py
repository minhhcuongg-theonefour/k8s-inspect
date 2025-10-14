import os
import subprocess
import yaml
import requests
import logging
from urllib.parse import urljoin
from pathlib import Path
from dotenv import load_dotenv

# --- LOGGING CONFIG ---
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

# --- LOAD ENVIRONMENT ---
env_path = Path(__file__).resolve().parents[2] / "env" / "registry.env"
if not env_path.exists():
    raise FileNotFoundError(f".env file not found at: {env_path}")

load_dotenv(dotenv_path=env_path)
logger.info(f"Loaded environment variables from {env_path}")

# --- CONFIG ---
HARBOR_REGISTRY = os.getenv("HARBOR_REGISTRY", "")
HARBOR_PROJECT = os.getenv("HARBOR_PROJECT", "")
HARBOR_URL = f"https://{HARBOR_REGISTRY}"
HARBOR_USERNAME = os.getenv("HARBOR_USERNAME", "admin")
HARBOR_PASSWORD = os.getenv("HARBOR_PASSWORD", "")
IMAGES_FILE = "images.yaml"

logger.debug(f"Registry: {HARBOR_REGISTRY}, Project: {HARBOR_PROJECT}")
logger.info(f"Using Harbor URL: {HARBOR_URL}")


# --- HELPERS ---
def run(cmd: list, check=True):
    logger.debug(f"Running command: {' '.join(cmd)}")
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0:
        logger.error(result.stderr.strip())
        if check:
            raise RuntimeError(f"Command failed: {' '.join(cmd)}")
    return result.stdout.strip()


def ensure_project_exists():
    logger.info(f"Checking if project '{HARBOR_PROJECT}' exists...")
    resp = requests.get(
        f"{HARBOR_URL}/api/v2.0/projects/{HARBOR_PROJECT}",
        auth=(HARBOR_USERNAME, HARBOR_PASSWORD),
        verify=False,
    )

    if resp.status_code == 200:
        logger.info("Project already exists.")
        return

    if resp.status_code == 404:
        logger.warning("Project not found, creating a new one...")
        create_resp = requests.post(
            f"{HARBOR_URL}/api/v2.0/projects",
            auth=(HARBOR_USERNAME, HARBOR_PASSWORD),
            headers={"Content-Type": "application/json"},
            json={"project_name": HARBOR_PROJECT, "public": True},
            verify=False,
        )
        if create_resp.status_code not in (201, 409):
            logger.error(f"Failed to create project: {create_resp.text}")
            raise RuntimeError(f"Cannot create project: {create_resp.text}")
        logger.info("Project created successfully.")
        return

    logger.error(f"Unexpected Harbor response: {resp.status_code}")
    raise RuntimeError(f"Unexpected Harbor response: {resp.status_code}")


def docker_login():
    logger.info("Logging into Harbor...")
    run(
        [
            "docker",
            "login",
            HARBOR_REGISTRY,
            "-u",
            HARBOR_USERNAME,
            "-p",
            HARBOR_PASSWORD,
        ]
    )
    logger.info("Docker login successful.")


def normalize_image_name(image_name: str) -> str:
    """Normalize docker image name, ensuring it has a tag and removing redundant prefixes."""
    image_name = image_name.strip()

    # Skip digest-based image (e.g., image@sha256:...)
    if "@" in image_name:
        return image_name

    # Remove redundant docker.io prefix
    if image_name.startswith("docker.io/"):
        image_name = image_name.replace("docker.io/", "", 1)

    # If image has no tag, assume latest
    if ":" not in image_name.split("/")[-1]:
        image_name += ":latest"

    return image_name


def push_images_to_harbor():
    if not HARBOR_REGISTRY or not HARBOR_PROJECT:
        raise ValueError("HARBOR_REGISTRY and HARBOR_PROJECT must be set in env vars.")

    if not os.path.exists(IMAGES_FILE):
        raise FileNotFoundError(f"{IMAGES_FILE} not found.")

    with open(IMAGES_FILE, "r") as f:
        data = yaml.safe_load(f)

    images = data.get("images", [])
    logger.info(f"Found {len(images)} images to process.")

    for img_entry in images:
        src_img = img_entry.get("name")
        if not src_img:
            continue

        src_img = normalize_image_name(src_img)

        # skip digest-based images
        if "@" in src_img:
            logger.warning(f"Skipping digest-based image (cannot retag): {src_img}")
            continue

        # 🧩 lấy phần repo và tag chính xác
        parts = src_img.split("/")
        if len(parts) > 2:
            # bỏ prefix như docker.io, ghcr.io,...
            repo_path = "/".join(parts[1:])
        else:
            repo_path = "/".join(parts)

        harbor_img = f"{HARBOR_REGISTRY}/{HARBOR_PROJECT}/{repo_path}"
        print("harbor_img: ", harbor_img)

        logger.info(f"Pushing → {src_img}  →  {harbor_img}")

        try:
            run(["docker", "pull", src_img])
            run(["docker", "tag", src_img, harbor_img])
            run(["docker", "push", harbor_img])
            logger.info(f"[OK] {src_img} → {harbor_img}")
        except subprocess.CalledProcessError as e:
            logger.error(f"[FAIL] {src_img}: {e.stderr}")
        except Exception as e:
            logger.error(f"[ERROR] {src_img}: {e}")


# --- MAIN ---
if __name__ == "__main__":
    import urllib3

    urllib3.disable_warnings()

    try:
        docker_login()
        # ensure_project_exists()
        push_images_to_harbor()
        logger.info("All images processed successfully.")
    except Exception as e:
        logger.exception(f" Script failed: {e}")
