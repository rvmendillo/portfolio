"""AST based Python -> Java/C++ lowering with explicit diagnostics.

Portable typed subset: scalar/list expressions, indexing, functions, classes,
inheritance, conditions, range/list loops, comprehensions and common builtins.
Dynamic or ambiguous constructs are rejected rather than silently discarded.
"""
import ast
import json

class CompileError(ValueError): pass

def transpile(source,target='java'):
    if target.lower()=='python':
        ast.parse(source)
        return source
    if target.lower() not in ('java','cpp','c++'):raise CompileError('Choose Java, C++, or Python.')
    return Compiler(source,target.lower()=='java').compile()

class Compiler:
    def __init__(self,source,java):
        if len(source)>200000:raise CompileError('Source exceeds 200 KB.')
        self.tree=ast.parse(source)
        self.java=java
        self.env={}
        self.classes={n.name:n for n in self.tree.body if isinstance(n,ast.ClassDef)}
        self.functions={n.name:n for n in self.tree.body if isinstance(n,ast.FunctionDef)}
        self.signatures={}
        self.fields={name:{} for name in self.classes}
        self.owner=None
        self.output=[]
        self.level=0
    def error(self,node,message):raise CompileError(f'Line {getattr(node,"lineno",1)}: {message}')
    def line(self,text=''):self.output.append('    '*self.level+text)
    def typ(self,t,boxed=False):
        if isinstance(t,tuple):return ('java.util.List<'+self.typ(t[1],True)+'>' if self.java else 'std::vector<'+self.typ(t[1])+'>')
        if self.java:return {'int':'Long' if boxed else 'long','float':'Double' if boxed else 'double','bool':'Boolean' if boxed else 'boolean','str':'String','void':'void'}.get(t,t)
        return {'int':'long long','float':'double','bool':'bool','str':'std::string','void':'void'}.get(t,t)
    def annotation(self,node):
        if isinstance(node,ast.Name):return {'int':'int','float':'float','str':'str','bool':'bool'}.get(node.id,node.id)
        if isinstance(node,ast.Subscript) and isinstance(node.value,ast.Name) and node.value.id in ('list','List'):return ('list',self.annotation(node.slice))
        if isinstance(node,ast.Constant) and node.value is None:return 'void'
        return None
    def infer(self,n,env=None):
        env=self.env if env is None else env
        if isinstance(n,ast.Constant):return 'bool' if isinstance(n.value,bool) else 'int' if isinstance(n.value,int) else 'float' if isinstance(n.value,float) else 'str' if isinstance(n.value,str) else 'void'
        if isinstance(n,ast.Name):return env.get(n.id,'int')
        if isinstance(n,ast.JoinedStr):return 'str'
        if isinstance(n,(ast.Compare,ast.BoolOp)):return 'bool'
        if isinstance(n,ast.UnaryOp):return 'bool' if isinstance(n.op,ast.Not) else self.infer(n.operand,env)
        if isinstance(n,ast.List):return ('list',self.infer(n.elts[0],env) if n.elts else 'int')
        if isinstance(n,ast.ListComp):
            local=dict(env);gen=n.generators[0];it=self.infer(gen.iter,env);local[gen.target.id]=it[1] if isinstance(it,tuple) else 'int';return ('list',self.infer(n.elt,local))
        if isinstance(n,ast.Subscript):
            t=self.infer(n.value,env);return t[1] if isinstance(t,tuple) else 'str'
        if isinstance(n,ast.Attribute):
            owner=self.owner if isinstance(n.value,ast.Name) and n.value.id=='self' else self.infer(n.value,env)
            return self.fields.get(owner,{}).get(n.attr,'int')
        if isinstance(n,ast.BinOp):
            a,b=self.infer(n.left,env),self.infer(n.right,env)
            if isinstance(n.op,(ast.Div,ast.Pow)):return 'float'
            if a=='str' or b=='str':return 'str'
            return 'float' if 'float' in (a,b) else a
        if isinstance(n,ast.IfExp):return self.infer(n.body,env)
        if isinstance(n,ast.Call):
            name=n.func.id if isinstance(n.func,ast.Name) else n.func.attr if isinstance(n.func,ast.Attribute) else ''
            if name in self.classes:return name
            if name in ('str','input','upper','lower','strip','join'):return 'str'
            if name in ('len','int','sum'):return 'int'
            if name=='float':return 'float'
            if name=='range':return ('list','int')
            if name in self.signatures:return self.signatures[name][1]
            if isinstance(n.func,ast.Attribute):
                owner=self.infer(n.func.value,env);return self.signatures.get(str(owner)+'.'+name,([], 'int'))[1]
        return 'int'
    def signature(self,node,owner=None):
        args=node.args.args[1:] if owner and node.args.args and node.args.args[0].arg=='self' else node.args.args
        if node.args.vararg or node.args.kwarg or node.args.kwonlyargs or node.args.posonlyargs or node.args.defaults:self.error(node,'Use required positional parameters; defaults and variable parameters need explicit lowering.')
        candidates=[]
        for call in ast.walk(self.tree):
            if not isinstance(call,ast.Call):continue
            name=call.func.id if isinstance(call.func,ast.Name) else call.func.attr if isinstance(call.func,ast.Attribute) else ''
            if name==(owner if node.name=='__init__' else node.name):candidates.append(call.args)
        params=[]
        for i,arg in enumerate(args):
            t=self.annotation(arg.annotation)
            if not t:
                candidate=next((c[i] for c in candidates if i<len(c)),None)
                if candidate is not None:t=self.infer(candidate)
                elif i>=len(args)-len(node.args.defaults):t=self.infer(node.args.defaults[i-(len(args)-len(node.args.defaults))])
                else:t='int'
            params.append((arg.arg,t))
        local=dict(params)
        for item in ast.walk(node):
            if isinstance(item,ast.Assign) and len(item.targets)==1 and isinstance(item.targets[0],ast.Name):local[item.targets[0].id]=self.infer(item.value,local)
            if owner and isinstance(item,ast.Assign) and isinstance(item.targets[0],ast.Attribute) and isinstance(item.targets[0].value,ast.Name) and item.targets[0].value.id=='self':self.fields[owner][item.targets[0].attr]=self.infer(item.value,local)
        returns=[r for r in ast.walk(node) if isinstance(r,ast.Return) and r.value]
        ret=self.annotation(node.returns) or (self.infer(returns[0].value,local) if returns else 'void')
        return params,ret
    def compile(self):
        for n in self.tree.body:
            if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name):self.env[n.targets[0].id]=self.infer(n.value)
        for _ in range(3):
            for owner,node in self.classes.items():
                self.owner=owner
                for base in node.bases:
                    if isinstance(base,ast.Name):self.fields[owner].update(self.fields.get(base.id,{}))
                for method in node.body:
                    if isinstance(method,ast.FunctionDef):self.signatures[owner+'.'+method.name]=self.signature(method,owner)
            self.owner=None
            for name,node in self.functions.items():self.signatures[name]=self.signature(node)
        self.line(JAVA_RUNTIME if self.java else CPP_RUNTIME)
        if self.java:self.line('public class Main {');self.level=1
        if not self.java:
            for name,(args,ret) in self.signatures.items():
                if '.' not in name:self.line(self.typ(ret)+' '+name+'('+', '.join(self.typ(t)+' '+a for a,t in args)+');')
        for owner,node in self.classes.items():self.classdef(node)
        for node in self.functions.values():self.function(node)
        self.owner=None;self.env={}
        self.line('public static void main(String[] args) {' if self.java else 'int main() {');self.level+=1
        for n in self.tree.body:
            if not isinstance(n,(ast.ClassDef,ast.FunctionDef)):self.statement(n)
        if not self.java:self.line('return 0;')
        self.level-=1;self.line('}')
        if self.java:self.level-=1;self.line('}')
        return '\n'.join(self.output)+'\n'
    def classdef(self,node):
        if node.decorator_list:self.error(node,'Class decorators are not portable.')
        if len(node.bases)>1:self.error(node,'Multiple inheritance is not supported in the Java/C++ common subset.')
        base=node.bases[0].id if node.bases and isinstance(node.bases[0],ast.Name) else None
        self.line(('static class ' if self.java else 'class ')+node.name+((' extends ' if self.java else ' : public ')+base if base else '')+' {');self.level+=1
        self.owner=node.name
        if not self.java:self.line('public:')
        inherited=self.fields.get(base,{}) if base else {}
        for name,t in self.fields[node.name].items():
            if name not in inherited:self.line(('public ' if self.java else '')+self.typ(t)+' '+name+';')
        for n in node.body:
            if isinstance(n,ast.FunctionDef):self.function(n,node.name)
            elif isinstance(n,ast.Pass) or isinstance(n,ast.Expr) and isinstance(n.value,ast.Constant):pass
            else:self.error(n,'Only methods and instance fields are supported in a class.')
        self.level-=1;self.line('}' if self.java else '};');self.owner=None
    def function(self,node,owner=None):
        for decorator in node.decorator_list:
            if not isinstance(decorator,ast.Name) or decorator.id not in ('staticmethod','override'):self.error(decorator,'Decorator is not supported.')
        params,ret=self.signatures[(owner+'.' if owner else '')+node.name]
        previous=self.env;self.env=dict(params)
        if owner:self.env['self']=owner
        constructor=owner and node.name=='__init__'
        static=not owner or any(isinstance(d,ast.Name) and d.id=='staticmethod' for d in node.decorator_list)
        prefix=('public '+('static ' if static else '')) if self.java else ('virtual ' if owner and not constructor and not static else '')
        title=owner if constructor else self.typ(ret)+' '+node.name
        self.line(prefix+title+'('+', '.join(self.typ(t)+' '+a for a,t in params)+') {');self.level+=1
        for n in node.body:self.statement(n)
        self.level-=1;self.line('}');self.env=previous
    def statement(self,n):
        if isinstance(n,(ast.Import,ast.ImportFrom)):
            self.error(n,'Imports require a target-specific library; remove the import or export the Python source.')
        if isinstance(n,ast.Pass):self.line(';');return
        if isinstance(n,ast.Expr):
            if isinstance(n.value,ast.Constant) and isinstance(n.value.value,str):return
            self.line(self.expr(n.value)+';');return
        if isinstance(n,(ast.Assign,ast.AnnAssign)):
            targets=n.targets if isinstance(n,ast.Assign) else [n.target]
            if len(targets)!=1:self.error(n,'Use separate assignments.')
            target=targets[0]
            if n.value is None:self.error(n,'Initialize annotated variables.')
            t=self.annotation(n.annotation) if isinstance(n,ast.AnnAssign) else self.infer(n.value)
            if isinstance(target,ast.Name):
                name=target.id
                if name in self.env and self.env[name]!=t:self.error(n,'Variable changes type; use separate typed variables.')
                prefix='' if name in self.env else self.typ(t)+' '
                self.env[name]=t;self.line(prefix+name+' = '+self.expr(n.value)+';');return
            if isinstance(target,ast.Attribute):self.line(self.expr(target)+' = '+self.expr(n.value)+';');return
            if isinstance(target,ast.Subscript):
                a,b,c=self.expr(target.value),self.expr(target.slice),self.expr(n.value)
                self.line(a+'.set((int)('+b+'), '+c+');' if self.java else a+'.at('+b+') = '+c+';');return
            self.error(n,'Assignment target is not supported.')
        if isinstance(n,ast.AugAssign):self.line(self.expr(n.target)+' '+self.op(n.op)+'= '+self.expr(n.value)+';');return
        if isinstance(n,ast.Return):self.line('return'+(' '+self.expr(n.value) if n.value else '')+';');return
        if isinstance(n,(ast.If,ast.While)):
            if isinstance(n,ast.While) and n.orelse:self.error(n,'while/else needs explicit target code.')
            previous=dict(self.env)
            self.line(('if' if isinstance(n,ast.If) else 'while')+' ('+self.truth(n.test)+') {');self.level+=1
            for x in n.body:self.statement(x)
            self.level-=1;self.line('}');self.env=dict(previous)
            if n.orelse:
                self.line('else {');self.level+=1
                for x in n.orelse:self.statement(x)
                self.level-=1;self.line('}');self.env=previous
            return
        if isinstance(n,ast.For):
            if n.orelse or not isinstance(n.target,ast.Name):self.error(n,'Use a simple loop variable without for/else.')
            t=self.infer(n.iter);name=n.target.id
            if not isinstance(t,tuple):self.error(n,'Loop over a list or range.')
            previous=dict(self.env);self.env[name]=t[1]
            self.line('for ('+self.typ(t[1])+' '+name+' : '+self.expr(n.iter)+') {');self.level+=1
            for x in n.body:self.statement(x)
            self.level-=1;self.line('}')
            self.env=previous
            return
        if isinstance(n,(ast.Break,ast.Continue)):self.line('break;' if isinstance(n,ast.Break) else 'continue;');return
        if isinstance(n,ast.Assert):self.line(('if (!('+self.truth(n.test)+')) throw new RuntimeException("Assertion failed");') if self.java else 'if (!('+self.truth(n.test)+')) throw std::runtime_error("Assertion failed");');return
        self.error(n,type(n).__name__+' cannot be lowered reliably.')
    def truth(self,n):
        value=self.expr(n);t=self.infer(n)
        if t=='bool':return value
        if t in ('int','float'):return '('+value+' != 0)'
        if t=='str' or isinstance(t,tuple):return '('+value+('.length()' if self.java and t=='str' else '.size()')+' != 0)'
        self.error(n,'Use an explicit comparison for this condition.')
    def op(self,n):
        table={ast.Add:'+',ast.Sub:'-',ast.Mult:'*',ast.Div:'/',ast.Mod:'%',ast.Eq:'==',ast.NotEq:'!=',ast.Lt:'<',ast.LtE:'<=',ast.Gt:'>',ast.GtE:'>='}
        if type(n) not in table:self.error(n,'Operator is not supported.')
        return table[type(n)]
    def expr(self,n):
        if isinstance(n,ast.Constant):
            if n.value is None:self.error(n,'None values need an explicit optional type.')
            if isinstance(n.value,str):return ('' if self.java else 'std::string(')+json.dumps(n.value,ensure_ascii=False)+('' if self.java else ')')
            if isinstance(n.value,bool):return 'true' if n.value else 'false'
            return str(n.value)+('L' if self.java else 'LL') if isinstance(n.value,int) else repr(n.value)
        if isinstance(n,ast.Name):
            if n.id=='self':return 'this'
            if n.id not in self.env and n.id not in self.classes and n.id not in self.functions:self.error(n,'Unknown or out-of-scope name: '+n.id)
            return n.id
        if isinstance(n,ast.Attribute):return self.expr(n.value)+('->' if not self.java and isinstance(n.value,ast.Name) and n.value.id=='self' else '.')+n.attr
        if isinstance(n,ast.BinOp):
            a,b=self.expr(n.left),self.expr(n.right)
            ta,tb=self.infer(n.left),self.infer(n.right)
            if ta=='str' or tb=='str':
                if ta!=tb or not isinstance(n.op,ast.Add):self.error(n,'Only string + string is supported; use str() for conversion.')
            elif ta not in ('int','float') or tb not in ('int','float'):self.error(n,'Use scalar numbers for this operation.')
            if isinstance(n.op,ast.FloorDiv):return ('R.' if self.java else 'rey::')+'floordiv('+a+', '+b+')'
            if isinstance(n.op,ast.Mod):return ('R.' if self.java else 'rey::')+'mod('+a+', '+b+')'
            if isinstance(n.op,ast.Pow):return ('Math.pow' if self.java else 'std::pow')+'('+a+', '+b+')'
            if isinstance(n.op,ast.Div):a='(double)('+a+')'
            return '('+a+' '+self.op(n.op)+' '+b+')'
        if isinstance(n,ast.UnaryOp):
            if isinstance(n.op,ast.Not):return '!('+self.truth(n.operand)+')'
            if not isinstance(n.op,(ast.USub,ast.UAdd)):self.error(n,'Unary operator is not supported.')
            return ('-' if isinstance(n.op,ast.USub) else '+')+'('+self.expr(n.operand)+')'
        if isinstance(n,ast.BoolOp):
            if any(self.infer(x)!='bool' for x in n.values):self.error(n,'and/or operands must be Boolean; compare numbers or strings explicitly.')
            return '('+(' && ' if isinstance(n.op,ast.And) else ' || ').join(self.expr(x) for x in n.values)+')'
        if isinstance(n,ast.Compare):
            parts=[];left=n.left
            for op,right in zip(n.ops,n.comparators):
                a,b=self.expr(left),self.expr(right)
                if self.java and self.infer(left)=='str' and isinstance(op,(ast.Eq,ast.NotEq)):parts.append(('!' if isinstance(op,ast.NotEq) else '')+'Objects.equals('+a+','+b+')')
                else:parts.append(a+' '+self.op(op)+' '+b)
                left=right
            return '('+' && '.join(parts)+')'
        if isinstance(n,ast.IfExp):
            if self.infer(n.body)!=self.infer(n.orelse):self.error(n,'Conditional branches must have the same type.')
            return '('+self.truth(n.test)+' ? '+self.expr(n.body)+' : '+self.expr(n.orelse)+')'
        if isinstance(n,ast.List):
            t=self.infer(n)
            if any(self.infer(x)!=t[1] for x in n.elts):self.error(n,'List elements must have one type.')
            values=', '.join(self.expr(x) for x in n.elts)
            return 'new ArrayList<>(Arrays.asList('+values+'))' if self.java else self.typ(t)+'{'+values+'}'
        if isinstance(n,ast.Subscript):
            if isinstance(n.slice,ast.Slice):self.error(n,'Slices require explicit target code.')
            a,i=self.expr(n.value),self.expr(n.slice)
            if self.infer(n.value)=='str':return ('String.valueOf('+a+'.charAt((int)('+i+')))' if self.java else 'std::string(1, '+a+'.at('+i+'))')
            return a+('.get((int)('+i+'))' if self.java else '.at('+i+')')
        if isinstance(n,ast.JoinedStr):
            values=[]
            for part in n.values:
                if isinstance(part,ast.FormattedValue):
                    if part.format_spec or part.conversion!=-1:self.error(part,'Formatted string conversions need explicit target code.')
                    values.append(('R.str(' if self.java else 'rey::str(')+self.expr(part.value)+')')
                else:values.append(self.expr(part))
            return '('+('""' if self.java else 'std::string("")')+' + '+' + '.join(values)+')'
        if isinstance(n,ast.ListComp):
            if len(n.generators)!=1:self.error(n,'Use a single comprehension generator.')
            g=n.generators[0]
            if g.is_async or not isinstance(g.target,ast.Name):self.error(n,'Use a simple comprehension variable.')
            iterable=self.expr(g.iter);t=self.infer(g.iter)
            if not isinstance(t,tuple):self.error(n,'Comprehension input must be a list or range.')
            old=self.env.get(g.target.id);self.env[g.target.id]=t[1]
            value=self.expr(n.elt);condition=' && '.join(self.expr(c) for c in g.ifs) or 'true';result=self.infer(n.elt)
            if old is None:self.env.pop(g.target.id,None)
            else:self.env[g.target.id]=old
            if self.java:return iterable+'.stream().filter('+g.target.id+' -> '+condition+').map('+g.target.id+' -> '+value+').collect(java.util.stream.Collectors.toCollection(ArrayList::new))'
            return '([&]() { '+self.typ(('list',result))+' result; for (auto '+g.target.id+' : '+iterable+') if ('+condition+') result.push_back('+value+'); return result; }())'
        if isinstance(n,ast.Call):
            if n.keywords:self.error(n,'Keyword arguments need positional lowering.')
            args=[self.expr(x) for x in n.args];joined=', '.join(args)
            if isinstance(n.func,ast.Name):
                name=n.func.id
                if name=='print':return ('R.print(' if self.java else 'rey::print(')+joined+')'
                if name=='range':return ('R.range(' if self.java else 'rey::range(')+joined+')'
                if name=='len':return '(long)('+args[0]+'.'+('length()' if self.infer(n.args[0])=='str' else 'size()')+')' if self.java else '(long long)('+args[0]+'.size())'
                if name=='str':return ('R.str(' if self.java else 'rey::str(')+joined+')'
                if name in ('int','float'):
                    if self.infer(n.args[0])=='str':return ('Long.parseLong' if name=='int' else 'Double.parseDouble')+'('+joined+')' if self.java else ('std::stoll' if name=='int' else 'std::stod')+'('+joined+')'
                    return '('+self.typ(name)+')('+joined+')'
                if name=='input':return ('R.input(' if self.java else 'rey::input(')+joined+')'
                if name in ('abs','min','max'):return ('Math.' if self.java else 'std::')+name+'('+joined+')'
                if name in self.classes:return ('new ' if self.java else '')+name+'('+joined+')'
                if name not in self.functions:self.error(n,'Unknown function: '+name)
                return name+'('+joined+')'
            if isinstance(n.func,ast.Attribute):
                a,name=self.expr(n.func.value),n.func.attr
                owner=self.infer(n.func.value)
                if name=='append' and isinstance(owner,tuple):
                    if len(n.args)!=1 or self.infer(n.args[0])!=owner[1]:self.error(n,'append requires one value matching the list type.')
                    return a+('.add(' if self.java else '.push_back(')+joined+')'
                if name in ('upper','lower','strip') and owner=='str':
                    if n.args:self.error(n,'This string method takes no arguments in the portable subset.')
                    return a+'.'+{'upper':'toUpperCase','lower':'toLowerCase','strip':'trim'}[name]+'()' if self.java else 'rey::'+name+'('+a+')'
                if name=='join' and owner=='str':
                    if len(n.args)!=1 or self.infer(n.args[0])!=('list','str'):self.error(n,'join requires one list of strings.')
                    return 'String.join('+a+', '+joined+')' if self.java else 'rey::join('+a+', '+joined+')'
                if str(owner)+'.'+name not in self.signatures:self.error(n,'Unsupported method: '+name)
                return self.expr(n.func)+'('+joined+')'
        self.error(n,type(n).__name__+' expression is not supported.')

JAVA_RUNTIME='''import java.util.*;
class R {
    static long floordiv(long a,long b){return Math.floorDiv(a,b);}
    static double floordiv(double a,double b){if(b==0)throw new ArithmeticException("division by zero");return Math.floor(a/b);}
    static long mod(long a,long b){return Math.floorMod(a,b);}
    static double mod(double a,double b){if(b==0)throw new ArithmeticException("division by zero");return a-b*Math.floor(a/b);}
    static String str(Object x) { return x instanceof Boolean ? ((Boolean)x ? "True" : "False") : String.valueOf(x); }
    static void print(Object... values) { for(int i=0;i<values.length;i++) { if(i>0)System.out.print(" "); System.out.print(str(values[i])); } System.out.println(); }
    static List<Long> range(long stop) { return range(0,stop,1); }
    static List<Long> range(long start,long stop) { return range(start,stop,1); }
    static List<Long> range(long start,long stop,long step) { if(step==0)throw new IllegalArgumentException("range step is zero"); List<Long> r=new ArrayList<>(); for(long i=start;step>0?i<stop:i>stop;i+=step){if(r.size()>1000000)throw new IllegalArgumentException("range too large");r.add(i);} return r; }
    static Scanner scanner = new Scanner(System.in);
    static String input() {return input("");}
    static String input(String prompt) {System.out.print(prompt);return scanner.nextLine();}
}'''

CPP_RUNTIME='''#include <iostream>
#include <string>
#include <vector>
#include <sstream>
#include <iomanip>
#include <limits>
#include <cmath>
#include <algorithm>
#include <stdexcept>
namespace rey {
    inline long long floordiv(long long a,long long b){if(!b)throw std::runtime_error("division by zero");auto q=a/b,r=a%b;return q-((r!=0)&&((r<0)!=(b<0)));}
    inline double floordiv(double a,double b){if(b==0)throw std::runtime_error("division by zero");return std::floor(a/b);}
    inline double floordiv(double a,long long b){return floordiv(a,(double)b);}
    inline double floordiv(long long a,double b){return floordiv((double)a,b);}
    inline long long mod(long long a,long long b){if(!b)throw std::runtime_error("division by zero");auto r=a%b;return (r!=0)&&((r<0)!=(b<0))?r+b:r;}
    inline double mod(double a,double b){if(b==0)throw std::runtime_error("division by zero");return a-b*std::floor(a/b);}
    inline double mod(double a,long long b){return mod(a,(double)b);}
    inline double mod(long long a,double b){return mod((double)a,b);}
    inline std::string str(const std::string& x) { return x; }
    inline std::string str(bool x) { return x ? "True" : "False"; }
    inline std::string str(double x) {std::ostringstream s;s<<std::setprecision(std::numeric_limits<double>::digits10)<<x;auto value=s.str();if(std::isfinite(x)&&value.find_first_of(".eE")==std::string::npos)value+=".0";return value;}
    template<class T> std::string str(const T& x) { std::ostringstream s;s<<x;return s.str(); }
    template<class T> std::string str(const std::vector<T>& xs) { std::string s="[";bool first=true;for(const auto& x:xs){if(!first)s+=", ";s+=str(x);first=false;}return s+"]"; }
    template<class... T> void print(const T&... xs) { bool first=true;((std::cout<<(first?"":" ")<<str(xs),first=false),...);std::cout<<std::endl; }
    inline std::vector<long long> range(long long start,long long stop,long long step=1) {if(!step)throw std::runtime_error("range step is zero");std::vector<long long> r;for(auto i=start;step>0?i<stop:i>stop;i+=step){if(r.size()>1000000)throw std::runtime_error("range too large");r.push_back(i);}return r;}
    inline std::vector<long long> range(long long stop){return range(0,stop,1);}
    inline std::string input(std::string prompt=""){std::cout<<prompt;std::string s;std::getline(std::cin,s);return s;}
    inline std::string upper(std::string s){std::transform(s.begin(),s.end(),s.begin(),::toupper);return s;}
    inline std::string lower(std::string s){std::transform(s.begin(),s.end(),s.begin(),::tolower);return s;}
    inline std::string strip(std::string s){auto a=s.find_first_not_of(" \\t\\r\\n");return a==std::string::npos?"":s.substr(a,s.find_last_not_of(" \\t\\r\\n")-a+1);}
    inline std::string join(std::string sep,const std::vector<std::string>& xs){std::string s;bool first=true;for(const auto& x:xs){if(!first)s+=sep;s+=x;first=false;}return s;}
}'''
