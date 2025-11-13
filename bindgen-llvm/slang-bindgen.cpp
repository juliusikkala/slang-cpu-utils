#include "llvm/Support/TargetSelect.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/DebugInfo.h"
#include "llvm/IR/Instructions.h"
#include "clang/Basic/Diagnostic.h"
#include "clang/CodeGen/CodeGenAction.h"
#include "clang/Driver/Driver.h"
#include "clang/Driver/Compilation.h"
#include "clang/Frontend/FrontendAction.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/FrontendTool/Utils.h"
#include "clang/Lex/PreprocessorOptions.h"

#include <vector>
#include <string>
#include <regex>
#include <cstring>
#include <cstdarg>
#include <cassert>

#define FUNCTION_ADAPTER_NAME "_BINDGEN_FUNC_ADAPTER"
#define FUNCTION_ADAPTER_ARG_NAME "_BINDGEN_ARG_"

static struct {
    std::string inNamespace;
    std::string outputPath;
    std::string targetTriple;
    std::vector<std::string> cHeaders;
    std::vector<std::string> importModules;
    std::vector<std::string> usingNamespaces;
    std::vector<std::string> importedSources;
    std::vector<std::string> defines;
    std::vector<std::string> includePaths;
    std::vector<std::regex> unscopedEnums;
    std::vector<std::regex> removeCommonPrefixes;
    std::vector<std::regex> removeEnumCases;
    std::string enumFallbackPrefix = "e";
    bool useByteBool = false;
} options;

static const char* const helpString = 
R"(Usage: %s [list of C headers] --output <name>.slang

Options:

--target-triple <triple>  sets the LLVM target triple used to resolve calling
                          conventions of functions with aggregate parameters.
--output <output-file>    writes the bindings to the given file. If not
                          specified, bindings are printed to stdout.
--namespace <ns>          puts the bindings in the given namespace
--using <ns>              adds a `using ns;` at the start
--import <module>         adds a `import module;` at the start 
--imported <header>       marks declarations from a C header as already included
                          through an `--import`ed module
--define <name>=<value>   uses the given preprocessor macro when parsing headers
--include-dir <path>      adds the given include path parsing headers
--unscoped-enums <regex>  uses unscoped enums for the listed types.
--rm-enum-prefix <regex>  removes a prefix from all enum cases if it's common to
                          all cases in the enum. For a regex, the longest
                          matching and present prefix is removed.
--rm-enum-case <regex>    removes matching cases from all enums
--fallback-prefix <str>   adds the given prefix to all enum case names that
                          would not be valid in Slang
--use-byte-bool           uses uint8_t instead of bool. Useful when overriding
                          default layout to something where sizeof(bool) != 1.
)";

void printHelp(bool asError, const char** argv)
{
    fprintf(asError ? stderr : stdout, helpString, argv[0]);
}

bool parseOptions(int argc, const char** argv)
{
    int i = 1;
    bool endFlags = false;
    while (i < argc)
    {
        const char* arg = argv[i];
        const char* value = i+1 < argc ? argv[i+1] : nullptr;

        if (!endFlags && *arg == '-')
        {
            arg++; // Skip first '-'
            if (*arg == '-')
            {
                arg++; // Skip second '-' if present.

                // If '--' is specified, that means that there are no further
                // flags to handle, and the rest of the parameters should be
                // taken literally as C header names.
                if (*arg == 0)
                {
                    endFlags = true;
                    ++i;
                    continue;
                }
            }

            if (strcmp(arg, "help") == 0)
            {
                printHelp(false, argv);
                exit(0);
            }
            if (strcmp(arg, "target-triple") == 0)
            {
                options.targetTriple = value;
                i++;
            }
            else if (strcmp(arg, "namespace") == 0)
            {
                options.inNamespace = value;
                i++;
            }
            else if (strcmp(arg, "import") == 0)
            {
                options.importModules.push_back(value);
                i++;
            }
            else if (strcmp(arg, "using") == 0)
            {
                options.usingNamespaces.push_back(value);
                i++;
            }
            else if (strcmp(arg, "imported") == 0)
            {
                options.importedSources.push_back(value);
                i++;
            }
            else if (strcmp(arg, "define") == 0)
            {
                options.defines.push_back(value);
                i++;
            }
            else if (strcmp(arg, "include-dir") == 0)
            {
                options.includePaths.push_back(value);
                i++;
            }
            else if (strcmp(arg, "output") == 0)
            {
                options.outputPath = value;
                i++;
            }
            else if (strcmp(arg, "unscoped-enums") == 0)
            {
                options.unscopedEnums.push_back(std::regex(value));
                i++;
            }
            else if (strcmp(arg, "rm-enum-prefix") == 0)
            {
                options.removeCommonPrefixes.push_back(std::regex(value));
                i++;
            }
            else if (strcmp(arg, "fallback-prefix") == 0)
            {
                options.enumFallbackPrefix = value;
                i++;
            }
            else if (strcmp(arg, "rm-enum-case") == 0)
            {
                options.removeEnumCases.push_back(std::regex(value));
                i++;
            }
            else if (strcmp(arg, "use-byte-bool") == 0)
            {
                options.useByteBool = true;
            }
            else
            {
                fprintf(stderr, "Unknown flag: %s\n", arg);
                return false;
            }
        }
        else
        {
            options.cHeaders.push_back(arg);
        }
        i++;
    }

    if (options.cHeaders.size() == 0)
    {
        fprintf(stderr, "No input headers specified!\n");
        return false;
    }
    return true;
}

size_t roundToAlignment(size_t size, size_t align)
{
    return (size+align-1)/align*align;
}

struct BindingContext;
void generateFunctionWrapper(
    BindingContext& ctx,
    const std::string& preamble,
    const std::string& slangPrototype,
    const std::string& cAdapter,
    const std::string& functionName,
    int argCount
);

struct ClangSession;
struct BindingContext
{
    ClangSession* session = nullptr;
    FILE* file = stdout;
    int indentLevel = 0;

    int nameCounter = 0;

    // Concretely sized names for builtin types with unpredictable size. 
    std::string wcharType = "int16_t";
    std::string shortType = "int16_t";
    std::string intType = "int";
    std::string longType = "int";

    int scopeDepth = 0;

    std::set<std::string> declaredFunctions;
    std::vector<std::set<std::string>> definedTypes;
    std::vector<std::set<std::string>> structForwardDeclarations;

    struct FunctionWrapperInfo
    {
        std::string slangPrototype;
        std::string cAdapter;
        std::string functionName;
        int argCount;
    };
    std::vector<FunctionWrapperInfo> pendingFunctionWrappers;

    BindingContext(const std::string& outputPath)
    {
        if (!outputPath.empty())
        {
            file = fopen(outputPath.c_str(), "w");
            if (!file)
            {
                fprintf(stderr, "Cannot open %s for writing\n", outputPath.c_str());
                exit(1);
            }
        }
    }

    ~BindingContext()
    {
        if (file != stdout)
        {
            fclose(file);
        }
    }

    std::string getAnonymousName()
    {
        return "_anonymous" + std::to_string(nameCounter++);
    }

    void output(const char* format, ...)
    {
        for (int i = 0; i < indentLevel; ++i)
            fprintf(file, "    ");
        va_list args;
        va_start(args, format);
        vfprintf(file, format, args);
        va_end(args);
        fprintf(file, "\n");
    }

    void pushScope()
    {
        definedTypes.push_back({});
        structForwardDeclarations.push_back({});
    }

    void addTypeDefinition(const std::string& name)
    {
        definedTypes.back().insert(name);
    }

    bool typeDeclarationExists(const std::string& name)
    {
        return definedTypes.back().count(name) != 0 ||
            structForwardDeclarations.back().count(name) != 0;
    }

    void addStructForwardDeclare(const std::string& name)
    {
        structForwardDeclarations.back().insert(name);
    }

    void popScope()
    {
        auto& decls = definedTypes.back();
        auto& structFwdDecls = structForwardDeclarations.back();

        // Emit forward declarations for all types that never got a definition.
        for (const std::string& name: structFwdDecls)
        {
            if (decls.count(name) == 0)
                output("public struct %s;", name.c_str());
        }

        structForwardDeclarations.pop_back();
        definedTypes.pop_back();
    }

    bool scopeIsGlobal()
    {
        // TODO: Kinda ugly to tie this to indentation, but reliable for now.
        return indentLevel == 0;
    }

    void emitPadding(size_t bytes)
    {
        if (bytes != 0)
            output("private uint8_t __pad%d[%d];", nameCounter++, bytes);
    }

    void generateFunctionWrappers(const std::string& preamble)
    {
        for (FunctionWrapperInfo& wrapper: pendingFunctionWrappers)
        {
            generateFunctionWrapper(*this, preamble, wrapper.slangPrototype, wrapper.cAdapter, wrapper.functionName, wrapper.argCount);
        }
    }
};

void dumpDecl(BindingContext& ctx, clang::Decl* decl, bool topLevel);

class SlangBindgen : public clang::ASTConsumer
{
public:
    BindingContext* ctx;
    SlangBindgen(BindingContext* ctx) : ctx(ctx) {}

    bool HandleTopLevelDecl(clang::DeclGroupRef decl)
    {
        for (clang::Decl* singleDecl: decl)
            dumpDecl(*ctx, singleDecl, true);
        return true;
    }
};

class SlangBindgenAction : public clang::ASTFrontendAction
{
public:
    BindingContext* ctx;
    SlangBindgenAction(BindingContext* ctx) : ctx(ctx) {}

    std::unique_ptr<clang::ASTConsumer> CreateASTConsumer(
        clang::CompilerInstance &CI,
        clang::StringRef InFile
    ){
        return std::unique_ptr<clang::ASTConsumer>(new SlangBindgen(ctx));
    }
};

class DiagConsumer : public clang::DiagnosticConsumer {
public:
    void HandleDiagnostic(
        clang::DiagnosticsEngine::Level level,
        const clang::Diagnostic& info
    ) override
    {
        if (
            level == clang::DiagnosticsEngine::Level::Fatal ||
            level == clang::DiagnosticsEngine::Level::Error
        ){
            llvm::SmallString<100> text;
            info.FormatDiagnostic(text);
            fprintf(stderr, "// Error: %s\n", text.c_str());
        }
    }
};

std::string getSizedIntNameInSlang(int bits)
{
    switch(bits)
    {
    case 8:
        return "int8_t";
    case 16:
        return "int16_t";
    case 32:
        return "int";
    case 64:
        return "int64_t";
    }
    assert(false);
    return "int";
}

struct ClangSession
{
    std::unique_ptr<clang::driver::Driver> driver;
    std::unique_ptr<clang::CompilerInstance> clang;
    std::unique_ptr<clang::driver::Compilation> comp;

    std::string verboseOutputString;
    llvm::SmallVector<char> outputString;
    DiagConsumer diagConsumer;
    clang::DiagnosticOptions diagOpts;

    ClangSession()
    {
        llvm::InitializeAllTargetInfos();
        llvm::InitializeAllTargets();
        llvm::InitializeAllTargetMCs();
        llvm::InitializeAllAsmParsers();
        llvm::InitializeAllAsmPrinters();

        if (options.targetTriple.empty())
            options.targetTriple = llvm::sys::getDefaultTargetTriple();

        auto fs = llvm::vfs::getRealFileSystem();
        llvm::IntrusiveRefCntPtr<clang::DiagnosticIDs> diagID(new clang::DiagnosticIDs());
        llvm::IntrusiveRefCntPtr<clang::DiagnosticsEngine> diags(new clang::DiagnosticsEngine(diagID, diagOpts, &diagConsumer, false));
        driver.reset(new clang::driver::Driver(BINDGEN_PATH_TO_CLANG, options.targetTriple, *diags, "Slang Bindgen", fs));

        // Add some fake job to dig out the system library directories from 
        // Clang :/
        driver->setCheckInputsExist(false);

        // The path to Clang is only needed because the driver computes some
        // include directories based on that :( it doesn't mean that this
        // program would actually depend on the presence of the Clang executable
        // itself.
        comp.reset(driver->BuildCompilation({"clang", "-w", "-S", "dummy.c", "-I.", "-g0"}));
        const auto &jobs = comp->getJobs();
        assert(jobs.size() == 1);
        // These args should contain correct system include directories as well.
        const llvm::opt::ArgStringList &ccArgs = jobs.begin()->getArguments();

        clang.reset(new clang::CompilerInstance());
        auto& invocation = clang->getInvocation();
        clang::CompilerInvocation::CreateFromArgs(invocation, ccArgs, *diags);

        auto& frontendOpts = invocation.getFrontendOpts();
        frontendOpts.Inputs.clear();

        clang->setVerboseOutputStream(std::make_unique<llvm::raw_string_ostream>(verboseOutputString));
        clang->setOutputStream(std::make_unique<llvm::raw_svector_ostream>(outputString));

        auto& targetOpts = invocation.getTargetOpts();
        targetOpts.Triple = options.targetTriple;

        auto& ppOpts = invocation.getPreprocessorOpts();
        for (const std::string& def: options.defines)
            ppOpts.addMacroDef(def);

        auto& opts = invocation.getLangOpts();
        std::vector<std::string> includes;
        clang::LangOptions::setLangDefaults(
            opts, clang::Language::C, llvm::Triple(options.targetTriple),
            includes, clang::LangStandard::Kind::lang_c17
        );
        auto& searchOpts = clang->getHeaderSearchOpts();
        for (const std::string& path: options.defines)
            searchOpts.AddPath(path, clang::frontend::IncludeDirGroup::Angled, false, false);

        searchOpts.UseBuiltinIncludes = true;
        searchOpts.UseStandardSystemIncludes = true;
        searchOpts.UseStandardCXXIncludes = false;
        //searchOpts.Verbose = true;

        clang->createDiagnostics(*fs);
        clang->setDiagnostics(diags.get());

        clang->createFileManager(fs);
        clang->createSourceManager(clang->getFileManager());
    }

    void determineIntegerSizes(BindingContext& ctx)
    {
        // Let's compile a quick probe to check what the sizes are on this
        // platform.
        const char* src = R"(
            #include <wchar.h>
            wchar_t globalWchar = 0;
            short globalShort = 0;
            int globalInt = 0;
            long globalLong = 0;
        )";

        clang::InputKind inputKind(clang::Language::C, clang::InputKind::Format::Source);
        clang::FrontendInputFile inputFile(llvm::MemoryBufferRef(src, "<input>"), inputKind);

        auto& invocation = clang->getInvocation();
        auto& frontendOpts = invocation.getFrontendOpts();
        frontendOpts.Inputs.clear();
        frontendOpts.Inputs.push_back(inputFile);

        std::unique_ptr<llvm::LLVMContext> llvmContext = std::make_unique<llvm::LLVMContext>();
        std::unique_ptr<clang::CodeGenAction> codeGenAction(new clang::EmitLLVMOnlyAction(llvmContext.get()));

        if (!clang->ExecuteAction(*codeGenAction))
            exit(1);

        std::unique_ptr<llvm::Module> mod = codeGenAction->takeModule();
        llvm::GlobalVariable* globalWchar = llvm::cast<llvm::GlobalVariable>(mod->getNamedValue("globalWchar"));
        assert(globalWchar);
        llvm::GlobalVariable* globalShort = llvm::cast<llvm::GlobalVariable>(mod->getNamedValue("globalShort"));
        assert(globalShort);
        llvm::GlobalVariable* globalInt = llvm::cast<llvm::GlobalVariable>(mod->getNamedValue("globalInt"));
        assert(globalInt);
        llvm::GlobalVariable* globalLong = llvm::cast<llvm::GlobalVariable>(mod->getNamedValue("globalLong"));
        assert(globalLong);

        llvm::IntegerType* wcharType = llvm::cast<llvm::IntegerType>(globalWchar->getValueType());
        llvm::IntegerType* shortType = llvm::cast<llvm::IntegerType>(globalShort->getValueType());
        llvm::IntegerType* intType = llvm::cast<llvm::IntegerType>(globalInt->getValueType());
        llvm::IntegerType* longType = llvm::cast<llvm::IntegerType>(globalLong->getValueType());

        ctx.wcharType = getSizedIntNameInSlang(wcharType->getIntegerBitWidth());
        ctx.shortType = getSizedIntNameInSlang(shortType->getIntegerBitWidth());
        ctx.intType = getSizedIntNameInSlang(intType->getIntegerBitWidth());
        ctx.longType = getSizedIntNameInSlang(longType->getIntegerBitWidth());
    }

    void parseSource(BindingContext& ctx, const std::string& source)
    {
        auto& invocation = clang->getInvocation();
        auto& frontendOpts = invocation.getFrontendOpts();

        clang::InputKind inputKind(clang::Language::C, clang::InputKind::Format::Source);
        clang::FrontendInputFile inputFile(
            llvm::MemoryBufferRef(source, "<input>"),
            inputKind);
        frontendOpts.Inputs.clear();
        frontendOpts.Inputs.push_back(inputFile);

        std::unique_ptr<SlangBindgenAction> bindgenAction(new SlangBindgenAction(&ctx));

        if (!clang->ExecuteAction(*bindgenAction))
        {
            exit(1);
        }
    }

    clang::ASTContext& getASTContext()
    {
        return clang->getASTContext();
    }
};

void generateFunctionWrapper(
    BindingContext& ctx,
    const std::string& preamble,
    const std::string& slangPrototype,
    const std::string& cAdapter,
    const std::string& functionName,
    int argCount
){
    std::string source = preamble + "\n" + cAdapter;

    clang::InputKind inputKind(clang::Language::C, clang::InputKind::Format::Source);
    clang::FrontendInputFile inputFile(llvm::MemoryBufferRef(source, "<input>"), inputKind);

    auto& session = *ctx.session;
    auto& invocation = session.clang->getInvocation();
    auto& frontendOpts = invocation.getFrontendOpts();
    frontendOpts.Inputs.clear();
    frontendOpts.Inputs.push_back(inputFile);

    auto& codegenOpts = invocation.getCodeGenOpts();
    codegenOpts.OptimizationLevel = 3;

    std::unique_ptr<llvm::LLVMContext> llvmContext = std::make_unique<llvm::LLVMContext>();
    std::unique_ptr<clang::CodeGenAction> codeGenAction(new clang::EmitLLVMOnlyAction(llvmContext.get()));

    if (!session.clang->ExecuteAction(*codeGenAction))
        exit(1);

    std::unique_ptr<llvm::Module> mod = codeGenAction->takeModule();
    llvm::StripDebugInfo(*mod);
    llvm::Function* adapter = llvm::cast<llvm::Function>(mod->getNamedValue(FUNCTION_ADAPTER_NAME));

    std::string ir;
    llvm::raw_string_ostream irStream(ir);
    //adapter->getEntryBlock().print(irStream);
    mod->print(irStream, nullptr);

    // TODO: This doesn't actually work yet, because:
    // * Name needs to be different and unique for each wrapper
    // * The wrapping function needs to have inline IR for calling this wrapper.
    ctx.output("%s {", slangPrototype.c_str());
    ctx.indentLevel++;
    ctx.output("__requirePrelude(R\"(%s)\")", ir.c_str());
    //ctx.output("%s", ir.c_str());
    ctx.output(")\";");
    ctx.indentLevel--;
    ctx.output("}");
}

bool isUnscopedEnum(const std::string& enumName)
{
    for (auto& expr: options.unscopedEnums)
    {
        if (std::regex_match(enumName, expr))
            return true;
    }
    return false;
}

std::optional<std::string> maybeGetName(clang::TagDecl* decl)
{
    clang::DeclarationName name = decl->getDeclName();
    if (name)
        return name.getAsString();

    clang::TypedefNameDecl* typedefName = decl->getTypedefNameForAnonDecl();
    if (typedefName)
        return typedefName->getNameAsString();

    return {};
}

std::string typeStr(BindingContext& ctx, clang::QualType qualType, bool omitQualifier = false)
{
    const clang::Type& type = *qualType.getTypePtr();
    std::string qualifier;
    if (!omitQualifier)
    {
        if (qualType.isConstQualified())
            qualifier += "const ";
    }

    if (type.isBuiltinType())
    {
        const clang::BuiltinType *builtin = type.getAs<clang::BuiltinType>();
        switch (builtin->getKind())
        {
        case clang::BuiltinType::Kind::Void:
            return qualifier + "void";
        case clang::BuiltinType::Kind::Bool:
            if (options.useByteBool)
                return qualifier + "uint8_t";
            else 
                return qualifier + "bool";
        case clang::BuiltinType::Kind::UChar:
        case clang::BuiltinType::Kind::Char_U:
            return qualifier + "uint8_t";
        case clang::BuiltinType::Kind::SChar:
        case clang::BuiltinType::Kind::Char_S:
            return qualifier + "int8_t";
        case clang::BuiltinType::Kind::UShort:
            return qualifier + "u" + ctx.shortType;
        case clang::BuiltinType::Kind::Short:
            return qualifier + ctx.shortType;
        case clang::BuiltinType::Kind::Char16:
            return qualifier + "int16_t";
        case clang::BuiltinType::Kind::UInt:
            return qualifier + "u" + ctx.intType;
        case clang::BuiltinType::Kind::Int:
            return qualifier + ctx.intType;
        case clang::BuiltinType::Kind::Char32:
            return qualifier + "int32_t";
        case clang::BuiltinType::Kind::ULong:
            return qualifier + "u" + ctx.longType;
        case clang::BuiltinType::Kind::Long:
            return qualifier + ctx.longType;
        case clang::BuiltinType::Kind::WChar_S:
            return qualifier + ctx.wcharType;
        case clang::BuiltinType::Kind::WChar_U:
            return qualifier + "u" + ctx.wcharType;
        case clang::BuiltinType::Kind::Float16:
            return qualifier + "half";
        case clang::BuiltinType::Kind::Float:
            return qualifier + "float";
        case clang::BuiltinType::Kind::Double:
            return qualifier + "double";
        default:
            assert(false);
        }
    }
    else if(type.isPointerType())
    {
        const clang::PointerType* ptr = type.getAs<clang::PointerType>();
        clang::QualType pointeeType = ptr->getPointeeType();

        if (pointeeType.isConstQualified() && pointeeType->isCharType() && pointeeType->isSignedIntegerType())
        {
            // Special case: turn const char* into NativeString
            return "NativeString";
        }
        // Pointer const qualifiers don't work in Slang, so we omit those.
        return "Ptr<"+typeStr(ctx, pointeeType, true)+">";
    }
    else if(type.isConstantArrayType())
    {
        const clang::ArrayType* arr = type.getAsArrayTypeUnsafe();
        const clang::ConstantArrayType* constArr = clang::cast<clang::ConstantArrayType>(arr);
        return typeStr(ctx, arr->getElementType())+"["+std::to_string(constArr->getLimitedSize())+"]";
    }
    else if(type.isFunctionProtoType())
    {
        // Function pointers don't exist in Slang (at least yet), so we just
        // turn those into void pointers here.
        return "void";
    }
    else if(type.isRecordType() || type.isEnumeralType())
    {
        // This relies on us never changing the names of types from C. I hope
        // we never have to do that.
        clang::TagDecl* decl = type.getAsTagDecl();
        return qualifier + decl->getName().str();
    }
    assert(false);
}

void dumpEnum(BindingContext& ctx, clang::EnumDecl* decl, const std::string& variableName = "")
{
    std::optional<std::string> name = maybeGetName(decl);

    std::vector<std::string> names;
    std::vector<std::string> values;
    for (clang::EnumConstantDecl* enumerator: decl->enumerators())
    {
        std::string name = enumerator->getName().str();
        // Filter cases that are "unwanted" in the bindings.
        bool matched = false;
        for (auto& expr : options.removeEnumCases)
        {
            if (std::regex_match(name, expr))
                matched = true;
        }
        if (matched)
            continue;

        llvm::SmallVector<char> valueString;
        enumerator->getInitVal().toString(valueString);

        names.push_back(name);
        values.push_back(std::string(valueString.data(), valueString.size()));
    }

    // Rewrite enum case names as requested by options.
    if (names.size() != 0)
    {
        // Find longest common prefix to all enum cases
        std::string prefix = names[0];
        for (size_t i = 1; i < names.size(); ++i)
        {
            const std::string& name = names[i];
            size_t j = 0;
            for (; j < std::min(prefix.size(), name.size()); ++j)
            {
                if (name[j] != prefix[j])
                    break;
            }
            prefix = prefix.substr(0, j);
        }

        // Find longest applicable prefix removal rule 
        std::pair<size_t, size_t> longest_match = {0, 0};
        for (auto& expr : options.removeCommonPrefixes)
        {
            std::smatch match;
            if (std::regex_search(prefix, match, expr))
            {
                if (longest_match.second < match[0].length())
                {
                    size_t begin = match[0].first - prefix.begin();
                    size_t end = match[0].second - prefix.begin();
                    longest_match = {begin, end-begin};
                }
            }
        }

        if (longest_match.second != 0)
        {
            // Rewrite entries without the matched part
            for (std::string& name : names)
            {
                // Would remove this case entirely; hence, can't apply this prefix
                // removal.
                if (longest_match.second == name.length())
                    continue;

                std::string newName = name.substr(0, longest_match.first) +
                    name.substr(longest_match.first + longest_match.second);

                if (isdigit(newName[0]))
                {
                    if (!options.enumFallbackPrefix.empty())
                        newName = options.enumFallbackPrefix + newName;
                    else
                    {
                        // Can't represent this enum correctly because it begins
                        // with a number and there's no prefix for us to use.
                        newName = name;
                    }
                }
                name = newName;
            }
        }
    }

    std::string underlyingType = typeStr(ctx, decl->getIntegerType());
    if (name)
    {
        // Normal named enum.
        if (isUnscopedEnum(*name))
            ctx.output("[UnscopedEnum]");
        ctx.output("public enum %s: %s {", name->c_str(), underlyingType.c_str());
        ctx.indentLevel++;

        for (size_t i = 0; i < names.size(); ++i)
            ctx.output("%s = %s,", names[i].c_str(), values[i].c_str());

        ctx.indentLevel--;
        if (variableName.empty())
            ctx.output("};");
        else
            ctx.output("} %s;", variableName.c_str());
    }
    else
    {
        // Completely anonymous enum, so we might as well pretend that the type
        // doesn't exist and this is just a list of global constants. These
        // cannot be scoped because there is no name to scope them with.
        for (size_t i = 0; i < names.size(); ++i)
            ctx.output("public static const %s %s = %s;", underlyingType.c_str(), names[i].c_str(), values[i].c_str());
        if (!variableName.empty())
            ctx.output("public %s %s;", underlyingType.c_str(), variableName.c_str());
    }
}

void dumpStructField(BindingContext& ctx, clang::FieldDecl* field, size_t& offset)
{
    auto& astCtx = ctx.session->getASTContext();

    clang::QualType qualType = field->getType();
    size_t size = astCtx.getTypeSizeInChars(qualType).getQuantity();
    size_t alignment = astCtx.getTypeAlignInChars(qualType).getQuantity();
    size_t alignedOffset = roundToAlignment(offset, alignment);

    if (field->isAnonymousStructOrUnion())
    {
        const clang::Type& type = *qualType.getTypePtr();

        ctx.pushScope();

        // Gotta align this one manually, because Slang doesn't know of the
        // struct boundary here (because we erased it)
        size_t leadingPadding = alignedOffset-offset;
        ctx.emitPadding(leadingPadding);
        offset += leadingPadding;

        size_t initialOffset = offset;

        if (type.isStructureType())
        {
            clang::RecordDecl* decl = type.getAsRecordDecl();
            for (clang::FieldDecl* field: decl->fields())
                dumpStructField(ctx, field, offset);
        }
        else if (type.isUnionType())
        {
            // TODO anonymous unions in structs
            assert(false);
        }

        size_t emittedSize = offset - initialOffset;
        size_t trailingPadding = size - emittedSize;
        ctx.emitPadding(trailingPadding);
        offset += trailingPadding;
        ctx.popScope();
    }
    else
    {
        offset += alignedOffset - offset;

        clang::QualType qualType = field->getType();
        std::string name = field->getName().str();
        std::string type = typeStr(ctx, qualType);

        if (field->isBitField())
        {
            ctx.output("public %s %s : %u;", type.c_str(), name.c_str(), field->getBitWidthValue());
        }
        else
        {
            ctx.output("public %s %s;", type.c_str(), name.c_str());
        }

        offset += size;
    }
}

void dumpStruct(
    BindingContext& ctx,
    clang::RecordDecl* decl,
    const std::string& variableName = "",
    const std::string& fallbackName = "")
{
    std::optional<std::string> maybeName = maybeGetName(decl);
    if (!maybeName.has_value() && !fallbackName.empty())
        maybeName = fallbackName;

    if (variableName.empty() && !maybeName.has_value())
    {
        // No variable name and no typename - not allowed in Slang. Nested
        // anonymous structs are handled in dumpStructField, though.
        return;
    }

    if (!decl->isCompleteDefinition())
    {
        // Forward declaration, make a note so that we can emit all forward
        // declarations at the end. Slang doesn't need forward declarations
        // unless the type is opaque.
        if (maybeName.has_value())
            ctx.addStructForwardDeclare(*maybeName);
        return;
    }

    if (maybeName.has_value())
    {
        ctx.output("public struct %s {", maybeName->c_str());
        ctx.addTypeDefinition(*maybeName);
    }
    else
    {
        ctx.output("public struct {");
    }
    ctx.indentLevel++;
    ctx.pushScope();

    size_t offset = 0;
    for (clang::Decl* decl: decl->decls())
    {
        if (
            decl->getKind() != clang::Decl::Kind::Field &&
            decl->getKind() != clang::Decl::Kind::IndirectField
        ) dumpDecl(ctx, decl, false);
    }

    for (clang::FieldDecl* field: decl->fields())
    {
        dumpStructField(ctx, field, offset);
    }

    ctx.popScope();
    ctx.indentLevel--;
    if (!variableName.empty())
        ctx.output("} %s;", variableName.c_str());
    else
        ctx.output("};");
}

void dumpUnion(BindingContext& ctx, clang::RecordDecl* decl)
{
    // TODO
}

void dumpRecord(BindingContext& ctx, clang::RecordDecl* decl)
{
    switch(decl->getTagKind())
    {
    case clang::TagTypeKind::Class:
    case clang::TagTypeKind::Struct:
        dumpStruct(ctx, decl);
        break;
    case clang::TagTypeKind::Union:
        dumpUnion(ctx, decl);
        break;
    default:
        assert(false);
        break;
    }
}

void dumpTypedef(BindingContext& ctx, clang::TypedefDecl* decl)
{
    std::string name = decl->getName().str();
    if (ctx.typeDeclarationExists(name))
        return;
    std::string underlyingType = typeStr(ctx, decl->getUnderlyingType(), true);
    ctx.output("public typealias %s = %s;", name.c_str(), underlyingType.c_str());
}

void dumpFunction(BindingContext& ctx, clang::FunctionDecl* decl)
{
    std::string name = decl->getName().str();
    if (ctx.declaredFunctions.count(name))
        return;

    if (decl->isVariadic())
    {
        // Sorry, we have literally zero options to emit this in Slang right
        // now :/
        return;
    }

    ctx.declaredFunctions.insert(name);

    bool paramsNeedCallWrapper = false;
    bool returnNeedsCallWrapper = false;

    std::string paramString;
    bool first = true;
    for (clang::ParmVarDecl* param: decl->parameters())
    {
        if (!first)
            paramString += ", ";
        clang::QualType qualType = param->getType();
        const clang::Type& type = *qualType.getTypePtr();

        // Passing structs by value... uh oh.
        if (type.isStructureType())
            paramsNeedCallWrapper = true;

        paramString += typeStr(ctx, qualType);
        paramString += " ";
        paramString += param->getName().str();
        first = false;
    }

    clang::QualType qualRetType = decl->getReturnType();
    const clang::Type& retType = *qualRetType.getTypePtr();
    if (retType.isStructureType() || retType.isConstantArrayType())
        returnNeedsCallWrapper = true;

    std::string returnString = typeStr(ctx, qualRetType);

    if (!paramsNeedCallWrapper && !returnNeedsCallWrapper)
    {
        // Simple case, our calling convention matches C
        ctx.output("public __extern_cpp %s %s(%s);", returnString.c_str(), name.c_str(), paramString.c_str());
    }
    else
    {
        // Hard case, struct arguments are turned into pointers and returned
        // structs into an extra pointer argument.
        ctx.output("[ForceInline]");
        ctx.output("public %s %s(%s) {", returnString.c_str(), name.c_str(), paramString.c_str());
        ctx.indentLevel++;

        std::string adapterName = "_bindgen_adapter_" + name;
        std::string call = adapterName + "(";
        std::string slangPrototype = "[ForceInline]\ninternal ";
        std::string cAdapterCall = name + "(";
        std::string cAdapter;
        if (returnNeedsCallWrapper)
        {
            cAdapter = "void";
            slangPrototype += "void";
        }
        else
        {
            cAdapter = qualRetType.getAsString();
            slangPrototype += returnString;
        }
        cAdapter += " " FUNCTION_ADAPTER_NAME "(";
        slangPrototype += " " + adapterName + "(";
        int paramIndex = 0;
        for (clang::ParmVarDecl* param: decl->parameters())
        {
            if (paramIndex != 0)
            {
                call += ", ";
                slangPrototype += ", ";
                cAdapter += ", ";
                cAdapterCall += ", ";
            }
            clang::QualType qualType = param->getType();
            const clang::Type& type = *qualType.getTypePtr();

            std::string name = param->getName().str();
            std::string cTagName = FUNCTION_ADAPTER_ARG_NAME + std::to_string(paramIndex);
            if (type.isStructureType())
            {
                call += "&"+name;
                slangPrototype += "Ptr<"+typeStr(ctx, qualType, true)+"> " + cTagName;
                cAdapter += qualType.getAsString() + "* " + cTagName;
                cAdapterCall += "*"+cTagName;
            }
            else
            {
                call += name;
                slangPrototype += typeStr(ctx, qualType) + " " + cTagName;
                cAdapter += qualType.getAsString() + " " + cTagName;
                cAdapterCall += cTagName;
            }

            paramIndex++;
        }
        if (returnNeedsCallWrapper)
        {
            if(paramIndex != 0)
            {
                call += ", ";
                slangPrototype += ", ";
                cAdapter += ", ";
            }

            call += "&returnval";
            std::string cTagName = FUNCTION_ADAPTER_ARG_NAME + std::to_string(paramIndex);
            slangPrototype += "Ptr<"+typeStr(ctx, qualRetType, true) + "> " + cTagName;
            cAdapter += qualRetType.getUnqualifiedType().getAsString() + "* "+cTagName;
            cAdapterCall = "*" + cTagName+" = " + cAdapterCall;
            paramIndex++;
        }
        else if(!retType.isVoidType())
        {
            cAdapterCall = "return " + cAdapterCall;
        }
        cAdapter += "){\n    "+cAdapterCall+");\n}\n";
        call += ")";
        slangPrototype += ")";

        if (returnNeedsCallWrapper)
        {
            ctx.output("%s returnval;", returnString.c_str());
            ctx.output("%s;", call.c_str());
            ctx.output("return returnval;");
        }
        else if(!retType.isVoidType())
        {
            ctx.output("return %s;", call.c_str());
        }
        else
        {
            ctx.output("%s;", call.c_str());
        }
        ctx.indentLevel--;
        ctx.output("}");

        ctx.pendingFunctionWrappers.push_back({
            slangPrototype,
            cAdapter,
            name,
            paramIndex
        });
    }
}

void dumpDecl(BindingContext& ctx, clang::Decl* decl, bool topLevel)
{
    switch(decl->getKind())
    {
    case clang::Decl::Kind::Enum:
        dumpEnum(ctx, clang::cast<clang::EnumDecl>(decl));
        break;
    case clang::Decl::Kind::Record:
        dumpRecord(ctx, clang::cast<clang::RecordDecl>(decl));
        break;
    case clang::Decl::Kind::Typedef:
        dumpTypedef(ctx, clang::cast<clang::TypedefDecl>(decl));
        break;
    case clang::Decl::Kind::Function:
        dumpFunction(ctx, clang::cast<clang::FunctionDecl>(decl));
        break;
    default:
        //if (!topLevel)
        //    assert(false);
        //printf("Unknown decl type\n");
        break;
    }
}


int main(int argc, const char** argv)
{
    if (!parseOptions(argc, argv))
    {
        printHelp(true, argv);
        return 1;
    }

    BindingContext ctx(options.outputPath);

    ctx.output("// Auto-generated bindings by slang-bindgen.py, from headers:");
    for (const std::string& header: options.cHeaders)
        ctx.output("//   %s", header.c_str());

    for (const std::string& mod: options.importModules)
        ctx.output("import %s;", mod.c_str());

    for (const std::string& ns: options.usingNamespaces)
        ctx.output("using %s;", ns.c_str());

    if (!options.inNamespace.empty())
    {
        ctx.output("namespace %s {", options.inNamespace.c_str());
        ctx.indentLevel++;
    }

    ClangSession session;
    ctx.session = &session;

    session.determineIntegerSizes(ctx);

    std::string inputSource = "";
    for (const std::string& ns: options.cHeaders)
        inputSource += "#include \""+ns+"\"\n";

    ctx.pushScope();

    session.parseSource(ctx, inputSource);

    ctx.popScope();

    ctx.generateFunctionWrappers(inputSource);

    if (!options.inNamespace.empty())
    {
        ctx.indentLevel--;
        ctx.output("}");
    }
    return 0;
}
