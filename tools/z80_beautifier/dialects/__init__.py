"""
Dialect Registry and Factory.
"""

from typing import Dict, Type
from .base import Dialect
from .z88dk import Z88dkDialect
from .tasm import TasmDialect
from .slr import SlrDialect
from .m80 import M80Dialect
from .sjasmplus import SjasmplusDialect

DIALECTS: Dict[str, Type[Dialect]] = {
    'z88dk': Z88dkDialect,
    'tasm': TasmDialect,
    'uz80as': TasmDialect,
    'slr': SlrDialect,
    'zmac': SlrDialect,
    'm80': M80Dialect,
    'sjasmplus': SjasmplusDialect,
    'sjasm': SjasmplusDialect
}

def get_dialect(name: str) -> Dialect:
    """Instantiate a dialect by name or by .dia file path."""
    import os
    if name.lower().endswith('.dia') or os.path.isfile(name):
        from ..meta import load_dialect_dia
        return load_dialect_dia(name)

    clean = name.lower().strip()
    if clean not in DIALECTS:
        raise ValueError(f"Unknown assembler dialect: '{name}'. Supported: {list(DIALECTS.keys())}")
    return DIALECTS[clean]()
