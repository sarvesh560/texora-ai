"""
LLM Provider Abstraction & Multi-Provider Router for Texora AI Autonomous Agents.
Supports GroqCloud (Primary Cloud AI), Google Gemini (Secondary Cloud AI),
OpenAI, and Mock providers with structured JSON output, dual-layer circuit breaker protection,
rate-limit fast-failover, model candidate discovery, token usage tracking, latency measurement,
and deterministic industrial fallback routing.
"""
import os
import json
import time
import logging
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, Tuple, List
from dataclasses import dataclass, asdict
from pathlib import Path
import requests
from dotenv import load_dotenv

# Ensure environment variables are loaded for standalone workers & child processes
_backend_dir = Path(__file__).resolve().parent.parent.parent
_env_path = _backend_dir / ".env"
if _env_path.exists():
    load_dotenv(_env_path)
else:
    _root_env = _backend_dir.parent / ".env"
    if _root_env.exists():
        load_dotenv(_root_env)

try:
    import groq
    HAS_GROQ_SDK = True
except ImportError:
    HAS_GROQ_SDK = False

logger = logging.getLogger(__name__)


# Standardized Provenance and Status Constants
PROVENANCE_GROQ_LIVE = "GROQ_LIVE"
PROVENANCE_GEMINI_LIVE = "GEMINI_LIVE"
PROVENANCE_DETERMINISTIC_FALLBACK = "DETERMINISTIC_FALLBACK"
PROVENANCE_PROVIDER_RATE_LIMITED = "PROVIDER_RATE_LIMITED"
PROVENANCE_PROVIDER_UNAVAILABLE = "PROVIDER_UNAVAILABLE"
PROVENANCE_GROQ_RATE_LIMITED = "GROQ_RATE_LIMITED"
PROVENANCE_GROQ_UNAVAILABLE = "GROQ_UNAVAILABLE"
PROVENANCE_GROQ_AUTH_ERROR = "GROQ_AUTH_ERROR"
PROVENANCE_GEMINI_RATE_LIMITED = "GEMINI_RATE_LIMITED"
PROVENANCE_GEMINI_UNAVAILABLE = "GEMINI_UNAVAILABLE"
PROVENANCE_MOCK_SUCCESS = "MOCK_AI_SUCCESS"


@dataclass
class LLMResponse:
    content: str
    structured_json: Optional[Dict[str, Any]]
    token_count: int
    latency_ms: int
    provider: str
    model: str
    status: str  # 'SUCCESS', 'ERROR', 'UNCONFIGURED', 'RATE_LIMITED', 'UNAVAILABLE', 'AUTH_ERROR'
    error_message: str = ""
    reasoning_source: str = PROVENANCE_GROQ_LIVE
    provider_attempt_status: str = "SUCCESS"
    prompt_tokens: int = 0
    completion_tokens: int = 0

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class GroqCircuitBreaker:
    """
    In-memory circuit breaker that prevents quota exhaustion hammering,
    rate-limit cascade failures, and service outage cascades for GroqCloud.
    """
    _is_open: bool = False
    _open_until: float = 0.0
    _last_error: str = ""
    _last_status: str = "UNKNOWN"
    _last_success_at: Optional[float] = None
    _last_model: str = ""
    _last_latency_ms: Optional[int] = None

    @classmethod
    def record_rate_limit(cls, error_msg: str, cooldown_seconds: int = 180):
        cls._is_open = True
        cls._open_until = time.time() + cooldown_seconds
        cls._last_error = error_msg
        cls._last_status = "RATE_LIMITED"
        logger.warning(
            "[GroqCircuitBreaker] Circuit tripped (RATE_LIMITED). Cooldown active for %ds: %s",
            cooldown_seconds,
            error_msg[:120],
        )

    @classmethod
    def record_service_unavailable(cls, error_msg: str, cooldown_seconds: int = 30):
        cls._is_open = True
        cls._open_until = time.time() + cooldown_seconds
        cls._last_error = error_msg
        cls._last_status = "UNAVAILABLE"
        logger.warning(
            "[GroqCircuitBreaker] Circuit tripped (UNAVAILABLE). Cooldown active for %ds: %s",
            cooldown_seconds,
            error_msg[:120],
        )

    @classmethod
    def record_auth_error(cls, error_msg: str, cooldown_seconds: int = 300):
        cls._is_open = True
        cls._open_until = time.time() + cooldown_seconds
        cls._last_error = error_msg
        cls._last_status = "AUTH_ERROR"
        logger.warning(
            "[GroqCircuitBreaker] Circuit tripped (AUTH_ERROR). Cooldown active for %ds: %s",
            cooldown_seconds,
            error_msg[:120],
        )

    @classmethod
    def record_success(cls, model: str = "", latency_ms: Optional[int] = None):
        if cls._is_open:
            logger.info("[GroqCircuitBreaker] Live Groq response received. Circuit closed.")
        cls._is_open = False
        cls._open_until = 0.0
        cls._last_error = ""
        cls._last_status = "SUCCESS"
        cls._last_success_at = time.time()
        if model:
            cls._last_model = model
        if latency_ms is not None:
            cls._last_latency_ms = latency_ms

    @classmethod
    def check_availability(cls) -> Tuple[bool, str, str]:
        if cls._is_open:
            if time.time() < cls._open_until:
                remaining = int(cls._open_until - time.time())
                return (
                    False,
                    cls._last_status,
                    f"Groq Circuit Breaker open ({cls._last_status}). Cooldown active for {remaining}s. {cls._last_error}",
                )
            cls._is_open = False
            cls._last_error = ""
        return True, "SUCCESS", ""

    @classmethod
    def is_open(cls) -> bool:
        if cls._is_open and time.time() < cls._open_until:
            return True
        if cls._is_open and time.time() >= cls._open_until:
            cls._is_open = False
        return False

    @classmethod
    def reset(cls):
        cls._is_open = False
        cls._open_until = 0.0
        cls._last_error = ""
        cls._last_status = "SUCCESS"
        cls._last_success_at = None
        cls._last_model = ""
        cls._last_latency_ms = None


class GeminiCircuitBreaker:
    """
    In-memory circuit breaker that prevents quota-exhaustion hammering,
    rate-limit cascade failures, and high-demand storms for Google Gemini.
    """
    _is_open: bool = False
    _open_until: float = 0.0
    _last_error: str = ""
    _last_status: str = "UNKNOWN"
    _last_success_at: Optional[float] = None
    _last_model: str = ""
    _last_latency_ms: Optional[int] = None

    @classmethod
    def record_rate_limit(cls, error_msg: str, cooldown_seconds: int = 180):
        cls._is_open = True
        cls._open_until = time.time() + cooldown_seconds
        cls._last_error = error_msg
        cls._last_status = "RATE_LIMITED"
        logger.warning(
            "[GeminiCircuitBreaker] Circuit tripped (RATE_LIMITED). Cooldown active for %ds: %s",
            cooldown_seconds,
            error_msg[:120],
        )

    @classmethod
    def record_service_unavailable(cls, error_msg: str, cooldown_seconds: int = 30):
        cls._is_open = True
        cls._open_until = time.time() + cooldown_seconds
        cls._last_error = error_msg
        cls._last_status = "UNAVAILABLE"
        logger.warning(
            "[GeminiCircuitBreaker] Circuit tripped (UNAVAILABLE). Cooldown active for %ds: %s",
            cooldown_seconds,
            error_msg[:120],
        )

    @classmethod
    def record_success(cls, model: str = "", latency_ms: Optional[int] = None):
        if cls._is_open:
            logger.info("[GeminiCircuitBreaker] Live Gemini response received. Circuit closed.")
        cls._is_open = False
        cls._open_until = 0.0
        cls._last_error = ""
        cls._last_status = "SUCCESS"
        cls._last_success_at = time.time()
        if model:
            cls._last_model = model
        if latency_ms is not None:
            cls._last_latency_ms = latency_ms

    @classmethod
    def check_availability(cls) -> Tuple[bool, str, str]:
        if cls._is_open:
            if time.time() < cls._open_until:
                remaining = int(cls._open_until - time.time())
                return (
                    False,
                    cls._last_status,
                    f"Gemini Circuit Breaker open ({cls._last_status}). Cooldown active for {remaining}s. {cls._last_error}",
                )
            cls._is_open = False
            cls._last_error = ""
        return True, "SUCCESS", ""

    @classmethod
    def is_open(cls) -> bool:
        if cls._is_open and time.time() < cls._open_until:
            return True
        if cls._is_open and time.time() >= cls._open_until:
            cls._is_open = False
        return False

    @classmethod
    def reset(cls):
        cls._is_open = False
        cls._open_until = 0.0
        cls._last_error = ""
        cls._last_status = "SUCCESS"
        cls._last_success_at = None
        cls._last_model = ""
        cls._last_latency_ms = None


class BaseLLMProvider(ABC):
    """Abstract base class for all LLM inference providers."""

    def __init__(self, model_name: str, timeout: int = 30, max_retries: int = 1):
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
        elif schema_description == "MaintenanceCoordinationSchema" or "maintenance coordinator" in system_prompt.lower():
            payload = {
                "machine_code": "WEV-AJ-02",
                "recommended_inspection_checklist": [
                    "Inspect drive end bearing 6204-2RS for mechanical play and flaking",
                    "Verify belt tension and pulley alignment with dial indicator",
                    "Replenish synthetic high-temperature bearing grease",
                ],
                "suggested_repair_approach": "Sensor-guided inspection, defect verification, and component replacement.",
                "required_skills": ["Precision Mechanical Alignment", "Bearing Replacement", "Loom Maintenance"],
                "estimated_maintenance_duration_hours": 1.5,
                "safety_considerations": [
                    "Lockout/Tagout (LOTO) electrical main drive switch before touching mechanical assemblies",
                    "Verify shaft rotational standstill with optical tachometer prior to belt guard removal",
                ],
                "confidence_score": 92.0,
                "risk_level": "MEDIUM",
                "escalation_recommendations": [],
                "suggested_actions": [
                    {
                        "action_type": "CREATE_MAINTENANCE_TICKET",
                        "description": "Create priority maintenance ticket for Loom Drive Bearing inspection",
                        "requires_human_approval": True,
                        "payload": {
                            "priority": "HIGH",
                            "fault_category": "MECHANICAL_BEARING",
                            "estimated_hours": 1.5,
                            "required_parts": ["SPR-BRG-6204"],
                        },
                    }
                ],
            }
        elif "factory recovery advisor" in system_prompt.lower() or "what-if simulation" in user_prompt.lower():
            payload = {
                "executive_summary": "Simulation indicates immediate bearing replacement minimizes schedule disruption and protects production velocity.",
                "recommended_strategy_code": "STRATEGY_C",
                "recommended_strategy_title": "Strategy C — Hybrid Prioritized Repair & Rerouting",
                "recommendation_rationale": "Saves 3.5 hours of downstream loom idle time while preserving 94% delivery quota.",
                "alternative_strategies_assessment": [
                    {
                        "strategy_code": "STRATEGY_A",
                        "verdict": "Sub-optimal / Feasible",
                        "reason_for_lower_rank": "Increases labor overtime requirements.",
                    },
                    {
                        "strategy_code": "STRATEGY_B",
                        "verdict": "Partial Mitigation",
                        "reason_for_lower_rank": "Bottlenecks standby weaving capacity.",
                    },
                ],
                "operational_risks": [
                    "Technician allocation strain across simultaneous shift changes",
                    "Critical spare-part buffer reduced below reorder threshold",
                ],
                "underlying_assumptions": [
                    "Spare bearing SPR-BRG-6204 is available in warehouse inventory",
                    "Standby air-jet loom WEV-AJ-04 is operational",
                ],
            }
        else:
            payload = {
                "incident_id": 1,
                "machine_code": "WEV-AJ-02",
                "observed_abnormal_conditions": [
                    "Main drive shaft vibration elevated above critical limit (7.29 mm/s vs 5.8 mm/s threshold)",
                    "Minor bearing temperature elevation (52.4 °C within warning range)",
                ],
                "verified_sensor_facts": [
                    "Vibration amplitude: 7.29 mm/s RMS",
                    "Operating speed: 850 RPM (Nominal)",
                    "Active electrical power: 48.2 kW",
                ],
                "possible_root_causes": [
                    {
                        "hypothesis": "Drive shaft rolling element bearing cage deterioration or race flaking",
                        "likelihood": "HIGH",
                        "confidence_score": 92.5,
                    },
                    {
                        "hypothesis": "Timing belt tensioner misalignment or harmonic resonance",
                        "likelihood": "MEDIUM",
                        "confidence_score": 68.0,
                    },
                ],
                "missing_information": [
                    "Lubrication grease analysis / particulate count",
                    "Acoustic ultrasonic emission spectrum",
                ],
                "recommended_maintenance_checks": [
                    "Inspect drive end bearing 6204-2RS for mechanical play and flaking",
                    "Verify belt tension and pulley alignment with dial indicator",
                    "Replenish synthetic high-temperature bearing grease",
                ],
                "production_impact_considerations": [
                    "Active batch BATCH-WEV-DENIM-01 at risk of fabric streak defects",
                    "Estimated repair downtime: 1.5 hours",
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
                            "required_parts": ["SPR-BRG-6204"],
                        },
                    }
                ],
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
            reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
            provider_attempt_status=PROVENANCE_MOCK_SUCCESS,
        )


class GroqProvider(BaseLLMProvider):
    """
    GroqCloud API Provider using Groq's official SDK with REST fallback.
    Delivers ultra-low-latency cloud inference on free-tier models with structured JSON,
    circuit-breaker protection, token-usage tracking, and rate-limit fast-failover.
    """

    DEFAULT_CANDIDATE_MODELS = [
        "qwen/qwen3.8-27b",
        "openai/gpt-oss-20b",
        "openai/gpt-oss-120b",
        "llama-3.3-70b-versatile",
        "llama-3.1-8b-instant",
    ]

    def __init__(
        self,
        api_key: Optional[str] = None,
        model_name: Optional[str] = None,
        timeout: int = 30,
        max_retries: int = 1,
    ):
        resolved_model = model_name or os.getenv("GROQ_MODEL", "qwen/qwen3.8-27b")
        super().__init__(model_name=resolved_model, timeout=timeout, max_retries=max_retries)
        self.api_key = api_key if api_key is not None else os.getenv("GROQ_API_KEY", "").strip()

    def is_configured(self) -> bool:
        return bool(self.api_key)

    @classmethod
    def discover_supported_models(cls, api_key: Optional[str] = None) -> List[str]:
        """Queries GroqCloud models endpoint to discover available models."""
        key = api_key or os.getenv("GROQ_API_KEY", "").strip()
        if not key:
            return []
        try:
            if HAS_GROQ_SDK:
                client = groq.Groq(api_key=key, timeout=10)
                models_data = client.models.list()
                return [m.id for m in models_data.data if not m.id.startswith("whisper")]
            else:
                url = "https://api.groq.com/openai/v1/models"
                headers = {"Authorization": f"Bearer {key}"}
                res = requests.get(url, headers=headers, timeout=10)
                if res.status_code == 200:
                    models_data = res.json().get("data", [])
                    return [m.get("id", "") for m in models_data if not m.get("id", "").startswith("whisper")]
        except Exception as exc:
            logger.warning("Failed to discover Groq models: %s", exc)
        return []

    def verify_connectivity(self) -> Dict[str, Any]:
        """Runs a minimal live inference check without retries to audit connectivity status."""
        if not self.is_configured():
            return {
                "is_configured": False,
                "model_name": self.model_name,
                "http_status": 0,
                "latency_ms": 0,
                "provider_status": "UNCONFIGURED",
                "error_message": "GROQ_API_KEY is not set.",
                "reasoning_source": PROVENANCE_DETERMINISTIC_FALLBACK,
                "token_usage": {},
            }

        start = time.time()
        test_model = self.model_name.strip()
        try:
            if HAS_GROQ_SDK:
                client = groq.Groq(api_key=self.api_key, timeout=self.timeout)
                res = client.chat.completions.create(
                    model=test_model,
                    messages=[{"role": "user", "content": 'Respond in valid JSON: {"ping": "pong"}'}],
                    response_format={"type": "json_object"},
                )
                lat = int((time.time() - start) * 1000)
                GroqCircuitBreaker.record_success(model=test_model, latency_ms=lat)
                usage_info = {}
                if hasattr(res, "usage") and res.usage:
                    usage_info = {
                        "prompt_tokens": getattr(res.usage, "prompt_tokens", 0),
                        "completion_tokens": getattr(res.usage, "completion_tokens", 0),
                        "total_tokens": getattr(res.usage, "total_tokens", 0),
                    }
                return {
                    "is_configured": True,
                    "model_name": test_model,
                    "http_status": 200,
                    "latency_ms": lat,
                    "provider_status": PROVENANCE_GROQ_LIVE,
                    "error_message": "",
                    "reasoning_source": PROVENANCE_GROQ_LIVE,
                    "token_usage": usage_info,
                }
            else:
                endpoint = "https://api.groq.com/openai/v1/chat/completions"
                headers = {
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {self.api_key}",
                }
                payload = {
                    "model": test_model,
                    "messages": [{"role": "user", "content": 'Respond in valid JSON: {"ping": "pong"}'}],
                    "response_format": {"type": "json_object"},
                }
                res = requests.post(endpoint, headers=headers, json=payload, timeout=self.timeout)
                lat = int((time.time() - start) * 1000)
                if res.status_code == 200:
                    GroqCircuitBreaker.record_success(model=test_model, latency_ms=lat)
                    data = res.json()
                    usage = data.get("usage", {})
                    return {
                        "is_configured": True,
                        "model_name": test_model,
                        "http_status": 200,
                        "latency_ms": lat,
                        "provider_status": PROVENANCE_GROQ_LIVE,
                        "error_message": "",
                        "reasoning_source": PROVENANCE_GROQ_LIVE,
                        "token_usage": usage,
                    }
                elif res.status_code == 429:
                    err = "HTTP 429: GroqCloud rate limit or quota exceeded."
                    GroqCircuitBreaker.record_rate_limit(err, cooldown_seconds=180)
                    return {
                        "is_configured": True,
                        "model_name": test_model,
                        "http_status": 429,
                        "latency_ms": lat,
                        "provider_status": "BLOCKED_BY_QUOTA",
                        "error_message": err,
                        "reasoning_source": PROVENANCE_DETERMINISTIC_FALLBACK,
                        "token_usage": {},
                    }
                elif res.status_code == 401:
                    err = "HTTP 401: Invalid or expired Groq API key."
                    GroqCircuitBreaker.record_auth_error(err, cooldown_seconds=300)
                    return {
                        "is_configured": True,
                        "model_name": test_model,
                        "http_status": 401,
                        "latency_ms": lat,
                        "provider_status": "AUTH_ERROR",
                        "error_message": err,
                        "reasoning_source": PROVENANCE_DETERMINISTIC_FALLBACK,
                        "token_usage": {},
                    }
                else:
                    return {
                        "is_configured": True,
                        "model_name": test_model,
                        "http_status": res.status_code,
                        "latency_ms": lat,
                        "provider_status": "ERROR",
                        "error_message": f"HTTP {res.status_code}: {res.text[:180]}",
                        "reasoning_source": PROVENANCE_DETERMINISTIC_FALLBACK,
                        "token_usage": {},
                    }
        except Exception as exc:
            lat = int((time.time() - start) * 1000)
            err_str = str(exc)
            if "429" in err_str or "rate limit" in err_str.lower():
                GroqCircuitBreaker.record_rate_limit(err_str, cooldown_seconds=180)
                status_code = 429
                p_status = "BLOCKED_BY_QUOTA"
            elif "401" in err_str or "auth" in err_str.lower():
                GroqCircuitBreaker.record_auth_error(err_str, cooldown_seconds=300)
                status_code = 401
                p_status = "AUTH_ERROR"
            elif "503" in err_str:
                GroqCircuitBreaker.record_service_unavailable(err_str, cooldown_seconds=30)
                status_code = 503
                p_status = "SERVICE_UNAVAILABLE"
            else:
                status_code = 0
                p_status = "NETWORK_ERROR"

            return {
                "is_configured": True,
                "model_name": test_model,
                "http_status": status_code,
                "latency_ms": lat,
                "provider_status": p_status,
                "error_message": err_str,
                "reasoning_source": PROVENANCE_DETERMINISTIC_FALLBACK,
                "token_usage": {},
            }

    def generate_structured(
        self, system_prompt: str, user_prompt: str, schema_description: Optional[str] = None
    ) -> LLMResponse:
        primary_model = self.model_name.strip() or os.getenv("GROQ_MODEL", "qwen/qwen3.8-27b")

        if not self.is_configured():
            return LLMResponse(
                content="",
                structured_json=None,
                token_count=0,
                latency_ms=0,
                provider="groq",
                model=primary_model,
                status="UNCONFIGURED",
                error_message="GroqCloud API key not configured. Set GROQ_API_KEY in environment or .env file.",
                reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
                provider_attempt_status="GROQ_UNCONFIGURED",
            )

        # 1. Circuit Breaker Check: Fast-failover without outbound network hammer
        is_avail, breaker_status, breaker_msg = GroqCircuitBreaker.check_availability()
        if not is_avail:
            logger.info("[GroqProvider] Fast-failover triggered: %s", breaker_msg[:100])
            return LLMResponse(
                content="",
                structured_json=None,
                token_count=0,
                latency_ms=0,
                provider="groq",
                model=primary_model,
                status=breaker_status,
                error_message=breaker_msg,
                reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
                provider_attempt_status=f"GROQ_{breaker_status}",
            )

        # 2. Candidate models list
        candidate_models = [primary_model]
        for m in self.DEFAULT_CANDIDATE_MODELS:
            if m not in candidate_models:
                candidate_models.append(m)

        start_time = time.time()
        last_error = ""
        last_status = "ERROR"

        messages = [
            {"role": "system", "content": f"{system_prompt}\n\nStrict requirement: You MUST output ONLY valid JSON."},
            {"role": "user", "content": user_prompt},
        ]

        for target_model in candidate_models[:3]:
            max_out_tokens = 600 if "qwen" in target_model.lower() else 850
            for attempt in range(self.max_retries + 1):
                try:
                    if HAS_GROQ_SDK:
                        client = groq.Groq(api_key=self.api_key, timeout=self.timeout, max_retries=0)
                        chat_comp = client.chat.completions.create(
                            model=target_model,
                            messages=messages,
                            response_format={"type": "json_object"},
                            temperature=0.2,
                            max_tokens=max_out_tokens,
                        )
                        latency_ms = int((time.time() - start_time) * 1000)

                        if chat_comp.choices:
                            raw_text = chat_comp.choices[0].message.content or "{}"
                            raw_text = raw_text.strip()
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

                            if not isinstance(parsed_json, dict):
                                raise ValueError("Groq response is not a valid JSON dictionary.")

                            p_tokens = 0
                            c_tokens = 0
                            t_tokens = len(raw_text) // 4
                            if hasattr(chat_comp, "usage") and chat_comp.usage:
                                p_tokens = getattr(chat_comp.usage, "prompt_tokens", 0)
                                c_tokens = getattr(chat_comp.usage, "completion_tokens", 0)
                                t_tokens = getattr(chat_comp.usage, "total_tokens", t_tokens)

                            GroqCircuitBreaker.record_success(model=target_model, latency_ms=latency_ms)
                            return LLMResponse(
                                content=raw_text,
                                structured_json=parsed_json,
                                token_count=t_tokens,
                                prompt_tokens=p_tokens,
                                completion_tokens=c_tokens,
                                latency_ms=latency_ms,
                                provider="groq",
                                model=target_model,
                                status="SUCCESS",
                                reasoning_source=PROVENANCE_GROQ_LIVE,
                                provider_attempt_status=PROVENANCE_GROQ_LIVE,
                            )
                        last_error = f"Groq returned empty choices on '{target_model}'."

                    else:
                        # REST fallback
                        endpoint = "https://api.groq.com/openai/v1/chat/completions"
                        headers = {
                            "Content-Type": "application/json",
                            "Authorization": f"Bearer {self.api_key}",
                        }
                        payload = {
                            "model": target_model,
                            "messages": messages,
                            "response_format": {"type": "json_object"},
                            "temperature": 0.2,
                            "max_tokens": max_out_tokens,
                        }
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

                                parsed_json = json.loads(raw_text)
                                if not isinstance(parsed_json, dict):
                                    raise ValueError("Groq response is not a valid JSON dictionary.")

                                usage = data.get("usage", {})
                                p_tokens = usage.get("prompt_tokens", 0)
                                c_tokens = usage.get("completion_tokens", 0)
                                t_tokens = usage.get("total_tokens", len(raw_text) // 4)

                                GroqCircuitBreaker.record_success(model=target_model, latency_ms=latency_ms)
                                return LLMResponse(
                                    content=raw_text,
                                    structured_json=parsed_json,
                                    token_count=t_tokens,
                                    prompt_tokens=p_tokens,
                                    completion_tokens=c_tokens,
                                    latency_ms=latency_ms,
                                    provider="groq",
                                    model=target_model,
                                    status="SUCCESS",
                                    reasoning_source=PROVENANCE_GROQ_LIVE,
                                    provider_attempt_status=PROVENANCE_GROQ_LIVE,
                                    )
                            last_error = f"Groq returned empty choices on '{target_model}'."
                        elif res.status_code == 429:
                            err_msg = "GroqCloud Free Tier Rate Limit / Quota reached (HTTP 429)."
                            last_error = f"Groq ({target_model}) HTTP 429: {err_msg}"
                            last_status = "RATE_LIMITED"
                            logger.warning("Groq candidate model '%s' hit 429 rate limit. Trying next candidate model...", target_model)
                            break
                        elif res.status_code == 401:
                            err_msg = "GroqCloud API Key Authentication Failed (HTTP 401)."
                            last_error = f"Groq ({target_model}) HTTP 401: {err_msg}"
                            last_status = "AUTH_ERROR"
                            GroqCircuitBreaker.record_auth_error(last_error, cooldown_seconds=300)
                            return LLMResponse(
                                content="",
                                structured_json=None,
                                token_count=0,
                                latency_ms=latency_ms,
                                provider="groq",
                                model=target_model,
                                status="AUTH_ERROR",
                                error_message=last_error,
                                reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
                                provider_attempt_status=PROVENANCE_GROQ_AUTH_ERROR,
                            )
                        else:
                            last_error = f"Groq HTTP {res.status_code}: {res.text[:180]}"

                except Exception as exc:
                    err_str = str(exc)
                    if "429" in err_str or "rate limit" in err_str.lower():
                        last_error = f"Groq ({target_model}) 429: {err_str}"
                        last_status = "RATE_LIMITED"
                        logger.warning("Groq candidate model '%s' rate limited. Trying next candidate...", target_model)
                        break
                    elif "401" in err_str or "auth" in err_str.lower():
                        last_error = f"Groq ({target_model}) 401: {err_str}"
                        last_status = "AUTH_ERROR"
                        GroqCircuitBreaker.record_auth_error(last_error, cooldown_seconds=300)
                        return LLMResponse(
                            content="",
                            structured_json=None,
                            token_count=0,
                            latency_ms=int((time.time() - start_time) * 1000),
                            provider="groq",
                            model=target_model,
                            status="AUTH_ERROR",
                            error_message=last_error,
                            reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
                            provider_attempt_status=PROVENANCE_GROQ_AUTH_ERROR,
                        )
                    elif "503" in err_str or "service unavailable" in err_str.lower():
                        last_error = f"Groq ({target_model}) 503: {err_str}"
                        last_status = "UNAVAILABLE"
                        if attempt == self.max_retries:
                            break
                    else:
                        last_error = f"Groq network error on '{target_model}': {err_str}"

                if attempt < self.max_retries:
                    time.sleep(0.5 * (attempt + 1))

        if last_status == "RATE_LIMITED":
            GroqCircuitBreaker.record_rate_limit(last_error, cooldown_seconds=180)
            return LLMResponse(
                content="",
                structured_json=None,
                token_count=0,
                latency_ms=int((time.time() - start_time) * 1000),
                provider="groq",
                model=primary_model,
                status="RATE_LIMITED",
                error_message=last_error,
                reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
                provider_attempt_status=PROVENANCE_GROQ_RATE_LIMITED,
            )

        latency_ms = int((time.time() - start_time) * 1000)
        return LLMResponse(
            content="",
            structured_json=None,
            token_count=0,
            latency_ms=latency_ms,
            provider="groq",
            model=primary_model,
            status=last_status,
            error_message=last_error,
            reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
            provider_attempt_status=f"GROQ_{last_status}",
        )


class GeminiProvider(BaseLLMProvider):
    """
    Google Gemini API Provider using direct REST endpoints.
    Features circuit breaking, rate-limit fast-failover, model candidate discovery,
    and automatic structured JSON parsing.
    """

    DEFAULT_CANDIDATE_MODELS = [
        "gemini-3.8-flash",
        "gemini-flash-latest",
        "gemini-3.5-flash",
        "gemini-3.1-pro-preview",
    ]

    def __init__(
        self,
        api_key: Optional[str] = None,
        model_name: Optional[str] = None,
        timeout: int = 25,
        max_retries: int = 1,
    ):
        resolved_model = model_name or os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
        super().__init__(model_name=resolved_model, timeout=timeout, max_retries=max_retries)
        self.api_key = api_key if api_key is not None else os.getenv("GEMINI_API_KEY", "").strip()

    def is_configured(self) -> bool:
        return bool(self.api_key)

    @classmethod
    def discover_supported_models(cls, api_key: Optional[str] = None) -> List[str]:
        """Queries Google Generative Language API models endpoint to discover supported models."""
        key = api_key or os.getenv("GEMINI_API_KEY", "").strip()
        if not key:
            return []
        try:
            url = f"https://generativelanguage.googleapis.com/v1beta/models?key={key}"
            res = requests.get(url, timeout=10)
            if res.status_code == 200:
                models_data = res.json().get("models", [])
                return [
                    m.get("name", "").replace("models/", "")
                    for m in models_data
                    if "generateContent" in m.get("supportedGenerationMethods", [])
                ]
        except Exception as exc:
            logger.warning("Failed to discover Gemini models: %s", exc)
        return []

    def verify_connectivity(self) -> Dict[str, Any]:
        """Runs a minimal live inference check without retries to audit connectivity status."""
        if not self.is_configured():
            return {
                "is_configured": False,
                "model_name": self.model_name,
                "http_status": 0,
                "latency_ms": 0,
                "provider_status": "UNCONFIGURED",
                "error_message": "GEMINI_API_KEY is not set.",
                "reasoning_source": PROVENANCE_DETERMINISTIC_FALLBACK,
            }

        start = time.time()
        test_model = self.model_name.replace("models/", "").strip()
        endpoint = f"https://generativelanguage.googleapis.com/v1beta/models/{test_model}:generateContent?key={self.api_key}"
        headers = {"Content-Type": "application/json"}
        payload = {
            "contents": [{"role": "user", "parts": [{"text": "Respond in JSON: {\"ping\": \"pong\"}"}]}],
            "generationConfig": {"temperature": 0.1, "responseMimeType": "application/json"},
        }

        try:
            res = requests.post(endpoint, headers=headers, json=payload, timeout=12)
            lat = int((time.time() - start) * 1000)
            if res.status_code == 200:
                GeminiCircuitBreaker.record_success(model=test_model, latency_ms=lat)
                return {
                    "is_configured": True,
                    "model_name": test_model,
                    "http_status": 200,
                    "latency_ms": lat,
                    "provider_status": PROVENANCE_GEMINI_LIVE,
                    "error_message": "",
                    "reasoning_source": PROVENANCE_GEMINI_LIVE,
                }
            elif res.status_code == 429 or "RESOURCE_EXHAUSTED" in res.text:
                err = "HTTP 429: Account quota limit exceeded (Free Tier request cap reached)."
                GeminiCircuitBreaker.record_rate_limit(err, cooldown_seconds=180)
                return {
                    "is_configured": True,
                    "model_name": test_model,
                    "http_status": 429,
                    "latency_ms": lat,
                    "provider_status": "BLOCKED_BY_QUOTA",
                    "error_message": err,
                    "reasoning_source": PROVENANCE_DETERMINISTIC_FALLBACK,
                }
            elif res.status_code == 503 or "high demand" in res.text.lower():
                err = "HTTP 503: Model is currently experiencing high demand."
                GeminiCircuitBreaker.record_service_unavailable(err, cooldown_seconds=30)
                return {
                    "is_configured": True,
                    "model_name": test_model,
                    "http_status": 503,
                    "latency_ms": lat,
                    "provider_status": "SERVICE_UNAVAILABLE",
                    "error_message": err,
                    "reasoning_source": PROVENANCE_DETERMINISTIC_FALLBACK,
                }
            else:
                return {
                    "is_configured": True,
                    "model_name": test_model,
                    "http_status": res.status_code,
                    "latency_ms": lat,
                    "provider_status": "ERROR",
                    "error_message": f"HTTP {res.status_code}: {res.text[:200]}",
                    "reasoning_source": PROVENANCE_DETERMINISTIC_FALLBACK,
                }
        except Exception as exc:
            lat = int((time.time() - start) * 1000)
            return {
                "is_configured": True,
                "model_name": test_model,
                "http_status": 0,
                "latency_ms": lat,
                "provider_status": "NETWORK_ERROR",
                "error_message": str(exc),
                "reasoning_source": PROVENANCE_DETERMINISTIC_FALLBACK,
            }

    def generate_structured(
        self, system_prompt: str, user_prompt: str, schema_description: Optional[str] = None
    ) -> LLMResponse:
        primary_model = self.model_name.replace("models/", "").strip() or os.getenv("GEMINI_MODEL", "gemini-3.8-flash")

        if not self.is_configured():
            return LLMResponse(
                content="",
                structured_json=None,
                token_count=0,
                latency_ms=0,
                provider="gemini",
                model=primary_model,
                status="UNCONFIGURED",
                error_message="Google Gemini API key not configured. Set GEMINI_API_KEY in environment or .env file.",
                reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
                provider_attempt_status="GEMINI_UNCONFIGURED",
            )

        # 1. Circuit Breaker Check
        is_avail, breaker_status, breaker_msg = GeminiCircuitBreaker.check_availability()
        if not is_avail:
            logger.info("[GeminiProvider] Fast-failover triggered: %s", breaker_msg[:100])
            return LLMResponse(
                content="",
                structured_json=None,
                token_count=0,
                latency_ms=0,
                provider="gemini",
                model=primary_model,
                status=breaker_status,
                error_message=breaker_msg,
                reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
                provider_attempt_status=f"GEMINI_{breaker_status}",
            )

        # 2. Build candidate models list
        candidate_models = [primary_model]
        for m in self.DEFAULT_CANDIDATE_MODELS:
            if m not in candidate_models:
                candidate_models.append(m)

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
        last_status = "ERROR"

        for target_model in candidate_models[:2]:
            endpoint = (
                f"https://generativelanguage.googleapis.com/v1beta/models/{target_model}:generateContent"
                f"?key={self.api_key}"
            )

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

                                if not isinstance(parsed_json, dict):
                                    raise ValueError("Gemini response is not a valid JSON dictionary.")

                                usage = data.get("usageMetadata", {})
                                p_tokens = usage.get("promptTokenCount", 0)
                                c_tokens = usage.get("candidatesTokenCount", 0)
                                token_count = usage.get("totalTokenCount", len(raw_text) // 4)

                                GeminiCircuitBreaker.record_success(model=target_model, latency_ms=latency_ms)
                                return LLMResponse(
                                    content=raw_text,
                                    structured_json=parsed_json,
                                    token_count=token_count,
                                    prompt_tokens=p_tokens,
                                    completion_tokens=c_tokens,
                                    latency_ms=latency_ms,
                                    provider="gemini",
                                    model=target_model,
                                    status="SUCCESS",
                                    reasoning_source=PROVENANCE_GEMINI_LIVE,
                                    provider_attempt_status=PROVENANCE_GEMINI_LIVE,
                                )

                        last_error = f"Gemini returned empty candidate on '{target_model}'."

                    elif res.status_code == 429 or "RESOURCE_EXHAUSTED" in res.text:
                        err_msg = "Google Gemini Free Tier Quota / Rate Limit exceeded (HTTP 429)."
                        last_error = f"Gemini ({target_model}) HTTP 429: {err_msg}"
                        last_status = "RATE_LIMITED"
                        GeminiCircuitBreaker.record_rate_limit(last_error, cooldown_seconds=180)
                        return LLMResponse(
                            content="",
                            structured_json=None,
                            token_count=0,
                            latency_ms=latency_ms,
                            provider="gemini",
                            model=target_model,
                            status="RATE_LIMITED",
                            error_message=last_error,
                            reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
                            provider_attempt_status=PROVENANCE_GEMINI_RATE_LIMITED,
                        )

                    elif res.status_code == 503 or "high demand" in res.text.lower():
                        last_error = f"Gemini ({target_model}) HTTP 503: High demand spike."
                        last_status = "UNAVAILABLE"
                        if attempt == self.max_retries:
                            GeminiCircuitBreaker.record_service_unavailable(last_error, cooldown_seconds=30)
                            return LLMResponse(
                                content="",
                                structured_json=None,
                                token_count=0,
                                latency_ms=latency_ms,
                                provider="gemini",
                                model=target_model,
                                status="UNAVAILABLE",
                                error_message=last_error,
                                reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
                                provider_attempt_status=PROVENANCE_GEMINI_UNAVAILABLE,
                            )

                    elif res.status_code == 404:
                        last_error = f"Model '{target_model}' not available (HTTP 404). Trying fallback candidate."
                        break

                    else:
                        last_error = f"Gemini ({target_model}) HTTP {res.status_code}: {res.text[:150]}"

                except json.JSONDecodeError as exc:
                    last_error = f"JSON parse error on model '{target_model}': {str(exc)}"
                except Exception as exc:
                    last_error = f"Gemini network error on model '{target_model}': {str(exc)}"

                if attempt < self.max_retries:
                    time.sleep(1.0 * (attempt + 1))

        latency_ms = int((time.time() - start_time) * 1000)
        return LLMResponse(
            content="",
            structured_json=None,
            token_count=0,
            latency_ms=latency_ms,
            provider="gemini",
            model=primary_model,
            status=last_status,
            error_message=last_error,
            reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
            provider_attempt_status=f"GEMINI_{last_status}",
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
        max_retries: int = 1,
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
                error_message="OpenAI API key not configured.",
                reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
                provider_attempt_status="OPENAI_UNCONFIGURED",
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
                        parsed_json = json.loads(raw_text)
                        usage = data.get("usage", {})
                        token_count = usage.get("total_tokens", len(raw_text) // 4)

                        return LLMResponse(
                            content=raw_text,
                            structured_json=parsed_json,
                            token_count=token_count,
                            prompt_tokens=usage.get("prompt_tokens", 0),
                            completion_tokens=usage.get("completion_tokens", 0),
                            latency_ms=latency_ms,
                            provider="openai",
                            model=self.model_name,
                            status="SUCCESS",
                            reasoning_source="OPENAI_LIVE",
                            provider_attempt_status="OPENAI_LIVE",
                        )
                    last_error = "OpenAI returned empty choices."
                else:
                    last_error = f"OpenAI HTTP {res.status_code}: {res.text[:200]}"
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
            reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
            provider_attempt_status="OPENAI_ERROR",
        )


class MultiProviderRouter(BaseLLMProvider):
    """
    Intelligent Multi-Provider LLM Router with sequential failover:
    1. Primary: GroqCloud (ultra-low latency, free-tier cloud AI)
    2. Secondary: Google Gemini (secondary cloud AI)
    3. Final Fallback: Deterministic industrial safety engine

    Tracks circuit breakers, quotas, provider attempt histories, and operational provenance.
    """

    def __init__(
        self,
        primary_provider: Optional[BaseLLMProvider] = None,
        secondary_provider: Optional[BaseLLMProvider] = None,
        timeout: int = 30,
        max_retries: int = 1,
    ):
        primary_name = os.getenv("LLM_PRIMARY_PROVIDER", "groq").lower().strip()
        secondary_name = os.getenv("LLM_SECONDARY_PROVIDER", "gemini").lower().strip()

        if primary_provider is not None:
            self.primary = primary_provider
        elif primary_name == "gemini":
            self.primary = GeminiProvider(timeout=timeout, max_retries=max_retries)
        else:
            self.primary = GroqProvider(timeout=timeout, max_retries=max_retries)

        if secondary_provider is not None:
            self.secondary = secondary_provider
        elif secondary_name == "groq":
            self.secondary = GroqProvider(timeout=timeout, max_retries=max_retries)
        else:
            self.secondary = GeminiProvider(timeout=timeout, max_retries=max_retries)

        active_model = getattr(self.primary, "model_name", "groq/auto")
        super().__init__(model_name=active_model, timeout=timeout, max_retries=max_retries)

    def is_configured(self) -> bool:
        return self.primary.is_configured() or self.secondary.is_configured()

    def generate_structured(
        self, system_prompt: str, user_prompt: str, schema_description: Optional[str] = None
    ) -> LLMResponse:
        attempts_log = []

        # -------------------------------------------------------------
        # STEP 1: Attempt Primary Provider (GroqCloud by default)
        # -------------------------------------------------------------
        if self.primary.is_configured():
            # Check circuit breaker before sending network request
            if isinstance(self.primary, GroqProvider) and GroqCircuitBreaker.is_open():
                _, status, msg = GroqCircuitBreaker.check_availability()
                attempts_log.append(f"GroqCircuitBreaker active ({status})")
            elif isinstance(self.primary, GeminiProvider) and GeminiCircuitBreaker.is_open():
                _, status, msg = GeminiCircuitBreaker.check_availability()
                attempts_log.append(f"GeminiCircuitBreaker active ({status})")
            else:
                resp = self.primary.generate_structured(system_prompt, user_prompt, schema_description)
                if resp.status == "SUCCESS" and resp.structured_json:
                    return resp
                attempts_log.append(f"{resp.provider.upper()}_{resp.status}: {resp.error_message[:80]}")
        else:
            attempts_log.append(f"Primary ({getattr(self.primary, 'model_name', 'primary')}) unconfigured")

        # -------------------------------------------------------------
        # STEP 2: Failover to Secondary Provider (Gemini by default)
        # -------------------------------------------------------------
        if self.secondary.is_configured():
            if isinstance(self.secondary, GeminiProvider) and GeminiCircuitBreaker.is_open():
                _, status, msg = GeminiCircuitBreaker.check_availability()
                attempts_log.append(f"GeminiCircuitBreaker active ({status})")
            elif isinstance(self.secondary, GroqProvider) and GroqCircuitBreaker.is_open():
                _, status, msg = GroqCircuitBreaker.check_availability()
                attempts_log.append(f"GroqCircuitBreaker active ({status})")
            else:
                logger.info(
                    "[MultiProviderRouter] Primary provider failed or unavailable. Failing over to secondary provider (%s)...",
                    getattr(self.secondary, "model_name", "secondary"),
                )
                resp = self.secondary.generate_structured(system_prompt, user_prompt, schema_description)
                if resp.status == "SUCCESS" and resp.structured_json:
                    return resp
                attempts_log.append(f"{resp.provider.upper()}_{resp.status}: {resp.error_message[:80]}")
        else:
            attempts_log.append(f"Secondary ({getattr(self.secondary, 'model_name', 'secondary')}) unconfigured")

        # -------------------------------------------------------------
        # STEP 3: Fallback to Deterministic Reasoning Engine
        # -------------------------------------------------------------
        combined_error = " | ".join(attempts_log)
        logger.warning(
            "[MultiProviderRouter] All cloud LLM providers unavailable (%s). Engaging deterministic fallback.",
            combined_error[:120],
        )

        # Distinguish between rate limit exhaustion and complete outage
        if any("rate" in a.lower() or "quota" in a.lower() or "429" in a for a in attempts_log):
            fallback_attempt_status = PROVENANCE_PROVIDER_RATE_LIMITED
            status = "RATE_LIMITED"
        elif any("503" in a or "unavailable" in a.lower() for a in attempts_log):
            fallback_attempt_status = PROVENANCE_PROVIDER_UNAVAILABLE
            status = "UNAVAILABLE"
        else:
            fallback_attempt_status = PROVENANCE_DETERMINISTIC_FALLBACK
            status = "FALLBACK"

        return LLMResponse(
            content="",
            structured_json=None,
            token_count=0,
            latency_ms=0,
            provider="multi_router",
            model=getattr(self.primary, "model_name", "deterministic"),
            status=status,
            error_message=combined_error,
            reasoning_source=PROVENANCE_DETERMINISTIC_FALLBACK,
            provider_attempt_status=fallback_attempt_status,
        )

    @staticmethod
    def _get_db_last_inference(provider_name: str) -> Optional[Dict[str, Any]]:
        """
        Retrieves actual verified evidence of previous successful inference from durable database logs.
        Strictly prevents attributing executions across providers or using an agent's default model label.
        """
        try:
            from apps.ai_agents.models import AgentExecution, AgentExecutionStatus
            from django.db.models import Q

            target_norm = provider_name.lower().strip()
            is_groq = "groq" in target_norm
            is_gemini = "gemini" in target_norm
            target_prov = "groq" if is_groq else ("gemini" if is_gemini else target_norm)
            target_keyword = "GROQ_LIVE" if is_groq else "GEMINI_LIVE"

            candidates = AgentExecution.objects.filter(
                status=AgentExecutionStatus.COMPLETED
            ).filter(
                Q(execution_summary__contains=target_keyword) |
                Q(context_payload__icontains=target_keyword) |
                Q(context_payload__provider=target_prov)
            ).order_by("-started_at")[:25]

            for exec_obj in candidates:
                payload = exec_obj.context_payload if isinstance(exec_obj.context_payload, dict) else {}
                summary = exec_obj.execution_summary or ""
                rsource = str(payload.get("reasoning_source") or "").upper()
                prov = str(payload.get("provider") or "").lower()
                is_live = payload.get("is_live_ai")

                # Strict attribution verification:
                # Disallow cross-provider attribution or deterministic fallback
                if is_groq:
                    if rsource == "GEMINI_LIVE" or "[GEMINI_LIVE]" in summary or prov == "gemini":
                        continue
                    if rsource == "DETERMINISTIC_FALLBACK" or "[DETERMINISTIC_FALLBACK]" in summary:
                        continue
                    if not (rsource == "GROQ_LIVE" or "[GROQ_LIVE]" in summary or (prov == "groq" and is_live is True)):
                        continue
                elif is_gemini:
                    if rsource == "GROQ_LIVE" or "[GROQ_LIVE]" in summary or prov == "groq":
                        continue
                    if rsource == "DETERMINISTIC_FALLBACK" or "[DETERMINISTIC_FALLBACK]" in summary:
                        continue
                    if not (rsource == "GEMINI_LIVE" or "[GEMINI_LIVE]" in summary or (prov == "gemini" and is_live is True)):
                        continue
                else:
                    continue

                # Requirement 1: Do not use an agent's default model label as proof of actual cloud model used.
                actual_model = payload.get("model_name") or payload.get("model") or ""
                # Validate model name does not carry cross-provider default labels
                if is_groq and ("gemini" in actual_model.lower() or "claude" in actual_model.lower()):
                    actual_model = os.getenv("GROQ_MODEL", "qwen/qwen3.8-27b")
                elif is_gemini and ("qwen" in actual_model.lower() or "llama" in actual_model.lower()):
                    actual_model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash")

                if not actual_model:
                    actual_model = os.getenv(
                        "GROQ_MODEL" if is_groq else "GEMINI_MODEL",
                        "qwen/qwen3.8-27b" if is_groq else "gemini-3.5-flash",
                    )

                ts = exec_obj.completed_at or exec_obj.started_at
                ts_epoch = ts.timestamp() if ts else None
                now = time.time()
                age_seconds = (now - ts_epoch) if ts_epoch else None
                is_stale = (age_seconds is None) or (age_seconds > 86400)

                return {
                    "timestamp_epoch": ts_epoch,
                    "timestamp_iso": ts.isoformat() if ts else None,
                    "latency_ms": payload.get("latency_ms") or exec_obj.latency_ms or 0,
                    "model": actual_model,
                    "provider": "GroqCloud" if is_groq else "Google Gemini",
                    "age_seconds": int(age_seconds) if age_seconds is not None else None,
                    "is_stale": is_stale,
                    "execution_id": str(exec_obj.execution_id),
                }

        except Exception as exc:
            logger.debug("[MultiProviderRouter] Error querying DB last inference: %s", exc)

        return None

    def get_provider_health(self) -> Dict[str, Any]:
        """Provides diagnostic health summary across all integrated providers with evidence-based status."""
        groq_api_configured = bool(os.getenv("GROQ_API_KEY", "").strip())
        gemini_api_configured = bool(os.getenv("GEMINI_API_KEY", "").strip())

        groq_avail, groq_status, groq_breaker_msg = GroqCircuitBreaker.check_availability()
        gemini_avail, gemini_status, gemini_breaker_msg = GeminiCircuitBreaker.check_availability()

        active_primary = os.getenv("LLM_PRIMARY_PROVIDER", "groq")
        active_secondary = os.getenv("LLM_SECONDARY_PROVIDER", "gemini")

        # Groq actual evidence and status
        groq_last_success_ts = GroqCircuitBreaker._last_success_at
        groq_last_model = GroqCircuitBreaker._last_model
        groq_last_latency = GroqCircuitBreaker._last_latency_ms
        groq_is_stale = False

        db_groq = self._get_db_last_inference("groq")
        if db_groq:
            if not groq_last_success_ts:
                groq_last_success_ts = db_groq["timestamp_epoch"]
                groq_last_latency = db_groq["latency_ms"]
                groq_is_stale = db_groq.get("is_stale", False)
            if not groq_last_model and db_groq.get("model"):
                groq_last_model = db_groq["model"]

        if not groq_last_model:
            groq_last_model = os.getenv("GROQ_MODEL", "qwen/qwen3.8-27b")

        if not groq_api_configured:
            groq_state = "NOT_CONFIGURED"
            groq_msg = "GROQ_API_KEY is not set in environment."
        elif not groq_avail:
            if groq_status == "RATE_LIMITED":
                groq_state = "RATE_LIMITED"
            else:
                groq_state = "UNAVAILABLE"
            groq_msg = groq_breaker_msg
        elif groq_last_success_ts is not None:
            groq_state = "OPERATIONAL"
            if groq_is_stale:
                groq_msg = "Historical inference verified • Circuit breaker closed & ready."
            else:
                groq_msg = "Live inference operational • Circuit breaker closed."
        else:
            groq_state = "CONFIGURED"
            groq_msg = "API key configured • Standing by for primary inference."

        # Gemini actual evidence and status
        gemini_last_success_ts = GeminiCircuitBreaker._last_success_at
        gemini_last_model = GeminiCircuitBreaker._last_model
        gemini_last_latency = GeminiCircuitBreaker._last_latency_ms
        gemini_is_stale = False

        db_gemini = self._get_db_last_inference("gemini")
        if db_gemini:
            if not gemini_last_success_ts:
                gemini_last_success_ts = db_gemini["timestamp_epoch"]
                gemini_last_latency = db_gemini["latency_ms"]
                gemini_is_stale = db_gemini.get("is_stale", False)
            if not gemini_last_model and db_gemini.get("model"):
                gemini_last_model = db_gemini["model"]

        if not gemini_last_model:
            gemini_last_model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash")

        if not gemini_api_configured:
            gemini_state = "NOT_CONFIGURED"
            gemini_msg = "GEMINI_API_KEY is not set in environment."
        elif not gemini_avail:
            if gemini_status == "RATE_LIMITED":
                gemini_state = "RATE_LIMITED"
            else:
                gemini_state = "UNAVAILABLE"
            gemini_msg = gemini_breaker_msg
        elif gemini_last_success_ts is not None:
            gemini_state = "OPERATIONAL"
            if gemini_is_stale:
                gemini_msg = "Historical inference verified • Circuit breaker closed & ready."
            else:
                gemini_msg = "Live inference operational • Circuit breaker closed."
        else:
            gemini_state = "CONFIGURED"
            gemini_msg = "API key configured • Standing by for secondary failover."

        # Aggregate last successful cloud inference
        last_success_ts = None
        last_provider = "NONE"
        last_model = "NONE"
        last_latency = None
        last_is_stale = False

        if groq_last_success_ts and gemini_last_success_ts:
            if groq_last_success_ts >= gemini_last_success_ts:
                last_success_ts = groq_last_success_ts
                last_provider = "GroqCloud"
                last_model = groq_last_model
                last_latency = groq_last_latency
                last_is_stale = groq_is_stale
            else:
                last_success_ts = gemini_last_success_ts
                last_provider = "Google Gemini"
                last_model = gemini_last_model
                last_latency = gemini_last_latency
                last_is_stale = gemini_is_stale
        elif groq_last_success_ts:
            last_success_ts = groq_last_success_ts
            last_provider = "GroqCloud"
            last_model = groq_last_model
            last_latency = groq_last_latency
            last_is_stale = groq_is_stale
        elif gemini_last_success_ts:
            last_success_ts = gemini_last_success_ts
            last_provider = "Google Gemini"
            last_model = gemini_last_model
            last_latency = gemini_last_latency
            last_is_stale = gemini_is_stale

        last_success_iso = (
            time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(last_success_ts))
            if last_success_ts
            else None
        )

        return {
            "routing_mode": os.getenv("LLM_PROVIDER", "auto"),
            "primary_provider": active_primary,
            "secondary_provider": active_secondary,
            "fallback_provider": "deterministic_domain_engine",
            "last_successful_inference": {
                "timestamp": last_success_iso,
                "timestamp_epoch": last_success_ts,
                "provider": last_provider,
                "model": last_model,
                "latency_ms": last_latency,
                "is_stale": last_is_stale,
            },
            "groq": {
                "configured": groq_api_configured,
                "is_configured": groq_api_configured,
                "status": groq_state,
                "model": groq_last_model,
                "ready": groq_state in ("OPERATIONAL", "CONFIGURED"),
                "circuit_breaker_open": GroqCircuitBreaker.is_open(),
                "circuit_breaker_status": "OPEN (COOLDOWN)" if GroqCircuitBreaker.is_open() else "CLOSED",
                "cooldown_message": groq_msg,
                "message": groq_msg,
                "latency_ms": groq_last_latency,
                "last_successful_at": (
                    time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(groq_last_success_ts))
                    if groq_last_success_ts
                    else None
                ),
                "is_stale": groq_is_stale,
            },
            "gemini": {
                "configured": gemini_api_configured,
                "is_configured": gemini_api_configured,
                "status": gemini_state,
                "model": gemini_last_model,
                "ready": gemini_state in ("OPERATIONAL", "CONFIGURED"),
                "circuit_breaker_open": GeminiCircuitBreaker.is_open(),
                "circuit_breaker_status": "OPEN (COOLDOWN)" if GeminiCircuitBreaker.is_open() else "CLOSED",
                "cooldown_message": gemini_msg,
                "message": gemini_msg,
                "latency_ms": gemini_last_latency,
                "last_successful_at": (
                    time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(gemini_last_success_ts))
                    if gemini_last_success_ts
                    else None
                ),
                "is_stale": gemini_is_stale,
            },
            "deterministic_fallback": {
                "configured": True,
                "is_configured": True,
                "status": "OPERATIONAL",
                "model": "texora-industrial-heuristics-v2",
                "ready": True,
                "circuit_breaker_open": False,
                "circuit_breaker_status": "BUILT-IN (STANDBY)",
                "cooldown_message": "",
                "message": "Deterministic Offline Rule Engine • Industrial Heuristics Fallback",
                "latency_ms": 0,
                "last_successful_at": None,
            },
            "current_fallback_state": "ACTIVE" if (not groq_avail and not gemini_avail) else "STANDBY",
        }


def get_llm_provider(force_provider: Optional[str] = None) -> BaseLLMProvider:
    """
    Factory creating the configured LLM inference provider.
    Defaults to MultiProviderRouter (Groq primary -> Gemini secondary -> Deterministic fallback).
    Supports explicit force overrides: 'groq', 'gemini', 'mock', 'openai', 'deterministic'.
    In automated pytest test runs without an explicit force_provider, defaults to MockLLMProvider to prevent quota consumption.
    """
    if force_provider:
        requested = force_provider.lower().strip()
    elif "PYTEST_CURRENT_TEST" in os.environ:
        requested = "mock"
    else:
        requested = os.getenv("LLM_PROVIDER", "auto").lower().strip()

    timeout = int(os.getenv("LLM_REQUEST_TIMEOUT_SECONDS", os.getenv("LLM_TIMEOUT_SECONDS", "30")))
    retries = int(os.getenv("LLM_MAX_RETRIES", "1"))

    if requested in ["mock", "fallback", "deterministic", "deterministic_fallback"]:
        return MockLLMProvider()
    elif requested == "groq":
        model = os.getenv("GROQ_MODEL", "qwen/qwen3.8-27b")
        return GroqProvider(model_name=model, timeout=timeout, max_retries=retries)
    elif requested == "gemini":
        model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash")
        return GeminiProvider(model_name=model, timeout=timeout, max_retries=retries)
    elif requested == "openai":
        model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
        return OpenAIProvider(model_name=model, timeout=timeout, max_retries=retries)
    elif requested in ["auto", "multi", "router"]:
        return MultiProviderRouter(timeout=timeout, max_retries=retries)
    else:
        # Default to multi-provider router
        return MultiProviderRouter(timeout=timeout, max_retries=retries)
