/// Library annotation class for generating FFmpeg bindings.
/// Annotate a library declaration with this class to generate FFmpeg bindings.
/// The resulting filename is the library filename with its extension
/// changed to '.ffipeg.dart'. It is not a part file; therefore,
/// to import it, use a standard `import` declaration.
class FFmpegGen {
  const FFmpegGen({
    this.versionSpec,
    this.headerPaths = const {},
    this.llvmPaths = const {},
    this.libraries = const {...FFmpegLibrary.values},
    this.excludeAllByDefault = false,
    this.functions = ffAllowAll,
    this.structs = ffAllowAll,
    this.enums = ffAllowAll,
    this.unnamedEnums = ffAllowAll,
    this.unions = ffAllowAll,
    this.globals = ffAllowAll,
    this.macros = ffAllowAll,
    this.typedefs = ffAllowAll,
    this.className = 'FFmpeg',
    this.excludeHeaders = defaultExcludeHeaders,
  });

  /// The (optional) FFmpeg version specifier to generate bindings for.
  /// e.g. "7.1", ">=7.1", ">=7.1 <8.0"
  /// respectively: 7.1 exactly, 7.1 and up, or 7.1 up to excluding 8.0.
  /// If null, the first headers found recursively in `headerPaths`
  /// will be used, ordered by:
  ///   - parent directory named "current"
  ///   - parent directory with highest name in lexical order.
  /// If not null, the `headerPaths` will be searched for FFmpeg headers
  /// with the given version, and the search will fail
  /// if a matching version of headers is not found.
  final String? versionSpec;

  /// Absolute paths to search for the FFmpeg headers.
  /// If empty, the bundled headers will be used.
  /// These should end in `include` and are searched in the order provided.
  /// The first successful one will be used. Errors ignored unless all fail.
  /// Example: `['/opt/homebrew/opt/ffmpeg/include', 'C:\FFmpeg\include']`
  final Set<String> headerPaths;

  /// Which FFmpeg libraries to generate bindings for. Default: all.
  /// Recommendation: generate only the libraries you need.
  final Set<FFmpegLibrary> libraries;

  /// If true, excludes everything by default (`FFIncludeAll()` will not work
  /// on the other options; you must explicitly include items you need using
  /// `FFInclude([...])`). Defaults to `false`.
  /// Maps to the `exclude-all-by-default` ffigen option.
  final bool excludeAllByDefault;

  /// Include or Exclude specific functions by regex pattern. Default: `FFIncludeAll()`.
  /// Recommendation: use `FFInclude` to allow-list only the ones you need.
  final FFIncludeExclude functions;

  /// Include or Exclude specific structs by regex pattern. Default: `FFIncludeAll()`.
  /// Recommendation: use `FFInclude` to allow-list only the ones you need.
  final FFIncludeExclude structs;

  /// Include or Exclude specific enums by regex pattern. Default: `FFIncludeAll()`.
  /// Recommendation: use `FFInclude` to allow-list only the ones you need.
  final FFIncludeExclude enums;

  /// Include or Exclude specific unnamed enums by regex pattern. Default: `FFIncludeAll()`.
  /// Recommendation: use `FFInclude` to allow-list only the ones you need.
  final FFIncludeExclude unnamedEnums;

  /// Include or Exclude specific unions by regex pattern. Default: `FFIncludeAll()`.
  /// Recommendation: use `FFInclude` to allow-list only the ones you need.
  final FFIncludeExclude unions;

  /// Include or Exclude specific globals by regex pattern. Default: `FFIncludeAll()`.
  /// Recommendation: use `FFInclude` to allow-list only the ones you need.
  final FFIncludeExclude globals;

  /// Include or Exclude specific macros by regex pattern. Default: `FFIncludeAll()`.
  /// Recommendation: use `FFInclude` to allow-list only the ones you need.
  final FFIncludeExclude macros;

  /// Include or Exclude specific typedefs by regex pattern. Default: `FFIncludeAll()`.
  /// Recommendation: use `FFInclude` to allow-list only the ones you need.
  final FFIncludeExclude typedefs;

  /// The generated class name.
  /// Defaults to `FFmpeg`.
  final String className;

  /// Path(s) to llvm folder(s) (same as `llvm-path` in ffigen config).
  /// From ffigen docs: ffigen will sequentially search for
  /// `lib/libclang.so` on linux, `lib/libclang.dylib` on macOs and `bin\libclang.dll` on windows, in the specified paths.
  /// Complete path to the dynamic library can also be supplied.
  /// Required if ffigen is unable to find this at default locations.
  final Set<String> llvmPaths;

  /// Header files to exclude.
  /// Default: `defaultExcludeHeaders`.
  /// You can augment `defaultExcludeHeaders` with:
  /// ```
  /// @FFmpegGen(
  ///  excludeHeaders: { ...defaultExcludeHeaders, 'libavcodec/your_header.h' }
  /// )
  final Set<String> excludeHeaders;
}

/// List of FFmpeg libraries to generate bindings for.
enum FFmpegLibrary {
  avCodec,
  avDevice,
  avFormat,
  avFilter,
  avUtil,
  postProc,
  swResample,
  swScale;

  /// The lowercase subdirectory name for the library's headers.
  String get dir => 'lib${name.toLowerCase()}';

  /// The generated Dart `ffi.Struct` subclass name for the library.
  String get genName => switch (this) {
        FFmpegLibrary.avCodec => 'AVCodec',
        FFmpegLibrary.avDevice => 'AVDevice',
        FFmpegLibrary.avFormat => 'AVFormat',
        FFmpegLibrary.avFilter => 'AVFilter',
        FFmpegLibrary.avUtil => 'AVUtil',
        FFmpegLibrary.postProc => 'PostProc',
        FFmpegLibrary.swResample => 'SWResample',
        FFmpegLibrary.swScale => 'SWScale',
      };
}

/// These headers will cause ffigen to fail if included.
/// You can augment them with:
/// ```
/// @FFmpegGen(
///  excludeHeaders: { ...defaultExcludeHeaders, 'libavcodec/your_header.h' }
/// )
const defaultExcludeHeaders = <String>{
  'libavcodec/d3d11va.h',
  'libavcodec/dxva2.h',
  'libavcodec/qsv.h',
  'libavcodec/vdpau.h',
  'libavcodec/videotoolbox.h',
  'libavcodec/xvmc.h',
  'libavutil/hwcontext_cuda.h',
  'libavutil/hwcontext_d3d11va.h',
  'libavutil/hwcontext_d3d12va.h',
  'libavutil/hwcontext_drm.h',
  'libavutil/hwcontext_dxva2.h',
  'libavutil/hwcontext_mediacodec.h',
  'libavutil/hwcontext_opencl.h',
  'libavutil/hwcontext_qsv.h',
  'libavutil/hwcontext_vaapi.h',
  'libavutil/hwcontext_vdpau.h',
  'libavutil/hwcontext_videotoolbox.h',
  'libavutil/hwcontext_vulkan.h',
};

/// Sealed parent class for include/exclude directives.
sealed class FFIncludeExclude {
  const FFIncludeExclude();
}

/// Include specific symbols of a type by pattern (refer to ffigen for supported patterns).
base class FFInclude extends FFIncludeExclude {
  const FFInclude(this.include);

  /// Set of symbols to explicitly include.
  final Set<String> include;
}

/// Exclude specific symbols of a type by pattern (refer to ffigen for supported patterns).
base class FFExclude extends FFIncludeExclude {
  const FFExclude(this.exclude);

  /// Set of symbols to explicitly exclude.
  final Set<String> exclude;
}

/// Allow all symbols of a type to be included (shorthand for `FFExclude({})`).
final class FFAllowAll extends FFExclude {
  const FFAllowAll() : super(const {});
}

/// Allow all symbols of a type to be included (shorthand for `FFExclude({})`).
const ffAllowAll = FFAllowAll();

/// Exclude all symbols of a type (shorthand for `FFInclude({})`).
final class FFDenyAll extends FFInclude {
  const FFDenyAll() : super(const {});
}

/// Exclude all symbols of a type (shorthand for `FFInclude({})`).
const ffDenyAll = FFDenyAll();
