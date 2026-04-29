from __future__ import annotations

import asyncio
import base64
import io
import json
import zipfile
from typing import Any

import httpx

from .config import MinerUSettings


class MinerUError(RuntimeError):
    pass


class MinerUClient:
    def __init__(self, settings: MinerUSettings) -> None:
        self.settings = settings

    async def parse_reference_pdf(self, file_data_base64: str, file_name: str) -> dict[str, str]:
        if not self.settings.configured:
            raise MinerUError("MinerU is not configured on the backend.")
        try:
            data = base64.b64decode(file_data_base64, validate=True)
        except Exception as error:
            raise MinerUError("The uploaded reference PDF payload is not valid base64.") from error
        if len(data) > 10 * 1024 * 1024:
            raise MinerUError("The reference lesson-plan PDF is larger than 10MB and cannot be processed right now.")

        batch_id = await self._submit(data, file_name)
        return await self._poll(batch_id)

    async def _submit(self, data: bytes, file_name: str) -> str:
        payload = {
            "enable_formula": self.settings.enable_formula,
            "enable_table": self.settings.enable_table,
            "language": self.settings.language,
            "model_version": self.settings.model_version,
            "files": [
                {
                    "name": file_name,
                    "is_ocr": self.settings.enable_ocr,
                    "data_id": file_name,
                }
            ],
        }
        async with httpx.AsyncClient(timeout=180) as client:
            response = await client.post(
                self.settings.apply_upload_url,
                headers=self._headers(),
                json=payload,
            )
        if response.status_code < 200 or response.status_code >= 300:
            raise MinerUError(response.text.strip() or f"HTTP {response.status_code}")
        raw = response.json()
        batch_id = _string_at(raw, [["data", "batch_id"], ["data", "batchId"], ["batch_id"], ["batchId"]])
        upload_url = _string_at(
            raw,
            [
                ["data", "file_urls", "0"],
                ["data", "file_urls", "0", "url"],
                ["data", "file_urls", "0", "upload_url"],
                ["file_urls", "0"],
                ["file_urls", "0", "url"],
                ["file_urls", "0", "upload_url"],
            ],
        )
        if not batch_id or not upload_url:
            raise MinerUError(_string_at(raw, [["message"], ["msg"], ["detail"]]) or "Invalid MinerU upload response.")
        async with httpx.AsyncClient(timeout=180) as client:
            upload_response = await client.put(upload_url, content=data)
        if upload_response.status_code < 200 or upload_response.status_code >= 300:
            raise MinerUError("Failed to upload the reference PDF to MinerU.")
        return batch_id

    async def _poll(self, batch_id: str) -> dict[str, str]:
        last_raw = ""
        for _ in range(self.settings.max_polling_attempts):
            async with httpx.AsyncClient(timeout=120) as client:
                response = await client.get(
                    self.settings.batch_result_url_prefix.rstrip("/") + "/" + batch_id,
                    headers=self._headers(),
                )
            if response.status_code < 200 or response.status_code >= 300:
                raise MinerUError(response.text.strip() or f"HTTP {response.status_code}")
            raw = response.json()
            last_raw = json.dumps(raw, ensure_ascii=False)
            state = (
                _string_at(
                    raw,
                    [
                        ["data", "state"],
                        ["data", "status"],
                        ["data", "extract_result", "0", "state"],
                        ["data", "extract_result", "0", "status"],
                        ["state"],
                        ["status"],
                    ],
                )
                or ""
            ).lower()
            if state in {"failed", "error", "cancelled", "canceled"}:
                raise MinerUError(_string_at(raw, [["data", "err_msg"], ["data", "message"], ["message"]]) or last_raw)
            if not state or state in {"done", "success", "succeeded", "completed", "finished"}:
                markdown = await self._extract_markdown(raw)
                if markdown.strip():
                    return {
                        "task_id": batch_id,
                        "markdown": markdown,
                        "raw_result_json": last_raw,
                    }
            await asyncio.sleep(self.settings.polling_interval_seconds)
        raise MinerUError("Timed out while waiting for the reference lesson plan to finish processing.")

    async def _extract_markdown(self, raw: dict[str, Any]) -> str:
        inline = _string_at(raw, [["data", "full_md"], ["data", "markdown"], ["data", "content"], ["markdown"], ["content"]])
        if inline:
            return inline
        url = _string_at(
            raw,
            [
                ["data", "full_md_link"],
                ["data", "full_md_url"],
                ["data", "markdown_url"],
                ["data", "md_url"],
                ["data", "result", "full_md_link"],
                ["data", "result", "full_md_url"],
                ["full_md_link"],
                ["markdown_url"],
            ],
        )
        if url:
            return await _download_text(url)
        archive_url = _string_at(
            raw,
            [
                ["data", "extract_result", "0", "full_zip_url"],
                ["data", "extract_result", "0", "zip_url"],
                ["data", "full_zip_url"],
                ["full_zip_url"],
            ],
        )
        if archive_url:
            return await _download_markdown_from_zip(archive_url)
        raise MinerUError("The reference lesson plan was processed, but no usable content was extracted.")

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.settings.api_token}",
            "Content-Type": "application/json",
        }


async def _download_text(url: str) -> str:
    async with httpx.AsyncClient(timeout=120) as client:
        response = await client.get(url)
    if response.status_code < 200 or response.status_code >= 300:
        raise MinerUError("Failed to download extracted markdown.")
    text = response.text.strip()
    if not text:
        raise MinerUError("The extracted markdown is empty.")
    return text


async def _download_markdown_from_zip(url: str) -> str:
    async with httpx.AsyncClient(timeout=120) as client:
        response = await client.get(url)
    if response.status_code < 200 or response.status_code >= 300:
        raise MinerUError("No readable archive was found in the reference lesson-plan result.")
    with zipfile.ZipFile(io.BytesIO(response.content)) as archive:
        names = sorted(archive.namelist(), key=lambda item: (not item.lower().endswith("full.md"), item))
        for name in names:
            if name.lower().endswith(".md"):
                text = archive.read(name).decode("utf-8").strip()
                if text:
                    return text
    raise MinerUError("The reference lesson plan was processed, but no usable content was extracted.")


def _object_at(raw: Any, path: list[str]) -> Any:
    current = raw
    for key in path:
        if isinstance(current, dict):
            current = current.get(key)
        elif isinstance(current, list) and key.isdigit() and int(key) < len(current):
            current = current[int(key)]
        else:
            return None
    return current


def _string_at(raw: Any, candidates: list[list[str]]) -> str:
    for path in candidates:
        value = _object_at(raw, path)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""

