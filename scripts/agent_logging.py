"""Structured logging designed to be read by a coding agent.

Usage:
    from scripts.agent_logging import get_agent_logger, debug_block

    log = get_agent_logger(__name__)
    with debug_block("parse_vcf"):
        log.debug("record=%s sample_count=%d", rec_id, n)

Principles:
- Messages always include the VALUES, not just the fact. A log without values
  forces the agent into a second round of instrumentation.
- Delimited blocks let a grep extract only the relevant window instead of
  re-reading the whole log file.
"""

from __future__ import annotations

import logging
import os
import sys
from contextlib import contextmanager

LOG_DIR = "logs/agent"
FMT = "%(asctime)s | %(levelname)-7s | %(name)s:%(lineno)d | %(message)s"


def get_agent_logger(name: str, to_file: str | None = None) -> logging.Logger:
    """Logger with a compact, parsable format. Writes to stderr (+ optional file)."""
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger

    formatter = logging.Formatter(FMT, datefmt="%H:%M:%S")

    stream = logging.StreamHandler(sys.stderr)
    stream.setFormatter(formatter)
    logger.addHandler(stream)

    if to_file:
        os.makedirs(LOG_DIR, exist_ok=True)
        fh = logging.FileHandler(os.path.join(LOG_DIR, to_file), encoding="utf-8")
        fh.setFormatter(formatter)
        logger.addHandler(fh)

    logger.setLevel(os.getenv("AGENT_LOG_LEVEL", "DEBUG"))
    logger.propagate = False
    return logger


@contextmanager
def debug_block(label: str, logger: logging.Logger | None = None):
    """Delimits a critical section: grep -A200 'DEBUG-START:label' extracts only that one."""
    log = logger or get_agent_logger("agent")
    log.debug("### DEBUG-START:%s", label)
    try:
        yield
    finally:
        log.debug("### DEBUG-END:%s", label)
