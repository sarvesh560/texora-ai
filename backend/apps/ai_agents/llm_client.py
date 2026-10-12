"""
LLM Provider Abstraction for Texora AI Autonomous Agents.
Supports Google Gemini, OpenAI, Anthropic, and Mock providers with structured JSON output,
retries, timeout protection, latency measurement, and unconfigured-state detection.
"""
import os
import json
import time
import logging
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, Tuple
from dataclasses import dataclass, asdict
import requests

logger = logging.getLogger(__name__)


@dataclass
class LLMResponse:
    content: str
    structured_json: Optional[Dict[str, Any]]
    token_count: int
    latency_ms: int
    provider: str
    model: str
    status: str  # 'SUCCESS', 'ERROR', 'UNCONFIGURED'
    error_message: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class BaseLLMProvider(ABC):
    """Abstract base class for all LLM inference providers."""

    def __init__(self, model_name: str, timeout: int = 25, max_retries: int = 2):
        self.model_name = model_name
        self.timeout = timeout
        self.max_retries = max_retries

    @abstractmethod
    def is_configured(self) -> bool:
        """Returns True if the required API keys or endpoints are configured."""
        pass

    @abstractmethod
    def generate_structured(
        self, system_prompt: str, user_prompt: str, schema_description: Optional[str] = None
    ) -> LLMResponse:
        """Generates a structured JSON completion conforming to the requested schema."""
        pass


class MockLLMProvider(BaseLLMProvider):
    """
    Deterministic Mock LLM Provider for unit testing, offline CI/CD, and simulated drills.
    Produces valid structured industrial machine diagnostics without making external network calls.
    """

    def __init__(self, model_name: str = "mock-industrial-v1", custom_response: Optional[Dict[str, Any]] = None):
        super().__init__(model_name=model_name, timeout=5, max_retries=0)
        self.custom_response = custom_response

    def is_configured(self) -> bool:
        return True

    def generate_structured(
        self, system_prompt: str, user_prompt: str, schema_description: Optional[str] = None
    ) -> LLMResponse:
        start_time = time.time()
        
        if self.custom_response:
            payload = self.custom_response
        else:
            payload = {
                "incident_id": 1,
                "machine_code": "WEV-AJ-02",
                "observed_abnormal_conditions": [
                    "Main drive shaft vibration elevated above critical limit (7.29 mm/s vs 5.8 mm/s threshold)",
                    "Minor bearing temperature elevation (52.4 °C within warning range)"
                ],
                "verified_sensor_facts": [
                    "Vibration amplitude: 7.29 mm/s RMS",
                    "Operating speed: 850 RPM (Nominal)",
                    "Active electrical power: 48.2 kW"
                ],
                "possible_root_causes": [
                    {
                        "hypothesis": "Drive shaft rolling element bearing cage deterioration or race flaking",
                        "likelihood": "HIGH",
                        "confidence_score": 92.5
                    },
                    {
                        "hypothesis": "Timing belt tensioner misalignment or harmonic resonance",
                        "likelihood": "MEDIUM",
                        "confidence_score": 68.0
                    }
                ],
                "missing_information": [
                    "Lubrication grease analysis / particulate count",
                    "Acoustic ultrasonic emission spectrum"
                ],
                "recommended_maintenance_checks": [
                    "Inspect drive end bearing 6204-2RS for mechanical play and flaking",
                    "Verify belt tension and pulley alignment with dial indicator",
                    "Replenish synthetic high-temperature bearing grease"
                ],
                "production_impact_considerations": [
                    "Active batch BATCH-WEV-DENIM-01 at risk of fabric streak defects",
                    "Estimated repair downtime: 1.5 hours"
                ],
                "severity_assessment": "CRITICAL",
                "confidence_explanation": "Vibration levels are 1.82x critical threshold with sustained high RMS while motor current is stable, strongly pointing to mechanical bearing flaking.",
                "suggested_next_actions": [
                    {
                        "action_type": "CREATE_MAINTENANCE_DRAFT",
                        "description": "Create priority maintenance ticket for Loom Drive Bearing inspection",
                        "requires_human_approval": True,
                        "payload": {
                            "priority": "HIGH",
                            "fault_category": "MECHANICAL_BEARING",
                            "estimated_hours": 1.5,
                            "required_parts": ["SPR-BRG-6204"]
                        }
                    }
                ]
            }

        latency_ms = int((time.time() - start_time) * 1000)
        content_str = json.dumps(payload, indent=2)
        return LLMResponse(
            content=content_str,
            structured_json=payload,
            token_count=len(content_str) // 4,
            latency_ms=latency_ms,
            provider="mock",
            model=self.model_name,
            status="SUCCESS",
        )


class GeminiProvider(BaseLLMProvider):
    """
    Google Gemini API Provider using direct REST endpoints.
    Enforces JSON structured response format and handles API key verification.
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        model_name: Optional[str] = None,
        timeout: int = 25,
        max_retries: int = 2,
    ):
        resolved_model = model_name or os.getenv("GEMINI_MODEL", "gemini-3.5-flash")
        super().__init__(model_name=resolved_model, timeout=timeout, max_retries=max_retries)
        self.api_key = api_key if api_key is not None else os.getenv("GEMINI_API_KEY", "").strip()

    def is_configured(self) -> bool:
        return bool(self.api_key)

    def generate_structured(
        self, system_prompt: str, user_prompt: str, schema_description: Optional[str] = None
    ) -> LLMResponse:
        # Normalize model name (remove 'models/' prefix if present)
        target_model = self.model_name.replace("models/", "").strip() or os.getenv("GEMINI_MODEL", "gemini-3.5-flash")

        if not self.is_configured():
            return LLMResponse(
                content="",
                structured_json=None,
                token_count=0,
                latency_ms=0,
                provider="gemini",
                model=target_model,
                status="UNCONFIGURED",
                error_message="Google Gemini API key not configured. Set GEMINI_API_KEY in environment or .env file.",
            )

        logger.info("Executing Gemini API inference using model: '%s' (timeout: %ds)", target_model, self.timeout)

        endpoint = (
            f"https://generativelanguage.googleapis.com/v1beta/models/{target_model}:generateContent"
            f"?key={self.api_key}"
        )

        headers = {"Content-Type": "application/json"}
        payload = {
            "contents": [
                {
                    "role": "user",
                    "parts": [{"text": f"SYSTEM INSTRUCTIONS:\n{system_prompt}\n\nUSER QUERY & EVIDENCE:\n{user_prompt}"}],
                }
            ],
            "generationConfig": {
                "temperature": 0.2,
                "responseMimeType": "application/json",
            },
        }

        start_time = time.time()
        last_error = ""

        for attempt in range(self.max_retries + 1):
            try:
                res = requests.post(endpoint, headers=headers, json=payload, timeout=self.timeout)
                latency_ms = int((time.time() - start_time) * 1000)

                if res.status_code == 200:
                    data = res.json()
                    candidates = data.get("candidates", [])
                    if candidates:
                        parts = candidates[0].get("content", {}).get("parts", [])
                        if parts:
                            raw_text = parts[0].get("text", "").strip()
                            # Clean markdown code fences if present
                            if raw_text.startswith("```"):
                                cleaned = raw_text.strip("`")
                                if cleaned.lower().startswith("json"):
                                    cleaned = cleaned[4:].strip()
                                raw_text = cleaned

                            try:
                                parsed_json = json.loads(raw_text)
                            except json.JSONDecodeError:
                                # Extract outermost JSON object if trailing text exists
                                first_brace = raw_text.find("{")
                                if first_brace != -1:
                                    decoder = json.JSONDecoder()
                                    parsed_json, end_idx = decoder.raw_decode(raw_text[first_brace:])
                                    raw_text = raw_text[first_brace : first_brace + end_idx]
                                else:
                                    raise

                            if not isinstance(parsed_json, dict):
                                raise ValueError("Gemini response is not a valid JSON object dictionary.")

                            usage = data.get("usageMetadata", {})
                            token_count = usage.get("totalTokenCount", len(raw_text) // 4)

                            return LLMResponse(
                                content=raw_text,
                                structured_json=parsed_json,
                                token_count=token_count,
                                latency_ms=latency_ms,
                                provider="gemini",
                                model=target_model,
                                status="SUCCESS",
                            )
                    last_error = f"Gemini returned empty candidate response on model '{target_model}'."
                elif res.status_code == 429 or "RESOURCE_EXHAUSTED" in res.text:
                    try:
                        err_msg = res.json().get("error", {}).get("message", "Quota / Rate limit exceeded")
                    except Exception:
                        err_msg = "HTTP 429 Quota / Rate limit exceeded"
                    last_error = f"Gemini ({target_model}) HTTP 429: {err_msg}"
                    logger.warning("[GeminiProvider] Quota/Rate limit exceeded (HTTP 429). Fast-failover to deterministic fallback.")
                    # Bounded fast-failover: Do not repeat quota-exhausted requests in retry loop
                    return LLMResponse(
                        content="",
                        structured_json=None,
                        token_count=0,
                        latency_ms=latency_ms,
                        provider="gemini",
                        model=target_model,
                        status="RATE_LIMITED",
                        error_message=last_error,
                    )
                else:
                    try:
                        err_msg = res.json().get("error", {}).get("message", res.text[:300])
                    except Exception:
                        err_msg = res.text[:300]
                    last_error = f"Gemini ({target_model}) HTTP {res.status_code}: {err_msg}"
                    logger.warning("Gemini API call failed (attempt %d/%d): %s", attempt + 1, self.max_retries + 1, last_error)

            except json.JSONDecodeError as exc:
                last_error = f"Failed to parse LLM JSON response from model '{target_model}': {str(exc)}"
                logger.error("JSON decode error from Gemini: %s", last_error)
            except Exception as exc:
                last_error = f"Gemini request exception for model '{target_model}': {str(exc)}"
                logger.warning("Gemini network error (attempt %d/%d): %s", attempt + 1, self.max_retries + 1, last_error)

            if attempt < self.max_retries:
                time.sleep(1.0 * (attempt + 1))

        latency_ms = int((time.time() - start_time) * 1000)
        return LLMResponse(
            content="",
            structured_json=None,
            token_count=0,
            latency_ms=latency_ms,
            provider="gemini",
            model=target_model,
            status="ERROR",
            error_message=last_error,
        )


class OpenAIProvider(BaseLLMProvider):
    """
    OpenAI-compatible API Provider supporting structured JSON mode.
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        model_name: str = "gpt-4o-mini",
        base_url: str = "https://api.openai.com/v1",
        timeout: int = 25,
        max_retries: int = 2,
    ):
        super().__init__(model_name=model_name, timeout=timeout, max_retries=max_retries)
        self.api_key = api_key if api_key is not None else os.getenv("OPENAI_API_KEY", "").strip()
        self.base_url = base_url

    def is_configured(self) -> bool:
        return bool(self.api_key)

    def generate_structured(
        self, system_prompt: str, user_prompt: str, schema_description: Optional[str] = None
    ) -> LLMResponse:
        if not self.is_configured():
            return LLMResponse(
                content="",
                structured_json=None,
                token_count=0,
                latency_ms=0,
                provider="openai",
                model=self.model_name,
                status="UNCONFIGURED",
                error_message="OpenAI API key not configured. Set OPENAI_API_KEY in environment or .env file.",
            )

        endpoint = f"{self.base_url}/chat/completions"
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.api_key}",
        }
        payload = {
            "model": self.model_name,
            "temperature": 0.2,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
        }

        start_time = time.time()
        last_error = ""

        for attempt in range(self.max_retries + 1):
            try:
                res = requests.post(endpoint, headers=headers, json=payload, timeout=self.timeout)
                latency_ms = int((time.time() - start_time) * 1000)

                if res.status_code == 200:
                    data = res.json()
                    choices = data.get("choices", [])
                    if choices:
                        raw_text = choices[0].get("message", {}).get("content", "").strip()
                        if raw_text.startswith("```"):
                            cleaned = raw_text.strip("`")
                            if cleaned.lower().startswith("json"):
                                cleaned = cleaned[4:].strip()
                            raw_text = cleaned
                        try:
                            parsed_json = json.loads(raw_text)
                        except json.JSONDecodeError:
                            first_brace = raw_text.find("{")
                            if first_brace != -1:
                                decoder = json.JSONDecoder()
                                parsed_json, end_idx = decoder.raw_decode(raw_text[first_brace:])
                                raw_text = raw_text[first_brace : first_brace + end_idx]
                            else:
                                raise
                        usage = data.get("usage", {})
                        token_count = usage.get("total_tokens", len(raw_text) // 4)

                        return LLMResponse(
                            content=raw_text,
                            structured_json=parsed_json,
                            token_count=token_count,
                            latency_ms=latency_ms,
                            provider="openai",
                            model=self.model_name,
                            status="SUCCESS",
                        )
                    last_error = "OpenAI returned empty choices."
                else:
                    last_error = f"OpenAI HTTP {res.status_code}: {res.text[:300]}"
            except Exception as exc:
                last_error = f"OpenAI request exception: {str(exc)}"

            if attempt < self.max_retries:
                time.sleep(1.0 * (attempt + 1))

        latency_ms = int((time.time() - start_time) * 1000)
        return LLMResponse(
            content="",
            structured_json=None,
            token_count=0,
            latency_ms=latency_ms,
            provider="openai",
            model=self.model_name,
            status="ERROR",
            error_message=last_error,
        )


def get_llm_provider(force_provider: Optional[str] = None) -> BaseLLMProvider:
    """
    Factory creating the configured LLM inference provider.
    Reads LLM_PROVIDER from environment ('gemini', 'openai', 'mock').
    """
    provider_type = (force_provider or os.getenv("LLM_PROVIDER", "gemini")).lower().strip()
    timeout = int(os.getenv("LLM_TIMEOUT_SECONDS", "25"))
    retries = int(os.getenv("LLM_MAX_RETRIES", "2"))

    if provider_type in ["mock", "fallback", "deterministic_fallback"]:
        return MockLLMProvider()
    elif provider_type == "openai":
        model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
        return OpenAIProvider(model_name=model, timeout=timeout, max_retries=retries)
    elif provider_type == "gemini":
        model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash")
        return GeminiProvider(model_name=model, timeout=timeout, max_retries=retries)
    else:
        # Default fallback to Gemini
        model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash")
        return GeminiProvider(model_name=model, timeout=timeout, max_retries=retries)
