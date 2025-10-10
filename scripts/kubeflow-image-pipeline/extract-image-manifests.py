#!/usr/bin/env python3
import os
import yaml
import re

ROOT_DIR = "."
OUTPUT_YAML = os.path.join(ROOT_DIR, "images.yaml")


def extract_images_from_yaml(file_path):
    images = set()
    try:
        with open(file_path, "r") as f:
            docs = list(yaml.safe_load_all(f))
            for doc in docs:
                if not isinstance(doc, dict):
                    continue
                if doc.get("kind") == "Deployment":
                    containers = (
                        doc.get("spec", {})
                        .get("template", {})
                        .get("spec", {})
                        .get("containers", [])
                    )
                    for c in containers:
                        image = c.get("image")
                        if image:
                            images.add(image)
    except Exception:
        # fallback for Helm template
        try:
            text = open(file_path, "r").read()
            matches = re.findall(r"image:\s*([^\s]+)", text)
            for m in matches:
                if "{{" not in m:
                    images.add(m.strip())
        except Exception as e:
            print(f"[WARN] Cannot parse {file_path}: {e}")
    return images


def scan_for_images(root_dir):
    all_images = set()
    for subdir, _, files in os.walk(root_dir):
        for file in files:
            if file.endswith((".yaml", ".yml")):
                file_path = os.path.join(subdir, file)
                imgs = extract_images_from_yaml(file_path)
                if imgs:
                    all_images.update(imgs)
    return all_images


def main():
    all_images = scan_for_images(ROOT_DIR)
    if not all_images:
        print("No images found.")
        return

    yaml_output = {"images": [{"name": img} for img in sorted(all_images)]}
    with open(OUTPUT_YAML, "w") as yml:
        yaml.dump(yaml_output, yml, sort_keys=False)

    print(f"Extracted {len(all_images)} images.")
    print(f"Saved to {OUTPUT_YAML}")


if __name__ == "__main__":
    main()
