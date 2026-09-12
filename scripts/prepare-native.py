"""Download pinned public runtime dependencies and verify every byte before use."""
from pathlib import Path
import hashlib,json,os,shutil,tarfile,urllib.request,zipfile,sys,subprocess,plistlib

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'ios-native'/'Vendor'
DEST.mkdir(parents=True,exist_ok=True)
CACHE=ROOT/'.dependency-cache'
CACHE.mkdir(exist_ok=True)

def download(url,name,digest):
    path=CACHE/name
    def valid():return path.exists() and hashlib.file_digest(path.open('rb'),'sha256').hexdigest()==digest
    if not valid():
        print('Downloading '+name,flush=True)
        partial=path.with_suffix('.partial')
        with urllib.request.urlopen(url,timeout=180) as r,partial.open('wb') as f:shutil.copyfileobj(r,f)
        partial.replace(path)
    if not valid():raise RuntimeError('Checksum mismatch: '+name)
    return path

llama=download('https://github.com/ggml-org/llama.cpp/releases/download/b10927/llama-b10927-xcframework.zip','llama-b10927.zip','5acfb47a6ad5a2c3cdda800ea19334e6e8b1ca10f2224350222bcbb97d8e8887')
if not (DEST/'llama.xcframework').exists():
    with zipfile.ZipFile(llama) as archive:archive.extractall(CACHE/'llama')
    shutil.copytree(CACHE/'llama/build-apple/llama.xcframework',DEST/'llama.xcframework',symlinks=True)
# The official release contains device/macOS slices. Build a real Simulator
# slice from the matching source revision, then combine it with the device one.
if sys.platform=='darwin':
    combined=CACHE/'llama-b10927-combined.xcframework'
    if not combined.exists():
        source=CACHE/'llama-source-b10927'
        if not source.exists():subprocess.run(['git','clone','--depth','1','--branch','b10927','https://github.com/ggml-org/llama.cpp.git',str(source)],check=True)
        revision=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
        if revision!='718f7b4175bf8b6af6f5eac09fee10754b3ecddd':raise RuntimeError('llama.cpp source revision mismatch')
        subprocess.run(['bash','build-xcframework.sh','ios-sim'],cwd=source,check=True)
        built=source/'build-apple/llama.xcframework'
        info=plistlib.loads((built/'Info.plist').read_bytes())
        simulator=next(item for item in info['AvailableLibraries'] if item.get('SupportedPlatformVariant')=='simulator' and item['SupportedPlatform']=='ios')
        partial=CACHE/'llama-b10927-combined.partial.xcframework'
        if partial.exists():shutil.rmtree(partial)
        subprocess.run(['xcodebuild','-create-xcframework','-framework',str(DEST/'llama.xcframework/ios-arm64/llama.framework'),'-framework',str(built/simulator['LibraryIdentifier']/simulator['LibraryPath']),'-output',str(partial)],check=True)
        partial.rename(combined)
        shutil.rmtree(source)
    info=plistlib.loads((combined/'Info.plist').read_bytes())
    if not any(item.get('SupportedPlatformVariant')=='simulator' for item in info['AvailableLibraries']):raise RuntimeError('Simulator runtime is missing')
    shutil.rmtree(DEST/'llama.xcframework')
    shutil.copytree(combined,DEST/'llama.xcframework',symlinks=True)
python=download('https://github.com/beeware/Python-Apple-support/releases/download/3.14-b11/Python-3.14-iOS-support.b11.tar.gz','python-3.14-b11.tar.gz','b591f3301bd22a4f423c49c746cac9e55558b909fd14d6eb8327ccc62234ab7b')
if not (DEST/'Python.xcframework').exists():
    with tarfile.open(python) as archive:archive.extractall(DEST,filter='data')
model=json.loads((ROOT/'shared/model.json').read_text())
path=download(model['url'],model['filename'],model['sha256'])
models=ROOT/'ios-native/Resources/Models';models.mkdir(exist_ok=True)
bundled=models/model['filename']
if not bundled.exists() or hashlib.file_digest(bundled.open('rb'),'sha256').hexdigest()!=model['sha256']:shutil.copyfile(path,bundled)
app=ROOT/'ios-native/Resources/app';app.mkdir(exist_ok=True)
for name in ['rey_runtime.py','rey_compiler.py']:shutil.copyfile(ROOT/'shared'/name,app/name)
print('Verified llama.cpp, CPython, and bundled Qwen model.',flush=True)
