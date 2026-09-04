import Foundation
import SwiftUI

enum StudioComponentKind: String, Codable, CaseIterable, Identifiable {
    case text = "Text", button = "Button", textField = "Text Field", secureField = "Secure Field", textEditor = "Text Editor"
    case image = "Image", symbol = "SF Symbol", label = "Label", toggle = "Toggle", slider = "Slider", stepper = "Stepper"
    case picker = "Picker", datePicker = "Date Picker", colorPicker = "Color Picker", progress = "Progress View", gauge = "Gauge"
    case divider = "Divider", spacer = "Spacer", link = "Link", menu = "Menu", navigationLink = "Navigation Link"
    case list = "List", scrollView = "Scroll View", vStack = "VStack", hStack = "HStack", zStack = "ZStack", form = "Form", section = "Section"
    case capsule = "Capsule", roundedRectangle = "Rounded Rectangle", circle = "Circle", webView = "Web View", map = "Map", shareLink = "Share Link"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .text: return "textformat"; case .button: return "rectangle.and.hand.point.up.left"; case .textField: return "character.cursor.ibeam"
        case .secureField: return "lock.rectangle"; case .textEditor: return "note.text"; case .image: return "photo"; case .symbol: return "sparkles"
        case .label: return "tag"; case .toggle: return "switch.2"; case .slider: return "slider.horizontal.3"; case .stepper: return "plusminus"
        case .picker: return "list.bullet.circle"; case .datePicker: return "calendar"; case .colorPicker: return "paintpalette"; case .progress: return "progress.indicator"
        case .gauge: return "gauge.with.dots.needle.50percent"; case .divider: return "minus"; case .spacer: return "arrow.up.and.down"; case .link: return "link"
        case .menu: return "ellipsis.circle"; case .navigationLink: return "chevron.right"; case .list: return "list.bullet"; case .scrollView: return "scroll"
        case .vStack: return "square.stack.3d.down.right"; case .hStack: return "rectangle.split.3x1"; case .zStack: return "square.3.layers.3d"; case .form: return "list.clipboard"
        case .section: return "rectangle.3.group"; case .capsule: return "capsule"; case .roundedRectangle: return "rectangle.roundedtop"; case .circle: return "circle"
        case .webView: return "safari"; case .map: return "map"; case .shareLink: return "square.and.arrow.up"
        }
    }
    var category: String {
        switch self {
        case .text,.label,.image,.symbol,.progress,.gauge,.divider,.capsule,.roundedRectangle,.circle: return "Display"
        case .button,.link,.menu,.navigationLink,.shareLink: return "Actions"
        case .textField,.secureField,.textEditor,.toggle,.slider,.stepper,.picker,.datePicker,.colorPicker: return "Inputs"
        case .list,.scrollView,.vStack,.hStack,.zStack,.form,.section,.spacer: return "Layout"
        case .webView,.map: return "Advanced"
        }
    }
    var defaultSize: CGSize {
        switch self {
        case .text: return .init(width:220,height:44); case .button: return .init(width:220,height:52)
        case .textField,.secureField,.picker,.datePicker,.colorPicker,.toggle,.slider,.stepper: return .init(width:260,height:52)
        case .textEditor: return .init(width:280,height:120); case .image,.webView,.map: return .init(width:280,height:180)
        case .symbol,.progress,.gauge: return .init(width:120,height:90); case .label,.link,.menu,.navigationLink,.shareLink: return .init(width:220,height:48)
        case .list,.scrollView,.form: return .init(width:300,height:260); case .vStack,.hStack,.zStack,.section: return .init(width:280,height:180)
        case .divider: return .init(width:280,height:20); case .spacer: return .init(width:200,height:40); case .capsule,.roundedRectangle,.circle: return .init(width:140,height:80)
        }
    }
}

enum StudioActionKind: String, Codable, CaseIterable, Identifiable {
    case showAlert="Show Alert", navigate="Navigate", setVariable="Set Variable", toggleVariable="Toggle Variable", increment="Increment", decrement="Decrement"
    case openURL="Open URL", saveLocal="Save Locally", apiGET="GET Request", copyText="Copy Text"
    var id:String{rawValue}
    var icon:String { switch self { case .showAlert:return "exclamationmark.bubble"; case .navigate:return "arrow.right.circle"; case .setVariable:return "equal.circle"; case .toggleVariable:return "switch.2"; case .increment:return "plus.circle"; case .decrement:return "minus.circle"; case .openURL:return "link.circle"; case .saveLocal:return "internaldrive"; case .apiGET:return "network"; case .copyText:return "doc.on.doc" } }
}
struct StudioAction: Identifiable,Codable,Equatable { var id=UUID(); var kind:StudioActionKind = .showAlert; var key="message"; var value="Hello from ReyForge" }
struct StudioComponent: Identifiable,Codable,Equatable {
    var id=UUID(); var kind:StudioComponentKind; var text:String; var detail=""; var x:Double; var y:Double; var width:Double; var height:Double
    var value:Double=0.5; var isOn=true; var options=["One","Two","Three"]; var cornerRadius:Double=14; var fontSize:Double=17; var actions:[StudioAction]=[]
    static func make(_ kind:StudioComponentKind,x:Double=195,y:Double=120)->StudioComponent {
        let size=kind.defaultSize; let text:String; let detail:String
        switch kind {
        case .text:text="Heading";detail=""; case .button:text="Continue";detail=""; case .textField:text="Email";detail=""; case .secureField:text="Password";detail=""
        case .textEditor:text="Write something…";detail=""; case .image:text="photo";detail=""; case .symbol:text="sparkles";detail=""; case .label:text="Label";detail="star.fill"
        case .toggle:text="Enable feature";detail=""; case .slider:text="Value";detail=""; case .stepper:text="Quantity";detail=""; case .picker:text="Choose";detail=""
        case .datePicker:text="Date";detail=""; case .colorPicker:text="Tint";detail=""; case .progress:text="Progress";detail=""; case .gauge:text="Gauge";detail=""
        case .divider:text="";detail=""; case .spacer:text="Spacer";detail=""; case .link:text="Open Website";detail="https://example.com"; case .menu:text="Menu";detail=""
        case .navigationLink:text="Next Screen";detail="reyforge://detail"; case .list:text="List";detail=""; case .scrollView:text="Scroll View";detail=""; case .vStack:text="VStack";detail=""
        case .hStack:text="HStack";detail=""; case .zStack:text="ZStack";detail=""; case .form:text="Form";detail=""; case .section:text="Section";detail=""
        case .capsule:text="Capsule";detail=""; case .roundedRectangle:text="Rounded Rectangle";detail=""; case .circle:text="Circle";detail=""; case .webView:text="Web View";detail="https://apple.com"
        case .map:text="Map";detail="Manila"; case .shareLink:text="Share";detail="Made with ReyForge"
        }
        return .init(kind:kind,text:text,detail:detail,x:x,y:y,width:size.width,height:size.height)
    }
}
struct StudioWidgetConfig:Codable,Equatable { var enabled=false; var displayName="My Widget"; var title="Hello"; var subtitle="Built with ReyForge"; var symbol="sparkles"; var family="systemMedium"; var deepLink="reyforge://home" }
struct StudioProject:Identifiable,Codable,Equatable { var id=UUID(); var name:String; var bundleIdentifier:String; var components:[StudioComponent]; var widget=StudioWidgetConfig(); var variables=["message":"Hello","count":"0","enabled":"true"]; var createdAt=Date(); var modifiedAt=Date() }

enum StudioTemplate:String,CaseIterable,Identifiable {
    case blank="Blank", login="Login", dashboard="Dashboard", settings="Settings", profile="Profile", commerce="Commerce", componentGallery="Native Component Gallery", widgetStarter="Widget Starter"
    var id:String{rawValue}; var icon:String { switch self { case .blank:return "doc"; case .login:return "person.badge.key"; case .dashboard:return "rectangle.3.group"; case .settings:return "gearshape"; case .profile:return "person.crop.circle"; case .commerce:return "cart"; case .componentGallery:return "square.grid.3x3"; case .widgetStarter:return "square.grid.2x2" } }
    func project(name:String?=nil)->StudioProject {
        let projectName=name ?? rawValue; let slug=projectName.lowercased().filter{$0.isLetter||$0.isNumber}; var cs:[StudioComponent]=[]
        func add(_ k:StudioComponentKind,_ t:String,_ x:Double,_ y:Double,_ w:Double?=nil,_ h:Double?=nil){var c=StudioComponent.make(k,x:x,y:y);c.text=t;if let w{c.width=w};if let h{c.height=h};cs.append(c)}
        switch self {
        case .blank:add(.text,"Start building",195,100,260,50)
        case .login:
            add(.symbol,"person.crop.circle.fill",195,90,100,100);add(.text,"Welcome back",195,165,280,50);add(.textField,"Email",195,245,300,52);add(.secureField,"Password",195,315,300,52)
            var b=StudioComponent.make(.button,x:195,y:395);b.text="Sign In";b.width=300;b.actions=[.init(kind:.showAlert,key:"Signed in",value:"Welcome!")];cs.append(b);add(.link,"Forgot password?",195,455,220,44)
        case .dashboard:add(.text,"Dashboard",195,65,300,50);add(.gauge,"Progress",95,150,150,110);add(.progress,"Completion",275,150,150,110);add(.list,"Recent Activity",195,350,330,260);add(.button,"Add Item",195,540,260,52)
        case .settings:add(.text,"Settings",195,60,300,50);add(.toggle,"Notifications",195,145,310,52);add(.toggle,"Use Face ID",195,210,310,52);add(.slider,"Text Size",195,285,310,60);add(.picker,"Theme",195,365,310,52);add(.navigationLink,"Privacy",195,435,310,52);add(.button,"Save",195,520,280,52)
        case .profile:add(.image,"person.crop.circle",195,115,150,150);add(.text,"Your Name",195,220,280,48);add(.label,"Software Engineer",195,265,260,44);add(.textEditor,"Bio",195,375,320,150);add(.shareLink,"Share Profile",195,510,260,50)
        case .commerce:add(.text,"Store",195,60,300,50);add(.image,"bag.fill",195,190,300,200);add(.text,"Featured Product",195,315,300,48);add(.stepper,"Quantity",195,390,300,52);add(.button,"Add to Cart",195,470,300,52);add(.shareLink,"Share Product",195,535,260,48)
        case .componentGallery:
            for (i,k) in StudioComponentKind.allCases.enumerated(){let col=i%2,row=i/2;var c=StudioComponent.make(k,x:col==0 ? 105:285,y:70+Double(row)*92);c.width=160;c.height=min(c.height,72);cs.append(c)}
        case .widgetStarter:add(.text,"Widget Companion",195,85,300,50);add(.symbol,"sparkles",195,190,120,120);add(.textField,"Widget title",195,300,300,52);add(.button,"Update Widget",195,385,300,52)
        }
        var w=StudioWidgetConfig(); if self == .widgetStarter { w.enabled=true;w.displayName="ReyForge Widget";w.title="ReyForge";w.subtitle="Built visually on iPhone" }
        return StudioProject(name:projectName,bundleIdentifier:"com.rvmendillo.\(slug.isEmpty ? "app":slug)",components:cs,widget:w)
    }
}

@MainActor final class StudioStore:ObservableObject {
    @Published var projects:[StudioProject]=[]; @Published var selectedID:UUID?; @Published var selectedComponentID:UUID?; private let key="reyforge.projects.v2"
    init(){load();if projects.isEmpty{let p=StudioTemplate.login.project(name:"My App");projects=[p];selectedID=p.id;selectedComponentID=p.components.first?.id;save()}else{selectedID=projects.first?.id;selectedComponentID=projects.first?.components.first?.id}}
    var selectedIndex:Int?{guard let id=selectedID else{return nil};return projects.firstIndex{$0.id==id}}
    var selected:StudioProject?{guard let i=selectedIndex else{return nil};return projects[i]}
    var selectedComponent:StudioComponent?{guard let p=selected,let id=selectedComponentID else{return nil};return p.components.first{$0.id==id}}
    func newProject(template:StudioTemplate,name:String?=nil){let p=template.project(name:name);projects.append(p);selectedID=p.id;selectedComponentID=p.components.first?.id;save()}
    func duplicateCurrent(){guard var p=selected else{return};p.id=UUID();p.name+=" Copy";p.bundleIdentifier+=".copy";p.components=p.components.map{old in var c=old;c.id=UUID();c.actions=c.actions.map{a in var x=a;x.id=UUID();return x};return c};projects.append(p);selectedID=p.id;selectedComponentID=p.components.first?.id;save()}
    func add(_ kind:StudioComponentKind,at point:CGPoint?=nil){guard let i=selectedIndex else{return};let n=projects[i].components.count;let p=point ?? CGPoint(x:195,y:90+Double(n%10)*64);var c=StudioComponent.make(kind,x:p.x,y:p.y);c.x=min(max(c.width/2,c.x),390-c.width/2);c.y=max(c.height/2,c.y);projects[i].components.append(c);projects[i].modifiedAt=Date();selectedComponentID=c.id;save()}
    func updateComponent(_ c:StudioComponent){guard let i=selectedIndex,let j=projects[i].components.firstIndex(where:{$0.id==c.id})else{return};projects[i].components[j]=c;projects[i].modifiedAt=Date();save()}
    func moveSelected(to p:CGPoint){guard var c=selectedComponent else{return};c.x=min(max(c.width/2,p.x),390-c.width/2);c.y=max(c.height/2,p.y);updateComponent(c)}
    func resizeSelected(width:Double,height:Double){guard var c=selectedComponent else{return};c.width=min(max(44,width),370);c.height=min(max(28,height),720);c.x=min(max(c.width/2,c.x),390-c.width/2);updateComponent(c)}
    func deleteSelectedComponent(){guard let i=selectedIndex,let id=selectedComponentID else{return};projects[i].components.removeAll{$0.id==id};selectedComponentID=projects[i].components.first?.id;save()}
    func addAction(_ kind:StudioActionKind){guard var c=selectedComponent else{return};c.actions.append(.init(kind:kind));updateComponent(c)}
    func updateAction(_ a:StudioAction){guard var c=selectedComponent,let i=c.actions.firstIndex(where:{$0.id==a.id})else{return};c.actions[i]=a;updateComponent(c)}
    func deleteAction(_ id:UUID){guard var c=selectedComponent else{return};c.actions.removeAll{$0.id==id};updateComponent(c)}
    func updateProject(_ transform:(inout StudioProject)->Void){guard let i=selectedIndex else{return};transform(&projects[i]);projects[i].modifiedAt=Date();save()}
    func save(){if let d=try? JSONEncoder().encode(projects){UserDefaults.standard.set(d,forKey:key)}}
    private func load(){guard let d=UserDefaults.standard.data(forKey:key),let p=try? JSONDecoder().decode([StudioProject].self,from:d)else{return};projects=p}
}
