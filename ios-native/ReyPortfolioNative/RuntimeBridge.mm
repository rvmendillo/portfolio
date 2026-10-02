#import "RuntimeBridge.h"
#include <Python/Python.h>
#include <llama/llama.h>
#include <atomic>
#include <vector>
#include <string>
#include <algorithm>
#include <TargetConditionals.h>

static NSError *RYError(NSString *message) {
    return [NSError errorWithDomain:@"ReyRuntime" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static NSString *JSONString(id object) {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:object options:0 error:nil] encoding:NSUTF8StringEncoding] ?: @"{}";
}
static std::atomic<bool> RYPythonCancelled(false);
static PyObject *RYShouldStop(PyObject *self,PyObject *args){return PyBool_FromLong(RYPythonCancelled.load());}
static PyMethodDef RYStopMethod={"_rey_should_stop",RYShouldStop,METH_NOARGS,"Check native stop request."};

@implementation RYRuntimeBridge
+ (NSString *)pythonRequest:(NSString *)json {
    RYPythonCancelled=false;
    // All calls enter through PythonRuntime's dedicated serial queue. The GIL is
    // acquired on every call because dispatch queues may change their OS thread.
    static dispatch_once_t once;
    static NSString *startupError=nil;
    dispatch_once(&once, ^{
        NSString *resource=NSBundle.mainBundle.resourcePath;
        PyConfig config;PyConfig_InitIsolatedConfig(&config);
        config.write_bytecode=0;config.site_import=0;config.install_signal_handlers=0;
        PyStatus status=PyConfig_SetBytesString(&config,&config.home,[[resource stringByAppendingPathComponent:@"python"] UTF8String]);
        if(!PyStatus_Exception(status))status=Py_InitializeFromConfig(&config);
        if(PyStatus_Exception(status))startupError=[NSString stringWithUTF8String:status.err_msg ?: "Python initialization failed"];
        PyConfig_Clear(&config);
        if(!startupError) {
            PyObject *paths=PySys_GetObject("path");
            PyObject *app=PyUnicode_FromString([[resource stringByAppendingPathComponent:@"app"] UTF8String]);
            PyList_Insert(paths,0,app);Py_DECREF(app);
            PyEval_SaveThread();
        }
    });
    if(startupError)return JSONString(@{@"error":startupError});
    PyGILState_STATE gil=PyGILState_Ensure();
    PyObject *globals=PyDict_New();PyDict_SetItemString(globals,"__builtins__",PyEval_GetBuiltins());
    PyObject *stop=PyCFunction_New(&RYStopMethod,nullptr);PyDict_SetItemString(globals,"_rey_should_stop",stop);Py_DECREF(stop);
    PyObject *request=PyUnicode_FromString(json.UTF8String);PyDict_SetItemString(globals,"_payload",request);Py_DECREF(request);
    const char *program=
    "import json, traceback, rey_runtime, rey_compiler\n"
    "try:\n"
    "    req=json.loads(_payload)\n"
    "    if req.get('action')=='compile':\n"
    "        result=rey_compiler.transpile(req['code'],req['target'])\n"
    "    else:\n"
    "        result=rey_runtime.run(req['code'],req.get('files',{}),req.get('input',''),cancelled=_rey_should_stop)\n"
    "    response=json.dumps({'result':result})\n"
    "except BaseException as error:\n"
    "    response=json.dumps({'error':str(error)})\n";
    PyObject *value=PyRun_String(program,Py_file_input,globals,globals);
    NSString *response;
    if(value) {
        Py_DECREF(value);PyObject *object=PyDict_GetItemString(globals,"response");
        const char *utf=object?PyUnicode_AsUTF8(object):nullptr;
        response=utf?[NSString stringWithUTF8String:utf]:JSONString(@{@"error":@"Python returned no response."});
    } else {PyErr_Print();response=JSONString(@{@"error":@"Python failed to start the program. Check the bundled runtime."});}
    PyDict_Clear(globals);Py_DECREF(globals);PyGILState_Release(gil);return response;
}
+ (void)cancelPython {RYPythonCancelled=true;}
@end

@implementation RYLocalModel {
    llama_model *_model;
    llama_context *_context;
    std::atomic<bool> _cancelled;
}
- (instancetype)init {if((self=[super init])){_model=nullptr;_context=nullptr;_cancelled=false;}return self;}
- (BOOL)loadPath:(NSString *)path error:(NSError **)error {
    [self unload];_cancelled=false;
    static dispatch_once_t once;dispatch_once(&once, ^{llama_backend_init();});
    auto params=llama_model_default_params();
#if TARGET_OS_SIMULATOR
    params.n_gpu_layers=0;
#else
    params.n_gpu_layers=99;
#endif
    _model=llama_model_load_from_file(path.UTF8String,params);
    if(!_model){if(error)*error=RYError(@"The GGUF model could not be loaded. Check available memory and the model file.");return NO;}
    auto context=llama_context_default_params();context.n_ctx=4096;context.n_batch=256;context.n_ubatch=128;
    context.n_threads=(int32_t)std::min((NSUInteger)4,NSProcessInfo.processInfo.activeProcessorCount);
    context.n_threads_batch=context.n_threads;
    _context=llama_init_from_model(_model,context);
    if(!_context){[self unload];if(error)*error=RYError(@"Not enough memory to create the model context.");return NO;}
    return YES;
}
- (NSString *)generate:(NSArray<NSDictionary<NSString *,NSString *> *> *)messages limit:(NSInteger)limit token:(void (^)(NSString *))callback error:(NSError **)error {
    if(!_context){if(error)*error=RYError(@"Load the local model first.");return nil;}
    _cancelled=false;
    std::vector<std::string> roles,contents;
    for(NSDictionary *message in messages){roles.emplace_back([message[@"role"] UTF8String]?:"user");contents.emplace_back([message[@"content"] UTF8String]?:"");}
    std::vector<llama_chat_message> chat;
    for(size_t i=0;i<roles.size();i++)chat.push_back({roles[i].c_str(),contents[i].c_str()});
    const char *tmpl=llama_model_chat_template(_model,nullptr);
    int needed=llama_chat_apply_template(tmpl,chat.data(),chat.size(),true,nullptr,0);
    if(needed<0){if(error)*error=RYError(@"This model's chat template is unsupported. Use the bundled Qwen model.");return nil;}
    std::vector<char> formatted(needed+1);
    llama_chat_apply_template(tmpl,chat.data(),chat.size(),true,formatted.data(),(int)formatted.size());
    const auto *vocab=llama_model_get_vocab(_model);
    int count=-llama_tokenize(vocab,formatted.data(),needed,nullptr,0,true,true);
    if(count<=0||count+limit>4096){if(error)*error=RYError(@"The request exceeds the model context. Start a new chat or include less code.");return nil;}
    std::vector<llama_token> tokens(count);
    count=llama_tokenize(vocab,formatted.data(),needed,tokens.data(),count,true,true);
    if(count<0){if(error)*error=RYError(@"Unable to tokenize this request.");return nil;}
    llama_memory_clear(llama_get_memory(_context),true);
    for(int offset=0;offset<count;offset+=256) {
        if(_cancelled){if(error)*error=RYError(@"Stopped.");return nil;}
        auto batch=llama_batch_get_one(tokens.data()+offset,std::min(256,count-offset));
        if(llama_decode(_context,batch)!=0){if(error)*error=RYError(@"The model could not process the prompt.");return nil;}
    }
    llama_sampler *sampler=llama_sampler_init_greedy();
    std::string answer;NSString *last=@"";
    for(NSInteger i=0;i<limit&&!_cancelled;i++) {
        auto next=llama_sampler_sample(sampler,_context,-1);
        if(llama_vocab_is_eog(vocab,next))break;
        char piece[512];int bytes=llama_token_to_piece(vocab,next,piece,sizeof(piece),0,true);
        if(bytes<0){std::vector<char> large(-bytes);bytes=llama_token_to_piece(vocab,next,large.data(),(int)large.size(),0,true);if(bytes>0)answer.append(large.data(),bytes);}
        else if(bytes>0)answer.append(piece,bytes);
        // UTF-8 characters may span tokens. Emit only complete byte sequences.
        NSString *text=[[NSString alloc] initWithBytes:answer.data() length:answer.size() encoding:NSUTF8StringEncoding];
        if(text){last=text;callback(text);}
        auto batch=llama_batch_get_one(&next,1);
        if(llama_decode(_context,batch)!=0){llama_sampler_free(sampler);if(error)*error=RYError(@"Generation failed; try a shorter request.");return nil;}
    }
    llama_sampler_free(sampler);
    if(_cancelled&&last.length==0){if(error)*error=RYError(@"Stopped.");return nil;}
    if(last.length==0){if(error)*error=RYError(@"The model returned no text.");return nil;}
    return last;
}
- (void)cancel {_cancelled=true;}
- (void)unload {if(_context){llama_free(_context);_context=nullptr;}if(_model){llama_model_free(_model);_model=nullptr;}}
- (void)dealloc {[self unload];}
@end
