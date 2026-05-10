"""TestFlight uploader — wraps `xcrun altool` (and the modern Transporter)
so the swarm can promote a freshly built `.ipa` straight to TestFlight.

Required environment / config:

    APPLE_ID                    — the Apple ID email
    APP_SPECIFIC_PASSWORD       — generated at appleid.apple.com → Sign-In and Security
    or
    ASC_API_KEY_ID              — App Store Connect API key id
    ASC_API_KEY_ISSUER_ID       — issuer id
    ASC_API_KEY_PATH            — path to the .p8 private key inside the workspace

We prefer the ASC API key flow when available (no app-specific password,
no 2FA prompts). Fall back to user/password otherwise.

This tool is intentionally NOT registered in the default tool registry —
the orchestrator opts it in only for jobs that have reached the
`shipping` stage. That keeps the blast radius small.
"""
from __future__ import annotations

import os
import shlex
from typing import Any

from .base import Tool, ToolContext
from ..sandbox import Sandbox


class TestFlightUpload(Tool):
    name = "testflight_upload"
    description = (
        "Validate, then upload an .ipa to TestFlight. Returns the build "
        "id so the caller can poll App Store Connect for processing."
    )

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "ipa_path":   {"type": "string", "description": "Workspace-relative path to the .ipa"},
                "validate":   {"type": "boolean", "default": True, "description": "Run `altool --validate-app` before uploading."},
                "asc_api_key_id":     {"type": "string"},
                "asc_api_issuer_id":  {"type": "string"},
                "asc_api_key_path":   {"type": "string"},
                "apple_id":             {"type": "string"},
                "app_specific_password": {"type": "string"},
                "platform":             {"type": "string", "enum": ["ios", "macos", "tvos"], "default": "ios"},
            },
            "required": ["ipa_path"],
            "additionalProperties": False,
        }

    async def run(self, args: dict[str, Any], sandbox: Sandbox, ctx: ToolContext) -> str:
        ipa = sandbox.safe_path(args["ipa_path"])
        if not ipa.exists():
            raise FileNotFoundError(f"ipa not found at {ipa}")
        platform = args.get("platform", "ios")

        creds_argv = self._auth_argv(args, sandbox)

        log: list[str] = [f"upload target: {ipa}"]

        if args.get("validate", True):
            validate = ["xcrun", "altool", "--validate-app", "-f", str(ipa), "-t", platform, *creds_argv]
            log.append("validate: " + _shell(validate))
            v = await sandbox.run(validate)
            log.append(f"  exit={v.exit_code}")
            log.append(v.stdout[-3000:] if v.stdout else "")
            if not v.ok:
                raise RuntimeError(f"validate failed: {v.stderr.strip() or v.stdout.strip()}")

        upload = ["xcrun", "altool", "--upload-app", "-f", str(ipa), "-t", platform, *creds_argv]
        log.append("upload: " + _shell(upload))
        u = await sandbox.run(upload)
        log.append(f"  exit={u.exit_code}")
        log.append(u.stdout[-3000:] if u.stdout else "")
        if not u.ok:
            raise RuntimeError(f"upload failed: {u.stderr.strip() or u.stdout.strip()}")

        build_id = self._extract_build_id(u.stdout) or self._extract_build_id(u.stderr) or "unknown"
        log.append(f"build_id={build_id}")
        return "\n".join(log)

    # ----- internals -----

    def _auth_argv(self, args: dict[str, Any], sandbox: Sandbox) -> list[str]:
        """Prefer ASC API key (no 2FA) over Apple-ID + app-specific-password."""
        key_id = args.get("asc_api_key_id") or os.environ.get("ASC_API_KEY_ID")
        issuer = args.get("asc_api_issuer_id") or os.environ.get("ASC_API_KEY_ISSUER_ID")
        key_path = args.get("asc_api_key_path") or os.environ.get("ASC_API_KEY_PATH")

        if key_id and issuer and key_path:
            resolved = sandbox.safe_path(key_path)  # enforce sandbox boundary
            return [
                "--apiKey", key_id,
                "--apiIssuer", issuer,
                # altool finds the key by id but some setups want the file path.
                "--apiKeyPath", str(resolved),
            ]

        apple_id = args.get("apple_id") or os.environ.get("APPLE_ID", "")
        password = args.get("app_specific_password") or os.environ.get("APP_SPECIFIC_PASSWORD", "")
        if not apple_id or not password:
            raise RuntimeError(
                "no upload credentials — set ASC_API_KEY_* env vars or pass apple_id + app_specific_password"
            )
        return ["-u", apple_id, "-p", password]

    def _extract_build_id(self, text: str) -> str | None:
        # altool prints something like:
        #   "No errors uploading 'Build.ipa'"
        #   "Generated JWT in 13ms"
        #   "Asset received with id ABC123-..."
        for line in text.splitlines():
            if "id " in line.lower() and ("asset" in line.lower() or "build" in line.lower()):
                parts = line.rsplit(" ", 1)
                if len(parts) == 2 and len(parts[1]) > 6:
                    return parts[1].strip()
        return None


def _shell(argv: list[str]) -> str:
    """Render an argv as a shell-quoted command for logs (without secrets)."""
    redacted: list[str] = []
    skip_next = False
    for token in argv:
        if skip_next:
            redacted.append("…")
            skip_next = False
            continue
        if token in {"-p", "--password", "--apiKey", "--apiIssuer", "--apiKeyPath"}:
            redacted.append(token); skip_next = True; continue
        redacted.append(token)
    return " ".join(shlex.quote(t) for t in redacted)
