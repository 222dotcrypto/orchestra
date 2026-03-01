"""
skill-indexer — автоматическая индексация скиллов Orchestra.

Использование:
    from system.skill_indexer import find_skill, catalog, full_reindex
"""

from .indexer import full_reindex, incremental_update
from .matcher import find_skill, exact_match
from .reporter import catalog, gaps, stats
from .store import get_skill

__all__ = [
    "full_reindex",
    "incremental_update",
    "find_skill",
    "exact_match",
    "catalog",
    "gaps",
    "stats",
    "get_skill",
]
