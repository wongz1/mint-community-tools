#!/usr/bin/env python3
"""Uploads a release zip to CurseForge.

    CF_API_KEY=... python3 tools/cf_upload.py <project id> <metadata.json> <zip> [url]

The token is trimmed of whitespace: a repository secret saved with a trailing newline breaks
the request when sent by curl, which is what made the packager's upload fail with "Missing
field metadata". The multipart body is built here with an explicit Content-Length. Prints
CurseForge's reply; exits 0 on HTTP 200.
"""

import json
import os
import sys
import urllib.request
import uuid


def multipart(fields, files):
    boundary = "----MintCommunityTools" + uuid.uuid4().hex
    body = bytearray()
    for name, value in fields.items():
        body += (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n"
            f"Content-Type: application/json\r\n\r\n"
        ).encode()
        body += value.encode() + b"\r\n"
    for name, (filename, data) in files.items():
        body += (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{filename}\"\r\n"
            f"Content-Type: application/zip\r\n\r\n"
        ).encode()
        body += data + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return bytes(body), f"multipart/form-data; boundary={boundary}"


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    project, meta_path, zip_path = sys.argv[1:4]
    url = sys.argv[4] if len(sys.argv) > 4 else f"https://wow.curseforge.com/api/projects/{project}/upload-file"
    # a secret pasted with a trailing newline would otherwise break the header (and, sent by
    # curl, confuses CurseForge into "Missing field metadata")
    token = os.environ.get("CF_API_KEY", "").strip()

    with open(meta_path, "rb") as f:
        metadata = json.dumps(json.load(f))   # validates the JSON and compacts it
    with open(zip_path, "rb") as f:
        data = f.read()

    body, content_type = multipart({"metadata": metadata}, {"file": (os.path.basename(zip_path), data)})
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", content_type)
    req.add_header("Content-Length", str(len(body)))
    req.add_header("User-Agent", "MintCommunityTools-release/1.0")
    if token:
        req.add_header("X-Api-Token", token)

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            status, text = resp.status, resp.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        status, text = e.code, e.read().decode(errors="replace")

    print(f"response {status}:")
    print(text[:2000])
    return 0 if status == 200 else 1


if __name__ == "__main__":
    sys.exit(main())
