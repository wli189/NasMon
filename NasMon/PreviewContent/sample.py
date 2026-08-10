"""Utility helpers used by the NasMon dashboard agent."""

from dataclasses import dataclass
from enum import Enum


class Tone(Enum):
    HEALTHY = "healthy"
    WARNING = "warning"
    CRITICAL = "critical"


@dataclass
class Metric:
    value: str
    detail: str | None = None
    progress: float | None = None
    tone: Tone = Tone.HEALTHY


def tone_for(value: float, warning_at: float, critical_at: float) -> Tone:
    if value >= critical_at:
        return Tone.CRITICAL
    if value >= warning_at:
        return Tone.WARNING
    return Tone.HEALTHY


def format_percent(value: float) -> str:
    return f"{value:.0f}%"
