import os
import subprocess
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


# --- HELPERS ---
def run(cmd: list, check=True):
    logger.debug(f"Running command: {' '.join(cmd)}")
    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0:
        logger.error(result.stderr.strip())
        if check:
            raise RuntimeError(f"Command failed: {' '.join(cmd)}")
    return result.stdout.strip()


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


def normalize_image_name(image_name: str, image_tag: str) -> str:
    """Build and normalize image name with tag."""
    image_name = image_name.strip()
    if ":" in image_name:
        # user entered with tag already
        return image_name
    return f"{image_name}:{image_tag}"


def push_single_image(image_name: str, image_tag: str):
    if not HARBOR_REGISTRY or not HARBOR_PROJECT:
        raise ValueError("HARBOR_REGISTRY and HARBOR_PROJECT must be set in env vars.")

    src_img = normalize_image_name(image_name, image_tag)

    parts = src_img.split("/")
    if len(parts) > 2:
        repo_path = "/".join(parts[1:])
    else:
        repo_path = "/".join(parts)

    harbor_img = f"{HARBOR_REGISTRY}/{HARBOR_PROJECT}/{repo_path}"

    logger.info(f"Pushing → {src_img}  →  {harbor_img}")

    try:
        run(["docker", "pull", src_img])
        run(["docker", "tag", src_img, harbor_img])
        run(["docker", "push", harbor_img])
        logger.info(f"[OK] {src_img} → {harbor_img}")
    except Exception as e:
        logger.error(f"[ERROR] {src_img}: {e}")
        raise


# --- MAIN ---
if __name__ == "__main__":
    import urllib3

    urllib3.disable_warnings()

    image_name = input(
        "Enter image name (e.g. quay.io/jetstack/cert-manager-acmesolver): "
    ).strip()
    image_tag = input("Enter image tag (e.g. v1.16.1): ").strip()

    try:
        docker_login()
        push_single_image(image_name, image_tag)
        logger.info("Image pushed successfully.")
    except Exception as e:
        logger.exception(f"Script failed: {e}")
