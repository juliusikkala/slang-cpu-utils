#include "llvm/Support/TargetSelect.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
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

static struct {
    std::string inNamespace;
    std::string outputPath;
    std::string targetTriple;
    std::vector<std::string> cHeaders;
    std::vector<std::string> importModules;
    std::vector<std::string> usingNamespaces;
    std::vector<std::string> importedSources;
    std::vector<std::string> clangArgs;
    std::vector<std::string> defines;
    std::vector<std::string> includePaths;
    std::vector<std::regex> unscopedEnums;
    std::vector<std::regex> removeCommonPrefixes;
    std::vector<std::regex> removeEnumCases;
    std::string enumFallbackPrefix = "e";
    bool useByteBool = false;
} options;

struct BindingContext
{
    FILE* file = stdout;
    int indentLevel = 0;

    // Concretely sized names for builtin types with unpredictable size. 
    std::string wcharType = "int16_t";
    std::string shortType = "int16_t";
    std::string intType = "int";
    std::string longType = "int";

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
};

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
        // doesn't exist and this is just a list of global constants.
        for (size_t i = 0; i < names.size(); ++i)
            ctx.output("public static const %s %s = %s;", underlyingType.c_str(), names[i].c_str(), values[i].c_str());
        if (!variableName.empty())
            ctx.output("public %s %s;", underlyingType.c_str(), variableName.c_str());
    }
}

void dumpDecl(BindingContext& ctx, clang::Decl* decl, bool topLevel)
{
    switch(decl->getKind())
    {
    case clang::Decl::Kind::Enum:
        dumpEnum(ctx, clang::cast<clang::EnumDecl>(decl));
        break;
    default:
        //printf("Unknown decl type\n");
        break;
    }
}

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
            fprintf(stderr, "%s\n", text.c_str());
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
        comp.reset(driver->BuildCompilation({"clang", "-w", "-S", "dummy.c"}));
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
};

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

    session.determineIntegerSizes(ctx);

    std::string inputSource = "";
    for (const std::string& ns: options.cHeaders)
        inputSource += "#include \""+ns+"\"\n";

    session.parseSource(ctx, inputSource);

    // TODO: Actual contents lol
    // Create a string that just includes all of the inputs 
    // Feed that to Clang to get AST
    // Detect functions signatures with struct value types
    // Compile wrapper with Clang, emit as LLVM IR, dig out the func

    if (!options.inNamespace.empty())
    {
        ctx.indentLevel--;
        ctx.output("}");
    }
    return 0;
}
