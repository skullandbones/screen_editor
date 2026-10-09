#!/usr/bin/env python3
"""
Setup script for the native Python 3 SE editor port.
"""

from setuptools import setup, find_packages

setup(
    name="se-editor",
    version="1.1.0",
    description="Native Python 3 Screen Editor for Linux",
    packages=find_packages(),
    python_requires=">=3.10",
    entry_points={
        "console_scripts": [
            "se = se.__main__:main",
        ],
    },
)
