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
#include <memory>
#include <filesystem>

#define FUNCTION_ADAPTER_NAME "_SLANG_BINDGEN_FUNC_ADAPTER_"
#define FUNCTION_ADAPTER_ARG_NAME "_SLANG_BINDGEN_ARG_"

static struct {
    std::string inNamespace;
    std::string outputPath;
    std::string shimOutputPath;
    std::string targetTriple;
    std::vector<std::string> cHeaders;
    std::vector<std::string> importModules;
    std::vector<std::string> usingNamespaces;
    std::vector<std::string> importedHeaders;
    std::vector<std::string> defines;
    std::vector<std::string> includePaths;
    std::set<std::string> exportSymbols;
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
--export-symbols <sym>    exports declarations with the given names even if they
                          come from outside the input headers.
--rm-enum-case <regex>    removes matching cases from all enums
--fallback-prefix <str>   adds the given prefix to all enum case names that
                          would not be valid in Slang
--use-byte-bool           uses uint8_t instead of bool. Useful when overriding
                          default layout to something where sizeof(bool) != 1.
--call-shim <object-file> generates shim object code for calling C functions
                          with difficult calling convention issues
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
                options.importedHeaders.push_back(value);
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
            else if (strcmp(arg, "call-shim") == 0)
            {
                options.shimOutputPath = value;
                i++;
            }
            else if (strcmp(arg, "export-symbols") == 0)
            {
                std::string sym;
                for (int j = 0; ; ++j)
                {
                    char c = value[j];
                    if (c == ',' || c == 0)
                    {
                        if (sym.size() != 0)
                            options.exportSymbols.insert(sym);
                        sym.clear();
                        if (c == 0)
                            break;
                    }
                    else sym += c;
                }
                i++;
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
    std::vector<std::set<std::string>> typeForwardDeclarations;
    std::vector<std::filesystem::path> allowedSources;
    std::vector<std::filesystem::path> visibleSources;

    std::map<std::string, std::string> knownDefinitions;

    std::string shimCode;

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

        for (const std::string& s: options.cHeaders)
        {
            allowedSources.push_back(s);
            visibleSources.push_back(s);
        }
        for (const std::string& s: options.importedHeaders)
        {
            visibleSources.push_back(s);
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
        typeForwardDeclarations.push_back({});
    }

    void addTypeDefinition(const std::string& name)
    {
        definedTypes.back().insert(name);
    }

    bool typeDeclarationExists(const std::string& name)
    {
        return definedTypes.back().count(name) != 0 ||
            typeForwardDeclarations.back().count(name) != 0;
    }

    void addTypeForwardDeclare(const std::string& name)
    {
        typeForwardDeclarations.back().insert(name);
    }

    void popScope()
    {
        auto& decls = definedTypes.back();
        auto& typeFwdDecls = typeForwardDeclarations.back();
        bool topLevel = typeForwardDeclarations.size() <= 1 ;
        auto& upperStructFwdDecls = topLevel ? typeFwdDecls :
            typeForwardDeclarations[typeForwardDeclarations.size()-2];

        // Emit forward declarations for all types that never got a definition.
        for (const std::string& name: typeFwdDecls)
        {
            if (decls.count(name) == 0)
            {
                if (topLevel)
                {
                    // No choice but to forward-declare.
                    output("public struct %s;", name.c_str());
                }
                else
                {
                    // Punt the problem into the outer scope.
                    upperStructFwdDecls.insert(name);
                }
            }
        }

        typeForwardDeclarations.pop_back();
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

    void emitShimLibrary();
};

class SlangMacroBindgen : public clang::PPCallbacks
{
public:
    BindingContext* ctx;
    SlangMacroBindgen(BindingContext* ctx) : ctx(ctx) {}

    void MacroDefined(const clang::Token &MacroNameTok, const clang::MacroDirective *MD) override;
};

class SlangBindgen : public clang::ASTConsumer
{
public:
    BindingContext* ctx;
    SlangBindgen(BindingContext* ctx) : ctx(ctx) {}
    ~SlangBindgen();

    void Initialize(clang::ASTContext &Context);
    bool HandleTopLevelDecl(clang::DeclGroupRef decl);
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
        auto loc = info.getLocation();
        auto& sourceManager = info.getSourceManager();
        std::string filename = sourceManager.getFilename(loc).str();
        int line = sourceManager.getPresumedLineNumber(loc);
        llvm::SmallString<100> text;
        info.FormatDiagnostic(text);
        if (
            level == clang::DiagnosticsEngine::Level::Fatal ||
            level == clang::DiagnosticsEngine::Level::Error
        ){
            fprintf(stderr, "// Error: (%s:%d) %s\n", filename.c_str(), line, text.c_str());
        }
        //else fprintf(stderr, "// (%s:%d) %s\n", filename.c_str(), line, text.c_str());
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
        comp.reset(driver->BuildCompilation({"clang", "-w", "-S", "dummy.c", "-I.", "-g0", "-fvisibility=default"}));
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
        for (const std::string& path: options.includePaths)
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

bool isLocationActive(BindingContext& ctx, clang::SourceLocation loc)
{
    auto& sourceManager = ctx.session->clang->getSourceManager();
    loc = sourceManager.getFileLoc(loc);
    std::filesystem::path path(sourceManager.getFilename(loc).str());

    for (auto& allowed: ctx.allowedSources)
    {
        try
        {
            if (std::filesystem::equivalent(path, allowed))
                return true;
        }
        catch(...)
        {
            continue;
        }
    }
    return false;
}

bool isNameActive(clang::Decl* decl)
{
    clang::NamedDecl* named = clang::cast_or_null<clang::NamedDecl>(decl);
    if (!named)
        return false;

    std::string name = named->getDeclName().getAsString();
    return options.exportSymbols.count(name) != 0;
}

bool isLocationVisible(BindingContext& ctx, clang::SourceLocation loc)
{
    auto& sourceManager = ctx.session->clang->getSourceManager();
    loc = sourceManager.getFileLoc(loc);
    std::filesystem::path path(sourceManager.getFilename(loc).str());

    for (auto& allowed: ctx.visibleSources)
    {
        try
        {
            if (std::filesystem::equivalent(path, allowed))
                return true;
        }
        catch(...)
        {
            continue;
        }
    }
    return false;
}

void BindingContext::emitShimLibrary()
{
    clang::InputKind inputKind(clang::Language::C, clang::InputKind::Format::Source);
    clang::FrontendInputFile inputFile(llvm::MemoryBufferRef(shimCode, "<inline-bindgen>"), inputKind);

    auto& invocation = session->clang->getInvocation();
    auto& frontendOpts = invocation.getFrontendOpts();
    frontendOpts.Inputs.clear();
    frontendOpts.Inputs.push_back(inputFile);
    frontendOpts.OutputFile = options.shimOutputPath;

    auto& codegenOpts = invocation.getCodeGenOpts();
    codegenOpts.OptimizationLevel = 3;

    std::unique_ptr<llvm::LLVMContext> llvmContext = std::make_unique<llvm::LLVMContext>();
    std::unique_ptr<clang::CodeGenAction> codeGenAction(new clang::EmitObjAction(llvmContext.get()));

    if (!session->clang->ExecuteAction(*codeGenAction))
        exit(1);
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

std::string getTypeStr(BindingContext& ctx, clang::QualType qualType, bool omitQualifier = false)
{
    const clang::Type& type = *qualType.getTypePtr();
    std::string qualifier;
    if (!omitQualifier)
    {
        if (qualType.isConstQualified())
            qualifier += "const ";
    }

    if (const clang::TypedefType* typedefType = type.getAs<clang::TypedefType>())
    {
        clang::TypedefNameDecl* decl = typedefType->getDecl();
        // Use typedef names if the decl is visible, those should exist.
        if (isLocationVisible(ctx, decl->getLocation()) || isNameActive(decl))
            return decl->getName().str();
        // Otherwise, continue with the canonical type.
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
        case clang::BuiltinType::Kind::ULongLong:
            return qualifier + "uint64_t";
        case clang::BuiltinType::Kind::LongLong:
            return qualifier + "int64_t";
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
        return "Ptr<"+getTypeStr(ctx, pointeeType, true)+">";
    }
    else if(type.isConstantArrayType())
    {
        const clang::ArrayType* arr = type.getAsArrayTypeUnsafe();
        const clang::ConstantArrayType* constArr = clang::cast<clang::ConstantArrayType>(arr);
        return getTypeStr(ctx, arr->getElementType())+"["+std::to_string(constArr->getLimitedSize())+"]";
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
        std::string ident = decl->getName().str();

        // If this type is not defined in the headers we're generating the
        // bindings for, we'll need to cover it somehow else.
        bool visible = isLocationVisible(ctx, decl->getLocation());

        if (!visible && type.isRecordType())
        {
            // Add a forward declare for structs and unions.
            ctx.addTypeForwardDeclare(ident);
        }

        if (type.isEnumeralType() && (!visible || ident.empty()))
        {
            // Use the underlying type for anonymous or externally defined enums.
            clang::EnumDecl* enumDecl = clang::cast<clang::EnumDecl>(decl);
            ident = getTypeStr(ctx, enumDecl->getIntegerType(), true);
        }
        return qualifier + ident;
    }
    assert(false);
}

void dumpDecl(BindingContext& ctx, clang::Decl* decl, bool topLevel);

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

    std::string underlyingType = getTypeStr(ctx, decl->getIntegerType());
    if (name)
    {
        ctx.addTypeDefinition(*name);

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

void dumpRecord(
    BindingContext& ctx,
    clang::RecordDecl* decl,
    const std::string& variableName = "",
    const std::string& fallbackName = "");

void dumpUnionContents(BindingContext& ctx, clang::RecordDecl* decl);

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

        clang::RecordDecl* recordDecl = type.getAsRecordDecl();
        if (type.isStructureType())
        {
            for (clang::FieldDecl* field: recordDecl->fields())
                dumpStructField(ctx, field, offset);
        }
        else if (type.isUnionType())
        {
            dumpUnionContents(ctx, recordDecl);
            offset += size;
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

        clang::RecordDecl* recordDecl = qualType->getAsRecordDecl();

        std::string name = field->getName().str();
        std::string type = getTypeStr(ctx, qualType);

        if (field->isBitField())
        {
            ctx.output("public %s %s : %u;", type.c_str(), name.c_str(), field->getBitWidthValue());
        }
        else if (recordDecl && !recordDecl->getDeclName())
        {
            dumpRecord(ctx, recordDecl, name);
        }
        else
        {
            ctx.output("public %s %s;", type.c_str(), name.c_str());
        }

        offset += size;
    }
}

void dumpStructContents(BindingContext& ctx, clang::RecordDecl* decl)
{
    size_t offset = 0;
    for (clang::FieldDecl* field: decl->fields())
    {
        dumpStructField(ctx, field, offset);
    }
}

void dumpUnionImplicitMemberAccessor(
    BindingContext& ctx,
    clang::FieldDecl* field,
    const std::string& adapterName,
    const char* backingMemoryType,
    size_t backingMemoryLength,
    const char* backingMemoryName
){
    clang::QualType qualType = field->getType();
    if (field->isAnonymousStructOrUnion())
    {
        clang::RecordDecl* decl = qualType->getAsRecordDecl();
        for (clang::FieldDecl* subfield: decl->fields())
            dumpUnionImplicitMemberAccessor(ctx, subfield, adapterName, backingMemoryType, backingMemoryLength, backingMemoryName);
    }
    else
    {
        std::string name = field->getName().str();
        std::string type = getTypeStr(ctx, qualType);

        ctx.output("public property %s %s {", type.c_str(), name.c_str());
        ctx.indentLevel++;
        ctx.output("get {");
        ctx.indentLevel++;
        ctx.output("%s tmp = reinterpret<%s>(%s);", adapterName.c_str(), adapterName.c_str(), backingMemoryName);
        ctx.output("return tmp.value.%s;", name.c_str());
        ctx.indentLevel--;
        ctx.output("}");
        ctx.output("set {");
        ctx.indentLevel++;
        ctx.output("%s tmp = reinterpret<%s>(%s);", adapterName.c_str(), adapterName.c_str(), backingMemoryName);
        ctx.output("tmp.value.%s = newValue;", name.c_str());
        ctx.output("%s = reinterpret<%s[%zu]>(tmp);", backingMemoryName, backingMemoryType, backingMemoryLength);
        ctx.indentLevel--;
        ctx.output("}");
        ctx.indentLevel--;
        ctx.output("};");
    }
}

void dumpUnionField(
    BindingContext& ctx,
    clang::FieldDecl* field,
    size_t unionSize,
    const char* backingMemoryType,
    size_t backingMemoryLength,
    const char* backingMemoryName
){
    auto& astCtx = ctx.session->getASTContext();

    clang::QualType qualType = field->getType();
    size_t size = astCtx.getTypeSizeInChars(qualType).getQuantity();
    size_t alignment = astCtx.getTypeAlignInChars(qualType).getQuantity();

    std::string name = field->getName().str();
    std::string type = getTypeStr(ctx, qualType);
    if (type.empty())
    {
        type = "_anonymousMemberTypeBinding"+std::to_string(ctx.nameCounter++);
        clang::RecordDecl* recordDecl = qualType->getAsRecordDecl();
        if (recordDecl)
        {
            dumpRecord(ctx, recordDecl, "", type);
        }
    }

    if (field->isAnonymousStructOrUnion())
    {
        // The type name should be unique.
        std::string adapterName = "_unionBindingAdapter_" + type;

        ctx.output("internal struct %s {", adapterName.c_str());
        ctx.indentLevel++;
        ctx.output("%s value;", type.c_str());
        if (size < unionSize)
            ctx.output("uint8_t pad[%zu];", unionSize - size);
        ctx.indentLevel--;
        ctx.output("};");

        dumpUnionImplicitMemberAccessor(ctx, field, adapterName, backingMemoryType, backingMemoryLength,backingMemoryName);
    }
    else
    {
        std::string adapterName = "_unionBindingAdapter_" + name;

        ctx.output("internal struct %s {", adapterName.c_str());
        ctx.indentLevel++;
        ctx.output("%s value;", type.c_str());
        if (size < unionSize)
            ctx.output("uint8_t pad[%zu];", unionSize - size);
        ctx.indentLevel--;
        ctx.output("};");

        ctx.output("public property %s %s {", type.c_str(), name.c_str());
        ctx.indentLevel++;
        ctx.output("get {");
        ctx.indentLevel++;
        ctx.output("%s tmp = reinterpret<%s>(%s);", adapterName.c_str(), adapterName.c_str(), backingMemoryName);
        ctx.output("return tmp.value;");
        ctx.indentLevel--;
        ctx.output("}");
        ctx.output("set {");
        ctx.indentLevel++;
        ctx.output("%s tmp;", adapterName.c_str());
        ctx.output("tmp.value = newValue;");
        ctx.output("%s = reinterpret<%s[%zu]>(tmp);", backingMemoryName, backingMemoryType, backingMemoryLength);
        ctx.indentLevel--;
        ctx.output("}");
        ctx.indentLevel--;
        ctx.output("};");
    }
}

void dumpUnionContents(BindingContext& ctx, clang::RecordDecl* decl)
{
    auto& astCtx = ctx.session->getASTContext();
    clang::QualType qualType = astCtx.getRecordType(decl);
    size_t size = astCtx.getTypeSizeInChars(qualType).getQuantity();
    size_t alignment = astCtx.getTypeAlignInChars(qualType).getQuantity();

    size_t backingMemoryLength = (size + alignment - 1)/ alignment;

    const char* backingMemoryType;
    if (alignment >= 8)
        backingMemoryType = "uint64_t";
    else if (alignment >= 4)
        backingMemoryType = "uint32_t";
    else if (alignment >= 2)
        backingMemoryType = "uint16_t";
    else
        backingMemoryType = "uint8_t";

    std::string backingMemoryName = "_unionBindingBackingMemory"+std::to_string(ctx.nameCounter++);

    ctx.output("internal %s %s[%zu];", backingMemoryType, backingMemoryName.c_str(), backingMemoryLength);

    for (clang::FieldDecl* field: decl->fields())
    {
        dumpUnionField(ctx, field, size, backingMemoryType, backingMemoryLength, backingMemoryName.c_str());
    }
}

void dumpRecord(
    BindingContext& ctx,
    clang::RecordDecl* decl,
    const std::string& variableName,
    const std::string& fallbackName)
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
            ctx.addTypeForwardDeclare(*maybeName);
        return;
    }

    // Unions don't exist in Slang, so we emit those as "weird" structs. So
    // here, we're always emitting a struct, even if the C type is a union.
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

    for (clang::Decl* decl: decl->decls())
    {
        if (
            decl->getKind() != clang::Decl::Kind::Field &&
            decl->getKind() != clang::Decl::Kind::IndirectField
        ) dumpDecl(ctx, decl, false);
    }

    switch(decl->getTagKind())
    {
    case clang::TagTypeKind::Class:
    case clang::TagTypeKind::Struct:
        dumpStructContents(ctx, decl);
        break;
    case clang::TagTypeKind::Union:
        dumpUnionContents(ctx, decl);
        break;
    default:
        assert(false);
        break;
    }

    ctx.popScope();
    ctx.indentLevel--;
    if (!variableName.empty())
        ctx.output("} %s;", variableName.c_str());
    else
        ctx.output("};");
}

void dumpTypedef(BindingContext& ctx, clang::TypedefDecl* decl)
{
    std::string name = decl->getName().str();
    if (ctx.typeDeclarationExists(name))
        return;
    ctx.addTypeDefinition(name);
    std::string underlyingType = getTypeStr(ctx, decl->getUnderlyingType(), true);
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

        paramString += getTypeStr(ctx, qualType);
        paramString += " ";
        paramString += param->getName().str();
        first = false;
    }

    clang::QualType qualRetType = decl->getReturnType();
    const clang::Type& retType = *qualRetType.getTypePtr();
    if (retType.isStructureType() || retType.isConstantArrayType())
        returnNeedsCallWrapper = true;

    std::string returnString = getTypeStr(ctx, qualRetType);

    if (!paramsNeedCallWrapper && !returnNeedsCallWrapper)
    {
        // Simple case, our calling convention matches C
        ctx.output("public __extern_cpp %s %s(%s);", returnString.c_str(), name.c_str(), paramString.c_str());
    }
    else if (!options.shimOutputPath.empty())
    {
        // Hard case, struct arguments are turned into pointers and returned
        // structs into an extra pointer argument. Need to emit shim library
        // for this.
        ctx.output("[ForceInline]");
        ctx.output("public %s %s(%s) {", returnString.c_str(), name.c_str(), paramString.c_str());
        ctx.indentLevel++;

        std::string call = FUNCTION_ADAPTER_NAME + name + "(";
        std::string cCall = name + "(";
        std::string adapterSlangDecl = call;

        llvm::raw_string_ostream shimStream(ctx.shimCode);
        auto printingPolicy = ctx.session->getASTContext().getPrintingPolicy();
        if (returnNeedsCallWrapper)
        {
            adapterSlangDecl += "void";
            shimStream << "void";
        }
        else
        {
            adapterSlangDecl = returnString;
            qualRetType.print(shimStream, printingPolicy);
        }

        adapterSlangDecl += " " + call;
        shimStream << " " << call;

        int paramIndex = 0;
        for (clang::ParmVarDecl* param: decl->parameters())
        {
            if (paramIndex != 0)
            {
                call += ", ";
                cCall += ", ";
                adapterSlangDecl += ", ";
                shimStream << ", ";
            }
            clang::QualType qualType = param->getType();
            const clang::Type& type = *qualType.getTypePtr();

            std::string name = param->getName().str();
            std::string cTagName = FUNCTION_ADAPTER_ARG_NAME + std::to_string(paramIndex);
            if (type.isStructureType())
            {
                call += "&";
                cCall += "*";
                adapterSlangDecl += "Ptr<"+getTypeStr(ctx, qualType, true)+">";

                clang::QualType qp = ctx.session->getASTContext().getPointerType(qualType);
                qp.print(shimStream, printingPolicy);
            }
            else
            {
                adapterSlangDecl += getTypeStr(ctx, qualType);
                qualType.print(shimStream, printingPolicy);
            }
            call += name;
            cCall += cTagName;
            adapterSlangDecl += " " + cTagName;
            shimStream << " " << cTagName;

            paramIndex++;
        }
        if (returnNeedsCallWrapper)
        {
            if (paramIndex != 0)
            {
                call += ", ";
                adapterSlangDecl += ", ";
                shimStream << ", ";
            }
            call += "&returnvalue";
            adapterSlangDecl += "Ptr<"+returnString+"> returnvalue";

            clang::QualType qp = ctx.session->getASTContext().getPointerType(qualRetType);
            qp.print(shimStream, printingPolicy);
            shimStream << " returnvalue";
        }

        call += ")";
        cCall += ")";
        adapterSlangDecl += ")";
        shimStream << ") {\n";

        if (returnNeedsCallWrapper)
        {
            ctx.output("%s returnvalue;", returnString.c_str());
            ctx.output("%s;", call.c_str());
            ctx.output("return returnvalue;");
            shimStream << "    *returnvalue = " << cCall << ";\n";
        }
        else if (retType.isVoidType())
        {
            ctx.output("%s;", call.c_str());
            shimStream << "    " << cCall << ";\n";
        }
        else
        {
            ctx.output("return %s;", call.c_str());
            shimStream << "    return " << cCall << ";\n";
        }

        ctx.indentLevel--;
        ctx.output("}");
        shimStream << "}\n";
        ctx.output("__extern_cpp %s;", adapterSlangDecl.c_str());
    }
}

void dumpConstantVar(BindingContext& ctx, clang::VarDecl* decl)
{
    clang::Expr* initializer = decl->getInit();
    clang::QualType initializerType = initializer->getType();
    std::string initializerStr;

    auto& astCtx = ctx.session->getASTContext();
    clang::Expr::EvalResult result;
    if (!initializer->EvaluateAsConstantExpr(result, astCtx))
        return;

    clang::PrintingPolicy policy = astCtx.getPrintingPolicy();
    policy.ConstantsAsWritten = 1;
    policy.PrintAsCanonical = 0;
    policy.EntireContentsOfLargeArray = 1;
    policy.Indentation = 4;

    std::string type = getTypeStr(ctx, decl->getType(), true);

    if (result.Val.isInt())
    {
        llvm::SmallString<10> text;
        result.Val.getInt().toString(text);

        initializerStr = text.str();

        if(astCtx.getTypeSize(initializerType) == 64)
            initializerStr += "ll";
        if(initializerType->isUnsignedIntegerType())
            initializerStr += "u";
    }
    else if (result.Val.isFloat())
    {
        llvm::SmallString<10> text;
        result.Val.getFloat().toString(text);

        initializerStr = text.str();

        const clang::BuiltinType *builtin = initializerType->getAs<clang::BuiltinType>();
        auto kind = builtin->getKind();
        if (kind == clang::BuiltinType::Kind::Float16)
            initializerStr += "h";
        else if(kind == clang::BuiltinType::Kind::Float)
            initializerStr += "f";
        else if(kind == clang::BuiltinType::Kind::Double)
            initializerStr += "l";
    }
    else if (result.Val.isLValue() && type == "NativeString")
    {
        auto base = result.Val.getLValueBase();
        llvm::raw_string_ostream os(initializerStr);

        if (const clang::Expr* vd = base.dyn_cast<const clang::Expr*>())
        {
            vd->printPretty(os, nullptr, astCtx.getPrintingPolicy());
        }
        else return;
    }
    else return;

    ctx.output(
        "public static const %s %s = %s;",
        type.c_str(),
        std::string(decl->getName()).c_str(),
        initializerStr.c_str()
    );
}

void dumpExternVar(BindingContext& ctx, clang::VarDecl* decl)
{
    std::string type = getTypeStr(ctx, decl->getType());
    ctx.output(
        "public static __extern_cpp %s %s;",
        type.c_str(),
        std::string(decl->getName()).c_str()
    );
}

void dumpVar(BindingContext& ctx, clang::VarDecl* decl)
{
    // Only expose constant variables.
    if (decl->getType().isConstQualified() && decl->hasInit())
        dumpConstantVar(ctx, decl);
    else if (!decl->hasInit() && decl->hasExternalStorage())
        dumpExternVar(ctx, decl);
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
    case clang::Decl::Kind::Var:
        dumpVar(ctx, clang::cast<clang::VarDecl>(decl));
        break;
    default:
        //if (!topLevel)
        //    assert(false);
        //printf("Unknown decl type\n");
        break;
    }
}

void SlangMacroBindgen::MacroDefined(const clang::Token &MacroNameTok, const clang::MacroDirective *MD)
{
    if (!isLocationActive(*ctx, MacroNameTok.getLocation()) || MD->getKind() != clang::MacroDirective::MD_Define)
        return;

    std::string name = MacroNameTok.getIdentifierInfo()->getName().str();
    const clang::MacroInfo* mi = MD->getMacroInfo();

    if (mi->isFunctionLike() || mi->getNumTokens() == 0)
    {
        // TODO: Can't yet generate bindings for function-like macros,
        // unfortunately. That's because we can't turn those into real
        // functions without knowing the types of the parameters, which is
        // non-trivial and sometimes impossible.
        return;
    }

    std::string definition;
    bool first = true;

    for (const auto& token : mi->tokens())
    {
        if (!first)
            definition += " ";
        switch (token.getKind())
        {
        case clang::tok::TokenKind::identifier:
            {
                std::string id = token.getIdentifierInfo()->getName().str();
                if (ctx->knownDefinitions.count(id))
                {
                    definition += id;
                    // Or:
                    //definition += ctx->knownDefinitions.at(id);
                }
                else return;
            }
            break;
        case clang::tok::TokenKind::string_literal:
        case clang::tok::TokenKind::numeric_constant:
        case clang::tok::TokenKind::char_constant:
            definition += std::string(token.getLiteralData(), token.getLength());
            break;
        case clang::tok::TokenKind::equalequal:
            definition += "==";
            break;
        case clang::tok::TokenKind::less:
            definition += "<";
            break;
        case clang::tok::TokenKind::lessequal:
            definition += "<=";
            break;
        case clang::tok::TokenKind::greater:
            definition += ">";
            break;
        case clang::tok::TokenKind::greaterequal:
            definition += ">=";
            break;
        case clang::tok::TokenKind::greatergreater:
            definition += ">>";
            break;
        case clang::tok::TokenKind::lessless:
            definition += "<<";
            break;
        case clang::tok::TokenKind::exclaim:
            definition += "!";
            break;
        case clang::tok::TokenKind::pipepipe:
            definition += "||";
            break;
        case clang::tok::TokenKind::ampamp:
            definition += "&&";
            break;
        case clang::tok::TokenKind::pipe:
            definition += "|";
            break;
        case clang::tok::TokenKind::caret:
            definition += "^";
            break;
        case clang::tok::TokenKind::amp:
            definition += "&";
            break;
        case clang::tok::TokenKind::tilde:
            definition += "~";
            break;
        case clang::tok::TokenKind::plus:
            definition += "+";
            break;
        case clang::tok::TokenKind::minus:
            definition += "-";
            break;
        case clang::tok::TokenKind::star:
            definition += "*";
            break;
        case clang::tok::TokenKind::slash:
            definition += "/";
            break;
        case clang::tok::TokenKind::percent:
            definition += "%";
            break;
        case clang::tok::TokenKind::l_paren:
            definition += "(";
            break;
        case clang::tok::TokenKind::r_paren:
            definition += ")";
            break;
        case clang::tok::TokenKind::question:
            definition += "?";
            break;
        case clang::tok::TokenKind::colon:
            definition += ":";
            break;
        default:
            // This token type won't work as Slang, and would require more
            // complex transformations.
            return;
        }
        first = false;
    }

    const clang::Token& token = mi->getReplacementToken(0);

    ctx->output("public static let %s = %s;", name.c_str(), definition.c_str());
    ctx->knownDefinitions[name] = definition;
}

SlangBindgen::~SlangBindgen()
{
    clang::Preprocessor& pp = ctx->session->clang->getPreprocessor();
    pp.addPPCallbacks(nullptr);
}

void SlangBindgen::Initialize(clang::ASTContext&)
{
    clang::Preprocessor& pp = ctx->session->clang->getPreprocessor();
    std::unique_ptr<clang::PPCallbacks> cb(new SlangMacroBindgen(ctx));
    pp.addPPCallbacks(std::move(cb));
}

bool SlangBindgen::HandleTopLevelDecl(clang::DeclGroupRef decl)
{
    for (clang::Decl* singleDecl: decl)
    {
        if (!isLocationActive(*ctx, singleDecl->getLocation()) && !isNameActive(singleDecl))
            continue;
        dumpDecl(*ctx, singleDecl, true);
    }
    return true;
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
    for (const std::string& header: options.importedHeaders)
        inputSource += "#include \""+header+"\"\n";
    for (const std::string& header: options.cHeaders)
        inputSource += "#include \""+header+"\"\n";

    ctx.shimCode = inputSource;

    ctx.pushScope();

    session.parseSource(ctx, inputSource);

    ctx.popScope();

    // TODO compile shim code
    if (!options.shimOutputPath.empty())
        ctx.emitShimLibrary();

    if (!options.inNamespace.empty())
    {
        ctx.indentLevel--;
        ctx.output("}");
    }
    return 0;
}
