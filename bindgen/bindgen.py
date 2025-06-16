#!/usr/bin/python
import sys
import os
import optparse
import clang.cindex as cx

allowed_files = set()
cur_indent = 0
ignore_output = False
global_output_file = None
def push_indent():
    global cur_indent
    cur_indent += 1

def pop_indent():
    global cur_indent
    cur_indent -= 1

def output(s):
    global ignore_output
    global global_output_file
    if not ignore_output:
        line = "    " * cur_indent + str(s)
        if global_output_file is not None:
            global_output_file.write(line+"\n")
        else:
            print(line)

struct_forward_declarations = set()
declared_types = set()

safe_types = {
    "int8_t",
    "uint8_t",
    "int16_t",
    "uint16_t",
    "int32_t",
    "uint32_t",
    "int64_t",
    "uint64_t",
    "size_t",
    "uintptr_t",
    "wchar_t",
    "long",
    "unsigned long",
    "_Bool",
    "FILE"
}
missing_types = []
def ensure_type(type):
    global allowed_files
    global safe_types
    if type.spelling in safe_types:
        return
    if type.spelling.startswith("const ") and type.spelling[6:] in safe_types:
        safe_types.add(type.spelling)
        return
    f = type.get_declaration().location.file
    if f is not None and os.path.realpath(f.name) not in allowed_files and not ignore_output:
        missing_types.append(type)
    safe_types.add(type.spelling)


def clean_spelling(type):
    parts = type.spelling.split()
    parts = filter(lambda x: x not in ["struct","enum","union","const"], parts)
    return " ".join(parts)

def create_missing_type(type):
    canon = type.get_canonical()
    name = clean_spelling(type)
    canon_name = clean_spelling(canon)
    if not canon.get_declaration().is_definition() or name == canon_name:
        output("public struct " + name + ";")
    else:
        ensure_type(canon)
        output("public typealias " + name + " = " + canon_name + ";")

def type_str(type, omit_const = False):
    ensure_type(type)
    if type.spelling == "const char *" or type.spelling == "const char *const":
        return "NativeString"
    qualifier = "const " if type.is_const_qualified() and not omit_const else ""
    if type.kind == cx.TypeKind.FUNCTIONPROTO:
        # Turn function pointers into void pointers.
        return "void"
    elif type.kind == cx.TypeKind.BOOL:
        return qualifier + "_Bool"
    elif type.kind == cx.TypeKind.UCHAR or type.kind == cx.TypeKind.CHAR_U:
        return qualifier + "uint8_t"
    elif type.kind == cx.TypeKind.SCHAR or type.kind == cx.TypeKind.CHAR_S:
        return qualifier + "int8_t"
    elif type.kind == cx.TypeKind.USHORT:
        return qualifier + "uint16_t"
    elif type.kind == cx.TypeKind.SHORT or type.kind == cx.TypeKind.CHAR16:
        return qualifier + "int16_t"
    elif type.kind == cx.TypeKind.UINT:
        return qualifier + "uint32_t"
    elif type.kind == cx.TypeKind.INT or type.kind == cx.TypeKind.CHAR32:
        return qualifier + "int32_t"
    elif type.kind == cx.TypeKind.ULONG:
        return qualifier + "ulong"
    elif type.kind == cx.TypeKind.LONG:
        return qualifier + "long"
    elif type.kind == cx.TypeKind.POINTER:
        # Pointer const qualifiers don't seem to work in Slang, so we omit those.
        return "Ptr<" + type_str(type.get_pointee(), True) + ">"
    elif type.kind == cx.TypeKind.CONSTANTARRAY:
        return type_str(type.get_array_element_type()) + "["+str(type.get_array_size())+"]"
    elif omit_const:
        return clean_spelling(type)
    else:
        parts = type.spelling.split()
        parts = filter(lambda x: x not in ["struct","enum","union"], parts)
        return " ".join(parts)

def dump_typedef(node):
    if node.type.spelling in declared_types:
        return

    # typedef structs / enums / unions are meaningless in the bindings.
    parts = node.underlying_typedef_type.spelling.split()
    parts = filter(lambda x: x not in ["struct","enum","union"], parts)
    name = " ".join(parts)
    if node.type.spelling == name:
        return
    output("public typealias " + node.type.spelling + " = " + type_str(node.underlying_typedef_type) + ";")
    declared_types.add(node.type.spelling)

def dump_union(node, varname = "", fallback_name = ""):
    global struct_forward_declarations
    name = fallback_name if node.is_anonymous() else node.type.spelling.split()[-1]
    if not node.is_definition():
        if cur_indent == 0:
            if ignore_output:
                declared_types.add(name)
            else:
                struct_forward_declarations.add(name)
        else:
            output("public struct " + name + ";")
        return

    if cur_indent == 0:
        if name in declared_types:
            # Assume we added this union already.
            return
        declared_types.add(name)

    output("public struct " + name + " { ")
    push_indent()
    unreferenced_anon_decls = []
    anonymous_type_names = {}
    anonymous_name_counter = 0

    # Pre-pass to figure out which anonymous structs do what.
    for decl in node.get_children():
        if decl.kind == cx.CursorKind.STRUCT_DECL or decl.kind == cx.CursorKind.UNION_DECL:
            if decl.is_anonymous():
                unreferenced_anon_decls.append(decl)
                anonymous_type_names[decl.hash] = "_anonymousBindingDecl"+str(anonymous_name_counter)
                anonymous_name_counter += 1
        if decl.kind == cx.CursorKind.ENUM_DECL:
            if decl.is_anonymous():
                anonymous_type_names[decl.hash] = "_anonymousBindingDecl"+str(anonymous_name_counter)
                anonymous_name_counter += 1
        elif decl.kind == cx.CursorKind.FIELD_DECL:
            ddecl = decl.type.get_declaration()
            if decl.type.kind == cx.TypeKind.ELABORATED:
                if ddecl.kind == cx.CursorKind.STRUCT_DECL or ddecl.kind == cx.CursorKind.UNION_DECL:
                    if decl.is_anonymous() and ddecl in unreferenced_anon_decls:
                        unreferenced_anon_decls.remove(ddecl)

    # Find max alignment and size from all fields.
    max_alignment = 0
    max_size = 0
    for decl in node.get_children():
        if decl.kind == cx.CursorKind.STRUCT_DECL or decl.kind == cx.CursorKind.UNION_DECL:
            if decl in unreferenced_anon_decls:
                max_size = max(max_size, decl.type.get_size())
                max_alignment = max(max_alignment, decl.type.get_align())
        if decl.kind == cx.CursorKind.FIELD_DECL:
            max_size = max(max_size, decl.type.get_size())
            max_alignment = max(max_alignment, decl.type.get_align())

    pad_type = "uint8_t"
    if max_alignment == 2:
        pad_type = "uint16_t"
    elif max_alignment == 4:
        pad_type = "uint32_t"
    else:
        pad_type = "uint64_t"
    pad_array_length = max_size // max_alignment
    output("internal " + pad_type + " _unionBindingBackingMemory[" + str(pad_array_length) + "];")

    # Dump types. TODO: Name unnamed decls.
    for decl in node.get_children():
        if decl.kind == cx.CursorKind.STRUCT_DECL:
            if not decl.is_anonymous():
                dump_struct(decl.type.get_declaration())
            else:
                dump_struct(decl.type.get_declaration(), "", anonymous_type_names[decl.hash])
        elif decl.kind == cx.CursorKind.UNION_DECL:
            if not decl.is_anonymous():
                dump_union(decl.type.get_declaration())
            else:
                dump_union(decl.type.get_declaration(), "", anonymous_type_names[decl.hash])
        elif decl.kind == cx.CursorKind.ENUM_DECL:
            if not decl.is_anonymous():
                dump_enum(decl.type.get_declaration())
            else:
                dump_enum(decl.type.get_declaration(), "", anonymous_type_names[decl.hash])

    # Dump entries.
    def dump_simple_wrapper(decl):
        type_name = type_str(decl.type)
        dhash = decl.type.get_declaration().hash
        if dhash in anonymous_type_names:
            type_name = anonymous_type_names[dhash]

        name = "_unionBindingAdapter_" + decl.spelling
        content = "{" + type_name + " value; ";
        size = decl.type.get_size()
        if size < max_size:
            content += "uint8_t pad["+str(max_size-size)+"]; "

        content += "};"
        output("internal struct " + name + content)

        output("public property " + type_name + " " + decl.spelling)
        output("{")
        push_indent()
        output("get {")
        push_indent()
        output(name + " tmp = reinterpret<" + name + ">(_unionBindingBackingMemory);")
        output("return tmp.value;")
        pop_indent()
        output("}")
        output("set {")
        push_indent()
        output(name + " tmp;")
        output("tmp.value = newValue;")
        output("_unionBindingBackingMemory = reinterpret<"+pad_type+"["+str(pad_array_length)+"]>(tmp);")
        pop_indent()
        output("}")
        pop_indent()
        output("}")

    def dump_complex_wrapper(decl):
        type_name = type_str(decl.type)
        dhash = decl.type.get_declaration().hash
        if dhash in anonymous_type_names:
            type_name = anonymous_type_names[dhash]

        name = "_unionBindingAdapter" + type_name
        content = "{" + type_name + " value; ";
        size = decl.type.get_size()
        if size < max_size:
            content += "uint8_t pad["+str(max_size-size)+"]; "

        content += "};"
        output("internal struct " + name + content)

        ddecl = decl.type.get_declaration()
        for field in ddecl.get_children():
            if field.kind == cx.CursorKind.FIELD_DECL:
                if field.type.kind == cx.TypeKind.ELABORATED and field.type.get_declaration().is_anonymous():
                    continue
                output("public property " + type_str(field.type) + " " + field.spelling)
                output("{")
                push_indent()
                output("get {")
                push_indent()
                output(name + " tmp = reinterpret<" + name + ">(_unionBindingBackingMemory);")
                output("return tmp.value."+field.spelling+";")
                pop_indent()
                output("}")
                output("set {")
                push_indent()
                output(name + " tmp = reinterpret<" + name + ">(_unionBindingBackingMemory);")
                output("tmp.value."+field.spelling+" = newValue;")
                output("_unionBindingBackingMemory = reinterpret<"+pad_type+"["+str(pad_array_length)+"]>(tmp);")
                pop_indent()
                output("}")
                pop_indent()
                output("}")

    for decl in node.get_children():
        if decl.kind == cx.CursorKind.STRUCT_DECL and decl.is_anonymous() and decl in unreferenced_anon_decls:
            dump_complex_wrapper(decl)
        elif decl.kind == cx.CursorKind.FIELD_DECL:
            dump_simple_wrapper(decl)

    pop_indent()
    output("}"+varname+";")

def dump_struct(node, varname = "", fallback_name = ""):
    global struct_forward_declarations
    name = fallback_name if node.is_anonymous() else node.type.spelling.split()[-1]
    if not node.is_definition():
        if cur_indent == 0:
            if ignore_output:
                declared_types.add(name)
            else:
                struct_forward_declarations.add(name)
        else:
            output("public struct " + name + ";")
        return

    if cur_indent == 0:
        if name in declared_types:
            # Assume we added this struct already.
            return
        declared_types.add(name)

    output("public struct " + name + " { ")
    push_indent()
    unreferenced_anon_decls = []
    # Pre-pass to figure out which anonymous structs do what.
    for decl in node.get_children():
        if decl.kind == cx.CursorKind.STRUCT_DECL or decl.kind == cx.CursorKind.UNION_DECL:
            if decl.is_anonymous():
                unreferenced_anon_decls.append(decl)
        elif decl.kind == cx.CursorKind.FIELD_DECL:
            ddecl = decl.type.get_declaration()
            if decl.type.kind == cx.TypeKind.ELABORATED:
                if ddecl.kind == cx.CursorKind.STRUCT_DECL or ddecl.kind == cx.CursorKind.UNION_DECL:
                    if decl.is_anonymous() and ddecl in unreferenced_anon_decls:
                        unreferenced_anon_decls.remove(ddecl)

    def dump_field(decl):
        type_name = type_str(decl.type)
        var_name = decl.spelling

        type_chain = decl.type
        while True:
            if type_chain.kind == cx.TypeKind.POINTER:
                type_chain = type_chain.get_pointee()
            elif type_chain.kind == cx.TypeKind.CONSTANTARRAY:
                type_chain = type_chain.get_array_element_type()
            else:
                break

        if var_name in type_chain.spelling.split():
            var_name += "_"
        
        output("public " + type_name + " " + var_name + ";")

    # Actually dump the structs.
    for decl in node.get_children():
        if decl.kind == cx.CursorKind.STRUCT_DECL:
            if not decl.is_anonymous() or decl in unreferenced_anon_decls:
                dump_struct(decl.type.get_declaration())
        elif decl.kind == cx.CursorKind.UNION_DECL:
            if not decl.is_anonymous() or decl in unreferenced_anon_decls:
                dump_union(decl.type.get_declaration())
        elif decl.kind == cx.CursorKind.ENUM_DECL:
            if not decl.is_anonymous():
                dump_enum(decl.type.get_declaration())
        elif decl.kind == cx.CursorKind.FIELD_DECL:
            ddecl = decl.type.get_declaration()
            if decl.type.kind == cx.TypeKind.ELABORATED:
                if ddecl.kind == cx.CursorKind.ENUM_DECL:
                    if ddecl.is_anonymous():
                        dump_enum(ddecl, " "+decl.spelling)
                    else:
                        dump_field(decl)
                elif ddecl.kind == cx.CursorKind.STRUCT_DECL:
                    if decl.is_anonymous():
                        dump_struct(ddecl, " "+decl.spelling)
                    else:
                        dump_field(decl)
                elif ddecl.kind == cx.CursorKind.UNION_DECL:
                    if decl.is_anonymous():
                        dump_union(ddecl, " "+decl.spelling)
                    else:
                        dump_field(decl)
                else:
                    dump_field(decl)
            else:
                dump_field(decl)

    pop_indent()
    output("}"+varname+";")

def dump_enum(node, varname = "", fallback_name = ""):
    name = fallback_name if node.is_anonymous() else node.type.spelling.split()[-1]
    if name in declared_types:
        # Assume we added this enum already.
        return
    declared_types.add(name)
    output("[UnscopedEnum]")
    output("public enum " + name + " : " + type_str(node.enum_type) + " { ")
    push_indent()
    for decl in node.get_children():
        if decl.kind == cx.CursorKind.ENUM_CONSTANT_DECL:
            output(decl.spelling + " = " + str(decl.enum_value) + ",")
    pop_indent()
    output("}"+varname+";")

def dump_function(node):
    name = node.spelling
    params = []
    for arg in node.get_arguments():
        if arg.kind == cx.CursorKind.PARM_DECL:
            if arg.type.spelling == 'va_list':
                # yeaaah... not gonna happen.
                return
            params.append(type_str(arg.type) + " " + arg.spelling)
    output("public __extern_cpp " + type_str(node.result_type) + " " + name + "(" + ", ".join(params) + ");")

extant_symbols = {}
def dump_macro(node):
    global extant_symbols

    tokens = list(node.get_tokens())
    if len(tokens) < 2:
        return
    token_str = [t.spelling for t in tokens]

    # No starting with _!!!
    if token_str[0].startswith('_'):
        return

    # If it looks and smells like a function, skip it.
    if token_str[1].startswith('(') and tokens[0].extent.end.column == tokens[1].extent.start.column:
        return

    for i in range(len(tokens)-1):
        t = tokens[1+i]
        if t.kind == cx.TokenKind.KEYWORD:
            return
        if t.kind == cx.TokenKind.IDENTIFIER:
            if t.spelling in extant_symbols:
                token_str[1+i] = extant_symbols[t.spelling]
            #and t.spelling not in extant_symbols:
            else:
                return

    # Dump the easy defines as-they-are, but with a different name.
    value_str = " ".join(token_str[1:])
    output("public static let " + token_str[0] + " = " +  value_str + ";");
    extant_symbols[token_str[0]] = value_str

def dump_var(node):
    if node.type.is_const_qualified():
        value_str = None
        for value in node.get_children():
            if value.kind == cx.CursorKind.INTEGER_LITERAL or value.kind == cx.CursorKind.UNEXPOSED_EXPR:
                tokens = list(value.get_tokens())
                if len(tokens) == 0:
                    return
                value_str = tokens[0].spelling

        if value_str is not None:
            typename = type_str(node.type)
            parts = typename.split()
            parts = filter(lambda x: x not in ["struct","enum","union","const"], parts)
            typename = " ".join(parts)
            output("public static const " + typename + " " + node.spelling + " = " + value_str + ";");

def dump_decl(node, toplevel):
    if node.kind == cx.CursorKind.TYPEDEF_DECL:
        dump_typedef(node)
    elif node.kind == cx.CursorKind.STRUCT_DECL:
        dump_struct(node)
    elif node.kind == cx.CursorKind.UNION_DECL:
        dump_union(node)
    elif node.kind == cx.CursorKind.ENUM_DECL:
        dump_enum(node)
    elif node.kind == cx.CursorKind.FUNCTION_DECL:
        dump_function(node)
    elif node.kind == cx.CursorKind.MACRO_DEFINITION:
        dump_macro(node)
    elif node.kind == cx.CursorKind.VAR_DECL:
        dump_var(node)

def main():
    parser = optparse.OptionParser()
    parser.add_option("--namespace", action="store", dest="namespace")
    parser.add_option("--import", action="append", dest="import_modules")
    parser.add_option("--using", action="append", dest="using_namespaces")
    parser.add_option("--imported", action="append", dest="imported_sources")
    parser.add_option("--define", action="append", dest="defines")
    parser.add_option("--output", action="store", dest="output_file")
    opts, args = parser.parse_args()
    if len(args) == 0:
        print("Usage: " + sys.argv[0] + " <C headers>...")
        sys.exit(1)

    global global_output_file
    if opts.output_file is not None:
        global_output_file = open(opts.output_file, 'w')

    output("// Auto-generated bindings by slang-bindgen.py, from headers:")
    for path in args:
        output("//   " + path)
    output("import platform;")

    global allowed_files
    allowed_files = set([os.path.realpath(x) for x in args])

    index = cx.Index.create()

    if opts.import_modules is not None:
        for module in opts.import_modules:
            output("import " + module + ";")

    if opts.using_namespaces is not None:
        for ns in opts.using_namespaces:
            output("using " + ns + ";")

    if opts.namespace:
        output("namespace " + opts.namespace + " {")

    # Silently ignore decls from imported sources
    cOptions = (
        cx.TranslationUnit.PARSE_DETAILED_PROCESSING_RECORD |
        cx.TranslationUnit.PARSE_INCOMPLETE |
        cx.TranslationUnit.PARSE_SKIP_FUNCTION_BODIES
    )
    cArgs = []
    if opts.defines is not None:
        for define in opts.defines:
            cArgs.append("-D"+define)

    if opts.imported_sources is not None:
        global ignore_output
        ignore_output = True
        for path in opts.imported_sources:
            tu = index.parse(path, args=cArgs, options=cOptions)
            root = tu.cursor
            cur_realpath = os.path.realpath(path);
            for decl in root.get_children():
                if decl.location.file is None:
                    continue
                decl_path = os.path.realpath(decl.location.file.name)
                if decl_path != cur_realpath:
                    continue

                dump_decl(decl, True)
        ignore_output = False

    # Then output the bindings for the actually requested sources.
    for path in args:
        tu = index.parse(path, args=cArgs, options=cOptions)
        root = tu.cursor
        cur_realpath = os.path.realpath(path);

        # We only care about the top level, where structs, enums and functions
        # are declared.
        for decl in root.get_children():
            if decl.location.file is None:
                continue
            decl_path = os.path.realpath(decl.location.file.name)
            if decl_path != cur_realpath:
                continue

            dump_decl(decl, True)

    for name in struct_forward_declarations:
        if name not in declared_types:
            output("public struct " + name + ";")

    while len(missing_types) != 0:
        type = missing_types.pop()
        if clean_spelling(type) not in declared_types:
            create_missing_type(type)

    if opts.namespace:
        output("}")

    if global_output_file is not None:
        global_output_file.close()

if __name__ == '__main__':
    main()

