# BaseFortify Integrations

A collection of official integration examples, OAuth2 workflows, and automation scripts for interacting with the **BaseFortify** External Attack Surface & Vulnerability Monitoring Platform.

This repository is designed for developers, security engineers, and SMB IT teams who want to automate asset discovery, vulnerability retrieval, and environment synchronization with BaseFortify.

<p align="center">
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/license-MIT-green.svg" /></a>
  <img src="https://img.shields.io/badge/python-3.10%2B-blue.svg" />
  <img src="https://img.shields.io/badge/status-active-success.svg" />
  <img src="https://img.shields.io/github/last-commit/axxemble/basefortify-integrations" />
</p>

---

## 🌐 Official Website

**https://basefortify.eu**

BaseFortify helps organizations stay continuously informed about vulnerabilities affecting their software stack and external attack surface — with minimal effort. The integrations in this repository allow you to extend BaseFortify into your automation workflows, SIEM pipelines, CMDB systems, and custom tooling.

---

## 🚀 Features

- Python OAuth2 authentication examples  
- Scripts for retrieving nodes, components, and threats  
- Refresh-token handling and secure token storage patterns  
- Collectors for installed applications across Windows / Linux / macOS (planned)  
- Example workflows for automation and monitoring  
- Fully open-source under MIT license  

---

## 🧩 Repository Structure

```text
basefortify-integrations/
│
├─ examples/
│   └─ python/
│       ├─ authenticate.py
│       ├─ list_nodes.py
│       ├─ list_components.py
│       ├─ list_threats.py
│
└─ collectors/
    ├─ windows/
    ├─ linux/
    └─ macos/
```

This structure is intentionally modular so users can easily drop scripts into CI pipelines or local automation jobs.

---

## 🔐 OAuth2 Overview

BaseFortify provides standards-compliant OAuth2 integration through:

    Authorization Code Grant

    Refresh Token Grant

Key endpoints include (paths shown relative to the API base):

    POST /api/v1/auth/authorize – obtain authorization codes

    POST /api/v1/auth/token – exchange codes or refresh tokens

    GET /api/v1/auth/profile – introspect the active user or token

    Resource endpoints under:

        /api/v1/nodes

        /api/v1/components

        /api/v1/threats

Base URL (for examples):

https://api.basefortify.eu/api/v1

Always check the live API documentation for the latest paths and parameters.

---

## Authorization Code Flow (Simplified)

```
Client App  →  /auth/authorize  →  Authorization Code
Auth Code   →  /auth/token      →  Access Token + Refresh Token
Tokens      →  /nodes, /components, /threats  →  Protected Resources
```

---

## 🐍 Python Quickstart

Create a virtual environment and install dependencies:

```
python3 -m venv venv
source venv/bin/activate
pip install requests python-dotenv
```

Create a `.env` file in the project root:

```
CLIENT_ID=your_client_id
CLIENT_SECRET=your_client_secret
REDIRECT_URI=https://localhost/callback
AUTH_URL=https://api.basefortify.eu/api/v1/auth/authorize
TOKEN_URL=https://api.basefortify.eu/api/v1/auth/token
API_BASE=https://api.basefortify.eu/api/v1
```

Adjust these values according to your actual client registration and environment.

---

## 🔑 authenticate.py (Interactive Example)

```python
import os
import webbrowser
from urllib.parse import urlencode

import requests
from dotenv import load_dotenv

load_dotenv()

AUTH_URL = os.getenv("AUTH_URL")
TOKEN_URL = os.getenv("TOKEN_URL")
CLIENT_ID = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")
REDIRECT_URI = os.getenv("REDIRECT_URI", "https://localhost/callback")


def main():
    # Step 1: Redirect user to BaseFortify login/consent screen
    params = {
        "response_type": "code",
        "client_id": CLIENT_ID,
        "redirect_uri": REDIRECT_URI,
        "scope": "openid profile",
    }
    auth_link = AUTH_URL + "?" + urlencode(params)
    print("Open this URL in your browser:")
    print(auth_link)
    webbrowser.open(auth_link)

    # Step 2: User logs in and is redirected to REDIRECT_URI with ?code=...
    code = input(
        "Enter the 'code' query parameter from the redirected URL: "
    ).strip()

    # Step 3: Exchange the authorization code for access + refresh token
    token_data = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": REDIRECT_URI,
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    }

    resp = requests.post(TOKEN_URL, data=token_data)
    resp.raise_for_status()
    tokens = resp.json()

    print("\nReceived tokens:")
    print(tokens)


if __name__ == "__main__":
    main()
```

---

## 📡 Example: list_nodes.py

```python
import os

import requests
from dotenv import load_dotenv

load_dotenv()

API_BASE = os.getenv("API_BASE", "https://api.basefortify.eu/api/v1")
ACCESS_TOKEN = os.getenv("ACCESS_TOKEN")  # set this after authentication


def main():
    if not ACCESS_TOKEN:
        raise SystemExit("Please set ACCESS_TOKEN in your .env file")

    headers = {
        "Authorization": f"Bearer {ACCESS_TOKEN}",
    }

    resp = requests.get(f"{API_BASE}/nodes", headers=headers)
    resp.raise_for_status()
    data = resp.json()

    print("Nodes:")
    print(data)


if __name__ == "__main__":
    main()
```

---

## 🗺️ Planned Additions

The following content is planned for this repository:

    Collectors

        Windows: installed software via registry / PowerShell

        Linux: packages via dpkg, rpm, or pacman

        macOS: Homebrew & system profiler

    Integration Examples

        Creating tickets in Jira / ServiceNow based on BaseFortify threats

        Sending events to SIEM (e.g., Splunk, Elastic, Sentinel)

        Generating summary reports or dashboards

    Automation Patterns

        Scheduled sync of components and nodes

        Alert routing based on severity / vendor

        CI/CD hooks for new deployments

---

## 📄 License

This repository is licensed under the MIT License.

You are free to use, modify, and integrate these examples in both commercial and private projects, subject to the terms of the MIT license.

---

## 🌍 Official Links

    🌐 Website: https://basefortify.eu

📘 API Reference (OpenAPI spec): https://api.basefortify.eu/api/v1/auth/openapi.yaml

✉️ Contact: mailto:support@basefortify.eu

<p align="center"> <strong>Build powerful automations with BaseFortify.</strong><br> Easily integrate. Effortlessly secure. </p>
