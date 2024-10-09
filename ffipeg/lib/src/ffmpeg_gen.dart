class FFmpegGen {
  const FFmpegGen({
    this.headerPaths = const [],
    this.libraries = FFmpegLibrary.values,
    this.excludeAllByDefault = false,
    this.functions = const FFIncludeAll(),
    this.structs = const FFIncludeAll(),
    this.enums = const FFIncludeAll(),
    this.globals = const FFIncludeAll(),
    this.typedefs = const FFIncludeAll(),
    this.className = 'FFmpeg',
    this.libclangDylib,
    this.excludeHeaders = defaultExcludeHeaders,
  });

  /// Absolute paths to search for the FFmpeg headers.
  /// If empty, the bundled headers will be used.
  /// These should end in `include` and are searched in the order provided.
  /// The first successful one will be used. Errors ignored unless all fail.
  /// Example: `['/opt/homebrew/opt/ffmpeg/include', 'C:\FFmpeg\include']`
  final List<String> headerPaths;

  /// Which FFmpeg libraries to generate bindings for. Default: all.
  /// Recommendation: generate only the libraries you need.
  final List<FFmpegLibrary> libraries;

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

  /// Include or Exclude specific globals by regex pattern. Default: `FFIncludeAll()`.
  /// Recommendation: use `FFInclude` to allow-list only the ones you need.
  final FFIncludeExclude globals;

  /// Include or Exclude specific typedefs by regex pattern. Default: `FFIncludeAll()`.
  /// Recommendation: use `FFInclude` to allow-list only the ones you need.
  final FFIncludeExclude typedefs;

  /// The generated class name.
  /// Defaults to `FFmpeg`.
  final String className;

  /// Path to the clang library.
  /// Default: `null` (autodetect).
  final String? libclangDylib;

  /// Header files to exclude.
  /// Default: `defaultExcludeHeaders`.
  final List<String> excludeHeaders;
}

enum FFmpegLibrary {
  avCodec,
  avDevice,
  avFormat,
  avFilter,
  avUtil,
  postProc,
  swResample,
  swScale;

  String get dir => 'lib${name.toLowerCase()}';

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

const defaultExcludeHeaders = <String>[
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
];

sealed class FFIncludeExclude {
  const FFIncludeExclude();
}

class FFInclude extends FFIncludeExclude {
  const FFInclude(this.include);

  final List<String> include;
}

class FFIncludeAll extends FFExclude {
  const FFIncludeAll() : super(const []);
}

class FFExcludeAll extends FFInclude {
  const FFExcludeAll() : super(const []);
}

class FFExclude extends FFIncludeExclude {
  const FFExclude(this.exclude);

  final List<String> exclude;
}
