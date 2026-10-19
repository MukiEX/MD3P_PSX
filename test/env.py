# Shared paths for the test scripts. Everything is relative to the repo root;
# override with environment variables where your setup differs.
import os, sys
ROOT = os.environ.get('MD3_ROOT', os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
sys.path.insert(0, os.path.join(ROOT, 'test'))
CORE = os.environ.get('PCSX_CORE', os.path.join(ROOT, 'work', 'pcsx_rearmed_libretro.so'))
for d in ('shots', 'shots/vol', 'shots/jp3', 'st', 'cov', 'work/sys'):
    os.makedirs(os.path.join(ROOT, d), exist_ok=True)
