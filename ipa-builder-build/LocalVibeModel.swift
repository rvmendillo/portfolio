import Foundation
import LlamaSwift

struct VibePatch { var summary:String; var components:[StudioComponent]; var widget:StudioWidgetConfig?; var variableUpdates:[String:String]=[:] }
enum VibeModelError:LocalizedError { case modelMissing,modelLoad,contextCreate,tokenize,decode; var errorDescription:String? { switch self { case .modelMissing:return "The bundled SmolLM2 model was not found.";case .modelLoad:return "SmolLM2 could not be loaded.";case .contextCreate:return "The local model context could not be created.";case .tokenize:return "The prompt could not be tokenized.";case .decode:return "Local model generation failed." } } }

final class LocalVibeModel {
    static let shared=LocalVibeModel(); private init(){}
    var modelURL:URL?{Bundle.main.url(forResource:"SmolLM2-360M-Instruct-Q4_K_M",withExtension:"gguf")}; var isBundled:Bool{modelURL != nil}
    func propose(prompt userPrompt:String,project:StudioProject)throws->String {
        guard let modelURL else{throw VibeModelError.modelMissing};llama_backend_init();defer{llama_backend_free()}
        var mp=llama_model_default_params();mp.use_mmap=true;mp.use_mlock=false
        guard let model=llama_model_load_from_file(modelURL.path,mp)else{throw VibeModelError.modelLoad};defer{llama_model_free(model)}
        var cp=llama_context_default_params();cp.n_ctx=1536;cp.n_batch=384;cp.n_threads=Int32(max(2,min(6,ProcessInfo.processInfo.activeProcessorCount)));cp.n_threads_batch=cp.n_threads
        guard let context=llama_init_from_model(model,cp)else{throw VibeModelError.contextCreate};defer{llama_free(context)}
        let current=project.components.map{$0.kind.rawValue}.joined(separator:", ")
        let system="""
You are ReyForge Local Vibe Coder. Convert requests into a tiny UI patch DSL. Output only DSL lines, no markdown.
ADD|<component kind>|<text>|<x>|<y>|<width>|<height>|<detail>
ACTION|<last component>|<action kind>|<key>|<value>
VARIABLE|<key>|<value>
WIDGET|<title>|<subtitle>|<sf symbol>|<systemSmall/systemMedium/systemLarge>
Component kinds: Text, Button, Text Field, Secure Field, Text Editor, Image, SF Symbol, Label, Toggle, Slider, Stepper, Picker, Date Picker, Color Picker, Progress View, Gauge, Divider, Spacer, Link, Menu, Navigation Link, List, Scroll View, VStack, HStack, ZStack, Form, Section, Capsule, Rounded Rectangle, Circle, Web View, Map, Share Link.
Action kinds: Show Alert, Navigate, Set Variable, Toggle Variable, Increment, Decrement, Open URL, Save Locally, GET Request, Copy Text. Canvas is 390x844. Keep elements in bounds.
"""
        let prompt="""<|im_start|>system
\(system)<|im_end|>
<|im_start|>user
App: \(project.name). Existing: \(current). Request: \(userPrompt)<|im_end|>
<|im_start|>assistant
"""
        let vocab=llama_model_get_vocab(model),utf8=prompt.utf8.count,maxTokens=max(256,utf8*2+128);var tokens=[llama_token](repeating:0,count:maxTokens)
        let tokenCount=llama_tokenize(vocab,prompt,Int32(utf8),&tokens,Int32(maxTokens),true,true);guard tokenCount>0 else{throw VibeModelError.tokenize};let promptTokens=Array(tokens.prefix(Int(tokenCount)))
        var batch=llama_batch_init(Int32(max(Int(cp.n_batch),promptTokens.count+8)),0,1);defer{llama_batch_free(batch)};batch.n_tokens=Int32(promptTokens.count)
        for i in 0..<promptTokens.count{batch.token[i]=promptTokens[i];batch.pos[i]=Int32(i);batch.n_seq_id[i]=1;if let seqIDs=batch.seq_id,let seqID=seqIDs[i]{seqID[0]=0};batch.logits[i]=0};if batch.n_tokens>0{batch.logits[Int(batch.n_tokens)-1]=1}
        guard llama_decode(context,batch)==0 else{throw VibeModelError.decode};var output="",nCur=batch.n_tokens;let vocabSize=Int(llama_vocab_n_tokens(vocab))
        for _ in 0..<260{guard let logits=llama_get_logits_ith(context,batch.n_tokens-1)else{throw VibeModelError.decode};var maxLogit=logits[0],next:llama_token=0;if vocabSize>1{for i in 1..<vocabSize where logits[i]>maxLogit{maxLogit=logits[i];next=llama_token(i)}};if next==llama_vocab_eos(vocab){break};var buffer=[CChar](repeating:0,count:128);let length=llama_token_to_piece(vocab,next,&buffer,Int32(buffer.count),0,false);if length>0{let bytes=buffer.prefix(Int(length)).map{UInt8(bitPattern:$0)};if let piece=String(bytes:bytes,encoding:.utf8){output+=piece;if output.contains("<|im_end|>"){break}}};batch.n_tokens=1;batch.token[0]=next;batch.pos[0]=nCur;batch.n_seq_id[0]=1;if let seqIDs=batch.seq_id,let seqID=seqIDs[0]{seqID[0]=0};batch.logits[0]=1;nCur+=1;guard llama_decode(context,batch)==0 else{throw VibeModelError.decode}}
        return output.replacingOccurrences(of:"<|im_end|>",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
    }
}

enum VibePatchParser {
    static func parse(_ output:String,fallbackPrompt:String,project:StudioProject)->VibePatch{
        var added:[StudioComponent]=[],widget:StudioWidgetConfig?,vars:[String:String]=[:],last:Int?
        for raw in output.split(whereSeparator:\.isNewline){let p=raw.split(separator:"|",omittingEmptySubsequences:false).map(String.init);guard let cmd=p.first?.uppercased()else{continue};switch cmd{
        case "ADD" where p.count>=7: guard let kind=StudioComponentKind(rawValue:p[1])else{continue};var c=StudioComponent.make(kind);c.text=p[2];c.x=Double(p[3]) ?? 195;c.y=Double(p[4]) ?? 120;c.width=Double(p[5]) ?? kind.defaultSize.width;c.height=Double(p[6]) ?? kind.defaultSize.height;if p.count>7{c.detail=p[7]};c.x=min(max(c.width/2,c.x),390-c.width/2);c.y=max(c.height/2,c.y);added.append(c);last=added.count-1
        case "ACTION" where p.count>=5: guard let i=last,let kind=StudioActionKind(rawValue:p[2])else{continue};added[i].actions.append(.init(kind:kind,key:p[3],value:p[4]))
        case "VARIABLE" where p.count>=3:vars[p[1]]=p[2]
        case "WIDGET" where p.count>=5:var w=project.widget;w.enabled=true;w.title=p[1];w.subtitle=p[2];w.symbol=p[3].isEmpty ? "sparkles":p[3];w.family=["systemSmall","systemMedium","systemLarge"].contains(p[4]) ? p[4]:"systemMedium";widget=w
        default:continue}}
        if added.isEmpty && widget==nil && vars.isEmpty{return heuristic(prompt:fallbackPrompt,project:project)}
        return VibePatch(summary:"Local SmolLM2 proposed \(added.count) component change(s).",components:added,widget:widget,variableUpdates:vars)
    }
    static func heuristic(prompt:String,project:StudioProject)->VibePatch{let p=prompt.lowercased();var cs:[StudioComponent]=[],widget:StudioWidgetConfig?;func make(_ k:StudioComponentKind,_ t:String,_ y:Double){var c=StudioComponent.make(k,x:195,y:y);c.text=t;if k==.button{c.width=300};cs.append(c)}
        if p.contains("login")||p.contains("sign in"){make(.text,"Welcome",120);make(.textField,"Email",210);make(.secureField,"Password",280);var b=StudioComponent.make(.button,x:195,y:370);b.text="Sign In";b.width=300;b.actions=[.init(kind:.showAlert,key:"Success",value:"Signed in")];cs.append(b)}
        else if p.contains("settings"){make(.text,"Settings",90);make(.toggle,"Notifications",180);make(.toggle,"Use Face ID",250);make(.picker,"Theme",330);make(.button,"Save",420)}
        else if p.contains("widget"){var w=project.widget;w.enabled=true;w.title=project.name;w.subtitle="Built with ReyForge";widget=w}
        else if p.contains("form"){make(.textField,"Name",130);make(.textField,"Email",205);make(.textEditor,"Message",330);make(.button,"Submit",470)}
        else{make(.text,project.name,100);make(.button,"Continue",190)}
        return VibePatch(summary:"Applied an offline fallback patch while keeping the project editable.",components:cs,widget:widget)
    }
}
