"""
title: Image OCR
description: Replaces images in a chat with text read by an OCR model on llama-swap, so a text-only model can use them.
version: 0.1.0
"""

# Open WebUI filter function (Admin Panel -> Functions, ID image_ocr), attached
# to the Household model. Open WebUI only runs Python here; keep it small.

import base64
import hashlib
import inspect
import os
import re

import aiohttp
from pydantic import BaseModel, Field


class Filter:
    class Valves(BaseModel):
        priority: int = Field(default=0)
        base_url: str = Field(default="http://helarctos:8080/v1")
        api_key: str = Field(
            default="",
            description="Blank: use the container's OPENAI_API_KEY (the llama-swap key).",
        )
        model: str = Field(default="glm-ocr")
        prompt: str = Field(
            default="Text Recognition:",
            description="The OCR model's fixed task prompt: 'Text Recognition:' for glm-ocr, 'OCR:' for paddleocr-vl.",
        )
        max_tokens: int = Field(default=4096)
        timeout: int = Field(default=120)

    def __init__(self):
        self.valves = self.Valves()
        # Image hash -> text. The chat keeps its images, so every turn sends
        # them again; this avoids re-reading them. Lost on restart.
        self.cache = {}

    async def inlet(self, body: dict, __event_emitter__=None) -> dict:
        for message in body.get("messages", []):
            content = message.get("content")
            if not isinstance(content, list):
                continue
            texts = []
            for part in content:
                if part.get("type") == "image_url":
                    url = (part.get("image_url") or {}).get("url", "")
                    texts.append(await self._read(url, __event_emitter__))
                elif part.get("type") == "text":
                    texts.append(part.get("text", ""))
            message["content"] = "\n\n".join(t for t in texts if t)
        return body

    async def _read(self, url: str, emit) -> str:
        key = hashlib.sha256(url.encode()).hexdigest()
        if key not in self.cache:
            await self._status(emit, f"Reading image with {self.valves.model}", False)
            try:
                data_url = url if url.startswith("data:") else await self._data_url(url)
                text = await self._ocr(data_url)
            except Exception as e:
                await self._status(emit, f"OCR failed: {e}", True)
                return f"[An image was attached, but OCR failed: {e}]"
            if len(self.cache) >= 200:
                self.cache.pop(next(iter(self.cache)))
            self.cache[key] = text
            await self._status(emit, "Image read", True)
        return (
            f"[Text read from an attached image by OCR ({self.valves.model}); it may contain errors:]\n"
            f"{self.cache[key]}\n[End of image text]"
        )

    async def _ocr(self, data_url: str) -> str:
        api_key = self.valves.api_key or os.environ.get("OPENAI_API_KEY", "")
        payload = {
            "model": self.valves.model,
            "temperature": 0,
            "max_tokens": self.valves.max_tokens,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": self.valves.prompt},
                        {"type": "image_url", "image_url": {"url": data_url}},
                    ],
                }
            ],
        }
        timeout = aiohttp.ClientTimeout(total=self.valves.timeout)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.post(
                f"{self.valves.base_url.rstrip('/')}/chat/completions",
                json=payload,
                headers={"Authorization": f"Bearer {api_key}"},
            ) as response:
                if response.status != 200:
                    detail = (await response.text())[:200]
                    raise RuntimeError(f"{self.valves.model} returned HTTP {response.status}: {detail}")
                data = await response.json()
        return data["choices"][0]["message"]["content"].strip()

    async def _data_url(self, url: str) -> str:
        # Fallback for an image passed as an Open WebUI file link rather than
        # base64. Uses Open WebUI internals; check after upgrades.
        match = re.search(r"/files/([0-9a-fA-F-]{36})", url)
        if not match:
            raise RuntimeError(f"unsupported image URL {url[:80]}")
        from open_webui.models.files import Files
        from open_webui.storage.provider import Storage

        file = Files.get_file_by_id(match.group(1))
        if inspect.isawaitable(file):
            file = await file
        if file is None:
            raise RuntimeError("image file not found")
        path = Storage.get_file(file.path)
        if inspect.isawaitable(path):
            path = await path
        with open(path, "rb") as f:
            data = base64.b64encode(f.read()).decode()
        mime = (file.meta or {}).get("content_type") or "image/png"
        return f"data:{mime};base64,{data}"

    @staticmethod
    async def _status(emit, description: str, done: bool):
        if emit:
            await emit({"type": "status", "data": {"description": description, "done": done}})
