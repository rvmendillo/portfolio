"""Shared CPython execution engine. This is a user-code runtime, not a security sandbox."""
import contextlib
import io
import os
import sys
import tempfile
import time
import traceback

class Output(io.StringIO):
    def write(self, text):
        if self.tell() + len(text) > 64000:
            raise RuntimeError('Output exceeded 64,000 characters')
        return super().write(text)

def run(source, files=None, stdin='', timeout=8, cancelled=None):
    if len(source) > 200000:
        return {'output':'Source exceeds 200 KB','exitCode':1}
    output=Output()
    started=time.monotonic()
    steps=0
    def trace(frame,event,arg):
        nonlocal steps
        steps+=1
        if steps % 100 == 0 and cancelled and cancelled():
            raise InterruptedError('Execution stopped.')
        if steps % 100 == 0 and (time.monotonic()-started > timeout or steps > 1000000):
            raise TimeoutError('Execution limit reached. Simplify the program or split the work.')
        return trace
    old_stdin, old_path, old_cwd, old_modules = sys.stdin, list(sys.path), os.getcwd(), set(sys.modules)
    code=0
    with tempfile.TemporaryDirectory(prefix='rey-run-') as directory:
        try:
            for name,content in (files or {}).items():
                parts=name.replace('\\','/').split('/')
                if not parts or any(p in ('','..','.') for p in parts) or name.startswith('/'):
                    raise ValueError('Invalid workspace path: '+name)
                path=os.path.join(directory,*parts)
                os.makedirs(os.path.dirname(path),exist_ok=True)
                with open(path,'w',encoding='utf-8') as f: f.write(str(content))
            os.chdir(directory)
            sys.path.insert(0,directory)
            sys.stdin=io.StringIO(stdin)
            with contextlib.redirect_stdout(output),contextlib.redirect_stderr(output):
                try:
                    compiled=compile(source,'main.py','exec')
                    sys.settrace(trace)
                    exec(compiled,{'__name__':'__main__','__file__':os.path.join(directory,'main.py')})
                except SystemExit as error:
                    code=error.code if isinstance(error.code,int) else (1 if error.code else 0)
                except BaseException:
                    code=1
                    sys.settrace(None)
                    try: traceback.print_exc(limit=12)
                    except RuntimeError: pass
                finally: sys.settrace(None)
        except BaseException as error:
            code=1
            try:output.write(type(error).__name__+': '+str(error))
            except RuntimeError:pass
        finally:
            sys.settrace(None)
            sys.stdin,sys.path=old_stdin,old_path
            os.chdir(old_cwd)
            for name in set(sys.modules)-old_modules:
                module=sys.modules.get(name)
                if str(getattr(module,'__file__','')).startswith(directory): sys.modules.pop(name,None)
    return {'output':output.getvalue(),'exitCode':code,'duration':round(time.monotonic()-started,3)}
