import Foundation
import SwiftUI

struct ExecutionResult: Codable { let output: String; let exitCode: Int; var duration: Double? }
enum DeveloperError: LocalizedError {case message(String);var errorDescription:String?{if case .message(let text)=self{return text};return nil}}

final class PythonRuntime {
    static let shared=PythonRuntime()
    private let queue=DispatchQueue(label:"rey.python",qos:.userInitiated)
    func request(_ request:[String:Any]) async throws -> Any {
        let data=try JSONSerialization.data(withJSONObject:request)
        let payload=String(decoding:data,as:UTF8.self)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let response=RYRuntimeBridge.pythonRequest(payload)
                do {
                    let object=try JSONSerialization.jsonObject(with:Data(response.utf8)) as? [String:Any] ?? [:]
                    if let error=object["error"] as? String {throw DeveloperError.message(error)}
                    guard let result=object["result"] else {throw DeveloperError.message("The runtime returned no result.")}
                    continuation.resume(returning:result)
                } catch {continuation.resume(throwing:error)}
            }
        }
    }
    func run(_ code:String, files:[String:String]=[:], input:String="") async throws -> ExecutionResult {
        let result=try await request(["action":"run","code":code,"files":files,"input":input])
        return try JSONDecoder().decode(ExecutionResult.self,from:JSONSerialization.data(withJSONObject:result))
    }
    func compile(_ code:String,target:String) async throws -> String {
        guard let text=try await request(["action":"compile","code":code,"target":target]) as? String else {throw DeveloperError.message("Compiler returned an invalid result.")};return text
    }
    func stop(){RYRuntimeBridge.cancelPython()}
}

@MainActor final class LocalModelStore:ObservableObject {
    static let shared=LocalModelStore()
    @Published var state="unloaded"
    @Published var status="Bundled Qwen2.5 Coder · 0.5B · Q4_K_M"
    @Published var busy=false
    private let engine=RYLocalModel()
    private let queue=DispatchQueue(label:"rey.local-model",qos:.userInitiated)
    func load() async throws {
        if state=="ready" {return}
        guard state != "loading" && !busy else {throw DeveloperError.message("The model is busy.")}
        guard let path=Bundle.main.path(forResource:"rey-coder",ofType:"gguf",inDirectory:"Models") else {throw DeveloperError.message("The bundled model is missing. Reinstall the complete IPA.")}
        state="loading";status="Loading on-device model…"
        do {
            try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
                queue.async {do{try self.engine.loadPath(path);continuation.resume()}catch{continuation.resume(throwing:error)}}
            }
            state="ready";status="Qwen2.5 Coder · ready on this device"
        }catch{state="error";status=error.localizedDescription;throw error}
    }
    func generate(messages:[[String:String]],onText:@escaping @MainActor (String)->Void) async throws -> String {
        guard state=="ready" else{throw DeveloperError.message("Load the local model first.")}
        guard !busy else{throw DeveloperError.message("The model is answering another request.")}
        busy=true;defer{busy=false}
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let answer=try self.engine.generate(messages,limit:768,token:{ text in Task{@MainActor in onText(text)} })
                    continuation.resume(returning:answer)
                } catch{continuation.resume(throwing:error)}
            }
        }
    }
    func stop(){engine.cancel()}
    func unload(){guard !busy && state != "loading" else{return};state="unloaded";status="Model unloaded. Tap Load model to resume.";queue.async{self.engine.unload()}}
}

struct SourceFile:Codable,Identifiable,Equatable {var id:String{name};var name:String;var text:String}
@MainActor final class IDEWorkspace:ObservableObject {
    @Published var files:[SourceFile]=[]
    @Published var selected="main.py"
    @Published var saveStatus="Saved locally"
    private let url:URL
    init(){
        url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("rey-workspace.json")
        if let data=try? Data(contentsOf:url),data.count<=2_000_000,let stored=try? JSONDecoder().decode([SourceFile].self,from:data),!stored.isEmpty,stored.count<=100,Set(stored.map(\.name)).count==stored.count,stored.allSatisfy({Self.validName($0.name) && $0.text.utf8.count<=200000}) {files=stored}
        else {files=[SourceFile(name:"main.py",text:"def greet(name):\n    return f\"Hello, {name}!\"\n\nprint(greet(\"Rey\"))\nprint([n * n for n in range(6)])\n"),SourceFile(name:"calculator.py",text:"first = float(input(\"First: \"))\nsecond = float(input(\"Second: \"))\nprint(first + second)\n")]}
        selected=files[0].name
    }
    var text:String {get{files.first{$0.name==selected}?.text ?? ""}set{if let i=files.firstIndex(where:{$0.name==selected}){files[i].text=newValue;save()}}}
    var allFiles:[String:String]{Dictionary(uniqueKeysWithValues:files.map{($0.name,$0.text)})}
    func save(){do{try JSONEncoder().encode(files).write(to:url,options:.atomic);saveStatus="Saved locally"}catch{saveStatus="Save failed: "+error.localizedDescription}}
    static func validName(_ name:String)->Bool{name.range(of:"^[A-Za-z0-9_][A-Za-z0-9_./ -]{0,79}$",options:.regularExpression) != nil && !name.contains("..") && !name.hasSuffix("/") && !name.contains("//")}
    func add(_ name:String)throws{guard Self.validName(name) else{throw DeveloperError.message("Use a relative filename such as helpers.py.")};if !files.contains(where:{$0.name==name}){guard files.count<100 else{throw DeveloperError.message("Projects support up to 100 files.")};files.append(SourceFile(name:name,text:""))};selected=name;save()}
    func importSources(_ sources:[String:String])throws{
        guard !sources.isEmpty,sources.allSatisfy({Self.validName($0.key) && $0.value.utf8.count<=200000}) else{throw DeveloperError.message("Invalid filename or source larger than 200 KB.")}
        var merged=allFiles;merged.merge(sources){_,new in new}
        guard merged.count<=100,try JSONEncoder().encode(merged).count<=2_000_000 else{throw DeveloperError.message("Projects support up to 100 files and 2 MB of source.")}
        let candidate=merged.sorted{$0.key<$1.key}.map{SourceFile(name:$0.key,text:$0.value)}
        try JSONEncoder().encode(candidate).write(to:url,options:.atomic)
        files=candidate;selected=sources.keys.sorted()[0];saveStatus="Saved locally"
    }
    func removeCurrent(){guard files.count>1 else{return};files.removeAll{$0.name==selected};selected=files[0].name;save()}
}
