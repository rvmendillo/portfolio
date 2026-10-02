"""Fetch and verify only the portable GGUF used by browser inference tests."""
from pathlib import Path
import hashlib, json, shutil, urllib.request
root=Path(__file__).resolve().parents[1]
model=json.loads((root/'shared/model.json').read_text())
cache=root/'.dependency-cache';cache.mkdir(exist_ok=True)
path=cache/model['filename']
def valid():
    if not path.is_file() or path.stat().st_size!=model['size']:return False
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()==model['sha256']
if not valid():
    partial=path.with_suffix('.partial')
    with urllib.request.urlopen(model['url'],timeout=180) as response,partial.open('wb') as output:shutil.copyfileobj(response,output)
    partial.replace(path)
if not valid():raise RuntimeError('Model checksum mismatch')
print('Verified local coding model:',path)
