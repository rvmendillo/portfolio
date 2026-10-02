import Foundation

enum DesignerCodec {
    static func validate(_ package:NativePackage)throws{
        let nodes=package.nodes,links=package.connections,ids=Set(nodes.map(\.id)),names=Set(nodes.map(\.name))
        guard !nodes.isEmpty,nodes.count<=50,links.count<=100,ids.count==nodes.count,names.count==nodes.count else{throw DeveloperError.message("Use 1–50 components with unique IDs and at most 100 connections.")}
        guard nodes.allSatisfy({$0.name.range(of:"^[A-Za-z_][A-Za-z0-9_]{0,31}$",options:.regularExpression) != nil && $0.x.isFinite && $0.y.isFinite && (0...900).contains($0.x) && (0...900).contains($0.y) && $0.text.count<=200 && $0.formula.count<=180}),links.allSatisfy({ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to}) else{throw DeveloperError.message("Check component names, positions, text lengths and connection endpoints.")}
    }
    static func quote(_ text:String)->String {
        guard let data=try? JSONEncoder().encode(text),let value=String(data:data,encoding:.utf8) else{return "\"\""};return value
    }
    static func parse(_ source:String)throws->NativePackage {
        guard source.count<100000 else{throw DeveloperError.message("Design exceeds 100 KB.")}
        var name="Imported App",section="",components:[[String:String]]=[],links:[[String:String]]=[]
        func scalar(_ raw:String)->String {
            let value=raw.trimmingCharacters(in:.whitespaces)
            if value.hasPrefix("\""),let decoded=try? JSONDecoder().decode(String.self,from:Data(value.utf8)){return decoded}
            if value.hasPrefix("'")&&value.hasSuffix("'"){return String(value.dropFirst().dropLast())};return value
        }
        for (index,raw) in source.components(separatedBy:.newlines).enumerated(){
            let line=raw.trimmingCharacters(in:.whitespaces)
            if line.isEmpty||line.hasPrefix("#"){continue}
            if line=="components:"{section="components";continue}
            if line=="connections:"{section="connections";continue}
            guard let colon=line.firstIndex(of:":") else{throw DeveloperError.message("YAML line \(index+1): expected key: value.")}
            let key=String(line[..<colon]).replacingOccurrences(of:"- ",with:"").trimmingCharacters(in:.whitespaces),value=scalar(String(line[line.index(after:colon)...]))
            if key=="app"{name=value;continue}
            if section=="components"{
                if line.hasPrefix("- id:"){components.append(["id":value])}
                else if !components.isEmpty{components[components.count-1][key]=value}
                else{throw DeveloperError.message("Add a component id first.")}
            }else if section=="connections"{
                if line.hasPrefix("- from:"){links.append(["from":value])}
                else if !links.isEmpty{links[links.count-1][key]=value}
                else{throw DeveloperError.message("Add a connection source first.")}
            }else{throw DeveloperError.message("Unknown YAML section at line \(index+1).")}
        }
        guard !components.isEmpty,components.count<=50,links.count<=100 else{throw DeveloperError.message("A design needs 1–50 components and at most 100 connections.")}
        var nodes:[DesignerNode]=[],ids:[String:UUID]=[:]
        for (index,item) in components.enumerated(){
            guard let id=item["id"],id.range(of:"^[A-Za-z_][A-Za-z0-9_]{0,31}$",options:.regularExpression) != nil,ids[id]==nil,let kind=DesignerNodeKind(rawValue:item["type"] ?? "") else{throw DeveloperError.message("Component IDs must be unique identifiers; choose label, input, button, or output.")}
            var node=DesignerNode(kind:kind,index:index+1);node.name=id;node.text=String((item["text"] ?? kind.title).prefix(200));node.x=min(900,max(0,Double(item["x"] ?? "80") ?? 80));node.y=min(900,max(0,Double(item["y"] ?? "80") ?? 80))
            let action=item["operation"] ?? "none";guard let operation=DesignerOperation(rawValue:action=="upper" ? "uppercase" : action=="lower" ? "lowercase" : action) else{throw DeveloperError.message("Unknown operation: "+action)};node.operation=operation
            node.formula=String((item["formula"] ?? "").prefix(180));ids[id]=node.id;nodes.append(node)
        }
        let connections=try links.map{item->DesignerConnection in
            guard let from=ids[item["from"] ?? ""],let to=ids[item["to"] ?? ""],from != to else{throw DeveloperError.message("Every connection must refer to two different component IDs.")}
            return DesignerConnection(from:from,to:to)
        }
        let package=NativePackage(name:String(name.prefix(48)),nodes:nodes,connections:connections);try validate(package);return package
    }
}
